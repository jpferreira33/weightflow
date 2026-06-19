test_that("step_trim_weights respects the floor of 1 and preserves the total", {
  set.seed(3)
  n   <- 300
  dat <- data.frame(pw = c(runif(n - 5, 1, 10), 80, 90, 100, 0.5, 0.7))
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_trim_weights(lower = 1, upper = NULL, strict = TRUE) |>
    prep()
  w0 <- fitted$history[["base"]]
  w1 <- fitted$final_weight
  expect_true(all(w1 >= 1 - 1e-8))                  # no weight below the floor
  expect_equal(sum(w1), sum(w0), tolerance = 1e-6)  # total preserved
})

test_that("step_rescale to 'n' makes the weights sum to the active count", {
  set.seed(5)
  n   <- 150
  dat <- data.frame(pw = runif(n, 1, 9))
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_rescale(to = "n") |>
    prep()
  w <- fitted$final_weight
  expect_equal(sum(w), n, tolerance = 1e-8)
  expect_equal(mean(w), 1, tolerance = 1e-8)
})

test_that("step_rescale to 'total' makes the weights sum to the target", {
  set.seed(6)
  dat <- data.frame(pw = runif(120, 1, 9))
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_rescale(to = "total", total = 1e6) |>
    prep()
  expect_equal(sum(fitted$final_weight), 1e6, tolerance = 1e-3)
})

test_that("design_effect equals 1 for equal weights", {
  de <- design_effect(rep(2, 100))
  expect_equal(de$deff,  1,   tolerance = 1e-8)
  expect_equal(de$n_eff, 100, tolerance = 1e-8)
})

test_that("design_effect rises above 1 for unequal weights", {
  expect_gt(design_effect(c(rep(1, 90), rep(20, 10)))$deff, 1)
})
