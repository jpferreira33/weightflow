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

# --- A5: duplicate category in tidy linear totals is summed ----------------

test_that("A5: a duplicate category in tidy linear/GREG totals is summed, not overwritten", {
  set.seed(5); n <- 200
  d <- data.frame(pw = rep(10, n),
                  region = sample(c("North", "South", "East", "West"), n, TRUE))
  # South duplicated (as census tables disaggregated by extra variables arrive)
  tot <- list(region = data.frame(
    region = c("North", "South", "South", "East", "West"),
    n      = c(600, 300, 350, 500, 450)))          # South intended = 300 + 350 = 650
  fit <- suppressMessages(prep(step_calibrate(weighting_spec(d, base_weights = pw),
    method = "linear", formula = ~ region, totals = tot, count = "n")))
  expect_equal(sum(fit$final_weight[d$region == "South"]), 650, tolerance = 1e-6)
  expect_message(prep(step_calibrate(weighting_spec(d, base_weights = pw),
    method = "linear", formula = ~ region, totals = tot, count = "n")),
    "duplicate category")
})

# --- A6: population level absent from the sample errors (tidy linear) -------

test_that("A6: a population level with no units in the sample errors (tidy linear/GREG)", {
  set.seed(6); n <- 200
  d <- data.frame(pw = rep(10, n),
                  region = sample(c("North", "South", "East"), n, TRUE))   # no West
  tot <- list(region = data.frame(
    region = c("North", "South", "East", "West"),   # West is in totals, not in sample
    n      = c(600, 500, 400, 300)))
  expect_error(suppressMessages(prep(step_calibrate(weighting_spec(d, base_weights = pw),
    method = "linear", formula = ~ region, totals = tot, count = "n"))),
    "no units in the sample")
})

# --- M5: by-domain calibration propagates the converged flag ---------------

test_that("M5: by-domain calibration sets a converged flag (was NULL -> looked green)", {
  set.seed(5); n <- 300
  d <- data.frame(pw = rep(10, n),
                  region = sample(c("A", "B"), n, TRUE),
                  sex    = sample(c("M", "F"), n, TRUE))
  m <- as.data.frame(stats::xtabs(pw ~ region + sex, d))   # region (domain) x sex + Freq
  m$Freq <- m$Freq * 1.05
  fit <- suppressMessages(prep(step_calibrate(weighting_spec(d, base_weights = pw),
    method = "raking", totals = list(m), count = "Freq", by = "region")))
  cvg <- attr(fit$steps[[1]]$diagnostics, "converged")
  expect_false(is.null(cvg))          # previously NULL for the by-domain path
  expect_true(isTRUE(cvg))            # clean case: every domain converged
})

# --- M10: bootstrap does not leak its RNG into the caller -------------------

test_that("M10: a seeded bootstrap leaves the caller's RNG stream unchanged", {
  set.seed(1)
  d <- data.frame(pw = rep(10, 20), stratum = rep(c("s1", "s2"), each = 10),
                  psu = paste0("p", rep(1:4, each = 5)), y = rnorm(20))
  set.seed(123); a <- runif(1)
  set.seed(123)
  invisible(bootstrap_weights(weighting_spec(d, base_weights = pw), replicates = 10,
                              strata = "stratum", psu = "psu", seed = 7, progress = FALSE))
  b <- runif(1)
  expect_equal(a, b)                  # RNG continues as if the bootstrap never ran
})

# --- M12: collect_replicate_weights drops failed replicates -----------------

test_that("M12: collect_replicate_weights drops a failed replicate and warns", {
  set.seed(2)
  d <- data.frame(pw = rep(10, 20), stratum = rep(c("s1", "s2"), each = 10),
                  psu = paste0("p", rep(1:4, each = 5)), y = rnorm(20))
  b <- bootstrap_weights(weighting_spec(d, base_weights = pw), replicates = 10,
                         strata = "stratum", psu = "psu", seed = 1, progress = FALSE)
  b$replicates[, 1] <- NA_real_                        # a failed replicate
  expect_warning(df <- collect_replicate_weights(b), "failed replicate")
  expect_equal(sum(grepl("^rep_", names(df))), 9L)     # 10 - 1 dropped
  expect_equal(attr(df, "R"), 9L)
  expect_equal(length(attr(df, "rscales")), 9L)
  expect_false(anyNA(df[, grepl("^rep_", names(df)), drop = FALSE]))
})

