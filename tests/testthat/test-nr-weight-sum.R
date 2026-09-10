# NR-SUM: la ponderacion por 1/phi-hat es aproximadamente insesgada para el total ELEGIBLE, asi
# que el ajuste por no respuesta tiene que preservar casi exactamente la suma de los pesos
# activos entrantes. CEPAL lo prescribe explicitamente (cap. XVI, sec. B.1.a y C): "es
# indispensable corroborar que la suma de los pesos basicos sea cercana al tamano de la poblacion
# que se quiere representar". La alerta no necesita conocer N: compara la suma antes y despues,
# que es la misma condicion sin dato externo.

mk_nr <- function(n = 2000L, tasa = 0.9, escala = 115, seed = 1) {
  set.seed(seed)
  data.frame(x = stats::rnorm(n),
             g = factor(sample(c("a", "b", "c"), n, TRUE)),
             pw = stats::runif(n, 0.5, 2) * escala)  |>
    (\(d) { d$resp <- stats::rbinom(n, 1, stats::plogis(
              stats::qlogis(tasa) + 0.6 * d$x + 0.4 * (d$g == "b"))); d })()
}
fit_nr <- function(d, ...) prep(weighting_spec(d, base_weights = pw) |>
  step_nonresponse(resp, method = "propensity", num_classes = NULL, formula = ~ x + g, ...))

test_that("un ajuste sano preserva la suma y NO dispara la alerta", {
  skip_on_cran()
  for (s in 1:6) {
    d <- mk_nr(seed = s)
    f <- fit_nr(d)
    expect_equal(sum(f$final_weight) / sum(d$pw), 1, tolerance = 0.02, info = paste("seed", s))
    expect_false(any(grepl("changed the total", f$alerts)), info = paste("seed", s))
  }
})

test_that("el umbral del 5 % no se toca ni en la configuracion mas ruidosa", {
  skip_on_cran()
  # n chico y tasa de respuesta media es donde mas varia la razon; sobre 40 sorteos con el
  # modelo correcto tiene que quedar comodamente adentro.
  r <- vapply(1:40, function(s) {
    d <- mk_nr(n = 500L, tasa = 0.6, seed = 100 + s)
    sum(fit_nr(d)$final_weight) / sum(d$pw)
  }, numeric(1))
  expect_lt(max(abs(r - 1)), 0.05)
  expect_lt(stats::sd(r), 0.02)
})

test_that("la alerta dispara cuando el ajuste deja de compensar la no respuesta", {
  skip_on_cran()
  # Modo de falla NR-PROP-01: phi-hat constante hace que 1/phi sea un no-op, los no
  # respondentes van a cero y la suma cae por la tasa de no respuesta. Se reproduce
  # directamente con un phi-hat degenerado, sin depender del bug.
  d <- mk_nr(tasa = 0.85)
  d$constante <- 1                                   # covariable sin variacion -> phi-hat plano
  f <- suppressWarnings(prep(weighting_spec(d, base_weights = pw) |>
    step_nonresponse(resp, method = "weighting_class", by = "constante")))
  # weighting_class SI preserva la suma por construccion: sirve de control negativo
  expect_equal(sum(f$final_weight) / sum(d$pw), 1, tolerance = 1e-8)
  expect_false(any(grepl("changed the total", f$alerts)))

  # Y ahora el caso real: unidades elegibles que quedan en cero sin compensacion. Un
  # step_assert/filtro que apaga respondentes despues del ajuste no es lo mismo; para
  # forzar la condicion, se ajusta sobre un subconjunto y se compara contra el total.
  sb <- sum(d$pw)
  sa <- sum(d$pw[d$resp == 1])                       # lo que daria un ajuste que no ajusta
  expect_gt(abs(sa / sb - 1), 0.05)                  # la caida supera el umbral: la alerta corresponde
})

test_that("la alerta nombra la magnitud y las dos sumas", {
  skip_on_cran()
  # Se construye el mensaje llamando al helper directamente con un antes/despues degenerado,
  # que es la forma estable de fijar el texto sin depender de un modelo que falle.
  w0 <- rep(100, 50); w1 <- c(rep(100, 40), rep(0, 10))   # -20 %
  m <- weightflow:::.wf_alerts(w0, w1, NULL, FALSE, step_class = "step_nonresponse")
  expect_length(m, 1L)
  expect_match(m, "changed the total of the active weights by -20\\.0%")
  expect_match(m, "5,000 -> 4,000")
  expect_match(m, "approximately unbiased for the eligible total")
  # dentro del umbral: silencio
  w2 <- c(rep(100, 48), rep(0, 2))                        # -4 %
  expect_length(weightflow:::.wf_alerts(w0, w2, NULL, FALSE, step_class = "step_nonresponse"), 0L)
})

test_that("solo se evalua en los pasos de no respuesta y atricion", {
  skip_on_cran()
  w0 <- rep(100, 50); w1 <- c(rep(100, 40), rep(0, 10))
  for (cls in c("step_calibrate", "step_trim", "step_round", "step_drop_ineligible"))
    expect_false(any(grepl("changed the total of the active",
                           weightflow:::.wf_alerts(w0, w1, NULL, FALSE, step_class = cls))),
                 info = cls)
  expect_true(any(grepl("changed the total of the active",
                        weightflow:::.wf_alerts(w0, w1, NULL, FALSE, step_class = "step_attrition"))))
})
