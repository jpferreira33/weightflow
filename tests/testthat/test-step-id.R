# Stable step ids: every step gets a unique "<class>_<k>" id, shown in print()
# and usable to select a step in collect_step_detail(). Closes CR-11 (two steps
# of the same class are no longer indistinguishable).

test_that("steps get unique derived ids, resolvable in collect_step_detail()", {
  fit <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    step_calibrate(method = "raking",
                   margins = list(region = c(table(population$region)))) |>
    prep()
  ids <- vapply(fit$steps, function(s) s$id, character(1))
  expect_setequal(ids, c("nonresponse_1", "calibrate_1"))
  expect_equal(collect_step_detail(fit, step = "nonresponse_1"),
               collect_step_detail(fit, step = 1L))
  expect_error(collect_step_detail(fit, step = "no_such_id"), "No step with id")
})

test_that("two steps of the same class get distinct ids (CR-11)", {
  fit <- weighting_spec(sample_survey, base_weights = pw) |>
    step_trim(max_ratio = 5) |>
    step_trim(max_ratio = 3) |>
    prep()
  expect_setequal(vapply(fit$steps, function(s) s$id, character(1)),
                  c("trim_1", "trim_2"))
})

test_that("explicit id= is honoured, selectable, and must be unique", {
  fit <- weighting_spec(sample_survey, base_weights = pw) |>
    step_trim(max_ratio = 5, id = "trim_grueso") |>
    step_trim(max_ratio = 3, id = "trim_fino") |>
    prep()
  expect_setequal(vapply(fit$steps, function(s) s$id, character(1)),
                  c("trim_grueso", "trim_fino"))
  expect_equal(collect_step_detail(fit, step = "trim_fino"),
               collect_step_detail(fit, step = 2L))
  expect_error(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_trim(max_ratio = 5, id = "t") |>
      step_trim(max_ratio = 3, id = "t"),
    "already exists")
})
