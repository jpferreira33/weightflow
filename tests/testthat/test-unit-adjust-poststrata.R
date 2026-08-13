# Unit tests for the internals of R/adjust-poststrata.R
# Focus on the validation branches of the tidy `totals` inputs, the margin-N
# reconciliation, and the poststratify / raking calculators.

d4     <- data.frame(g = c("a", "a", "b", "b"),
                     h = c("x", "y", "x", "y"),
                     stringsAsFactors = FALSE)
act4   <- rep(TRUE, 4)
tot_g  <- data.frame(g = c("a", "b"), N = c(10, 20), stringsAsFactors = FALSE)

# ---------------------------------------------------------------------------
# .reconcile_margin_N()
# ---------------------------------------------------------------------------

test_that(".reconcile_margin_N is a no-op when the margins agree", {
  rec <- .reconcile_margin_N(c(a = 100, b = 100))
  expect_equal(rec$target, 100)
  expect_equal(unname(rec$factors), c(1, 1))
  expect_null(rec$note)
})

test_that(".reconcile_margin_N rescales to the largest N and explains it", {
  rec <- .reconcile_margin_N(c(age = 100, sex = 120))
  expect_equal(rec$target, 120)
  expect_equal(unname(rec$factors), c(1.2, 1))
  expect_match(rec$note, "did not all sum")
  expect_match(rec$note, "age")
})

test_that(".reconcile_margin_N names unnamed margins and drops NA", {
  rec <- .reconcile_margin_N(c(100, 120))
  expect_match(rec$note, "margin 1")
  rec2 <- .reconcile_margin_N(c(a = 100, b = NA))
  expect_equal(rec2$target, 100)
  expect_length(rec2$factors, 1L)
})

# ---------------------------------------------------------------------------
# .prep_poststrata() -- validation
# ---------------------------------------------------------------------------

test_that(".prep_poststrata prepares cells, vars and the sample key", {
  prep <- .prep_poststrata(tot_g, "N", d4, act4)
  expect_equal(prep$vars, "g")
  expect_equal(prep$cells$.key, c("a", "b"))
  expect_equal(prep$cells$.Freq, c(10, 20))
  expect_equal(prep$sample_key, c("a", "a", "b", "b"))
  expect_null(prep$note)
})

test_that(".prep_poststrata validates the counts column", {
  expect_error(.prep_poststrata(tot_g, 1, d4, act4), "single string")
  expect_error(.prep_poststrata(tot_g, c("N", "N"), d4, act4), "single string")
  expect_error(.prep_poststrata(tot_g, "nope", d4, act4), "not in the totals")
  bad <- data.frame(g = c("a", "b"), N = c("10", "20"), stringsAsFactors = FALSE)
  expect_error(.prep_poststrata(bad, "N", d4, act4), "must be numeric")
})

test_that(".prep_poststrata needs at least one category column", {
  expect_error(.prep_poststrata(data.frame(N = 30), "N", d4, act4),
               "no category columns")
})

test_that(".prep_poststrata errors when a totals column is not in the data", {
  bad <- data.frame(zz = c("a", "b"), N = c(10, 20), stringsAsFactors = FALSE)
  expect_error(.prep_poststrata(bad, "N", d4, act4), "not present in the data")
})

test_that(".prep_poststrata errors on a sample post-stratum with no total", {
  d <- data.frame(g = c("a", "b", "c"), stringsAsFactors = FALSE)
  expect_error(.prep_poststrata(tot_g, "N", d, rep(TRUE, 3)),
               "no population total")
})

test_that(".prep_poststrata warns on a population post-stratum with no units", {
  tot <- data.frame(g = c("a", "b", "c"), N = c(10, 20, 5),
                    stringsAsFactors = FALSE)
  expect_warning(prep <- .prep_poststrata(tot, "N", d4, act4),
                 "no units in the sample")
  expect_match(prep$note, "shortfall")
})

test_that(".prep_poststrata collapses duplicated cells by summing counts", {
  tot <- data.frame(g = c("a", "a", "b"), N = c(4, 6, 20),
                    stringsAsFactors = FALSE)
  prep <- .prep_poststrata(tot, "N", d4, act4)
  expect_equal(prep$cells$.key, c("a", "b"))
  expect_equal(prep$cells$.Freq, c(10, 20))
})

