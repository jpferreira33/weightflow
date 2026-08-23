# Regression tests for the four high-severity findings of the second audit.
# BUG-08 (jackknife rscales when a replicate fails) is not covered here: forcing
# a deterministic replicate failure is brittle; the fix mirrors the correction
# already in jackknife_estimate() and is verified by inspection.

# BUG-05: integrative calibration must refuse non-constant within-cluster weights
# in EVERY path (previously only step_calibrate() guarded it).
test_that("model calibration (integrative) rejects non-uniform within-cluster weights", {
  set.seed(1)
  n <- 40
  d <- data.frame(hh = rep(seq_len(20), each = 2),
                  region = factor(sample(c("A", "B"), n, TRUE)),
                  y = stats::rnorm(n), pw = 1)
  d$pw[1] <- 2                                   # household 1 no longer uniform
  expect_error(
    weighting_spec(d, base_weights = pw) |>
      step_model_calibration(x_formula = ~ region,
                             models = list(y = y_model(y ~ region)),
                             population = d, cluster = "hh",
                             equal_within_cluster = TRUE) |>
      prep(),
    "one weight per cluster")
})

test_that("nonresponse-by-calibration (integrative) rejects non-uniform within-cluster weights", {
  set.seed(2)
  n <- 40
  d <- data.frame(hh = rep(seq_len(20), each = 2),
                  region = factor(sample(c("A", "B"), n, TRUE)),
                  resp = TRUE, pw = 1)
  d$pw[1] <- 2
  expect_error(
    weighting_spec(d, base_weights = pw) |>
      step_nonresponse(respondent = resp, method = "calibration", formula = ~ region,
                       cluster = "hh", equal_within_cluster = TRUE) |>
      prep(),
    "one weight per cluster")
})

# BUG-09a: the R-indicator must be evaluated in the step's captured environment,
# so a `respondent` expression that references a caller-environment object still
# works instead of silently returning NULL.
test_that("R-indicator survives a respondent expression using the caller environment", {
  set.seed(3)
  n <- 120
  ids_resp <- sample(seq_len(n), 80)                       # lives in this environment
  d <- data.frame(id = seq_len(n),
                  region = factor(sample(c("A", "B", "C"), n, TRUE)), pw = 10)
  fit <- weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = id %in% ids_resp, method = "weighting_class",
                     by = "region") |>
    prep()
  ri <- weightflow:::.r_indicator(fit)
  expect_false(is.null(ri))
  expect_true(is.finite(ri$R))
})

# BUG-10: the documented min_cell_n small-cell alert must fire for raking and
# post-stratification cells, not only for weighting classes.
test_that("min_cell_n alert fires for raking and post-stratification cells", {
  d <- data.frame(region = factor(c(rep("A", 100), rep("B", 3))), pw = 1)  # B tiny
  fit_rk <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(region = c(A = 100, B = 3))) |>
    prep(min_cell_n = 30)
  expect_true(any(grepl("fewer than", weighting_alerts(fit_rk))))

  fit_ps <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "poststratify",
                   totals = data.frame(region = c("A", "B"), Freq = c(100, 3)),
                   count = "Freq") |>
    prep(min_cell_n = 30)
  expect_true(any(grepl("fewer than", weighting_alerts(fit_ps))))
})
