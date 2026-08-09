# A numeric category (e.g. age) in a tidy counts table must appear in the report
# in natural numeric order (2, 10, 20), not lexicographic ("10", "2", "20").
# The string keys used for matching are unchanged; only the display order is
# fixed, so the calibrated weights are identical either way.

test_that("tidy poststratify orders a numeric category naturally in the diagnostics", {
  set.seed(1); n <- 400L
  d   <- data.frame(age = sample(c(2, 10, 20), n, TRUE), pw = runif(n, 1, 2))
  tot <- data.frame(age = c(2, 10, 20), n = c(1000, 1000, 1000))
  fit <- prep(weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "poststratify", totals = tot, count = "n"))
  cat <- fit$steps[[1]]$diagnostics$category
  expect_identical(cat, c("2", "10", "20"))          # numeric, not "10","2","20"
  # calibration still hits the targets exactly
  w <- collect_weights(fit)$.weight
  expect_equal(as.numeric(tapply(w, d$age, sum)), c(1000, 1000, 1000), tolerance = 1e-6)
})

test_that("tidy raking orders a numeric margin naturally too", {
  set.seed(2); n <- 600L
  d   <- data.frame(age = sample(c(3, 12, 45), n, TRUE),
                    sex = sample(c("F", "M"), n, TRUE), pw = runif(n, 1, 2))
  tot <- list(age = data.frame(age = c(3, 12, 45), n = c(2000, 2000, 2000)),
              sex = data.frame(sex = c("F", "M"), n = c(3000, 3000)))
  fit <- prep(weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "raking", totals = tot, count = "n"))
  age_cat <- fit$steps[[1]]$diagnostics$category[
    fit$steps[[1]]$diagnostics$variable == "age"]
  expect_identical(age_cat, c("3", "12", "45"))
})
