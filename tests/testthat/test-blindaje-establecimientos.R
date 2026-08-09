# Hardening: BUSINESS / establishment surveys (ONS, StatCan, CBS).
# The package also fits economic surveys: certainty stratum (w = 1),
# dead and untraceable firms, GREG calibration to CONTINUOUS register totals.
# registro (empleo), y winsorizacion unilateral del estilo ONS.

emp_d <- function(n = 600, seed = 201) {
  set.seed(seed)
  # business register: size by employment, with a certainty stratum (large firms)
  emp <- c(rpois(round(n * .70), 8) + 1,       # chicas
           rpois(round(n * .25), 60) + 20,     # medianas
           rpois(n - round(n * .70) - round(n * .25), 900) + 300)  # grandes
  d <- data.frame(id = seq_len(n), emp = emp,
                  sector = factor(sample(c("Ind", "Com", "Serv"), n, TRUE)))
  d$tam <- cut(d$emp, c(0, 20, 200, Inf), labels = c("chica", "mediana", "grande"))
  # typical design: certainty for large firms (w = 1), fractions for the rest
  # (con variacion continua dentro del estrato, como deja un marco real)
  d$w <- ifelse(d$tam == "grande", 1,
                ifelse(d$tam == "mediana", runif(n, 3.5, 5.5), runif(n, 10, 14)))
  # dead firms (closed: out of scope) and untraceable ones (unknown
  # eligibility), as they arrive from an outdated register
  d$muerta <- rbinom(n, 1, .06) == 1
  # las grandes siempre se ubican (seguimiento intensivo): iloc solo fuera de certeza
  d$iloc   <- rbinom(n, 1, .05) == 1 & !d$muerta & d$tam != "grande"
  # response: large firms under intensive follow-up all respond
  d$resp <- ifelse(d$tam == "grande", TRUE, rbinom(n, 1, .75) == 1) &
    !d$muerta & !d$iloc
  d
}

test_that("ONS/StatCan-style business survey: certainty stratum keeps weight 1 through the cascade, register employment total hit exactly", {
  d <- emp_d()
  # register totals (live universe approximated by the updated frame)
  t_emp  <- sum(d$w * d$emp) * 0.97
  t_sec  <- setNames(as.numeric(tapply(d$w, d$sector, sum)) * 0.97, levels(d$sector))
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_unknown_eligibility(unknown = iloc, by = "tam") |>
      step_drop_ineligible(ineligible = muerta) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = "tam") |>
      step_calibrate(method = "linear", formula = ~ sector + emp,
                     totals = c("(Intercept)" = sum(t_sec),
                                structure(as.numeric(t_sec[-1]),
                                          names = paste0("sector", names(t_sec)[-1])),
                                emp = t_emp))))
  hw <- collect_weights(p, keep_intermediate = TRUE)
  # promise 1: the certainty stratum (full response after follow-up) reaches
  # calibration with weight EXACTLY 1 (no stage touches it)
  nrcol <- grep("nonresponse", names(hw), value = TRUE)[1]
  cert  <- hw$tam == "grande" & hw[[nrcol]] > 0
  expect_true(all(abs(hw[[nrcol]][cert] - 1) < 1e-12))
  # promise 2: the CONTINUOUS register employment total is reproduced exactly
  cw <- collect_weights(p)
  expect_equal(sum(cw$.weight * cw$emp), t_emp, tolerance = 1e-8 * t_emp)
  # promise 3: the sector totals too
  ts <- tapply(cw$.weight, cw$sector, sum)
  expect_lt(max(abs(as.numeric(ts[names(t_sec)]) - t_sec) / t_sec), 1e-6)
  # and the dead firms are left out with weight 0
  expect_true(all(collect_weights(p, drop_zero = FALSE)$.weight[d$muerta] == 0))
})

test_that("CBS-style mixed calibration: categorical sector AND continuous employment, both exact at once", {
  d <- emp_d(seed = 211)
  X  <- stats::model.matrix(~ sector + emp, d)
  tt <- colSums(X * d$w) * 1.03
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_calibrate(method = "linear", formula = ~ sector + emp, totals = tt)))
  cw <- collect_weights(p, drop_zero = FALSE)
  ach <- colSums(cw$.weight * X)
  expect_lt(max(abs(ach - tt) / abs(tt)), 1e-8)
})

test_that("ONS-style one-sided winsorization: upper cap with FEASIBLE redistribution preserves the total exactly", {
  d <- emp_d(seed = 221)
  p0 <- suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = "tam")))
  w0 <- collect_weights(p0, drop_zero = FALSE)$.weight
  cap <- as.numeric(quantile(w0[w0 > 0], .97))   # el cap muerde el 3% superior
  expect_gt(sum(w0 > cap), 0)
  # y la preservacion es factible: hay espacio de sobra bajo el cap
  expect_gt(sum(w0 > 0) * cap, 1.05 * sum(w0))
  p1 <- suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = "tam") |>
      step_trim_weights(lower = min(w0[w0 > 0]) / 2, upper = cap)))
  w1 <- collect_weights(p1, drop_zero = FALSE)$.weight
  expect_equal(sum(w1), sum(w0), tolerance = 1e-6)     # masa preservada (feasible)
  expect_lte(max(w1), cap + 1e-8)                      # cola capada
  # el deff mejora (esa es la razon de winsorizar)
  expect_lt(design_effect(w1)$deff, design_effect(w0)$deff)
})
