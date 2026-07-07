# R-indicator (representativity of response): an internal diagnostic surfaced by
# summary() and report_weighting() when the recipe adjusts for nonresponse.

test_that(".r_indicator is NULL without a nonresponse step", {
  f <- weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(region = c(table(population$region)))) |>
    prep()
  expect_null(.r_indicator(f))
})

test_that(".r_indicator returns a sensible R and partials with a nonresponse step", {
  f <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class",
                     by = c("region", "sex")) |>
    prep()
  ri <- .r_indicator(f)

  expect_false(is.null(ri))
  expect_true(is.finite(ri$R) && ri$R <= 1)
  expect_true(ri$S >= 0)
  expect_setequal(ri$partials$variable, c("region", "sex"))
  expect_true(all(ri$partials$partial_R >= 0))
  # a single-variable (unconditional) partial cannot exceed the overall SD
  expect_true(all(ri$partials$partial_R <= ri$S + 1e-8))
})

test_that("summary() shows the R-indicator only when there is a nonresponse step", {
  f_nr <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class",
                     by = "region") |>
    prep()
  expect_output(summary(f_nr), "R-indicator")

  f_no <- weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(region = c(table(population$region)))) |>
    prep()
  expect_false(any(grepl("R-indicator", capture.output(summary(f_no)))))
})