# --- M13: NA count in poststratification totals errors ----------------------

test_that("M13: an NA in the counts column of poststratification totals errors", {
  set.seed(13)
  d <- data.frame(pw = rep(10, 30), region = sample(c("A", "B", "C"), 30, TRUE))
  tot <- data.frame(region = c("A", "B", "C"), Freq = c(120, NA, 90))
  expect_error(prep(step_calibrate(weighting_spec(d, base_weights = pw),
    method = "poststratify", totals = tot, count = "Freq")),
    "missing values")
})

# --- M15: NA in a `by` cell variable -> explicit (missing) cell + warning ----

test_that("M15: NA in a `by` cell forms a '(missing)' group with a warning", {
  set.seed(15)
  d <- data.frame(pw = rep(10, 40), grp = sample(c("A", "B"), 40, TRUE),
                  resp = rbinom(40, 1, .7))
  d$grp[c(3, 7, 11)] <- NA
  expect_warning(
    f <- suppressMessages(prep(step_nonresponse(weighting_spec(d, base_weights = pw),
      respondent = resp, method = "weighting_class", by = "grp"), min_cell_n = NULL)),
    "missing")
  expect_false(anyNA(f$final_weight))          # the (missing) cell is handled, not NA
})

# --- M16: collect_weights with an NA weight -> no phantom rows ---------------

test_that("M16: collect_weights() with an NA weight drops it, no phantom all-NA rows", {
  f <- prep(weighting_spec(data.frame(pw = rep(10, 5)), base_weights = pw))
  f$final_weight[2] <- NA_real_                 # inject an NA weight
  cw <- collect_weights(f)                      # drop_zero = TRUE
  expect_equal(nrow(cw), 4L)                    # NA row dropped, no phantom row
  expect_false(anyNA(cw$.weight))
})

# --- Round 2 -----------------------------------------------------------------

test_that("NUEVO-3: a non-finite weight mid-cascade errors instead of propagating", {
  d <- data.frame(pw = rep(10, 20), p = c(1e-320, rep(0.5, 19)))
  expect_error(
    prep(step_select_within(weighting_spec(d, base_weights = pw), prob = p)),
    "non-finite")
})

test_that("M2: step_trim_weights(lower >= upper) errors", {
  d <- data.frame(pw = c(rep(1, 20), 5, 8, 12))
  expect_error(
    prep(step_trim_weights(weighting_spec(d, base_weights = pw), lower = 10, upper = 5)),
    "strictly below")
})

test_that("M2: step_trim(min_ratio >= max_ratio) errors", {
  d <- data.frame(pw = c(rep(1, 20), 5, 8, 12))
  expect_error(
    prep(step_trim(weighting_spec(d, base_weights = pw),
                   max_ratio = 3, min_ratio = 5, reference = "value")),
    "strictly below")
})

test_that("NUEVO-4: trimming that inflates the total now raises an alert", {
  set.seed(44); d <- data.frame(pw = rgamma(200, shape = 3, rate = 0.3))   # mean ~10
  f <- suppressWarnings(prep(step_trim_weights(weighting_spec(d, base_weights = pw),
                                               lower = 20, upper = 25)))
  expect_true(any(grepl("increased the weight total", f$alerts)))
})

test_that("NUEVO-1: step_assert is a no-op inside replicates (does not kill the bootstrap)", {
  set.seed(1)
  d <- data.frame(pw = rep(10, 60), stratum = rep(c("s1", "s2"), each = 30),
                  psu = paste0("p", rep(1:6, each = 10)),
                  grp = sample(c("A", "B"), 60, TRUE),
                  resp = rbinom(60, 1, .8), y = rnorm(60, 100, 20))
  base <- weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "grp")
  dp   <- design_effect(prep(base)$final_weight)$deff       # point-weight deff
  spec <- base |> step_assert(max_deff = dp * 1.05, on_fail = "error")
  b <- suppressWarnings(bootstrap_weights(spec, replicates = 30, strata = "stratum",
                                          psu = "psu", seed = 7, progress = FALSE))
  nfail <- b$R - sum(apply(is.finite(b$replicates), 2, all))
  expect_lt(nfail, b$R)                                     # not ALL replicates failed
  expect_true(is.finite(boot_total(b, "y")$se))             # SE is finite (was NaN)
})

