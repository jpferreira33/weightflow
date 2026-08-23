# Regression tests for the medium-severity audit batch (BUG-18/20/21/22/24).
# BUG-18 (equal-split redistribution when the free-set weight sum is not positive)
# is a defensive guard that needs mid-cascade negative weights inside the trim
# band to exercise; it is verified by inspection and covered indirectly by the
# mass-preservation invariants elsewhere.

# BUG-20: a literal "(missing)" category alongside real NAs must not collide.
test_that("domain_summary tolerates a literal (missing) category plus NAs", {
  d <- data.frame(region = c("A", "B", "(missing)", NA, "A", "B"), pw = 1)
  fit <- weighting_spec(d, base_weights = pw) |> prep()
  ds  <- expect_no_error(domain_summary(fit, by = "region"))
  labs <- unique(as.character(ds$domain))
  expect_true("(missing)" %in% labs)                 # the real category is kept
  expect_gte(length(grep("missing", labs)), 2L)      # NAs get a distinct label
})

# BUG-24: method = "linear" must reject a single data frame as `totals` up front.
test_that("step_calibrate(linear) rejects a single data frame as totals", {
  sp <- weighting_spec(data.frame(g = factor(c("A", "B")), pw = 1), base_weights = pw)
  expect_error(
    step_calibrate(sp, method = "linear", formula = ~ g,
                   totals = data.frame(g = c("A", "B"), Freq = c(1, 1)), count = "Freq"),
    "does not take a single data frame")
})

# BUG-21/22: report closing/labels are honest.
test_that("report closing is honest without a calibration step, and pluralises correctly", {
  fit <- weighting_spec(sample_survey, base_weights = pw) |>
    step_trim(max_ratio = 3) |>                       # a single, non-calibration step
    prep()
  f <- tempfile(fileext = ".html")
  report_weighting(fit, file = f, open = FALSE, lang = "en")
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_false(grepl("calibration constraints preserved", html, fixed = TRUE))  # BUG-21a
  expect_false(grepl("1 steps", html, fixed = TRUE))                            # BUG-22 singular
})
