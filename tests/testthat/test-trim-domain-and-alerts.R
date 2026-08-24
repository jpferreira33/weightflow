# Audit hardening:
#  (1) step_trim() validates the domain of max_ratio / min_ratio at construction
#      time, branching on `reference` (a multiplier for base/median, an absolute
#      cap for value). Out-of-domain values used to pass silently and produce
#      negative or empty weight vectors.
#  (2) Every warning a step raises inside apply_step() is captured into $alerts,
#      readable with weighting_alerts() / has_alerts(), even under
#      suppressWarnings(); the warning still propagates as before.

test_that("step_trim() rejects out-of-domain max_ratio (base/median = multiplier)", {
  sp <- weighting_spec(sample_survey, base_weights = pw)
  expect_error(step_trim(sp, max_ratio = -2),   "greater than 1")
  expect_error(step_trim(sp, max_ratio = 0),    "greater than 1")
  expect_error(step_trim(sp, max_ratio = 0.5),  "greater than 1")
  expect_error(step_trim(sp, max_ratio = c(2, 3)), "single finite")
  expect_error(step_trim(sp, max_ratio = Inf),  "single finite")
  expect_error(step_trim(sp, max_ratio = NA_real_), "single finite")
})

test_that("step_trim() reference = 'value' is an absolute cap (> 0, may be < 1)", {
  sp <- weighting_spec(sample_survey, base_weights = pw)
  expect_error(step_trim(sp, max_ratio = 0, reference = "value"),  "greater than 0")
  expect_error(step_trim(sp, max_ratio = -1, reference = "value"), "greater than 0")
  # a cap below 1 is legitimate in absolute units
  expect_s3_class(step_trim(sp, max_ratio = 0.5, reference = "value"), "weighting_spec")
})

test_that("step_trim() rejects non-positive min_ratio, accepts a valid trim", {
  sp <- weighting_spec(sample_survey, base_weights = pw)
  expect_error(step_trim(sp, max_ratio = 3, min_ratio = -1), "greater than 0")
  expect_error(step_trim(sp, max_ratio = 3, min_ratio = 0),  "greater than 0")
  expect_s3_class(step_trim(sp, max_ratio = 3), "weighting_spec")
  expect_s3_class(step_trim(sp, max_ratio = 3, min_ratio = 0.5), "weighting_spec")
})

test_that("weighting_alerts()/has_alerts() are empty on a clean recipe", {
  fit <- weighting_spec(sample_survey, base_weights = pw) |> prep()   # no steps
  expect_identical(weighting_alerts(fit), character(0))
  expect_false(has_alerts(fit))
})

test_that("weighting_alerts() errors on a non-prepped object", {
  expect_error(weighting_alerts(weighting_spec(sample_survey, base_weights = pw)),
               "prepped")
})

test_that("a warning raised inside a step is captured in $alerts and still propagates", {
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_assert(min_n_eff = 1e9, on_fail = "warning")   # impossible -> warns
  # the warning still surfaces (behaviour unchanged)
  expect_warning(prep(spec), "Assertion")
  # and it is recorded in the structured channel, readable under suppressWarnings()
  fit <- suppressWarnings(prep(spec))
  expect_true(has_alerts(fit))
  expect_true(any(grepl("Assertion", weighting_alerts(fit), fixed = TRUE)))
  expect_true(any(grepl("[step_assert]", weighting_alerts(fit), fixed = TRUE)))
})
