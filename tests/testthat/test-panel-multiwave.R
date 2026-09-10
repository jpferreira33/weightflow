# El caso ANUAL del capitulo XVI de CEPAL (sec. C): combinar tres o cuatro olas, no dos.
# La muestra longitudinal es la interseccion s(1234) = s1 n s2 n s3 n s4, el peso basico sale
# de Pr(seleccion de paneles) = 1/4 en un diseno 4(0)1, y el ajuste por no respuesta se modela
# sobre "respondio en TODAS las olas". Todo esto lo soporta el codigo, pero hasta ahora ningun
# test lo ejercitaba: los cinco archivos que usan panel_merge() pasaban siempre T1/T2, asi que
# el caso que el manual prescribe por escrito era una afirmacion sin verificar.

olas_ine <- function() {
  w <- split(panel_ine, panel_ine$ola)
  stats::setNames(w, paste0("T", seq_along(w)))
}

test_that("panel_merge enlaza mas de dos olas y marca la presencia en cada una", {
  skip_on_cran()
  w <- olas_ine()
  expect_gte(length(w), 3L)
  wide <- panel_merge(w, by = c("id_hogar", "nper"), require = "all")
  ind <- grep("^\\.wf_in_", names(wide), value = TRUE)
  expect_equal(ind, paste0(".wf_in_T", seq_along(w)))
  expect_true(all(vapply(ind, function(v) all(wide[[v]] %in% 0:1), logical(1))))
  # una columna sufijada por ola para cada variable repetida
  for (v in c("condicion", "sexo", "w_base"))
    expect_true(all(paste0(v, "_T", seq_along(w)) %in% names(wide)), info = v)
})

test_that("la muestra longitudinal se ACHICA al agregar olas (es una interseccion)", {
  skip_on_cran()
  w <- olas_ine()
  n <- vapply(2:length(w), function(k)
    nrow(panel_merge(w[seq_len(k)], by = c("id_hogar", "nper"), require = "all")),
    integer(1))
  # s(123) subset de s(12): mas periodos, menos unidades. El manual lo dice explicitamente.
  expect_true(all(diff(n) <= 0))
  expect_lt(n[length(n)], n[1L])
  # y `require = "any"` va al reves: es la union
  n_any <- nrow(panel_merge(w, by = c("id_hogar", "nper"), require = "any"))
  expect_gt(n_any, n[length(n)])
})

test_that("el ponderador longitudinal de tres olas corre entero y conserva el total", {
  skip_on_cran()
  w <- olas_ine()
  wide <- panel_merge(w, by = c("id_hogar", "nper"), require = "all")
  # respondio en TODAS las olas: es la definicion de sr(123) del capitulo
  wide$resp_todas <- with(wide, disp_T1 == "R" & disp_T2 == "R" & disp_T3 == "R")
  expect_gt(sum(wide$resp_todas), 100L)

  f <- prep(weighting_spec(wide, base_weights = w_base_T1) |>
              step_drop_ineligible(disp_T3 == "OS") |>
              step_attrition(respondent = resp_todas, method = "propensity",
                             formula = ~ sexo_T1 + edad_T1))
  activos <- f$final_weight > 0
  expect_equal(sum(activos), sum(wide$resp_todas & wide$disp_T3 != "OS"))
  # 1/phi-hat preserva el total de los elegibles (la verificacion del cap. XVI)
  base_elig <- sum(wide$w_base_T1[wide$disp_T3 != "OS"])
  expect_equal(sum(f$final_weight) / base_elig, 1, tolerance = 0.05)
  expect_false(any(grepl("changed the total", f$alerts)))
})

test_that("Pr(seleccion de paneles) cae al agregar olas, y step_panel_overlap lo aplica", {
  skip_on_cran()
  w <- olas_ine()
  pd <- panel_design(panel_ine, unit = c("id_hogar", "nper"), wave = "ola",
                     rotation_group = "grupo_rotacion", pattern = "6")
  pr2 <- panel_pr(pd, waves = c("1", "2"))
  pr3 <- panel_pr(pd, waves = c("1", "2", "3"))
  expect_true(pr2 > pr3)                       # menos cohortes coinciden en tres olas
  expect_true(pr3 > 0 && pr2 <= 1)

  wide <- panel_merge(w, by = c("id_hogar", "nper"), require = "all")
  f <- prep(weighting_spec(wide, base_weights = w_base_T1) |>
              step_panel_overlap(prob = pr3))
  # d_base = d1 / Pr  -> el total sube por el reciproco, exactamente
  expect_equal(sum(f$final_weight), sum(wide$w_base_T1) / pr3, tolerance = 1e-8)
})

test_that("los flujos de tres olas se pueden encadenar de a pares sobre el mismo archivo", {
  skip_on_cran()
  w <- olas_ine()
  wide <- panel_merge(w, by = c("id_hogar", "nper"), require = "all")
  wide$resp_todas <- with(wide, disp_T1 == "R" & disp_T2 == "R" & disp_T3 == "R")
  f <- prep(weighting_spec(wide, base_weights = w_base_T1) |>
              step_attrition(respondent = resp_todas, method = "weighting_class",
                             by = "sexo_T1"))
  EST <- c("emp", "unemp", "inact")
  t12 <- transition_matrix(f, "condicion_T1", "condicion_T2", states = EST, format = "row")
  t23 <- transition_matrix(f, "condicion_T2", "condicion_T3", states = EST, format = "row")
  for (m in list(t12$matrix, t23$matrix)) {
    expect_equal(dim(m), c(3L, 3L))
    # cada fila es una distribucion condicional: suma 1 (salvo estados sin nadie)
    r <- rowSums(m)
    expect_true(all(abs(r[r > 0] - 1) < 1e-8))
  }
  # los conteos totales de las dos transiciones son el mismo universo
  expect_equal(sum(t12$counts), sum(t23$counts), tolerance = 1e-6)
})

test_that("una cadena de wave_step de tres periodos coordina contra los dos anteriores", {
  skip_on_cran()
  w <- olas_ine()
  rec <- function(d) {
    d <- subset(d, disp == "R"); d$sexo <- factor(d$sexo)
    weighting_spec(d, base_weights = w_base) |>
      step_nonresponse(respondent = disp == "R", by = "sexo")
  }
  E <- list(desoc = function(w, d) stats::weighted.mean(d$desocupado, w, na.rm = TRUE))
  out <- list(); prev <- NULL
  for (k in seq_along(w)) {
    s <- wave_step(rec(w[[k]]), previous = prev, estimands = E, replicates = 60,
                   strata = "estrato", psu = "psu", period = paste0("T", k),
                   seed = 300 + k, progress = FALSE)
    out[[k]] <- wave_carry(s); prev <- rev(out)
    if (k == 3L) {
      # el tercer periodo reporta un cambio contra CADA uno de los dos anteriores
      expect_equal(sort(unique(s$change$from)), c("T1", "T2"))
      expect_true(all(is.finite(s$change$se)))
      # y el solape decae: la correlacion con T2 supera a la de T1 (rezago 1 vs 2)
      r <- s$change
      expect_gt(r$rho[r$from == "T2"], r$rho[r$from == "T1"])
    }
  }
  # y el contraste lineal sobre las tres reproduce el cambio par a par
  d31 <- wave_contrast(list(out[[1]], out[[3]]), "desoc", contrast = c(-1, 1))
  expect_equal(d31$estimate, out[[3]]$point[["desoc"]] - out[[1]]$point[["desoc"]], tolerance = 1e-12)
})