test_that("NUEVO-5: a zero-length `by` errors instead of skipping the step", {
  d <- data.frame(pw = rep(10, 20), grp = sample(c("A", "B"), 20, TRUE),
                  resp = rbinom(20, 1, .7))
  expect_error(
    prep(step_nonresponse(weighting_spec(d, base_weights = pw), respondent = resp,
                          method = "weighting_class", by = character(0))),
    "length 0")
})

test_that("NUEVO-6: an invalid maxit errors instead of silently skipping the trim", {
  d <- data.frame(pw = c(rep(1, 20), 5, 8, 12))
  expect_error(
    prep(step_trim_weights(weighting_spec(d, base_weights = pw), upper = 15, maxit = 0)),
    "integer >= 1")
})

test_that("NUEVO-7: a non-logical weight_model errors instead of flipping the estimator", {
  d <- data.frame(pw = rep(10, 30), x = rnorm(30), resp = rbinom(30, 1, .7))
  expect_error(
    step_nonresponse(weighting_spec(d, base_weights = pw), respondent = resp,
                     method = "propensity", formula = ~x, weight_model = 1),
    "TRUE or FALSE")
})

test_that("NUEVO-11: JKn stays finite and rescales when replicates drop", {
  set.seed(11)
  d <- data.frame(pw = rep(10, 40), stratum = rep(c("s1", "s2"), each = 20),
                  psu = paste0("p", rep(1:8, each = 5)), y = rnorm(40, 100, 15))
  jk <- jackknife_weights(weighting_spec(d, base_weights = pw),
                          strata = "stratum", psu = "psu", progress = FALSE)
  se_full <- jack_total(jk, "y")$se
  jk2 <- jk; jk2$replicates[, 1:2] <- NA_real_               # drop 2 replicates
  expect_warning(se_drop <- jack_total(jk2, "y")$se, "non-finite")
  expect_true(is.finite(se_drop) && se_drop > 0)
  expect_gt(se_drop, se_full * 0.5)                          # rescaled, not collapsed low
})

test_that("A10/NUEVO-2: a negative weight stays active (collect_weights, design_effect)", {
  f <- prep(weighting_spec(data.frame(pw = rep(10, 5)), base_weights = pw))
  f$final_weight[2] <- -3                                    # a negative (active) weight
  cw <- collect_weights(f)
  expect_equal(nrow(cw), 5L)                                 # negative kept, not dropped
  expect_equal(sum(cw$.weight), sum(f$final_weight), tolerance = 1e-9)
  expect_equal(design_effect(f$final_weight)$n, 5L)          # negative counted as active
})

test_that("Bloque 2 (variance): level, variable and replicates are validated", {
  set.seed(2)
  d <- data.frame(pw = rep(10, 20), stratum = rep(c("s1", "s2"), each = 10),
                  psu = paste0("p", rep(1:4, each = 5)), y = rnorm(20))
  b <- bootstrap_weights(weighting_spec(d, base_weights = pw), replicates = 10,
                         strata = "stratum", psu = "psu", seed = 1, progress = FALSE)
  expect_error(bootstrap_estimate(b, function(w, dd) sum(w * dd$y), level = 95),
               "between 0 and 1")                                  # N-18
  expect_error(boot_total(b, "no_existe"), "column name present")  # NUEVO-8
  expect_error(bootstrap_weights(weighting_spec(d, base_weights = pw), replicates = 0,
                                 strata = "stratum", psu = "psu", progress = FALSE),
               "integer >= 2")                                     # B4
})

test_that("N-22: prep() validates warn / min_cell_n / max_factor", {
  s <- weighting_spec(data.frame(pw = rep(10, 5)), base_weights = pw)
  expect_error(prep(s, warn = "yes"), "TRUE or FALSE")
  expect_error(prep(s, min_cell_n = NA), "non-negative")
  expect_error(prep(s, max_factor = -1), "positive number")
})

test_that("N-27: step_rescale(to = 'total') validates total", {
  d <- data.frame(pw = rep(10, 5))
  expect_error(prep(step_rescale(weighting_spec(d, base_weights = pw), to = "total", total = 0)),
               "positive")
  expect_error(prep(step_rescale(weighting_spec(d, base_weights = pw), to = "total", total = -5)),
               "positive")
})

test_that("N-28: step_select_within with a factor prob errors (not integer codes)", {
  d <- data.frame(pw = rep(10, 6), hh = rep(1:3, each = 2), p = factor("0.5"))
  expect_error(prep(step_select_within(weighting_spec(d, base_weights = pw), prob = p)),
               "factor")
})

