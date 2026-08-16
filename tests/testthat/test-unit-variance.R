# Unit tests for R/variance.R: the lonely-PSU handling, the estimator branches
# (vector vs matrix statistics, non-finite replicates) and the survey bridges.
# A tiny 24-unit design keeps the re-prep per replicate cheap.

vd <- data.frame(
  pw     = rep(1, 24),
  region = rep(c("A", "B"), each = 12),
  psu    = rep(1:6, each = 4),
  y      = rep(c(1, 1, 0, 0, 1, 0), each = 4),   # varies BY PSU -> non-zero variance
  stringsAsFactors = FALSE
)
vspec <- weighting_spec(vd, base_weights = pw) |>
  step_calibrate(method = "raking", margins = list(region = c(A = 1200, B = 1200)))

vboot <- bootstrap_weights(vspec, replicates = 20, strata = "region",
                           psu = "psu", seed = 1, progress = FALSE)
vjack <- jackknife_weights(vspec, strata = "region", psu = "psu",
                           progress = FALSE)

# ---------------------------------------------------------------------------
# .collapse_lonely()
# ---------------------------------------------------------------------------

test_that(".collapse_lonely leaves a healthy design untouched", {
  st <- c("a", "a", "b", "b")
  expect_identical(.collapse_lonely(st, c("1", "2", "3", "4")), st)
})

test_that(".collapse_lonely pools several single-PSU strata together", {
  st  <- c("a", "b", "c", "c")
  out <- .collapse_lonely(st, c("1", "2", "3", "4"))
  expect_equal(out[1:2], c("__collapsed__", "__collapsed__"))
  expect_equal(out[3:4], c("c", "c"))
})

test_that(".collapse_lonely merges a single lonely stratum with the smallest one", {
  st  <- c("a", "b", "b", "c", "c", "c")
  out <- .collapse_lonely(st, as.character(1:6))
  expect_equal(out[1:3], rep("__collapsed_b", 3))   # b has 2 PSUs, c has 3
  expect_equal(out[4:6], rep("c", 3))
})

test_that(".collapse_lonely gives up when there is only one stratum", {
  st <- c("a", "a")
  expect_identical(.collapse_lonely(st, c("1", "1")), st)
})

# ---------------------------------------------------------------------------
# bootstrap_weights()
# ---------------------------------------------------------------------------

test_that("bootstrap_weights validates its inputs", {
  expect_error(bootstrap_weights(list(), replicates = 2), "must be a weighting_spec")
  expect_error(bootstrap_weights(vspec, replicates = 2, strata = "nope",
                                 progress = FALSE),
               "Strata column 'nope' not found")
  expect_error(bootstrap_weights(vspec, replicates = 2, psu = "nope",
                                 progress = FALSE),
               "PSU column 'nope' not found")
})

test_that("bootstrap_weights returns a well-formed object", {
  expect_s3_class(vboot, "weightflow_boot")
  expect_equal(dim(vboot$replicates), c(24L, 20L))
  expect_equal(vboot$R, 20L)
  expect_equal(vboot$method, "bootstrap")
  expect_true(all(is.finite(vboot$replicates)))
  expect_output(print(vboot), "weightflow bootstrap")
})

test_that("bootstrap_weights is reproducible from its seed", {
  b2 <- bootstrap_weights(vspec, replicates = 20, strata = "region",
                          psu = "psu", seed = 1, progress = FALSE)
  expect_equal(b2$replicates, vboot$replicates)
})

test_that("bootstrap_weights honours the `m` argument", {
  b <- bootstrap_weights(vspec, replicates = 5, strata = "region", psu = "psu",
                         m = 2, seed = 2, progress = FALSE)
  expect_equal(dim(b$replicates), c(24L, 5L))
  expect_true(all(is.finite(b$replicates)))
})

test_that("lonely_psu = 'collapse' resamples a single-PSU stratum instead of warning", {
  d <- data.frame(pw = rep(1, 16),
                  region = c(rep("A", 12), rep("B", 4)),
                  psu    = c(rep(1:3, each = 4), rep(4, 4)),
                  stringsAsFactors = FALSE)
  # a rescale step (not raking) so a replicate that drops PSU 4 entirely still
  # preps cleanly and the only warning under "certainty" is the lonely-PSU one
  sp <- weighting_spec(d, base_weights = pw) |> step_rescale(to = "n")

  w_cert <- testthat::capture_warnings(
    bootstrap_weights(sp, replicates = 5, strata = "region", psu = "psu",
                      seed = 1, progress = FALSE))
  expect_true(any(grepl("single PSU", w_cert)))

  w_coll <- testthat::capture_warnings(
    b <- bootstrap_weights(sp, replicates = 5, strata = "region", psu = "psu",
                           lonely_psu = "collapse", seed = 1, progress = FALSE))
  expect_false(any(grepl("single PSU", w_coll)))
  expect_equal(b$lonely_psu, "collapse")
})

