# Snapshot tests: freeze the printed output so any future change to the format
# or the diagnostics (including the R-indicator line) shows up as a diff.
# The recipe uses only raking + weighting classes (no matrix solve), so the
# numbers are bit-stable across platforms.
#
# First run records the snapshots under tests/testthat/_snaps/ — review them once
# and commit. Later runs compare against them.

snap_rec <- function() {
  prep(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_nonresponse(respondent = responded, method = "weighting_class",
                       by = c("region", "sex")) |>
      step_calibrate(method = "raking",
                     margins = list(region = c(table(population$region)),
                                    sex    = c(table(population$sex)))))
}

# Skipped on CRAN: snapshots guard the format in CI / locally, but small
# cross-platform formatting differences should never fail CRAN's checks.

test_that("print() output is stable", {
  skip_on_cran()
  expect_snapshot(print(snap_rec()))
})

test_that("summary() output (incl. the R-indicator line) is stable", {
  skip_on_cran()
  expect_snapshot(summary(snap_rec()))
})

test_that("design_effect() output is stable", {
  skip_on_cran()
  expect_snapshot(str(design_effect(collect_weights(snap_rec())$.weight)))
})
