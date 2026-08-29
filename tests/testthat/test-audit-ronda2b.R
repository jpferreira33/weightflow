# Regression tests for the ronda-2 MEDIUM/COSMETIC findings (Tanda 2 + 3): mostly
# constructor validation that used to accept malformed input and crash later.

sp <- weighting_spec(sample_survey, base_weights = pw)

# 2A-07: a vector-valued statistic must still work (the failed-replicate guard
# rewrote the apply loop; check the matrix path is intact).
test_that("bootstrap_estimate() supports a vector-valued statistic (2A-07)", {
  boot <- suppressWarnings(
    bootstrap_weights(weighting_spec(sample_survey, base_weights = pw),
                      replicates = 20, strata = "region", psu = "psu",
                      seed = 1, progress = FALSE))
  est <- bootstrap_estimate(boot, function(w, d)
    c(n = sum(w), sx = sum(w * (d$sex == "M"))))
  expect_equal(nrow(est), 2L)
  expect_true(all(is.finite(est$se)))
})

# 2A-08: raking with a single data frame is a joint table -> must error and point
# to post-stratification (parity with the linear/GREG constructor).
test_that("step_calibrate(method='raking') rejects a single data frame (2A-08)", {
  tab <- data.frame(region = c("North", "South"), Freq = c(10, 10))
  expect_error(step_calibrate(sp, method = "raking", totals = tab, count = "Freq"),
               "LIST of data frames|poststratify")
})

# 2A-09: nonresponse-by-calibration must block penalty with a non-Euclidean
# distance, as step_calibrate() does.
test_that("nonresponse calibration rejects penalty + raking distance (2A-09)", {
  expect_error(
    step_nonresponse(sp, respondent = responded, method = "calibration",
                     formula = ~ region, calfun = "raking", penalty = 1),
    "linear|Euclidean")
})

# 2A-10: trimming bounds must be numeric (no lexicographic comparison).
test_that("trimming bounds must be numeric (2A-10)", {
  expect_error(step_trim_weights(sp, lower = "5"), "single number")
  expect_error(step_trim_calibrated(sp, ~ region, lower = "5", upper = 13.5), "numeric")
  expect_error(step_trim_weights(sp, lower = 6, upper = 5), "strictly below")
})

# 2A-15/2A-16: flags given as strings and malformed counts / ids must error at
# build time, not crash later.
test_that("constructor validation catches malformed flags, counts and ids (2A-15/16)", {
  expect_error(step_calibrate(sp, method = "raking",
                              margins = list(region = c(North = 1)),
                              equal_within_cluster = "TRUE"),
               "TRUE or FALSE")
  expect_error(step_nonresponse(sp, respondent = responded, method = "propensity",
                                formula = ~ region, crossfit = Inf),
               "integer >= 2")
  expect_error(step_nonresponse(sp, respondent = responded, method = "propensity",
                                formula = ~ region, num_classes = 2.5),
               "integer >= 2")
  expect_error(step_calibrate(sp, method = "raking",
                              margins = list(region = c(North = 1)),
                              id = NA_character_),
               "non-empty string")
})

# y_model() must be a two-sided formula, and models must be y_model() results.
test_that("y_model() requires a two-sided formula (2A-16)", {
  expect_error(y_model(~ age), "must be a formula")
})

# 2A-13: a reference_sample() with an unused factor level (e.g. a reference subset
# by region) must not crash raking; a level with zero reference weight errors clearly.
test_that("reference_sample raking drops empty levels and guards zero totals (2A-13)", {
  set.seed(1)
  samp <- data.frame(region = factor(sample(c("A", "B"), 100, TRUE), levels = c("A", "B", "C")),
                     pw = 1)
  ref  <- data.frame(region = factor(sample(c("A", "B"), 200, TRUE), levels = c("A", "B", "C")),
                     w = 5)                                   # level C is empty
  fit <- suppressWarnings(
    weighting_spec(samp, base_weights = pw) |>
      step_calibrate(method = "raking", formula = ~ region,
                     population = reference_sample(ref, "w")) |>
      prep())
  expect_s3_class(fit, "prepped_weighting_spec")
})

# 2A-12: a blank PSU id must be rejected before resampling (all replicates would
# otherwise fail with a misleading message).
test_that("bootstrap rejects a blank PSU id (2A-12)", {
  d <- sample_survey
  d$psu <- as.character(d$psu); d$psu[1] <- ""
  expect_error(
    bootstrap_weights(weighting_spec(d, base_weights = pw), replicates = 10,
                      strata = "region", psu = "psu", seed = 1, progress = FALSE),
    "blank")
})
