# Unit tests for R/adjust-calibrate.R: the domain-split helpers, the margin-level
# guard, and the branches of apply_step.step_calibrate() (linear/GREG variants,
# integrative clusters, classic raking).

cd <- data.frame(
  region = rep(c("A", "B"), each = 6),
  sex    = c("M", "M", "F", "F", "M", "F", "M", "M", "F", "F", "M", "F"),
  hh     = rep(1:6, each = 2),
  stringsAsFactors = FALSE
)
cw <- rep(1, 12)

cal_step <- function(...) {
  st <- list(method = "linear", formula = ~ sex, totals = NULL, margins = NULL,
             count = NULL, by = NULL, cluster = NULL,
             equal_within_cluster = FALSE, calfun = "linear", bounds = NULL,
             maxit = 50L, tol = 1e-6, penalty = NULL)
  structure(utils::modifyList(st, list(...)),
            class = c("step_calibrate", "weighting_step"))
}

lin_totals <- c("(Intercept)" = 120, sexM = 60)

# ---------------------------------------------------------------------------
# .split_totals_by_domain()
# ---------------------------------------------------------------------------

test_that(".split_totals_by_domain keeps one domain and drops the domain column", {
  tot <- data.frame(region = c("A", "A", "B"), sex = c("M", "F", "M"),
                    Freq = c(10, 20, 30), stringsAsFactors = FALSE)
  out <- .split_totals_by_domain(tot, "region", "Freq", "A")
  expect_equal(names(out), c("sex", "Freq"))
  expect_equal(out$Freq, c(10, 20))
  expect_equal(rownames(out), c("1", "2"))
})

test_that(".split_totals_by_domain collapses a continuous total to a number", {
  tot <- data.frame(region = c("A", "B"), income = c(100, 200),
                    stringsAsFactors = FALSE)
  expect_identical(.split_totals_by_domain(tot, "region", "Freq", "B"), 200)
})

test_that(".split_totals_by_domain walks a named list and keeps its names", {
  tot <- list(sex    = data.frame(region = c("A", "B"), sex = c("M", "M"),
                                  Freq = c(10, 20), stringsAsFactors = FALSE),
              income = data.frame(region = c("A", "B"), value = c(100, 200),
                                  stringsAsFactors = FALSE))
  out <- .split_totals_by_domain(tot, "region", "Freq", "A")
  expect_named(out, c("sex", "income"))
  expect_s3_class(out$sex, "data.frame")
  expect_identical(out$income, 100)
})

test_that(".split_totals_by_domain passes a non-tabular totals object through", {
  tot <- c("(Intercept)" = 100, sexM = 40)
  expect_identical(.split_totals_by_domain(tot, "region", "Freq", "A"), tot)
})

test_that(".split_totals_by_domain needs the domain column in every table", {
  tot <- data.frame(sex = c("M", "F"), Freq = c(10, 20), stringsAsFactors = FALSE)
  expect_error(.split_totals_by_domain(tot, "region", "Freq", "A"),
               "missing the domain column")
})

# ---------------------------------------------------------------------------
# .check_margin_levels()
# ---------------------------------------------------------------------------

test_that(".check_margin_levels accepts margins that match the data", {
  expect_silent(.check_margin_levels(list(sex = c(M = 60, F = 60)), cd,
                                     rep(TRUE, 12)))
})

test_that(".check_margin_levels catches a margin variable that is not a column", {
  expect_error(.check_margin_levels(list(nope = c(a = 1)), cd, rep(TRUE, 12)),
               "not found in the data")
})

test_that(".check_margin_levels catches a level that matches no active unit", {
  expect_error(
    .check_margin_levels(list(sex = c(M = 60, F = 60, X = 10)), cd,
                         rep(TRUE, 12)),
    "match no active unit")
})

test_that(".check_margin_levels only looks at ACTIVE units", {
  act <- c(rep(TRUE, 6), rep(FALSE, 6))   # only region A is active
  expect_error(.check_margin_levels(list(region = c(A = 100, B = 100)), cd, act),
               "match no active unit")
})

# ---------------------------------------------------------------------------
# apply_step.step_calibrate() -- linear / GREG
# ---------------------------------------------------------------------------

