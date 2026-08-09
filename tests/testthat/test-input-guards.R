# Guards for natural misuse: empty data, clobbering a user's .weight column,
# and passing a prepped recipe where a weight vector is expected.

test_that("weighting_spec() rejects a 0-row data frame", {
  d <- data.frame(pw = numeric(0))
  expect_error(weighting_spec(d, base_weights = pw), "0 rows")
})

test_that("collect_weights() warns when it overwrites an existing weight column", {
  d <- data.frame(pw = runif(50, 1, 2), .weight = 1, resp = rbinom(50, 1, .7) == 1,
                  x = factor(sample(c("A", "B"), 50, TRUE)))
  rec <- suppressMessages(prep(weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  expect_warning(collect_weights(rec), "overwritten")
  # a different output name does not warn
  expect_warning(collect_weights(rec, weight_name = ".w2"), NA)
})

test_that("base weights must be finite (Inf / NaN rejected, not only NA)", {
  d <- data.frame(pw = c(1, 2, Inf, 4), x = 1:4)
  expect_error(weighting_spec(d, base_weights = pw), "finite")
})

test_that("a classic raking/poststrat margin level matching no active unit errors", {
  d <- sample_survey
  m <- c(table(d$region)); m["Zona99"] <- 1000        # phantom / typo level
  expect_error(prep(weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(region = m))),
    "match no active unit")
  expect_error(prep(weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "poststratify", margins = list(region = m))),
    "match no active unit")
})

test_that("a disposition flag with NA is an error, not a silent FALSE", {
  d <- data.frame(pw = runif(60, 1, 2), x = factor(sample(c("A", "B"), 60, TRUE)),
                  resp = rbinom(60, 1, .7), inelig = rbinom(60, 1, .1),
                  unk = rbinom(60, 1, .05))
  d$resp[3]   <- NA
  d$inelig[5] <- NA
  d$unk[7]    <- NA
  expect_error(prep(weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")),
    "missing value")
  expect_error(prep(weighting_spec(d, base_weights = pw) |>
    step_drop_ineligible(ineligible = inelig)), "missing value")
  expect_error(prep(weighting_spec(d, base_weights = pw) |>
    step_unknown_eligibility(unknown = unk)), "missing value")
})

test_that("design_effect() accepts a prepped recipe, not only a weight vector", {
  d <- data.frame(pw = runif(80, 1, 2), resp = rbinom(80, 1, .7) == 1,
                  x = factor(sample(c("A", "B"), 80, TRUE)))
  rec <- suppressMessages(prep(weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  de_spec <- design_effect(rec)
  de_vec  <- design_effect(rec$final_weight)
  expect_identical(de_spec, de_vec)
})
