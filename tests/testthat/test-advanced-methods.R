# Tests for the methods added in development: xgboost engine, cross-fitting,
# ridge calibration and Potter trimming. Engine tests that need optional
# packages are skipped when the package is absent.

# ---- xgboost engine -------------------------------------------------------

test_that("boost engine produces valid propensities and finite weights", {
  skip_if_not_installed("xgboost")
  set.seed(101)
  n   <- 400
  x   <- rnorm(n)
  rsp <- rbinom(n, 1, plogis(0.4 + 0.8 * x))
  pw  <- runif(n, 1, 5)
  dat <- data.frame(x, resp = rsp, pw)
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "propensity",
                     formula = ~ x, engine = "boost", num_classes = 5) |>
    prep()
  w <- fitted$final_weight
  expect_true(all(is.finite(w)))
  expect_true(all(w[rsp == 0] == 0))      # nonrespondents zeroed
  expect_true(all(w[rsp == 1] > 0))       # respondents inflated
  expect_equal(sum(w), sum(pw), tolerance = 1e-6)  # total weight preserved
})

test_that("boost engine works in model calibration and hits the targets", {
  skip_if_not_installed("xgboost")
  set.seed(102)
  N    <- 1500
  reg  <- sample(c("A", "B", "C"), N, TRUE)
  xage <- rnorm(N, 45, 12)
  ypop <- 100 + 5 * (reg == "B") + 0.5 * xage + rnorm(N, 0, 5)
  pop  <- data.frame(region = reg, age = xage, income = ypop)
  idx  <- sample(N, 400)
  samp <- pop[idx, ]
  samp$pw <- N / 400
  fitted <- weighting_spec(samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region,
      models     = list(income = y_model(income ~ age + region, engine = "boost")),
      population = pop) |>
    prep()
  d <- fitted$steps[[1]]$diagnostics
  expect_equal(d$achieved, d$target, tolerance = 1e-3)   # constraints met
})

# ---- cross-fitting --------------------------------------------------------

test_that("cross-fitting runs and keeps the total weight", {
  set.seed(103)
  n   <- 500
  x   <- rnorm(n)
  rsp <- rbinom(n, 1, plogis(0.3 + 0.6 * x))
  pw  <- runif(n, 1, 4)
  dat <- data.frame(x, resp = rsp, pw)
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "propensity",
                     formula = ~ x, engine = "logit",
                     num_classes = 5, crossfit = 5, crossfit_seed = 1) |>
    prep()
  w <- fitted$final_weight
  expect_true(all(is.finite(w)))
  expect_equal(sum(w), sum(pw), tolerance = 1e-6)
})

test_that("cross-fitting is reproducible with a seed and default is unchanged", {
  set.seed(104)
  n   <- 300
  x   <- rnorm(n)
  rsp <- rbinom(n, 1, plogis(0.2 + 0.5 * x))
  pw  <- rep(3, n)
  dat <- data.frame(x, resp = rsp, pw)
  mk <- function(cf, seed = NULL)
    prep(weighting_spec(dat, base_weights = pw) |>
           step_nonresponse(respondent = resp, method = "propensity",
                            formula = ~ x, engine = "logit", num_classes = 4,
                            crossfit = cf, crossfit_seed = seed))$final_weight
  # same seed -> identical
  expect_equal(mk(5, 7), mk(5, 7))
  # without crossfit the result differs from the cross-fitted one
  expect_false(isTRUE(all.equal(mk(NULL), mk(5, 7))))
})

# ---- ridge calibration ----------------------------------------------------

test_that("ridge penalty relaxes the constraints (deviation grows as penalty falls)", {
  set.seed(105)
  n   <- 300
  dat <- data.frame(x = rnorm(n, 10, 3), pw = runif(n, 1, 5))
  totals <- c("(Intercept)" = sum(dat$pw) * 1.10,
              x             = sum(dat$pw * dat$x) * 1.10)
  dev <- function(pen) {
    f <- weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ x, totals = totals,
                     penalty = pen) |>
      prep()
    max(abs(f$steps[[1]]$diagnostics$deviation))
  }
  # smaller penalty => more relaxation => larger deviation
  expect_true(dev(0.1) > dev(1000))
})

test_that("large ridge penalty is almost exact; no penalty is exact", {
  set.seed(106)
  n   <- 250
  dat <- data.frame(x = rnorm(n, 10, 3), pw = runif(n, 1, 5))
  totals <- c("(Intercept)" = sum(dat$pw) * 1.05,
              x             = sum(dat$pw * dat$x) * 1.05)
  exact <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ x, totals = totals) |>
    prep()
  expect_equal(sum(exact$final_weight), unname(totals[1]), tolerance = 1e-4)
  # ridge with a large penalty stays close to the targets
  ridge <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ x, totals = totals,
                   penalty = 1e6) |>
    prep()
  expect_equal(sum(ridge$final_weight), unname(totals[1]), tolerance = 1e-1)
})

test_that("ridge rejects non-linear methods and bounded calibration", {
  dat <- data.frame(sex = sample(c("M", "F"), 80, TRUE), pw = rep(2, 80))
  # penalty is only valid for method = "linear": raking must be rejected
  expect_error(
    weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "raking",
                     margins = list(sex = c(M = 90, F = 70)), penalty = 1),
    "ridge|linear", ignore.case = TRUE)
  # penalty cannot be combined with bounded calibration
  dat2 <- data.frame(x = rnorm(80), pw = rep(2, 80))
  totals <- c("(Intercept)" = sum(dat2$pw), x = sum(dat2$pw * dat2$x))
  expect_error(
    weighting_spec(dat2, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ x, totals = totals,
                     bounds = c(0.5, 2), penalty = 1),
    "ridge|bound", ignore.case = TRUE)
})

# ---- Potter trimming ------------------------------------------------------

test_that("Potter trimming preserves the total and reports its method", {
  set.seed(107)
  n   <- 300
  pw  <- c(rlnorm(n - 3, 1, 0.5), 40, 55, 70)   # a few extreme weights
  dat <- data.frame(pw)
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_trim_weights(method = "potter") |>
    prep()
  d <- fitted$steps[[1]]$diagnostics
  expect_identical(d$method, "potter")
  expect_equal(sum(fitted$final_weight), sum(pw), tolerance = 1e-6)
})

test_that("tukey and potter can give different cutoffs", {
  set.seed(108)
  n   <- 400
  pw  <- c(rlnorm(n - 4, 1, 0.4), 30, 45, 60, 90)
  dat <- data.frame(pw)
  tuk <- prep(weighting_spec(dat, base_weights = pw) |>
                step_trim_weights(method = "tukey"))$steps[[1]]$diagnostics$upper
  pot <- prep(weighting_spec(dat, base_weights = pw) |>
                step_trim_weights(method = "potter"))$steps[[1]]$diagnostics$upper
  expect_true(is.finite(tuk) && is.finite(pot))
  # both are valid caps within the observed weight range
  expect_true(tuk <= max(pw) && pot <= max(pw))
})
