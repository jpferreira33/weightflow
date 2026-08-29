# Regression tests for the SECOND round of the technical audit (2026-08, ronda 2).
# Each test targets one HIGH finding; the fixes are, again, guards present in one
# engine and missing in a sibling path.

# 2A-01: the integrative trimmed calibration assigns one weight per cluster, so
# the incoming weight must be uniform within the cluster. A non-uniform incoming
# weight used to violate the absolute bounds silently.
test_that("step_trim_calibrated() integrative rejects non-uniform within-cluster weights (2A-01)", {
  d <- data.frame(x = c(1, 2, 3, 4), hh = c("A", "A", "B", "B"),
                  pw = c(10, 20, 15, 15))       # household A is NOT uniform
  expect_error(
    suppressWarnings(
      weighting_spec(d, base_weights = pw) |>
        step_trim_calibrated(~ x, lower = 1, upper = 30,
                             cluster = "hh", equal_within_cluster = TRUE) |>
        prep()),
    "constant within")
})

# 2A-02: domain calibration with a continuous total given as a bare number would
# apply the same national total to every domain. It must error.
test_that("domain calibration rejects a scalar continuous total (2A-02)", {
  df      <- data.frame(dom = c("A", "A", "B", "B"), sex = c("F", "M", "F", "M"),
                        income = c(10, 20, 30, 40), pw = 1)
  sex_tab <- data.frame(dom = c("A", "A", "B", "B"), sex = c("F", "M", "F", "M"),
                        Freq = c(1, 1, 1, 1))
  expect_error(
    weighting_spec(df, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ sex + income,
                     totals = list(sex = sex_tab, income = 6000),
                     count = "Freq", by = "dom") |>
      prep(),
    "single number")
})

# 2A-03: the report's calibration drift must recompute `achieved` within each
# domain, not over the whole sample; otherwise a per-domain target is compared to
# the global total and reports spurious deviations of hundreds of percent.
test_that("calibration drift is computed within domain, not globally (2A-03)", {
  set.seed(1)
  n   <- 200
  df  <- data.frame(region = sample(c("A", "B"), n, TRUE),
                    sex    = sample(c("F", "M"), n, TRUE), pw = 1)
  tab <- as.data.frame(table(region = df$region, sex = df$sex))
  names(tab)[names(tab) == "Freq"] <- "Freq"
  fit <- suppressWarnings(
    weighting_spec(df, base_weights = pw) |>
      step_calibrate(method = "poststratify", totals = tab, count = "Freq",
                     by = "region") |>
      step_round() |>
      prep())
  drift <- weightflow:::.calibration_drift(fit, lang = "en")
  mx <- suppressWarnings(as.numeric(sub(".*deviation ([0-9.]+)%.*", "\\1", drift)))
  # rounding barely moves the totals, so within-domain drift is small; the bug
  # (global achieved vs domain target) would report ~100%.
  expect_true(is.finite(mx) && mx < 20)
})

# 2A-05: the tidy post-stratification path must guard NA in the cell variables;
# otherwise a missing value silently matches a literal "NA" category.
test_that("tidy post-stratification errors on NA in a cell variable (2A-05)", {
  df  <- data.frame(region = c("N", "S", "N", NA), pw = 1)
  tab <- data.frame(region = c("N", "S"), Freq = c(2, 2))
  expect_error(
    weighting_spec(df, base_weights = pw) |>
      step_calibrate(method = "poststratify", totals = tab, count = "Freq") |>
      prep(),
    "missing values")
})

# 2A-11: a reference-metadata entry with length > 1 (or a named vector) must not
# crash the report.
test_that("report metadata accepts a multi-value entry (2A-11)", {
  fit <- suppressWarnings(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_calibrate(method = "raking",
                     margins = list(region = c(table(population$region)))) |>
      prep())
  expect_no_error(
    report_weighting(fit, file = tempfile(fileext = ".html"), open = FALSE,
                     metadata = list(author = c("A. One", "B. Two"))))
  expect_no_error(
    report_weighting(fit, file = tempfile(fileext = ".html"), open = FALSE,
                     metadata = c(producer = "INE", contact = "x@y.z")))
})
