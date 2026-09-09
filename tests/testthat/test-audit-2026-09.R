# Regression tests for the 2026-09 audit fixes (validation-asymmetry class).

test_that("step_trim records mass loss and reports sum_before/after (TRIM-02)", {
  d <- data.frame(pw = c(10, 12, 15, 20))         # all above an absolute cap of 5
  expect_warning(
    f <- prep(weighting_spec(d, base_weights = pw) |>
                step_trim(max_ratio = 5, reference = "value")),
    "could not be redistributed")
  dg <- f$steps[[1]]$diagnostics
  expect_true(all(c("sum_before", "sum_after") %in% names(dg)))
  expect_equal(dg$sum_before, 57)
  expect_true(is.finite(attr(dg, "trim_rec")$unredist) &&
                attr(dg, "trim_rec")$unredist != 0)   # no longer NA
})

test_that("step_trim rejects min_ratio >= 1 for a relative reference (TRIM-03)", {
  sp <- weighting_spec(data.frame(pw = rep(1, 10)), base_weights = pw)
  expect_error(step_trim(sp, max_ratio = 5, min_ratio = 1.5, reference = "median"),
               "less than 1")
  # an absolute floor (reference = "value") above 1 is fine
  expect_no_error(step_trim(sp, max_ratio = 50, min_ratio = 1.5, reference = "value"))
})

test_that("prep alerts when a step empties the active sample (PREP-01)", {
  d <- data.frame(region = rep("A", 10), pw = rep(5, 10))
  f <- suppressWarnings(
    weighting_spec(d, base_weights = pw) |>
      step_drop_ineligible(pw > 0) |>              # marks every unit out of frame
      prep(warn = FALSE))
  expect_true(any(grepl("0 active units", weighting_alerts(f))))
})

test_that("a haven_labelled base weight yields a plain-numeric final weight (SPEC-01)", {
  skip_if_not_installed("haven")
  d <- data.frame(x = 1:5)
  d$w <- haven::labelled(c(1, 2, 3, 4, 5), labels = c(lo = 1, hi = 5))
  skip_if_not(is.numeric(d$w), "haven_labelled is not is.numeric in this version")
  f <- prep(weighting_spec(d, base_weights = w))
  expect_null(oldClass(f$final_weight))     # no haven_labelled class carried onto the weight
  expect_true(is.numeric(f$final_weight))
})

test_that("prep errors on a non-numeric base-weight column (PREP-02)", {
  # a recipe rebuilt outside weighting_spec() (as read_recipe does) with a character weight
  spec <- structure(list(data = data.frame(pw = c("1", "2", "3")),
                         base_weights = "pw", steps = list(), nonprob = FALSE),
                    class = "weighting_spec")
  expect_error(prep(spec), "must be numeric")
})
