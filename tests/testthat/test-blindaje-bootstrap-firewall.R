# FIREWALL for the variance engine. The panel work (coordinated bootstrap) is built
# self-contained in R/variance-panel.R and MUST NOT change R/variance.R. This test
# freezes the current bootstrap_weights() behaviour: if anything ever alters the
# engine, it fails loudly. Snapshot is recorded on first run (the current, correct
# CRAN behaviour) and compared thereafter.

test_that("bootstrap_weights is deterministic under a fixed seed", {
  skip_on_cran()
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
  a <- bootstrap_weights(spec, replicates = 25, strata = "region",
                         psu = "psu", seed = 20260906, progress = FALSE)
  b <- bootstrap_weights(spec, replicates = 25, strata = "region",
                         psu = "psu", seed = 20260906, progress = FALSE)
  expect_identical(a$replicates, b$replicates)          # same seed -> same replicates
  expect_identical(a$weights, b$weights)
})

test_that("bootstrap_weights output is frozen bit-for-bit (firewall)", {
  skip_on_cran()
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
  boot <- bootstrap_weights(spec, replicates = 25, strata = "region",
                            psu = "psu", seed = 20260906, progress = FALSE)
  est <- boot_mean(boot, "income")
  # A compact but sensitive fingerprint of the whole realized bootstrap: the point
  # weights, the per-replicate weight totals, and the estimate/SE. Any change to the
  # Rao-Wu draw or the rescaling formula moves at least one of these.
  expect_snapshot_value(
    list(point   = round(boot$weights, 8),
         rep_tot = round(colSums(boot$replicates), 6),
         mean    = round(est$estimate, 8),
         se      = round(est$se, 8)),
    style = "serialize")
})

# --- Segundo frente: el camino de PROPENSION con pesos de escala real ---------
#
# El fixture de arriba usa step_nonresponse(method = "weighting_class") sobre `sample_survey`,
# que tiene pw = 12.5 constante y 58 % de respuesta. Ese es un modelo SIN glm, en la esquina
# segura de las dos dimensiones que gobiernan NR-PROP-01 (escala del peso x tasa de respuesta),
# y por eso el cortafuegos paso en verde ante un cambio que si altera la salida de
# bootstrap_weights() cuando la receta lleva un modelo de propension. El blindaje del modulo de
# panel se leia como si cubriera mas de lo que cubria.
#
# Este bloque cierra ese hueco por los dos lados: un snapshot que congela la salida del camino
# de propension, y las invariantes SEMANTICAS que habrian atrapado el bug en cualquier
# plataforma -- que es lo que un snapshot solo no da.

mk_ech <- function(n = 1500L, escala = 115, seed = 3) {
  set.seed(seed)
  psu <- rep(seq_len(60L), length.out = n)
  d <- data.frame(
    psu    = psu,
    estrato = ((psu - 1L) %% 6L) + 1L,
    sexo   = factor(sample(c("F", "M"), n, TRUE)),
    edad   = factor(sample(c("18-29", "30-49", "50+"), n, TRUE, c(.3, .42, .28))),
    pw     = stats::runif(n, 0.5, 2) * escala)          # peso de diseno de escala ECH
  # tasa de respuesta ALTA (~0.92): la clase mayoritaria es la que lleva los pesos grandes,
  # que es la configuracion en la que el arranque del IRLS se va a la frontera.
  d$resp <- stats::rbinom(n, 1, stats::plogis(
    2.6 + 0.5 * (d$edad == "50+") - 0.4 * (d$sexo == "M")))
  d
}

rec_prop <- function(d) weighting_spec(d, base_weights = pw) |>
  step_nonresponse(respondent = resp, method = "propensity", num_classes = NULL,
                   formula = ~ sexo + edad)

test_that("bootstrap_weights on the PROPENSITY path is frozen bit-for-bit (firewall 2)", {
  skip_on_cran()
  b <- bootstrap_weights(rec_prop(mk_ech()), replicates = 25, strata = "estrato",
                         psu = "psu", seed = 20260909, progress = FALSE)
  expect_snapshot_value(
    list(point   = round(b$weights, 8),
         rep_tot = round(colSums(b$replicates), 6),
         phi_rng = round(range(collect_step_detail(prep(rec_prop(mk_ech())))$.propensity), 8)),
    style = "serialize")
})

test_that("the fitted propensity does not collapse under production weights", {
  skip_on_cran()
  d   <- mk_ech()
  phi <- collect_step_detail(prep(rec_prop(d)))$.propensity
  expect_gt(mean(d$pw), 100)                       # el fixture esta en la zona de riesgo
  expect_gt(mean(d$resp), 0.85)                    # ...en las dos dimensiones
  expect_gt(min(phi), 0.05)                        # no toca el piso de 1e-6
  expect_lt(max(phi), 0.999)                       # ni colapsa a 1 (ajuste = no-op)
  expect_gt(stats::sd(phi), 0.005)                 # y sigue discriminando
})

test_that("the engine's output does not depend on the SCALE of the base weights", {
  skip_on_cran()
  # La ecuacion de estimacion del modelo es invariante a reescalar w por una constante, asi que
  # multiplicar los pesos base por 150 tiene que multiplicar la salida por 150 y nada mas. Esta
  # es la invariante que NR-PROP-01 violaba, y la que sobrevive a cualquier plataforma.
  d1 <- mk_ech(escala = 1); d2 <- d1; d2$pw <- d1$pw * 150
  f1 <- prep(rec_prop(d1)); f2 <- prep(rec_prop(d2))
  expect_equal(collect_step_detail(f1)$.propensity,
               collect_step_detail(f2)$.propensity, tolerance = 1e-6)
  expect_equal(f2$final_weight, 150 * f1$final_weight, tolerance = 1e-6)

  b1 <- bootstrap_weights(rec_prop(d1), replicates = 20, strata = "estrato", psu = "psu",
                          seed = 77, progress = FALSE)
  b2 <- bootstrap_weights(rec_prop(d2), replicates = 20, strata = "estrato", psu = "psu",
                          seed = 77, progress = FALSE)
  expect_equal(b2$replicates, 150 * b1$replicates, tolerance = 1e-6)
})

test_that("no replicate leaves the scale of the point weights", {
  skip_on_cran()
  # El sintoma por el que NR-PROP-01 aparecio: una replica cuyo ajuste diverge se lleva un peso
  # de 1e6 veces el suyo, y eso viaja hasta un SE absurdo tres capas mas arriba.
  b  <- bootstrap_weights(rec_prop(mk_ech()), replicates = 40, strata = "estrato",
                          psu = "psu", seed = 5, progress = FALSE)
  cs <- colSums(b$replicates)
  expect_true(all(cs > 0.6 * sum(b$weights) & cs < 1.6 * sum(b$weights)))
  expect_lt(max(b$replicates), 20 * max(b$weights))
  expect_false(anyNA(b$replicates))
})
