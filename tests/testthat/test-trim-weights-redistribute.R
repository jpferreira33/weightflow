# step_trim_weights(): redistribution mode and negative-weight flooring.

test_that("step_trim_weights floors negative weights (bug fix)", {
  # Unbounded linear calibration to a small total forces a negative weight on the
  # high-x unit. A lower floor of 1 must raise it (previously w > 0 skipped it).
  set.seed(1)
  n <- 50
  d <- data.frame(x = c(rep(1, n), 30), pw = rep(5, n + 1))

  raw <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ 0 + x, totals = c(x = 100)) |>
    prep()
  w_raw <- collect_weights(raw, drop_zero = FALSE)$.weight
  expect_true(min(w_raw) < 0)                 # the calibration really produces a negative

  trimmed <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ 0 + x, totals = c(x = 100)) |>
    step_trim_weights(lower = 1, upper = Inf, redistribute = "uniform", strict = TRUE) |>
    prep()
  w_trim <- collect_weights(trimmed, drop_zero = FALSE)$.weight
  expect_true(min(w_trim) >= 1 - 1e-8)        # negative floored to 1, none left below
})

test_that("dropped units (weight 0) are not resurrected by trimming", {
  set.seed(2)
  d <- data.frame(resp = c(TRUE, TRUE, FALSE, TRUE), by = c("a", "a", "a", "b"),
                  pw = c(2, 2, 2, 2))
  w <- weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "by") |>
    step_trim_weights(lower = 1, upper = Inf, redistribute = "uniform") |>
    prep()
  w <- collect_weights(w, drop_zero = FALSE)$.weight
  expect_equal(w[3], 0)                        # the nonrespondent stays dropped, not floored to 1
})

test_that("redistribute = 'uniform' reproduces survey::trimWeights", {
  skip_if_not_installed("survey")
  set.seed(3)
  n <- 200
  d <- data.frame(pw = c(runif(n - 3, 1, 5), 40, 45, 50))   # all >= 1, a few large

  w_wf <- weighting_spec(d, base_weights = pw) |>
    step_trim_weights(upper = 30, redistribute = "uniform", strict = TRUE) |>
    prep()
  w_wf <- collect_weights(w_wf, drop_zero = FALSE)$.weight

  des  <- survey::svydesign(ids = ~ 1, weights = ~ pw, data = d)
  w_sv <- as.numeric(weights(survey::trimWeights(des, upper = 30, strict = TRUE)))

  expect_equal(w_wf, w_sv, tolerance = 1e-8)
})

test_that("both redistribution modes preserve the total", {
  set.seed(4)
  d <- data.frame(pw = c(runif(100, 1, 4), 50, 60))
  for (r in c("proportional", "uniform")) {
    w <- weighting_spec(d, base_weights = pw) |>
      step_trim_weights(upper = 20, redistribute = r, strict = TRUE) |>
      prep()
    w <- collect_weights(w, drop_zero = FALSE)$.weight
    expect_equal(sum(w), sum(d$pw), tolerance = 1e-6, info = r)
    expect_true(max(w) <= 20 + 1e-8, info = r)
  }
})
