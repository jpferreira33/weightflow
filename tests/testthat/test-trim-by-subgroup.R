# Differentiated trimming by subgroup:
#  (1) step_trim(reference = "median", by = ) uses each group's own median.
#  (2) step_trim_calibrated(lower/upper as a named vector + by = ) applies
#      subgroup-specific absolute bounds while preserving the GLOBAL totals.

test_that("step_trim median threshold is computed within each `by` group", {
  # two strata with very different weight levels; a global median would cap the
  # low stratum far too hard and barely touch the high one.
  set.seed(1)
  dat <- data.frame(
    stratum = rep(c("A", "B"), each = 100),
    pw      = c(runif(100, 1, 3), runif(100, 50, 150)))
  dat$pw[1]   <- 40     # outlier within A (relative to A's own median ~2)
  dat$pw[101] <- 400    # outlier within B (relative to B's own median ~100)

  fit <- weighting_spec(dat, base_weights = pw) |>
    step_trim(max_ratio = 3, reference = "median", by = "stratum",
              redistribute = FALSE) |>
    prep()
  w <- fit$final_weight

  medA <- median(dat$pw[dat$stratum == "A"])
  medB <- median(dat$pw[dat$stratum == "B"])
  # each group capped at 3x ITS OWN median
  expect_lte(max(w[dat$stratum == "A"]), 3 * medA + 1e-8)
  expect_lte(max(w[dat$stratum == "B"]), 3 * medB + 1e-8)
  # the B outlier (400) is trimmed (a global median would have left it alone or
  # over-trimmed A); B's cap is well above A's, so bounds really differ by group
  expect_gt(3 * medB, 3 * medA)
  expect_lt(w[101], 400)
})

test_that("step_trim_calibrated takes per-subgroup bounds and keeps global totals", {
  set.seed(2)
  n   <- 300
  dat <- data.frame(
    stratum = sample(c("A", "B"), n, TRUE),
    region  = sample(c("N", "S"), n, TRUE),
    pw      = runif(n, 1, 5))
  # calibrate to region totals first so there is something to preserve
  cal <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "raking",
                   totals = list(data.frame(region = c("N", "S"),
                                            Freq = c(600, 600))),
                   count = "Freq") |>
    prep()
  totals_before <- tapply(cal$final_weight, dat$region, sum)

  dat$w_cal <- cal$final_weight            # calibrated weights as the base column
  # different absolute bounds per stratum
  fit <- weighting_spec(dat, base_weights = w_cal) |>
    step_trim_calibrated(~ region,
                         lower = c(A = 0.5, B = 1.0),
                         upper = c(A = 6.0, B = 8.0),
                         by = "stratum") |>
    prep()
  w <- fit$final_weight

  # bounds respected within each stratum
  expect_gte(min(w[dat$stratum == "A"]), 0.5 - 1e-6)
  expect_lte(max(w[dat$stratum == "A"]), 6.0 + 1e-6)
  expect_gte(min(w[dat$stratum == "B"]), 1.0 - 1e-6)
  expect_lte(max(w[dat$stratum == "B"]), 8.0 + 1e-6)
  # the preserved (global) region totals are unchanged
  totals_after <- tapply(w, dat$region, sum)
  expect_equal(as.numeric(totals_after), as.numeric(totals_before),
               tolerance = 1e-4)
})

test_that("report_weighting() renders with per-subgroup bounds", {
  set.seed(4)
  n   <- 200
  dat <- data.frame(
    estrato = sample(c("A", "B"), n, TRUE),
    region  = sample(c("N", "S"), n, TRUE),
    bw      = runif(n, 1, 5))
  fit <- weighting_spec(dat, base_weights = bw) |>
    step_calibrate(method = "raking",
                   totals = list(data.frame(region = c("N", "S"),
                                            Freq = c(400, 400))),
                   count = "Freq") |>
    step_trim_calibrated(~ region,
                         lower = c(A = 0.5, B = 0.8),
                         upper = c(A = 6.0, B = 7.0),
                         by = "estrato") |>
    prep()
  f <- tempfile(fileext = ".html")
  expect_no_error(report_weighting(fit, file = f, open = FALSE, lang = "en"))
  expect_true(file.exists(f))
})

test_that("step_trim_calibrated errors clearly on a vector bound without `by`", {
  expect_error(
    step_trim_calibrated(weighting_spec(data.frame(x = 1, pw = 1),
                                        base_weights = pw),
                         ~ x, lower = c(A = 1, B = 2)),
    "needs `by`")
})
