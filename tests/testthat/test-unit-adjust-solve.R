# Unit tests for the internals of R/adjust-solve.R
# These call the internal helpers directly (visible from testthat because tests
# run inside the package namespace), so the rarely-reached error branches and
# the numeric fallbacks get exercised without building a whole spec.

# ---------------------------------------------------------------------------
# .eval_cond()
# ---------------------------------------------------------------------------

test_that(".eval_cond returns NULL for a NULL expression", {
  expect_null(.eval_cond(NULL, data.frame(x = 1:3)))
})

test_that(".eval_cond accepts a logical expression and a 0/1 dummy", {
  d <- data.frame(flag = c(1, 0, 1), x = c(5, 1, 9))
  expect_identical(.eval_cond(quote(flag), d), c(TRUE, FALSE, TRUE))
  expect_identical(.eval_cond(quote(x > 3), d), c(TRUE, FALSE, TRUE))
})

test_that(".eval_cond works when `env` is NULL (falls back to baseenv)", {
  d <- data.frame(flag = c(TRUE, FALSE))
  expect_identical(.eval_cond(quote(flag), d, env = NULL), c(TRUE, FALSE))
})

test_that(".eval_cond rejects a numeric column that is not a 0/1 dummy", {
  d <- data.frame(flag = c(0, 1, 2))
  expect_error(.eval_cond(quote(flag), d), "0/1 dummy")
})

test_that(".eval_cond rejects a condition that is neither logical nor 0/1", {
  d <- data.frame(flag = c("yes", "no"), stringsAsFactors = FALSE)
  expect_error(.eval_cond(quote(flag), d), "TRUE/FALSE")
})

test_that(".eval_cond errors on NA among the units still in scope", {
  d <- data.frame(flag = c(TRUE, NA, FALSE))
  expect_error(.eval_cond(quote(flag), d, active = c(TRUE, TRUE, TRUE)),
               "missing value")
  # ... but NA outside the active set is fine and falls through as FALSE
  out <- .eval_cond(quote(flag), d, active = c(TRUE, FALSE, TRUE))
  expect_identical(out, c(TRUE, FALSE, FALSE))
})

# ---------------------------------------------------------------------------
# .make_cells()
# ---------------------------------------------------------------------------

test_that(".make_cells builds a single cell when `by` is NULL", {
  cells <- .make_cells(data.frame(g = c("a", "b")), NULL, 2L)
  expect_s3_class(cells, "factor")
  expect_identical(levels(cells), "(all)")
  expect_length(cells, 2L)
})

test_that(".make_cells crosses several `by` variables", {
  d <- data.frame(g = c("a", "a", "b"), h = c("x", "y", "x"),
                  stringsAsFactors = FALSE)
  cells <- .make_cells(d, c("g", "h"), 3L)
  expect_identical(as.character(cells), c("a | x", "a | y", "b | x"))
})

test_that(".make_cells errors on an unknown cell variable", {
  expect_error(.make_cells(data.frame(g = "a"), "nope", 1L), "not found")
})

# ---------------------------------------------------------------------------
# .ridge_diag()
# ---------------------------------------------------------------------------

test_that(".ridge_diag builds a scale-free penalty from a scalar cost", {
  A <- diag(c(2, 4))
  P <- .ridge_diag(2, c("a", "b"), A)     # s = mean(diag(A)) = 3, cost = 2
  expect_equal(diag(P), c(1.5, 1.5))
  expect_equal(dim(P), c(2L, 2L))
})

test_that(".ridge_diag accepts a named per-constraint cost vector", {
  A <- diag(c(2, 4))
  P <- .ridge_diag(c(a = 1, b = 3), c("a", "b"), A)
  expect_equal(diag(P), c(3 / 1, 3 / 3))
})

test_that(".ridge_diag requires a named vector and complete costs", {
  A <- diag(c(2, 4))
  expect_error(.ridge_diag(c(1, 3), c("a", "b"), A), "named")
  # a vector with more than one cost must name every constraint in `cn`
  expect_error(.ridge_diag(c(a = 1, z = 3), c("a", "b"), A), "missing costs")
})

test_that(".ridge_diag treats a length-1 penalty as a global cost, named or not", {
  A <- diag(c(2, 4))                        # s = mean(diag(A)) = 3
  expect_equal(diag(.ridge_diag(c(a = 1), c("a", "b"), A)), c(3, 3))
  expect_equal(diag(.ridge_diag(1, c("a", "b"), A)), c(3, 3))
})

# ---------------------------------------------------------------------------
# .solve_calib()
# ---------------------------------------------------------------------------

