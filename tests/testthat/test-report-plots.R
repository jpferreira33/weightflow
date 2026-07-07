# Cover the reporting/plotting/output surface (report.R and plots.R sit at 0%).

test_that("report_weighting builds a self-contained HTML file (with plots)", {
  rec <- prep(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
      step_calibrate(method = "raking",
                     margins = list(region = c(table(population$region)),
                                    sex    = c(table(population$sex)))))
  f <- tempfile(fileext = ".html")
  out <- report_weighting(rec, file = f, open = FALSE, plots = TRUE)
  expect_true(file.exists(f))
  html <- paste(readLines(f), collapse = "\n")
  expect_match(html, "weightflow")
  expect_match(html, "R-indicator")     # nonresponse present -> R-indicator section
  expect_gt(nchar(html), 2000)
})

test_that("report_weighting also runs without plots", {
  rec <- prep(weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "poststratify",
                   totals = as.data.frame(table(region = population$region)), count = "Freq"))
  f <- tempfile(fileext = ".html")
  report_weighting(rec, file = f, open = FALSE, plots = FALSE)
  expect_true(file.exists(f))
})

test_that("plot() runs for every type and weight_factors() returns something", {
  rec <- prep(weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region)))))
  grDevices::pdf(NULL); on.exit(grDevices::dev.off())
  expect_error(plot(rec, type = "all"), NA)
  expect_error(plot(rec, type = "factors"), NA)
  expect_error(plot(rec, type = "summary"), NA)
  wf <- weight_factors(rec)
  expect_false(is.null(wf))
})

test_that("collect_weights options and the print methods run", {
  rec <- prep(weighting_spec(sample_one, base_weights = pw) |>
    step_drop_ineligible(ineligible = ineligible) |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region)))))
  full <- collect_weights(rec, drop_zero = FALSE, keep_intermediate = TRUE)
  expect_equal(nrow(full), nrow(sample_one))
  zero <- collect_weights(rec, drop_zero = TRUE)
  expect_lt(nrow(zero), nrow(sample_one))          # ineligibles dropped
  expect_output(print(rec))
  expect_output(summary(rec))
})