test_that("N-19: collect_weights / collect_replicate_weights validate the output name", {
  f <- prep(weighting_spec(data.frame(pw = rep(10, 5)), base_weights = pw))
  expect_error(collect_weights(f, weight_name = 1),  "non-empty column name")
  expect_error(collect_weights(f, weight_name = ""), "non-empty column name")
})

test_that("B2: a numeric category 100000 matches between totals and data (no sci-notation gap)", {
  d   <- data.frame(pw = rep(10, 20), g = rep(c(100000L, 200000L), each = 10))
  tot <- data.frame(g = c(100000, 200000), Freq = c(120, 90))       # double vs integer
  fit <- prep(step_calibrate(weighting_spec(d, base_weights = pw),
    method = "poststratify", totals = tot, count = "Freq"))
  expect_equal(sum(fit$final_weight[d$g == 100000L]), 120)          # matched, not "no total"
})

test_that("B1: duplicate names in a classic totals vector error", {
  d   <- data.frame(pw = rep(10, 20), sex = rep(c("F", "M"), 10))
  tot <- c("(Intercept)" = 200, sexM = 100, sexM = 999)             # sexM duplicated
  expect_error(prep(step_calibrate(weighting_spec(d, base_weights = pw),
    method = "linear", formula = ~ sex, totals = tot)),
    "duplicate names")
})

test_that("N-15: step_calibrate warns about ignored arguments (cluster with raking)", {
  d <- data.frame(pw = rep(10, 20), region = rep(c("A", "B"), 10))
  expect_warning(
    step_calibrate(weighting_spec(d, base_weights = pw), method = "raking",
                   margins = list(region = c(A = 100, B = 100)), cluster = "region"),
    "ignored")
})

test_that("N-20: report_weighting() survives a non-finite deff (overflow / all-zero base weights)", {
  d <- data.frame(id = 1:60, x = factor(rep(c("A", "B"), 30)),
                  w = rep(1e155, 60),                       # w^2 overflows to Inf -> deff NaN (sum(w) stays finite)
                  resp = rep(c(TRUE, TRUE, FALSE), 20), y = rnorm(60))
  fit <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  f <- tempfile(fileext = ".html")
  expect_error(
    suppressWarnings(suppressMessages(report_weighting(fit, file = f, open = FALSE))),
    NA)                                                     # must not die on "missing value where TRUE/FALSE needed"
})

test_that("N-25: collect_replicate_weights() refuses to collide with an existing column", {
  set.seed(3)
  d <- data.frame(w = runif(60, 1, 3), str = rep(1:3, each = 20),
                  psu = rep(1:12, each = 5), rep_1 = 0)          # stray user column
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w)))
  b <- suppressWarnings(bootstrap_weights(p, replicates = 5, strata = "str", psu = "psu", seed = 1))
  expect_error(collect_replicate_weights(b), "prefix")          # rep_1 would be duplicated
  expect_error(collect_replicate_weights(b, prefix = "boot_"), NA)   # a free prefix works
})

test_that("N-24: report flags an all-failed replicate set instead of showing success", {
  set.seed(4)
  d <- data.frame(w = runif(60, 1, 3), str = rep(1:3, each = 20),
                  psu = rep(1:12, each = 5), y = rnorm(60))
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w)))
  b <- suppressWarnings(bootstrap_weights(p, replicates = 5, strata = "str", psu = "psu", seed = 1))
  b$replicates[] <- NA_real_                                     # simulate every replicate failing
  f <- tempfile(fileext = ".html")
  suppressWarnings(suppressMessages(report_weighting(p, file = f, open = FALSE, replicates = b)))
  h <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_true(grepl("failed", h, ignore.case = TRUE))           # the failure is surfaced
  expect_false(grepl("all usable", h, ignore.case = TRUE))      # not shown as usable
})

