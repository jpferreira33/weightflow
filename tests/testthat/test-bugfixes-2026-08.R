# Regression tests for the 2026-08 bug report (criticals C1, C2, C3).

# --- C1: (raking/poststrat NA & coverage handling left as-is; the asymmetric
#         error/warning is a poststratification concept already implemented in
#         the tidy poststrata path, NOT raking/IPW. Pending: quality alert for
#         NA-in-margin pass-through. No behaviour change here.)

# --- C2: propensity nonresponse with NA in a model covariate ---------------

test_that("C2: propensity nonresponse aborts on NA in a model covariate", {
  set.seed(1); n <- 30
  d <- data.frame(pw = rep(10, n), x = rnorm(n), resp = rbinom(n, 1, .6))
  d$x[5] <- NA
  expect_error(
    prep(step_nonresponse(weighting_spec(d, base_weights = pw), respondent = resp,
                          method = "propensity", formula = ~x, engine = "logit"),
         min_cell_n = NULL),
    "missing values")
})

test_that("C2: clean propensity nonresponse still drops nonrespondents", {
  set.seed(2); n <- 40
  d <- data.frame(pw = rep(10, n), x = rnorm(n), resp = rbinom(n, 1, .7))
  fit <- prep(step_nonresponse(weighting_spec(d, base_weights = pw), respondent = resp,
                               method = "propensity", formula = ~x, engine = "logit"),
              min_cell_n = NULL)
  expect_true(all(fit$final_weight[d$resp == 0] == 0))
  expect_false(anyNA(fit$final_weight))
})

# --- C3: equal_within_cluster + non-uniform base weights, and the totals check -
# Design decision (2026-08): non-uniform within-cluster base weights are a HARD
# ERROR (one-weight-per-cluster is otherwise undefined). The uniform case must
# still close exactly with and without bounds (survey match), and the
# achieved-vs-target check must run even under bounds.

test_that("C3: non-uniform within-cluster base weights are a hard error", {
  set.seed(21); n <- 300
  sexo <- sample(c("H", "M"), n, TRUE)
  d <- data.frame(id = 1:n, sexo = factor(sexo), hogar = rep(1:(n / 2), each = 2),
                  pw = ifelse(sexo == "M", 18, 6) * runif(n, .9, 1.1))   # weight ~ sex
  X  <- stats::model.matrix(~sexo, d); tt <- colSums(X * d$pw) * 1.05
  expect_error(suppressMessages(
    prep(step_calibrate(weighting_spec(d, base_weights = pw), method = "linear",
                        formula = ~sexo, totals = tt, cluster = "hogar",
                        equal_within_cluster = TRUE))),
    "constant within|one weight per cluster")
  # also errors under bounds (the old silently-converged path)
  expect_error(suppressMessages(
    prep(step_calibrate(weighting_spec(d, base_weights = pw), method = "linear",
                        formula = ~sexo, totals = tt, cluster = "hogar",
                        equal_within_cluster = TRUE, bounds = c(.2, 5)))),
    "constant within|one weight per cluster")
})

test_that("C3: uniform weights close exactly UNDER bounds (check no longer skipped)", {
  set.seed(22); n <- 300
  sexo <- sample(c("H", "M"), n, TRUE)
  d <- data.frame(id = 1:n, sexo = factor(sexo), hogar = rep(1:(n / 2), each = 2),
                  pw = rep(10, n))
  X  <- stats::model.matrix(~sexo, d); tt <- colSums(X * d$pw) * 1.05
  fit <- suppressWarnings(prep(step_calibrate(weighting_spec(d, base_weights = pw),
                        method = "linear", formula = ~sexo, totals = tt, cluster = "hogar",
                        equal_within_cluster = TRUE, bounds = c(.2, 5))))
  w <- fit$final_weight; ach <- colSums(w * X)
  expect_lt(max(abs(ach - tt) / abs(tt)), 1e-3)             # closes within the bounded tol
  expect_true(isTRUE(attr(fit$steps[[1]]$diagnostics, "converged")))
})

test_that("C3: uniform weights: totals exact, one weight per hh (no regression, survey match)", {
  set.seed(23); n <- 300
  sexo <- sample(c("H", "M"), n, TRUE)
  d <- data.frame(id = 1:n, sexo = factor(sexo), hogar = rep(1:(n / 2), each = 2),
                  pw = rep(10, n))
  X  <- stats::model.matrix(~sexo, d); tt <- colSums(X * d$pw) * 1.05
  fit <- prep(step_calibrate(weighting_spec(d, base_weights = pw), method = "linear",
                             formula = ~sexo, totals = tt, cluster = "hogar",
                             equal_within_cluster = TRUE))
  w   <- fit$final_weight; ach <- colSums(w * X)
  expect_lt(max(abs(ach - tt) / abs(tt)), 1e-6)             # closes exactly
  expect_true(isTRUE(attr(fit$steps[[1]]$diagnostics, "converged")))
  by_hh <- tapply(w, d$hogar, function(z) diff(range(z)))   # one weight per hh
  expect_true(max(by_hh) < 1e-8)
})

