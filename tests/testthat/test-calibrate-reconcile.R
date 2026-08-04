# Tidy control totals that do not sum to a common N are reconciled to the
# LARGEST margin (others rescaled proportionally): calibration always closes,
# it is reported via message() (never fatal, even under options(warn = 2)), and
# the note is carried into the step alerts so report_weighting() surfaces it.

test_that("raking (tidy) reconciles margins with different Ns to the largest", {
  set.seed(11)
  n   <- 600
  dat <- data.frame(region = sample(c("N", "S", "E"), n, TRUE),
                    sex    = sample(c("M", "F"), n, TRUE),
                    pw     = runif(n, 1, 5))
  reg <- data.frame(region = c("N", "S", "E"), Freq = c(4000, 3000, 3000)) # 10000
  sx  <- data.frame(sex = c("M", "F"), Freq = c(4900, 5000))               #  9900

  expect_message(
    fit <- weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "raking", totals = list(reg, sx), count = "Freq") |>
      prep(),
    "did not all sum to the same population size")

  w <- fit$final_weight
  expect_equal(sum(w), 10000, tolerance = 1e-3)                 # closes to largest N
  for (r in c("N", "S", "E"))
    expect_equal(sum(w[dat$region == r]),
                 reg$Freq[reg$region == r], tolerance = 1e-2)
  expect_equal(sum(w[dat$sex == "M"]), 4900 * 10000 / 9900, tolerance = 5e-2)

  # the reconciliation is carried into the step alerts (so the report shows it)
  al <- unlist(lapply(fit$steps, function(s) s$alerts))
  expect_true(any(grepl("did not all sum to the same population size", al)))
})

test_that("reconciliation is a message, not a warning (safe under warn = 2)", {
  set.seed(21)
  n   <- 300
  dat <- data.frame(region = sample(c("N", "S"), n, TRUE),
                    sex    = sample(c("M", "F"), n, TRUE),
                    pw     = runif(n, 1, 5))
  reg <- data.frame(region = c("N", "S"), Freq = c(6000, 4000))  # 10000
  sx  <- data.frame(sex = c("M", "F"), Freq = c(4900, 5000))     #  9900
  expect_no_warning(
    weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "raking", totals = list(reg, sx), count = "Freq") |>
      prep())
})

test_that("linear (tidy) reconciles margins with different Ns to the largest", {
  set.seed(13)
  n   <- 600
  dat <- data.frame(region = sample(c("N", "S", "E"), n, TRUE),
                    sex    = sample(c("M", "F"), n, TRUE),
                    pw     = runif(n, 1, 5))
  reg <- data.frame(region = c("N", "S", "E"), Freq = c(4000, 3000, 3000)) # 10000
  sx  <- data.frame(sex = c("M", "F"), Freq = c(4900, 5000))               #  9900

  expect_message(
    fit <- weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ region + sex,
                     totals = list(region = reg, sex = sx), count = "Freq") |>
      prep(),
    "did not all sum to the same population size")

  expect_equal(sum(fit$final_weight), 10000, tolerance = 1e-4)  # intercept = largest N
  al <- unlist(lapply(fit$steps, function(s) s$alerts))
  expect_true(any(grepl("did not all sum to the same population size", al)))
})

test_that("consistent margins reconcile silently and close to their common N", {
  set.seed(14)
  n   <- 400
  dat <- data.frame(region = sample(c("N", "S"), n, TRUE),
                    sex    = sample(c("M", "F"), n, TRUE),
                    pw     = runif(n, 1, 5))
  reg <- data.frame(region = c("N", "S"), Freq = c(6000, 4000))  # 10000
  sx  <- data.frame(sex = c("M", "F"), Freq = c(5500, 4500))     # 10000
  fit <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "raking", totals = list(reg, sx), count = "Freq") |>
    prep()
  expect_equal(sum(fit$final_weight), 10000, tolerance = 1e-4)
  al <- unlist(lapply(fit$steps, function(s) s$alerts))
  expect_false(any(grepl("did not all sum", al)))
})
