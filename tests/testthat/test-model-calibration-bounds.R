# Bounds on step_model_calibration(), mirroring step_calibrate(method = "linear").

make_mc_data <- function(N = 3000, n = 500, seed = 1) {
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

test_that("unbounded model calibration still meets the constraints (backward compatible)", {
  d <- make_mc_data(seed = 11)
  fitted <- weighting_spec(d$samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region,
      models     = list(income = y_model(income ~ age + region, engine = "glm")),
      population = d$pop) |>
    prep()
  diag <- fitted$steps[[1]]$diagnostics
  expect_equal(diag$achieved, diag$target, tolerance = 1e-3)   # constraints exact
  expect_true(isTRUE(attr(diag, "converged")))
})

test_that("bounds keep the calibration g-factor within [L, U]", {
  d <- make_mc_data(seed = 12)
  L <- 0.7; U <- 1.3
  fitted <- weighting_spec(d$samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region,
      models     = list(income = y_model(income ~ age + region, engine = "glm")),
      population = d$pop, bounds = c(L, U)) |>
    prep()
  w <- fitted$final_weight
  g <- w / d$samp$pw               # base weight is the constant N/n
  active <- w > 0
  expect_true(all(g[active] >= L - 1e-6 & g[active] <= U + 1e-6))
  expect_true(all(w[active] > 0))
})

test_that("calfun = 'logit' with bounds runs and respects the bounds", {
  d <- make_mc_data(seed = 15)
  fitted <- weighting_spec(d$samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region,
      models     = list(income = y_model(income ~ age, engine = "glm")),
      population = d$pop, calfun = "logit", bounds = c(0.5, 2)) |>
    prep()
  w <- fitted$final_weight
  g <- w / d$samp$pw
  active <- w > 0
  expect_true(all(g[active] >= 0.5 - 1e-6 & g[active] <= 2 + 1e-6))
})

test_that("bounds are validated as in step_calibrate", {
  d <- make_mc_data(seed = 13)
  mk <- function(...) weighting_spec(d$samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region,
      models     = list(income = y_model(income ~ age, engine = "glm")),
      population = d$pop, ...)
  expect_error(mk(bounds = c(1.1, 1.5)), "L < 1 < U")          # L >= 1
  expect_error(mk(bounds = c(0.5, 0.9)), "L < 1 < U")          # U <= 1
  expect_error(mk(bounds = 0.5),         "two finite numbers") # wrong shape
  expect_error(mk(calfun = "logit"),     "requires")           # logit needs bounds
})
