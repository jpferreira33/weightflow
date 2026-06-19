test_that("step_assert errors when a threshold is crossed (on_fail = 'error')", {
  set.seed(7)
  dat <- data.frame(pw = c(rep(1, 90), rep(50, 10)))   # very unequal => high deff
  recipe <- weighting_spec(dat, base_weights = pw) |>
    step_assert(max_deff = 1.01, on_fail = "error")
  expect_error(prep(recipe), "Assertion")
})

test_that("step_assert passes (no error) when thresholds are met", {
  set.seed(8)
  dat <- data.frame(pw = rep(3, 100))                  # equal weights => deff = 1
  recipe <- weighting_spec(dat, base_weights = pw) |>
    step_assert(max_deff = 1.5, min_n_eff = 50, on_fail = "error")
  expect_no_error(prep(recipe))
})

test_that("step_assert does not modify the weights", {
  set.seed(9)
  dat <- data.frame(pw = runif(100, 1, 5))
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_assert(max_deff = 99, on_fail = "warning") |>
    prep()
  expect_equal(fitted$final_weight, fitted$history[["base"]])
})
