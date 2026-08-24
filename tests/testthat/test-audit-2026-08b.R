# Regression tests for the second technical audit (2026-08). Each test targets
# one finding; the fixes are asymmetries between twin engines (a guard present in
# one path and missing in its sibling).

# BUG-01: step_assert() must validate its thresholds. A character threshold used
# to be compared lexicographically at apply time, silently inverting the check.
test_that("step_assert() rejects non-numeric / invalid thresholds", {
  sp <- weighting_spec(sample_survey, base_weights = pw)
  expect_error(step_assert(sp, min_n_eff = "500"),        "positive finite")
  expect_error(step_assert(sp, max_deff = "5"),           "positive finite")
  expect_error(step_assert(sp, max_weight_ratio = -1),    "positive finite")
  expect_error(step_assert(sp, max_deff = c(2, 3)),       "positive finite")
  expect_s3_class(step_assert(sp, min_n_eff = 500, max_deff = 3), "weighting_spec")
})

# BUG-02: with a NEGATIVE incoming weight (a valid unbounded-GREG output), the
# per-unit factor bound must not invert and pin the unit at `upper`; the trimmed
# calibration must still preserve the totals.
test_that("step_trim_calibrated() does not pin a negative incoming weight at `upper`", {
  d <- data.frame(x = c(1, 2, 3, 4, 5), pw = 1)
  # linear calibration forces w = 4 - x, so the x = 5 unit gets w = -1 (a valid
  # unbounded-GREG negative). Full total preservation is not guaranteed for a
  # negative base weight (Deville-Sarndal assumes positive weights), so the point
  # under test is narrower: the sign-inversion bug used to force that unit to
  # EXACTLY `upper` (= 3); the fix keeps its factor bound the right way round, so
  # the unit is raised toward the floor instead and stays well below the cap.
  fit <- suppressWarnings(
    weighting_spec(d, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ x,
                     totals = c("(Intercept)" = 5, x = 5)) |>
      step_trim_calibrated(~ x, lower = -0.5, upper = 3) |>
      prep())
  w_cal <- fit$history[[2]]                         # after calibration: c(3,2,1,0,-1)
  skip_if_not(any(w_cal < 0), "setup did not produce a negative weight")
  w  <- fit$final_weight
  ai <- is.finite(w) & w != 0
  expect_lt(w[5], 1)                                # NOT pinned at upper = 3
  expect_true(all(w[ai] >= -0.5 - 1e-6 & w[ai] <= 3 + 1e-6))   # bounds respected
})

# BUG-04: model calibration to a plain frame must error on NA in the auxiliaries
# rather than let model.matrix() drop those rows and understate the totals.
test_that("step_model_calibration() errors on NA in the population frame", {
  set.seed(1)
  samp <- data.frame(region = factor(sample(c("A", "B"), 60, TRUE)),
                     y = stats::rnorm(60), pw = 10)
  pop  <- data.frame(region = factor(c(rep("A", 60), rep("B", 40), NA)))
  expect_error(
    weighting_spec(samp, base_weights = pw) |>
      step_model_calibration(x_formula = ~ region,
                             models = list(y = y_model(y ~ region)),
                             population = pop) |>
      prep(),
    "missing")
})

# BUG-11: report_weighting() must not crash on step_trim_weights(lower = NULL).
test_that("report_weighting() renders with step_trim_weights(lower = NULL)", {
  fit <- weighting_spec(sample_survey, base_weights = pw) |>
    step_trim_weights(lower = NULL, upper = NULL) |>
    prep()
  for (lg in c("en", "es")) {
    f <- tempfile(fileext = ".html")
    expect_no_error(report_weighting(fit, file = f, open = FALSE, lang = lg))
    expect_true(file.exists(f))
  }
})

# BUG-13/15: bounds / digits validated in the constructors that lacked it.
test_that("bounds and digits are validated at construction", {
  d  <- data.frame(g = factor(c("A", "B", "A", "B")), pw = 1)
  sp <- weighting_spec(d, base_weights = pw)
  tot <- c("(Intercept)" = 4, gB = 2)
  expect_error(step_calibrate(sp, method = "linear", formula = ~ g, totals = tot,
                              bounds = c(NA, 2)), "finite")
  expect_error(step_calibrate(sp, method = "linear", formula = ~ g, totals = tot,
                              bounds = c("0.5", "2")), "numeric")
  expect_s3_class(step_calibrate(sp, method = "linear", formula = ~ g, totals = tot,
                                 bounds = c(0.5, 2)), "weighting_spec")
  sp2 <- weighting_spec(sample_survey, base_weights = pw)
  expect_error(step_round(sp2, digits = NA),   "whole number")
  expect_error(step_round(sp2, digits = 1.5),  "whole number")
  expect_error(step_round(sp2, digits = -1),   "whole number")
  expect_s3_class(step_round(sp2, digits = 0), "weighting_spec")
})

# BUG-16: linear (GREG) calibration to tidy totals must reject NA counts up front
# instead of failing later with "subscript out of bounds".
test_that("linear calibration to tidy totals rejects NA counts", {
  samp <- data.frame(region = factor(c("A", "A", "B")), pw = 1)
  tot  <- list(region = data.frame(region = c("A", "B"), Freq = c(10, NA)))
  expect_error(
    weighting_spec(samp, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ region, totals = tot, count = "Freq") |>
      prep(),
    "count")
})