test_that(".prep_poststrata orders numeric categories naturally, not as text", {
  d   <- data.frame(age = c(2, 10, 20))
  tot <- data.frame(age = c(20, 2, 10), N = c(1, 2, 3))
  prep <- .prep_poststrata(tot, "N", d, rep(TRUE, 3))
  expect_equal(prep$cells$.key, c("2", "10", "20"))
  expect_equal(prep$cells$.Freq, c(2, 3, 1))
})

test_that(".prep_poststrata keys on the crossing of several variables", {
  tot <- data.frame(g = c("a", "a", "b", "b"), h = c("x", "y", "x", "y"),
                    N = c(1, 2, 3, 4), stringsAsFactors = FALSE)
  prep <- .prep_poststrata(tot, "N", d4, act4)
  expect_equal(prep$vars, c("g", "h"))
  expect_length(prep$cells$.key, 4L)
})

# ---------------------------------------------------------------------------
# .poststratify_calc()
# ---------------------------------------------------------------------------

test_that(".poststratify_calc rescales each cell to its known total", {
  prep <- .prep_poststrata(tot_g, "N", d4, act4)
  res  <- .poststratify_calc(prep, rep(1, 4), act4)
  expect_equal(res$weights, c(5, 5, 10, 10))
  expect_equal(sum(res$weights), 30)
  expect_equal(res$diagnostics$target, c(10, 20))
  expect_equal(res$diagnostics$factor, c(5, 10))
  expect_equal(res$diagnostics$variable, rep("g", 2))
})

test_that(".poststratify_calc leaves a zero-weight cell alone and flags NA", {
  prep <- .prep_poststrata(tot_g, "N", d4, act4)
  res  <- .poststratify_calc(prep, c(0, 0, 1, 1), act4)
  expect_equal(res$weights[1:2], c(0, 0))
  expect_true(is.na(res$diagnostics$factor[1]))
  expect_equal(res$weights[3:4], c(10, 10))
})

test_that(".poststratify_calc only touches active units", {
  prep <- .prep_poststrata(tot_g, "N", d4, c(TRUE, FALSE, TRUE, TRUE))
  res  <- .poststratify_calc(prep, rep(1, 4), c(TRUE, FALSE, TRUE, TRUE))
  expect_equal(res$weights[2], 1)      # inactive unit untouched
  expect_equal(res$weights[1], 10)     # cell "a" now has a single active unit
})

# ---------------------------------------------------------------------------
# .prep_raking_margins()
# ---------------------------------------------------------------------------

test_that(".prep_raking_margins requires a non-empty list of data frames", {
  expect_error(.prep_raking_margins(tot_g, "N", d4, act4), "LIST")
  expect_error(.prep_raking_margins("nope", "N", d4, act4), "LIST")
  expect_error(.prep_raking_margins(list(), "N", d4, act4), "empty list")
})

test_that(".prep_raking_margins prepares one entry per margin", {
  tot_h <- data.frame(h = c("x", "y"), N = c(12, 18), stringsAsFactors = FALSE)
  mp <- .prep_raking_margins(list(tot_g, tot_h), "N", d4, act4)
  expect_length(mp, 2L)
  expect_equal(mp[[1]]$vars, "g")
  expect_equal(mp[[2]]$vars, "h")
  expect_named(mp[[1]], c("cells", "vars", "sample_key"))
})

# ---------------------------------------------------------------------------
# .raking_calc()
# ---------------------------------------------------------------------------

test_that(".raking_calc converges and reports achieved totals per margin", {
  mg <- data.frame(g = c("a", "b"), N = c(50, 50), stringsAsFactors = FALSE)
  mh <- data.frame(h = c("x", "y"), N = c(40, 60), stringsAsFactors = FALSE)
  mp <- .prep_raking_margins(list(mg, mh), "N", d4, act4)
  res <- .raking_calc(mp, rep(1, 4), act4, maxit = 100L, tol = 1e-8)
  expect_equal(sum(res$weights), 100, tolerance = 1e-5)
  expect_true(attr(res$diagnostics, "converged"))
  expect_true(attr(res$diagnostics, "iterations") >= 1L)
  expect_equal(res$diagnostics$achieved, res$diagnostics$target,
               tolerance = 1e-5)
})