test_that("A10 leftovers: plots/weight_factors count negative weights like the rest of the cascade", {
  dat    <- data.frame(x = c(rep(2, 19), 40), pw = rep(1, 20))   # outlier forces a negative g
  totals <- c("(Intercept)" = 20, x = 30)
  fit <- suppressWarnings(suppressMessages(
    weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ x, totals = totals) |>
      step_rescale(to = "total", total = 25) |>
      prep()))
  fw <- fit$final_weight
  expect_true(any(fw < 0))                                       # sanity: a negative weight exists
  nact <- sum(is.finite(fw) & fw != 0)                           # .wf_active count
  expect_equal(design_effect(fit)$n, nact)                       # deff counts the negatives
  expect_equal(nrow(collect_weights(fit)), nact)                 # collect_weights keeps them
  wf   <- weight_factors(fit)
  facs <- grep("^factor_", names(wf), value = TRUE)
  # the factor of the step AFTER the negative appeared is no longer NA for the
  # negative-weight row (weight_factors migrated from `> 0` to .wf_active)
  expect_equal(sum(!is.na(wf[[tail(facs, 1)]])), nact)
  # the negative-weight alert now carries the Kish-deff caveat
  expect_true(any(grepl("not interpretable", fit$alerts)))
})

test_that("step_trim_calibrated help example uses a feasible band [5.5, 13.5] that preserves totals", {
  fit <- suppressMessages(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_calibrate(method = "raking",
                     margins = list(region = c(table(population$region)),
                                    sex    = c(table(population$sex)))) |>
      step_trim_calibrated(~ region + sex, lower = 5.5, upper = 13.5) |>
      prep())
  w   <- fit$final_weight
  reg <- tapply(w, sample_survey$region, sum)
  tgt <- table(population$region)
  expect_equal(as.numeric(reg[names(tgt)]), as.numeric(tgt), tolerance = 1e-3)  # region totals preserved
  active <- w[is.finite(w) & w != 0]
  expect_true(all(active >= 5.5 - 1e-6 & active <= 13.5 + 1e-6))                 # weights inside the band
})

test_that("calfun ignored by raking/poststratify now warns (N-15 sibling)", {
  d <- data.frame(region = rep(c("A", "B"), 20), pw = rep(1, 40))
  expect_warning(
    step_calibrate(weighting_spec(d, base_weights = pw), method = "raking",
                   margins = list(region = c(A = 20, B = 20)), calfun = "logit"),
    "calfun")
  # with method = "linear" calfun applies, so no warning
  expect_warning(
    step_calibrate(weighting_spec(d, base_weights = pw), method = "linear",
                   formula = ~ region, totals = c("(Intercept)" = 40, regionB = 20),
                   calfun = "raking"),
    NA)
})

test_that("A4: step_rescale(by=) is rejected with to='total' and works with to='n'", {
  d <- data.frame(region = rep(c("A", "B"), 20), pw = rep(1, 40))
  sp <- weighting_spec(d, base_weights = pw)
  expect_error(step_rescale(sp, to = "total", total = 100, by = "region"), "by")
  expect_error(step_rescale(sp, to = "n", by = "region"), NA)          # by is valid here
  expect_error(step_rescale(sp, to = "total", total = 100), NA)        # no by, fine
})

test_that("M3: step_trim_weights rejects a named/non-scalar bound", {
  d  <- data.frame(pw = runif(30, 1, 5))
  sp <- weighting_spec(d, base_weights = pw)
  expect_error(step_trim_weights(sp, upper = c(North = 16)), "single unnamed")
  expect_error(step_trim_weights(sp, lower = c(1, 2)),       "single unnamed")
  expect_error(step_trim_weights(sp, upper = 16),            NA)        # scalar OK
})

test_that("M8: step_assert with a non-finite deff fails cleanly instead of crashing", {
  st <- structure(list(max_deff = 1.5, on_fail = "warning"),
                  class = c("step_assert", "weighting_step"))
  # all-zero weights -> design_effect() returns deff = NA; must not error with
  # "missing value where TRUE/FALSE needed"
  expect_warning(apply_step(st, data.frame(x = 1:10), rep(0, 10)), "Assertion")
  st$on_fail <- "error"
  expect_error(apply_step(st, data.frame(x = 1:10), rep(0, 10)), "Assertion")
})

test_that("NUEVO-13: duplicate cells in tidy poststrata totals emit a message (still summed)", {
  d   <- data.frame(pw = rep(10, 30), region = sample(c("A", "B", "C"), 30, TRUE))
  tot <- data.frame(region = c("A", "B", "C", "A"), Freq = c(60, 120, 90, 40))  # A duplicated
  expect_message(fit <- prep(step_calibrate(weighting_spec(d, base_weights = pw),
    method = "poststratify", totals = tot, count = "Freq")), "duplicate cell")
  expect_equal(sum(fit$final_weight[d$region == "A"]), 100)                      # 60 + 40 summed
})
