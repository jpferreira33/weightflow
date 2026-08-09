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

test_that("design_effect() accepts a prepped recipe, not only a weight vector", {
  d <- data.frame(pw = runif(80, 1, 2), resp = rbinom(80, 1, .7) == 1,
                  x = factor(sample(c("A", "B"), 80, TRUE)))
  rec <- suppressMessages(prep(weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  de_spec <- design_effect(rec)
  de_vec  <- design_effect(rec$final_weight)
  expect_identical(de_spec, de_vec)
})
