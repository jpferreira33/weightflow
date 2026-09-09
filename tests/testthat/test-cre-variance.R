# step_cre() dentro de los motores coordinados (wave_bootstrap / wave_jackknife).
# Cubre el hueco que la auditoria marco: la pieza central del modulo no tenia ningun
# test que corriera el compuesto por replica. Porta los experimentos §B de la auditoria.

# --- panel sintetico de 2 olas, traslape 5/6, con link id_unit y diseño estrato/UPM ---
cre_panel <- function(seed = 11) {
  set.seed(seed)
  Ncoh <- 7L; psu_per_coh <- 4L; hh_per_psu <- 5L
  states <- c("emp", "unemp", "inact")
  cell <- expand.grid(coh = seq_len(Ncoh), k = seq_len(psu_per_coh))
  cell$upm <- seq_len(nrow(cell))
  cell$str <- rep(1:4, length.out = nrow(cell))          # >= 2 UPM por estrato
  hh <- cell[rep(seq_len(nrow(cell)), each = hh_per_psu), c("coh", "upm", "str")]
  hh$hh <- seq_len(nrow(hh))
  per <- hh[rep(seq_len(nrow(hh)), each = 2L), ]
  per$pid  <- rep(1:2, nrow(hh))
  per$sexo <- factor(sample(c("H", "M"), nrow(per), TRUE))
  per$s1 <- sample(states, nrow(per), TRUE, prob = c(.58, .06, .36))
  # persistencia alta: s2 casi igual a s1
  per$s2 <- ifelse(runif(nrow(per)) < 0.9, per$s1, sample(states, nrow(per), TRUE))
  per$w_base <- 20 + 4 * per$str
  d1 <- per[per$coh %in% 1:6, ]; d1$condicion <- d1$s1
  d2 <- per[per$coh %in% 2:7, ]; d2$condicion <- d2$s2
  d1$emp <- as.integer(d1$condicion == "emp")
  d2$emp <- as.integer(d2$condicion == "emp")
  list(d1 = d1, d2 = d2)
}
cre_tot <- function(d) colSums(d$w_base * stats::model.matrix(~ sexo, data = d))

# recetas: semilla (ola 1) y compuesta (ola 2). composite = list(NULL) (nivel pais, factible).
cre_specs <- function(p, alpha = 2/3) {
  seed <- weighting_spec(p$d1, base_weights = w_base) |>
    step_cre(previous = NULL, status = condicion, formula = ~ sexo, totals = cre_tot(p$d1)) |>
    prep()
  spec1 <- weighting_spec(p$d1, base_weights = w_base) |>
    step_cre(previous = NULL, status = condicion, formula = ~ sexo, totals = cre_tot(p$d1))
  spec2 <- weighting_spec(p$d2, base_weights = w_base) |>
    step_cre(previous = seed, status = condicion, composite = list(NULL),
             id_unit = c("hh", "pid"), formula = ~ sexo, totals = cre_tot(p$d2),
             birth = coh == 7, alpha = alpha, status_ref = "inact")
  list(seed = seed, spec1 = spec1, spec2 = spec2)
}
emp_rate <- function(w, d) stats::weighted.mean(d$emp, w)

test_that("step_cre corre dentro de wave_bootstrap y wave_jackknife (SE de cambio finito y > 0)", {
  skip_on_cran()
  p <- cre_panel(); s <- cre_specs(p)
  wb <- wave_bootstrap(list(t1 = s$spec1, t2 = s$spec2), replicates = 150,
                       strata = "str", psu = "upm", seed = 3,
                       refit_steps = "calibration", progress = FALSE)
  wj <- wave_jackknife(list(t1 = s$spec1, t2 = s$spec2), strata = "str", psu = "upm",
                       refit_steps = "calibration", progress = FALSE)
  cb <- change_estimate(wb, emp_rate)
  cj <- change_estimate(wj, emp_rate)
  expect_true(is.finite(cb$se) && cb$se > 0)
  expect_true(is.finite(cj$se) && cj$se > 0)
  # el traslape induce covarianza positiva: V(cambio) < V1 + V2 (no independiente)
  expect_lt(cb$V, cb$V1 + cb$V2)
  # boot y jackknife en el mismo orden de magnitud (no un factor 5)
  expect_lt(cb$se / cj$se, 3); expect_gt(cb$se / cj$se, 1/3)
})

test_that("alpha cambia los pesos del compuesto (un step_cre que lo ignorara fallaria)", {
  skip_on_cran()
  p <- cre_panel()
  w0 <- prep(cre_specs(p, alpha = 0)$spec2)$final_weight
  w1 <- prep(cre_specs(p, alpha = 1)$spec2)$final_weight
  expect_gt(max(abs(w0 - w1)), 1e-6)      # difieren de verdad (auditoria §E2: max|Δ| ~ 88)
})

test_that("la inyeccion de Zhat* NO es inerte: apagarla mueve el SE del cambio", {
  skip_on_cran()
  p <- cre_panel(); s <- cre_specs(p)
  se_on <- change_estimate(
    wave_bootstrap(list(t1 = s$spec1, t2 = s$spec2), replicates = 200, strata = "str",
                   psu = "upm", seed = 5, refit_steps = "calibration", progress = FALSE),
    emp_rate)$se
  # reemplazar el inyector por identidad (Zhat fijo) via mock del binding interno
  testthat::local_mocked_bindings(.wf_cre_inject_prev = function(spec, w_prev) spec)
  se_off <- change_estimate(
    wave_bootstrap(list(t1 = s$spec1, t2 = s$spec2), replicates = 200, strata = "str",
                   psu = "upm", seed = 5, refit_steps = "calibration", progress = FALSE),
    emp_rate)$se
  # la coordinacion no es un no-op: cambia el SE de forma material (auditoria §B1)
  expect_gt(abs(se_off - se_on) / se_on, 0.02)
})