test_that("bootstrap_weights reports progress when asked", {
  expect_message(
    bootstrap_weights(vspec, replicates = 25, strata = "region", psu = "psu",
                      seed = 3, progress = TRUE),
    "bootstrap replicate 25/25")
})

test_that("bootstrap_weights can fork the replicates across cores", {
  skip_on_cran()
  skip_on_os("windows")
  b <- bootstrap_weights(vspec, replicates = 4, strata = "region", psu = "psu",
                         seed = 5, cores = 2L, progress = FALSE)
  expect_equal(dim(b$replicates), c(24L, 4L))
  expect_equal(b$cores, 2L)
  expect_true(all(is.finite(b$replicates)))
})

# ---------------------------------------------------------------------------
# bootstrap_estimate() and friends
# ---------------------------------------------------------------------------

test_that("bootstrap_estimate rejects a foreign object", {
  expect_error(bootstrap_estimate(list(), function(w, d) sum(w)),
               "must be a weightflow_boot")
})

test_that("boot_total and boot_mean give a finite estimate and a positive se", {
  tot <- boot_total(vboot, "y")
  expect_true(is.finite(tot$estimate) && tot$se > 0)
  expect_true(tot$ci_lower < tot$estimate && tot$estimate < tot$ci_upper)

  mu <- boot_mean(vboot, "y")
  expect_true(mu$estimate >= 0 && mu$estimate <= 1)
  expect_true(is.finite(mu$se))
})

test_that("bootstrap_estimate handles a vector-valued statistic", {
  est <- bootstrap_estimate(vboot, function(w, d)
    c(total = sum(w * d$y), n_active = sum(w > 0)))
  expect_equal(nrow(est), 2L)
  expect_equal(rownames(est), c("total", "n_active"))
  expect_true(all(is.finite(est$se)))
})

test_that("bootstrap_estimate drops non-finite replicates with a warning", {
  b <- vboot; b$replicates[, 1] <- NA_real_
  # NOTE: the statistic must propagate NA. boot_total() uses na.rm = TRUE, so a
  # failed (all-NA) replicate silently evaluates to 0 instead of being dropped.
  expect_warning(est <- bootstrap_estimate(b, function(w, d) sum(w * d$y)),
                 "non-finite replicate")
  expect_true(is.finite(est$se))
})

test_that("bootstrap_estimate honours the confidence level", {
  narrow <- bootstrap_estimate(vboot, function(w, d) sum(w * d$y), level = 0.80)
  wide   <- bootstrap_estimate(vboot, function(w, d) sum(w * d$y), level = 0.99)
  expect_true((wide$ci_upper - wide$ci_lower) >
              (narrow$ci_upper - narrow$ci_lower))
})

# ---------------------------------------------------------------------------
# jackknife_weights()
# ---------------------------------------------------------------------------

test_that("jackknife_weights validates its inputs", {
  expect_error(jackknife_weights(list()), "must be a weighting_spec")
  expect_error(jackknife_weights(vspec, strata = "nope", progress = FALSE),
               "Strata column 'nope' not found")
  expect_error(jackknife_weights(vspec, psu = "nope", progress = FALSE),
               "PSU column 'nope' not found")
})

test_that("jackknife_weights errors when no stratum has two PSUs", {
  d <- data.frame(pw = rep(1, 4), region = c("A", "A", "B", "B"),
                  psu = c(1, 1, 2, 2), stringsAsFactors = FALSE)
  sp <- weighting_spec(d, base_weights = pw) |> step_rescale(to = "n")
  expect_error(jackknife_weights(sp, strata = "region", psu = "psu",
                                 progress = FALSE),
               "no replicates")
})

test_that("jackknife_weights builds one replicate per PSU", {
  expect_s3_class(vjack, "weightflow_jack")
  expect_equal(vjack$R, 6L)                     # 3 PSUs in each of 2 strata
  expect_equal(vjack$rep_nh, rep(3L, 6L))
  expect_equal(sort(unique(vjack$rep_stratum)), c("A", "B"))
  expect_output(print(vjack), "delete-a-PSU")
})

test_that("jackknife_weights collapses a lonely stratum on request", {
  d <- data.frame(pw = rep(1, 16),
                  region = c(rep("A", 12), rep("B", 4)),
                  psu    = c(rep(1:3, each = 4), rep(4, 4)),
                  stringsAsFactors = FALSE)
  sp <- weighting_spec(d, base_weights = pw) |> step_rescale(to = "n")
  w_coll <- testthat::capture_warnings(
    jk <- jackknife_weights(sp, strata = "region", psu = "psu",
                            lonely_psu = "collapse", progress = FALSE))
  expect_false(any(grepl("single PSU", w_coll)))
  expect_equal(jk$R, 4L)                        # all 4 PSUs now resampled
})

# ---------------------------------------------------------------------------
# jackknife_estimate() and friends
# ---------------------------------------------------------------------------

test_that("jackknife_estimate rejects a foreign object", {
  expect_error(jackknife_estimate(list(), function(w, d) sum(w)),
               "must be a weightflow_jack")
})