test_that("linear calibration hits the targets exactly (closed form)", {
  res <- apply_step.step_calibrate(cal_step(totals = lin_totals), cd, cw)
  expect_equal(sum(res$weights), 120)
  expect_equal(sum(res$weights[cd$sex == "M"]), 60)
  expect_true(attr(res$diagnostics, "converged"))
  expect_equal(res$diagnostics$variable, c("(Intercept)", "sexM"))
  expect_match(attr(res$diagnostics, "note"), "g \\(calibration factor\\)")
})

test_that("linear calibration rejects auxiliaries with NA", {
  d <- cd; d$sex[1] <- NA
  expect_error(apply_step.step_calibrate(cal_step(totals = lin_totals), d, cw),
               "missing values")
})

test_that("linear calibration rejects totals that do not match the columns", {
  bad <- c("(Intercept)" = 120, wrong = 60)
  expect_error(apply_step.step_calibrate(cal_step(totals = bad), cd, cw),
               "must match the model.matrix columns")
})

test_that("linear calibration refuses a ridge penalty with bounds", {
  st <- cal_step(totals = lin_totals, bounds = c(0.5, 20), penalty = 1)
  expect_error(apply_step.step_calibrate(st, cd, cw),
               "only available for unbounded linear")
})

test_that("ridge calibration relaxes the totals and reports the deviation", {
  res <- apply_step.step_calibrate(
    cal_step(totals = lin_totals, penalty = 1), cd, cw)
  expect_true("deviation" %in% names(res$diagnostics))
  expect_match(attr(res$diagnostics, "note"), "ridge")
  expect_true(all(is.finite(res$weights)))
})

test_that("bounded calibration keeps g inside the bounds and notes them", {
  res <- apply_step.step_calibrate(
    cal_step(totals = lin_totals, bounds = c(0.5, 20)), cd, cw)
  g <- res$weights / cw
  expect_true(all(g >= 0.5 - 1e-6 & g <= 20 + 1e-6))
  expect_true(attr(res$diagnostics, "converged"))
  expect_match(attr(res$diagnostics, "note"), "bounds")
})

test_that("the raking distance (calfun) also satisfies the constraints", {
  res <- apply_step.step_calibrate(
    cal_step(totals = lin_totals, calfun = "raking", bounds = c(0.01, 100)),
    cd, cw)
  expect_equal(sum(res$weights), 120, tolerance = 1e-5)
  expect_true(all(res$weights > 0))
  expect_match(attr(res$diagnostics, "note"), "calfun = raking")
})

test_that("linear calibration validates the cluster column", {
  st <- cal_step(totals = lin_totals, equal_within_cluster = TRUE,
                 cluster = "nope")
  expect_error(apply_step.step_calibrate(st, cd, cw), "not found in the data")

  d <- cd; d$hh[1] <- NA
  st2 <- cal_step(totals = lin_totals, equal_within_cluster = TRUE,
                  cluster = "hh")
  expect_error(apply_step.step_calibrate(st2, d, cw), "missing values")
})

test_that("integrative calibration gives one weight per cluster", {
  st  <- cal_step(totals = lin_totals, equal_within_cluster = TRUE,
                  cluster = "hh")
  res <- apply_step.step_calibrate(st, cd, cw)
  per_hh <- tapply(res$weights, cd$hh, function(x) length(unique(round(x, 8))))
  expect_true(all(per_hh == 1L))
  expect_equal(sum(res$weights), 120, tolerance = 1e-6)
  expect_match(attr(res$diagnostics, "note"), "integrative")
})

test_that("linear calibration exposes the report diagnostics", {
  res <- apply_step.step_calibrate(cal_step(totals = lin_totals), cd, cw)
  cal <- attr(res$diagnostics, "calibrate")
  expect_named(cal, c("g", "d", "calfun", "bounds", "cond", "chi2", "covars",
                      "formula", "active_idx"))
  expect_length(cal$g, 12L)
  expect_equal(cal$chi2, sum(cal$d * (cal$g - 1)^2))
  expect_equal(names(cal$covars), "sex")
})