test_that(".solve_calib solves a well-conditioned system", {
  A <- matrix(c(2, 0, 0, 4), 2)
  expect_equal(as.numeric(.solve_calib(A, c(2, 8))), c(1, 2))
})

test_that(".solve_calib falls back to the pseudo-inverse when singular", {
  A <- matrix(1, 2, 2)                      # exactly singular
  expect_warning(out <- .solve_calib(A, c(1, 1)), "pseudo-inverse")
  expect_equal(as.numeric(out), c(0.5, 0.5))   # minimum-norm solution
})

# ---------------------------------------------------------------------------
# .calib_ds()
# ---------------------------------------------------------------------------

test_that(".calib_ds converges for linear, raking and logit distances", {
  X <- matrix(1, nrow = 10, ncol = 1)
  d <- rep(1, 10)
  Tv <- 20                                   # every g should land on 2

  g_lin <- .calib_ds(X, d, Tv, calfun = "linear")
  expect_equal(as.numeric(g_lin), rep(2, 10), tolerance = 1e-6)
  expect_true(attr(g_lin, "converged"))

  g_rak <- .calib_ds(X, d, Tv, calfun = "raking")
  expect_equal(as.numeric(g_rak), rep(2, 10), tolerance = 1e-6)
  expect_true(attr(g_rak, "converged"))

  g_log <- .calib_ds(X, d, Tv, calfun = "logit", bounds = c(0.5, 3))
  expect_equal(as.numeric(g_log), rep(2, 10), tolerance = 1e-6)
  expect_true(attr(g_log, "converged"))
})

test_that(".calib_ds requires bounds for the logit distance", {
  X <- matrix(1, nrow = 5, ncol = 1)
  expect_error(.calib_ds(X, rep(1, 5), 10, calfun = "logit"), "bounds")
})

test_that(".calib_ds accepts per-unit bounds given as an n x 2 matrix", {
  X  <- matrix(1, nrow = 10, ncol = 1)
  bd <- cbind(rep(0.5, 10), rep(3, 10))
  g  <- .calib_ds(X, rep(1, 10), 20, calfun = "linear", bounds = bd)
  expect_true(all(g >= 0.5 - 1e-8 & g <= 3 + 1e-8))
  expect_equal(as.numeric(g), rep(2, 10), tolerance = 1e-6)
})

test_that(".calib_ds warns and flags non-convergence on infeasible bounds", {
  X <- matrix(1, nrow = 10, ncol = 1)
  expect_warning(
    g <- .calib_ds(X, rep(1, 10), 100, calfun = "linear",
                   bounds = c(0.5, 2), maxit = 10L),
    "did not fully converge")
  expect_false(attr(g, "converged"))
  expect_true(all(g <= 2 + 1e-8))
})

test_that(".calib_ds tolerates an all-zero auxiliary column", {
  X <- cbind(rep(1, 10), rep(0, 10))          # second column has zero scale
  g <- suppressWarnings(.calib_ds(X, rep(1, 10), c(20, 0), calfun = "linear"))
  expect_true(all(is.finite(g)))
})

# ---------------------------------------------------------------------------
# .solve_calibration()
# ---------------------------------------------------------------------------

test_that(".solve_calibration hits the calibration equation exactly (linear)", {
  set.seed(11)
  df <- data.frame(x = rnorm(30))
  Z  <- stats::model.matrix(~ x, df)
  v  <- rep(2, 30)
  Tv <- colSums(v * Z) * 1.3
  res <- .solve_calibration(Z, v, Tv)
  expect_true(res$converged)
  expect_equal(as.numeric(colSums(v * res$g * Z)), as.numeric(Tv))
})

test_that(".solve_calibration applies a ridge penalty and stays finite", {
  set.seed(12)
  df <- data.frame(x = rnorm(30))
  Z  <- stats::model.matrix(~ x, df)
  v  <- rep(1, 30)
  Tv <- colSums(v * Z) * 1.1
  res <- .solve_calibration(Z, v, Tv, penalty = 1)
  expect_true(res$converged)
  expect_true(all(is.finite(res$g)))
})

test_that(".solve_calibration routes to Deville-Sarndal for raking and bounds", {
  X <- matrix(1, nrow = 10, ncol = 1)
  r1 <- .solve_calibration(X, rep(1, 10), 20, calfun = "raking")
  expect_true(r1$converged)
  expect_equal(r1$g, rep(2, 10), tolerance = 1e-6)

  r2 <- .solve_calibration(X, rep(1, 10), 20, calfun = "linear",
                           bounds = c(0.5, 3))
  expect_true(r2$converged)
  expect_equal(r2$g, rep(2, 10), tolerance = 1e-6)
})