test_that("jack_total and jack_mean give a finite estimate and a positive se", {
  tot <- jack_total(vjack, "y")
  expect_true(is.finite(tot$estimate) && tot$se > 0)
  mu <- jack_mean(vjack, "y")
  expect_true(mu$estimate >= 0 && mu$estimate <= 1)
  expect_true(is.finite(mu$se))
})

test_that("jackknife_estimate handles a vector-valued statistic", {
  est <- jackknife_estimate(vjack, function(w, d)
    c(total = sum(w * d$y), n_active = sum(w > 0)))
  expect_equal(nrow(est), 2L)
  expect_equal(rownames(est), c("total", "n_active"))
  expect_true(all(is.finite(est$se)))
})

test_that("jackknife_estimate drops non-finite replicates with a warning", {
  j <- vjack; j$replicates[, 1] <- NA_real_
  # as above: jack_total() uses na.rm = TRUE and would not see the failure
  expect_warning(est <- jackknife_estimate(j, function(w, d) sum(w * d$y)),
                 "non-finite replicate")
  expect_true(is.finite(est$se))
})

test_that("a failed replicate is dropped by boot_total (with a warning), not counted as 0", {
  # Fixed 2026-08 (A8): boot_total()/jack_total() return NA for an all-NA
  # replicate, so the existing good-replicate filter drops it and warns, instead
  # of the failed replicate contributing a spurious 0 that inflated the SE.
  b <- vboot; b$replicates[, 1] <- NA_real_
  clean  <- boot_total(vboot, "y")
  expect_warning(broken <- boot_total(b, "y"), "non-finite replicate")
  expect_equal(broken$estimate, clean$estimate)
  expect_true(is.finite(broken$se))
  expect_lt(broken$se, clean$se * 1.5)          # no longer blown up by the failed replicate
})

# ---------------------------------------------------------------------------
# as_svydesign() / as_svrepdesign()
# ---------------------------------------------------------------------------

test_that("as_svydesign accepts a prepped recipe and a plain data frame", {
  skip_if_not_installed("survey")
  rec <- prep(vspec)
  d1  <- as_svydesign(rec, ids = "psu", strata = "region")
  expect_s3_class(d1, "survey.design")

  df <- vd; df$.weight <- rec$final_weight
  d2 <- as_svydesign(df, ids = ~ psu, strata = ~ region)   # formulas also work
  expect_s3_class(d2, "survey.design")
})

test_that("as_svydesign validates its input", {
  skip_if_not_installed("survey")
  expect_error(as_svydesign(vd, ids = "psu"), "not found; pass weight_name")
  expect_error(as_svydesign(1:10, ids = "psu"),
               "prepped recipe or a data frame")
})

test_that("as_svrepdesign drops failed replicates and says so", {
  skip_if_not_installed("survey")
  b <- vboot; b$replicates[, 1] <- NA_real_
  expect_warning(rd <- as_svrepdesign(b), "failed replicate")
  expect_s3_class(rd, "svyrep.design")
})

test_that("as_svrepdesign refuses an all-NA replicate matrix", {
  skip_if_not_installed("survey")
  b <- vboot; b$replicates[] <- NA_real_
  expect_error(as_svrepdesign(b), "every replicate failed")
})

test_that("as_svrepdesign refuses an object of the wrong class", {
  skip_if_not_installed("survey")
  b <- vboot; class(b) <- "not_a_weightflow_object"
  expect_error(as_svrepdesign(b), "weightflow_boot or weightflow_jack")
})

# ---------------------------------------------------------------------------
# collect_replicate_weights()
# ---------------------------------------------------------------------------

test_that("collect_replicate_weights refuses a foreign object", {
  expect_error(collect_replicate_weights(list()),
               "weightflow_boot or weightflow_jack")
})

test_that("collect_replicate_weights carries the bootstrap design in attributes", {
  df <- collect_replicate_weights(vboot)
  expect_true(all(c(".weight", "rep_1", "rep_20") %in% names(df)))
  expect_equal(attr(df, "R"), 20L)
  expect_equal(attr(df, "type"), "bootstrap")
  expect_equal(attr(df, "scale"), 1 / 20)
  expect_equal(attr(df, "rscales"), rep(1, 20))
})

test_that("collect_replicate_weights carries the jackknife design in attributes", {
  df <- collect_replicate_weights(vjack)
  expect_equal(attr(df, "type"), "other")
  expect_equal(attr(df, "scale"), 1)
  expect_equal(attr(df, "rscales"), (vjack$rep_nh - 1) / vjack$rep_nh)
})

test_that("collect_replicate_weights can keep the inactive units", {
  df <- collect_replicate_weights(vboot, drop_zero = FALSE,
                                  weight_name = "wt", prefix = "b")
  expect_equal(nrow(df), nrow(vd))
  expect_true("wt" %in% names(df))
  expect_true("b1" %in% names(df))
})