# ---------------------------------------------------------------------------
# apply_step.step_calibrate() -- poststratify and raking (classic margins)
# ---------------------------------------------------------------------------

test_that("classic poststratify takes exactly one margin", {
  st <- cal_step(method = "poststratify",
                 margins = list(sex = c(M = 60, F = 60),
                                region = c(A = 70, B = 50)))
  expect_error(apply_step.step_calibrate(st, cd, cw), "exactly one variable")
})

test_that("classic poststratify rescales each category to its total", {
  st  <- cal_step(method = "poststratify", margins = list(sex = c(M = 60, F = 60)))
  res <- apply_step.step_calibrate(st, cd, cw)
  expect_equal(sum(res$weights[cd$sex == "M"]), 60)
  expect_equal(sum(res$weights[cd$sex == "F"]), 60)
  expect_equal(res$diagnostics$factor, c(10, 10))
})

test_that("classic raking converges and reports its iterations", {
  st  <- cal_step(method = "raking",
                  margins = list(sex = c(M = 60, F = 60),
                                 region = c(A = 70, B = 50)))
  res <- apply_step.step_calibrate(st, cd, cw)
  expect_true(attr(res$diagnostics, "converged"))
  expect_true(attr(res$diagnostics, "iterations") >= 1L)
  expect_equal(res$diagnostics$achieved, res$diagnostics$target,
               tolerance = 1e-5)
})

test_that("classic raking warns when it runs out of iterations", {
  st <- cal_step(method = "raking", maxit = 1L,
                 margins = list(sex = c(M = 60, F = 60),
                                region = c(A = 70, B = 50)))
  expect_warning(res <- apply_step.step_calibrate(st, cd, cw),
                 "did not converge")
  expect_false(attr(res$diagnostics, "converged"))
})

# ---------------------------------------------------------------------------
# .calibrate_by_domain()
# ---------------------------------------------------------------------------

dom_totals <- data.frame(region = c("A", "A", "B", "B"),
                         sex    = c("M", "F", "M", "F"),
                         Freq   = c(30, 30, 50, 50),
                         stringsAsFactors = FALSE)

test_that("domain calibration validates the domain column", {
  st <- cal_step(method = "poststratify", by = "nope", count = "Freq",
                 totals = dom_totals)
  expect_error(apply_step.step_calibrate(st, cd, cw), "not found in the data")

  d <- cd; d$region[1] <- NA
  st2 <- cal_step(method = "poststratify", by = "region", count = "Freq",
                  totals = dom_totals)
  expect_error(apply_step.step_calibrate(st2, d, cw), "missing values")
})

test_that("domain calibration calibrates each domain to its own totals", {
  st  <- cal_step(method = "poststratify", by = "region", count = "Freq",
                  totals = dom_totals)
  res <- apply_step.step_calibrate(st, cd, cw)
  expect_equal(sum(res$weights[cd$region == "A"]), 60)
  expect_equal(sum(res$weights[cd$region == "B"]), 100)
  expect_true("domain" %in% names(res$diagnostics))
  expect_equal(sort(unique(res$diagnostics$domain)), c("A", "B"))
  expect_match(attr(res$diagnostics, "note"), "independently within 'region'")
})

test_that("domain linear calibration pools the per-domain report pieces", {
  tot <- list(sex = data.frame(region = c("A", "A", "B", "B"),
                               sex    = c("M", "F", "M", "F"),
                               Freq   = c(30, 30, 50, 50),
                               stringsAsFactors = FALSE))
  st  <- cal_step(method = "linear", formula = ~ sex, by = "region",
                  count = "Freq", totals = tot)
  res <- apply_step.step_calibrate(st, cd, cw)
  expect_equal(sum(res$weights), 160, tolerance = 1e-6)

  dsum <- attr(res$diagnostics, "calib_domains")
  expect_equal(nrow(dsum), 2L)
  expect_true(all(dsum$converged))
  expect_equal(dsum$n, c(6L, 6L))

  cal <- attr(res$diagnostics, "calibrate")
  expect_true(isTRUE(cal$pooled))
  expect_length(cal$g, 12L)
  expect_equal(sort(cal$active_idx), 1:12)
})