# --- A1 / A2a / A2b: household-level guards --------------------------------

test_that("A1: household nonresponse with a `by` varying within the cluster errors", {
  d <- data.frame(pw = rep(10, 8),
                  hh  = c("h1","h1","h2","h2","h3","h3","h4","h4"),
                  reg = c("A","B","A","A","B","B","A","B"),   # varies inside h1, h4
                  resp = c(1,1,0,0,1,1,0,0))
  expect_error(suppressMessages(
    prep(step_nonresponse(weighting_spec(d, base_weights = pw), respondent = resp,
                          method = "weighting_class", by = "reg", cluster = "hh"),
         min_cell_n = NULL)),
    "not constant within")
})

test_that("A2a: household nonresponse with NA in the cluster id errors", {
  d <- data.frame(pw = rep(10, 8),
                  hh  = c("h1","h1","h2","h2", NA, NA,"h3","h3"),
                  reg = rep("A", 8), resp = c(1,1,0,0,1,1,1,1))
  expect_error(suppressMessages(
    prep(step_nonresponse(weighting_spec(d, base_weights = pw), respondent = resp,
                          method = "weighting_class", by = "reg", cluster = "hh"),
         min_cell_n = NULL)),
    "missing values")
})

test_that("A2b: unknown_eligibility with NA in the cluster id errors", {
  d <- data.frame(pw = rep(10, 8),
                  hh  = c("h1","h1","h2","h2", NA, NA,"h3","h3"),
                  reg = rep("A", 8), unk = c(0,0,1,1,0,0,0,0))
  expect_error(suppressMessages(
    prep(step_unknown_eligibility(weighting_spec(d, base_weights = pw),
                                  unknown = unk, by = "reg", cluster = "hh"),
         min_cell_n = NULL)),
    "missing values")
})

# --- A3: step_trim_weights(lower = NULL) -----------------------------------

test_that("A3: step_trim_weights(lower = NULL) means no floor (no cryptic error)", {
  d <- data.frame(pw = c(rep(10, 20), 100, 200))
  fit <- prep(step_trim_weights(weighting_spec(d, base_weights = pw),
                                lower = NULL, upper = 25))
  w <- fit$final_weight
  expect_false(anyNA(w))
  expect_lte(max(w), 25 + 1e-8)                    # capped at upper
  expect_equal(sum(w), sum(d$pw), tolerance = 1e-6) # mass preserved
})

# --- A8: failed replicate dropped (self-contained) -------------------------

test_that("A8: boot_total drops an all-NA replicate with a warning", {
  set.seed(9)
  d <- data.frame(pw = rep(10, 20), stratum = rep(c("s1","s2"), each = 10),
                  psu = paste0("p", rep(1:4, each = 5)), y = rnorm(20, 100, 15))
  b <- bootstrap_weights(weighting_spec(d, base_weights = pw), replicates = 20,
                         strata = "stratum", psu = "psu", seed = 1, progress = FALSE)
  b$replicates[, 1] <- NA_real_                    # simulate a failed replicate
  expect_warning(est <- boot_total(b, "y"), "non-finite replicate")
  expect_true(is.finite(est$se))
})

# --- A9: NA in the design ids -> error --------------------------------------

test_that("A9: NA in the stratum id errors before resampling (bootstrap and jackknife)", {
  set.seed(1)
  d <- data.frame(pw = rep(10, 12), stratum = rep(c("s1","s2","s3"), each = 4),
                  psu = paste0("p", rep(1:6, each = 2)), y = rnorm(12))
  d$stratum[3] <- NA
  expect_error(bootstrap_weights(weighting_spec(d, base_weights = pw), replicates = 4,
                                 strata = "stratum", psu = "psu", seed = 1, progress = FALSE),
               "missing values")
  expect_error(jackknife_weights(weighting_spec(d, base_weights = pw),
                                 strata = "stratum", psu = "psu", progress = FALSE),
               "missing values")
})

# --- M1 / M11 ---------------------------------------------------------------

test_that("M1: step_trim_weights(method = 'potter') attaches the Potter curve", {
  set.seed(4)
  d <- data.frame(pw = rgamma(200, shape = 4, rate = 0.2))
  fit <- suppressWarnings(prep(step_trim_weights(weighting_spec(d, base_weights = pw),
                                                 method = "potter")))
  pot <- attr(fit$steps[[1]]$diagnostics, "potter")
  expect_false(is.null(pot))                       # was NULL before the fix
  expect_true(all(c("grid", "mse", "chosen") %in% names(pot)))
})

test_that("M11: weight_factors() on a 0-step recipe returns the base table (no error)", {
  d   <- data.frame(pw = rep(10, 5))
  fit <- prep(weighting_spec(d, base_weights = pw))
  expect_error(weight_factors(fit), NA)            # no 2:length() subscript error
  expect_equal(nrow(weight_factors(fit)), 5L)
})