test_that(".raking_calc warns when it runs out of iterations", {
  mg <- data.frame(g = c("a", "b"), N = c(50, 50), stringsAsFactors = FALSE)
  mh <- data.frame(h = c("x", "y"), N = c(40, 60), stringsAsFactors = FALSE)
  mp <- .prep_raking_margins(list(mg, mh), "N", d4, act4)
  expect_warning(
    res <- .raking_calc(mp, rep(1, 4), act4, maxit = 1L, tol = 1e-8),
    "did not converge")
  expect_false(attr(res$diagnostics, "converged"))
})

test_that(".raking_calc reconciles margins with different population sizes", {
  mg <- data.frame(g = c("a", "b"), N = c(50, 50), stringsAsFactors = FALSE)
  mh <- data.frame(h = c("x", "y"), N = c(40, 80), stringsAsFactors = FALSE)
  mp <- .prep_raking_margins(list(mg, mh), "N", d4, act4)
  expect_message(
    res <- .raking_calc(mp, rep(1, 4), act4, maxit = 100L, tol = 1e-8),
    "did not all sum")
  expect_equal(sum(res$weights), 120, tolerance = 1e-5)
  expect_match(attr(res$diagnostics, "reconcile"), "rescaled")
})

# ---------------------------------------------------------------------------
# .prep_linear_totals()
# ---------------------------------------------------------------------------

dl   <- data.frame(g = c("a", "a", "b", "b"), z = c(1, 2, 3, 4),
                   stringsAsFactors = TRUE)
actl <- rep(TRUE, 4)
tg   <- data.frame(g = c("a", "b"), N = c(50, 50), stringsAsFactors = FALSE)

test_that(".prep_linear_totals translates tidy targets into a model.matrix vector", {
  Tv <- .prep_linear_totals(~ g + z, list(g = tg, z = 250), "N", dl, actl)
  expect_named(Tv, c("(Intercept)", "gb", "z"))
  expect_equal(unname(Tv), c(100, 50, 250))
})

test_that(".prep_linear_totals requires a NAMED list", {
  expect_error(.prep_linear_totals(~ g, list(tg), "N", dl, actl), "NAMED list")
  expect_error(.prep_linear_totals(~ g, tg, "N", dl, actl), "NAMED list")
})

test_that(".prep_linear_totals rejects calibration variables with NA", {
  d <- dl; d$z[2] <- NA
  expect_error(.prep_linear_totals(~ g + z, list(g = tg, z = 250), "N", d, actl),
               "missing values")
})

test_that(".prep_linear_totals needs at least one categorical target", {
  expect_error(.prep_linear_totals(~ z, list(z = 250), "N", dl, actl),
               "categorical target")
})

test_that(".prep_linear_totals validates the shape of each target", {
  bad_count <- data.frame(g = c("a", "b"), M = c(50, 50), stringsAsFactors = FALSE)
  expect_error(.prep_linear_totals(~ g, list(g = bad_count), "N", dl, actl),
               "not a column of the totals")

  two_cols <- data.frame(g = c("a", "b"), extra = c(1, 2), N = c(50, 50),
                         stringsAsFactors = FALSE)
  expect_error(.prep_linear_totals(~ g, list(g = two_cols), "N", dl, actl),
               "exactly one category column")

  expect_error(
    .prep_linear_totals(~ g, list(g = tg, nothere = 5), "N", dl, actl),
    "not a column of the")

  expect_error(
    .prep_linear_totals(~ g, list(g = tg, bad = "x"), "N", dl, actl),
    "must be a data frame")
})

test_that(".prep_linear_totals errors when a model term has no total", {
  expect_error(.prep_linear_totals(~ g + z, list(g = tg), "N", dl, actl),
               "No population total")
})

test_that(".prep_linear_totals reconciles disagreeing categorical margins", {
  th <- data.frame(h = c("x", "y"), N = c(40, 80), stringsAsFactors = FALSE)
  d  <- data.frame(g = factor(c("a", "a", "b", "b")),
                   h = factor(c("x", "y", "x", "y")))
  expect_message(
    Tv <- .prep_linear_totals(~ g + h, list(g = tg, h = th), "N", d, actl),
    "did not all sum")
  expect_equal(unname(Tv[["(Intercept)"]]), 120)
  expect_equal(unname(Tv[["gb"]]), 60)      # g margin rescaled 100 -> 120
  expect_equal(unname(Tv[["hy"]]), 80)
  expect_match(attr(Tv, "reconcile"), "rescaled")
})