test_that("resample: el default es 'multinom' y el esquema cambia el SE del compuesto", {
  skip_on_cran()
  p <- cre_panel(); s <- cre_specs(p)
  se <- function(scheme = NULL) {
    args <- list(list(t1 = s$spec1, t2 = s$spec2), replicates = 300, strata = "str",
                 psu = "upm", seed = 9, refit_steps = "calibration", progress = FALSE)
    if (!is.null(scheme)) args$resample <- scheme
    change_estimate(do.call(wave_bootstrap, args), emp_rate)$se
  }
  se_default <- se(); se_multi <- se("multinom"); se_binom <- se("binom")
  expect_equal(se_default, se_multi, tolerance = 1e-8)             # default == multinom
  expect_false(isTRUE(all.equal(se_binom, se_multi)))             # el esquema importa
  expect_true(is.finite(se_binom) && se_binom > 0)
})

test_that("step_cre: la expresion birth puede ver una variable del entorno (CRE-03)", {
  p <- cre_panel(); s <- cre_specs(p)
  k <- 7L                                    # variable externa referenciada por birth=
  spec <- weighting_spec(p$d2, base_weights = w_base) |>
    step_cre(previous = s$seed, status = condicion, composite = list(NULL),
             id_unit = c("hh", "pid"), formula = ~ sexo, totals = cre_tot(p$d2),
             birth = coh == k, status_ref = "inact")
  expect_no_error(prep(spec))                # k se resuelve del env del llamador, no "object 'k' not found"
})

test_that("bootstrap_weights / jackknife_weights avisan sobre una receta con step_cre (VAR-04)", {
  skip_on_cran()
  p <- cre_panel(); s <- cre_specs(p)
  # el motor monofasico trata Zhat como fijo -> varianza anticonservadora; debe avisar y
  # remitir a los motores coordinados.
  expect_warning(bootstrap_weights(s$spec2, replicates = 10, strata = "str", psu = "upm",
                                   progress = FALSE), "step_cre")
  expect_warning(jackknife_weights(s$spec2, strata = "str", psu = "upm", progress = FALSE),
                 "step_cre")
})

test_that("wave_bootstrap contabiliza la inyeccion de Zhat* (n_cre_injected) sin saltos", {
  skip_on_cran()
  p <- cre_panel(); s <- cre_specs(p)
  wb <- wave_bootstrap(list(t1 = s$spec1, t2 = s$spec2), replicates = 60, strata = "str",
                       psu = "upm", seed = 3, refit_steps = "calibration", progress = FALSE)
  expect_gte(wb$n_cre_injected, 1L)     # la ola 2 tiene un step_cre que recibe Zhat*
  expect_identical(wb$n_cre_skipped, 0L) # las olas alinean -> no hay salto silencioso
})

test_that("wave_bootstrap AVISA y cuenta cuando la inyeccion de Zhat* se saltea (auditoria C2)", {
  skip_on_cran()
  p <- cre_panel()
  # semilla prepada sobre d1 SIN una fila -> nrow(previous$data) != nrow(la ola t1 real)
  d1_short <- p$d1[-1, ]
  seed_bad <- weighting_spec(d1_short, base_weights = w_base) |>
    step_cre(previous = NULL, status = condicion, formula = ~ sexo,
             totals = cre_tot(d1_short)) |>
    prep()
  spec1 <- weighting_spec(p$d1, base_weights = w_base) |>
    step_cre(previous = NULL, status = condicion, formula = ~ sexo, totals = cre_tot(p$d1))
  spec2 <- weighting_spec(p$d2, base_weights = w_base) |>
    step_cre(previous = seed_bad, status = condicion, composite = list(NULL),
             id_unit = c("hh", "pid"), formula = ~ sexo, totals = cre_tot(p$d2),
             status_ref = "inact")
  expect_warning(
    wb <- wave_bootstrap(list(t1 = spec1, t2 = spec2), replicates = 40, strata = "str",
                         psu = "upm", seed = 3, refit_steps = "calibration", progress = FALSE),
    "held FIXED")
  expect_gte(wb$n_cre_skipped, 1L)
})

test_that(".wf_cre_inject_prev inyecta si nrow coincide y saltea si no (guard del salto silencioso)", {
  p <- cre_panel()
  seed <- cre_specs(p)$seed
  spec2 <- weighting_spec(p$d2, base_weights = w_base) |>
    step_cre(previous = seed, status = condicion, composite = list(NULL),
             id_unit = c("hh", "pid"), formula = ~ sexo, totals = cre_tot(p$d2),
             status_ref = "inact")
  n_prev <- nrow(seed$data)
  w_ok   <- rep(1, n_prev)
  w_bad  <- rep(1, n_prev - 1L)                 # longitud distinta -> debe saltear
  inj_ok  <- weightflow:::.wf_cre_inject_prev(spec2, w_ok)
  inj_bad <- weightflow:::.wf_cre_inject_prev(spec2, w_bad)
  # coincide -> reemplaza previous$final_weight por w_ok
  expect_equal(unname(inj_ok$steps[[1]]$previous$final_weight), w_ok)
  # no coincide -> queda el original (salto), y HOY no emite warning (bug documentado)
  expect_false(isTRUE(all.equal(inj_bad$steps[[1]]$previous$final_weight, w_bad)))
  expect_no_warning(weightflow:::.wf_cre_inject_prev(spec2, w_bad))  # TODO: deberia avisar
})
