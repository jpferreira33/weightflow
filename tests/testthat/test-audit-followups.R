# Follow-ups from the independent re-audit of the fixes.

# CR-2: supplying both `margins` and `totals` used to drop `margins` silently.
test_that("step_calibrate warns when both margins and totals are supplied", {
  sp <- weighting_spec(data.frame(region = factor(c("A", "B")), pw = 1), base_weights = pw)
  expect_warning(
    step_calibrate(sp, method = "raking",
                   margins = list(region = c(A = 1, B = 1)),
                   totals  = list(region = data.frame(region = c("A", "B"), Freq = c(1, 1))),
                   count   = "Freq"),
    "takes precedence")
})

# BUG-04 companion: NA in a y_model PREDICTOR on the population frame must error,
# not reach the model engine (the earlier guard only covered x_formula).
test_that("step_model_calibration guards NA in a y_model predictor on the frame", {
  set.seed(1)
  samp <- data.frame(region = factor(sample(c("A", "B"), 60, TRUE)),
                     age = stats::rnorm(60), y = stats::rnorm(60), pw = 10)
  pop  <- data.frame(region = factor(sample(c("A", "B"), 100, TRUE)),
                     age = c(stats::rnorm(99), NA))         # NA in a predictor, x_formula clean
  expect_error(
    weighting_spec(samp, base_weights = pw) |>
      step_model_calibration(x_formula = ~ region,
                             models = list(y = y_model(y ~ age)),
                             population = pop) |>
      prep(),
    "y_model predictor")
})
