# step_trim_calibrated() after step_model_calibration() must preserve the model
# prediction totals (T_mu), not only the X margins.

make_tc_data <- function(N = 3000, n = 500, seed = 1) {
  set.seed(seed)
  reg  <- sample(c("A", "B", "C"), N, TRUE)
  xage <- rnorm(N, 45, 12)
  ypop <- 100 + 5 * (reg == "B") + 0.5 * xage + rnorm(N, 0, 5)
  pop  <- data.frame(region = reg, age = xage, income = ypop)
  idx  <- sample(N, n)
  samp <- pop[idx, ]
  samp$pw <- N / n
  list(pop = pop, samp = samp)
}

test_that("trim after model calibration preserves the model totals, not only X", {
  d <- make_tc_data(seed = 21)
  fitted <- weighting_spec(d$samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region,
      models     = list(income = y_model(income ~ age + region, engine = "glm")),
      population = d$pop) |>
    step_trim_calibrated(formula = ~ region, lower = 2, upper = 15) |>
    prep()

  diag_trim <- fitted$steps[[2]]$diagnostics
  # the model-prediction total is now a preserved constraint of the trim
  expect_true("income" %in% diag_trim$variable)
  expect_equal(diag_trim$achieved, diag_trim$target, tolerance = 1e-2)

  w <- fitted$final_weight
  active <- w > 0
  expect_true(all(w[active] >= 2 - 1e-6 & w[active] <= 15 + 1e-6))
  # the internal predictions attribute must not leak into the user weight
  expect_null(attr(w, "wf_modelcal"))
})

test_that("trim after model calibration keeps the achieved income total at its target", {
  d <- make_tc_data(seed = 23)
  fitted <- weighting_spec(d$samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region,
      models     = list(income = y_model(income ~ age + region, engine = "glm")),
      population = d$pop) |>
    step_trim_calibrated(formula = ~ region, lower = 2, upper = 15) |>
    prep()
  diag_trim <- fitted$steps[[2]]$diagnostics
  inc <- diag_trim[diag_trim$variable == "income", ]
  expect_equal(inc$achieved, inc$target, tolerance = 1e-2)
})

test_that("trim after plain step_calibrate is unchanged (no model constraint)", {
  d <- make_tc_data(seed = 22)
  fitted <- weighting_spec(d$samp, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ region,
                   totals = colSums(model.matrix(~ region, d$pop))) |>
    step_trim_calibrated(formula = ~ region, lower = 2, upper = 15) |>
    prep()
  diag_trim <- fitted$steps[[2]]$diagnostics
  expect_false("income" %in% diag_trim$variable)   # X-only, as before
  w <- fitted$final_weight
  active <- w > 0
  expect_true(all(w[active] >= 2 - 1e-6 & w[active] <= 15 + 1e-6))
})
