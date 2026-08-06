# Regression tests for silent-wrong-result bugs on degenerate data.

test_that("weighting_class drops nonrespondents even in a cell with no respondents (C1)", {
  dat <- data.frame(region    = c("A", "A", "B", "B"),
                    responded = c(1,   0,   0,   0),   # region B has NO respondents
                    pw        = c(10,  10,  10,  10))
  fit <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    prep()
  w <- fit$final_weight
  expect_equal(w[3], 0)                 # region B nonrespondents must be zeroed, not leak
  expect_equal(w[4], 0)
  expect_equal(w[2], 0)                 # region A nonrespondent zeroed
  expect_gt(w[1], 0)                    # region A respondent inflated
  # the empty cell is flagged for the report
  al <- unlist(lapply(fit$steps, function(s) s$alerts))
  expect_true(any(grepl("no units to adjust", al)))
})

test_that("linear/GREG calibration errors on NA auxiliaries (C2)", {
  set.seed(1)
  dat <- data.frame(region = c("A", "A", "B", "B", "A"),
                    x      = c(1, 2, NA, 4, 5),         # NA auxiliary
                    pw     = runif(5, 1, 2))
  tot <- c("(Intercept)" = 100, x = 50)                 # classic named-vector totals
  expect_error(
    weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ x, totals = tot) |>
      prep(),
    "missing values")
})

test_that("lonely-PSU collapse keeps distinct PSUs distinct (C3)", {
  # two strata, each a single PSU, whose ids collide ("1" in both)
  dat <- data.frame(stratum = c("A", "A", "B", "B"),
                    psu     = c("1", "1", "1", "1"),
                    pw      = c(1, 1, 1, 1))
  spec <- weighting_spec(dat, base_weights = pw)
  bw <- bootstrap_weights(spec, replicates = 20, strata = "stratum", psu = "psu",
                          lonely_psu = "collapse", seed = 1, progress = FALSE)
  # the two collapsed PSUs are now distinct, so they get resampled: at least one
  # replicate must differ from the point weights (otherwise variance is zero).
  expect_true(any(bw$replicates != bw$weights))
})
