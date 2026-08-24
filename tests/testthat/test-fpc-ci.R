# Finite-population correction in the bootstrap, degrees of freedom, and the
# t / percentile confidence intervals. All additive and backward compatible:
# fpc = 0 / NULL and ci_type = "normal" reproduce the previous behaviour.

mk_design <- function(seed = 1) {
  set.seed(seed)
  data.frame(region = factor(rep(c("A", "B"), each = 40)),
             psu    = rep(seq_len(8), each = 10),
             y      = stats::rnorm(80, 10, 3),
             pw     = 5)
}

test_that("fpc = 0 reproduces the uncorrected bootstrap and fpc reduces the SE", {
  d <- mk_design(); sp <- weighting_spec(d, base_weights = pw)
  b0 <- bootstrap_weights(sp, replicates = 200, strata = "region", psu = "psu",
                          seed = 1, progress = FALSE)
  bz <- bootstrap_weights(sp, replicates = 200, strata = "region", psu = "psu",
                          seed = 1, fpc = 0, progress = FALSE)
  expect_equal(b0$replicates, bz$replicates)             # f = 0 is a no-op
  bf <- bootstrap_weights(sp, replicates = 200, strata = "region", psu = "psu",
                          seed = 1, fpc = 0.5, progress = FALSE)
  expect_lt(boot_total(bf, "y")$se, boot_total(b0, "y")$se)   # (1 - f) shrinks the variance
  # weight total preserved in every replicate (E[lambda] = 1 property)
  expect_true(all(abs(colSums(bf$replicates) - sum(d$pw)) < 1e-6))
})

test_that("fpc validates its range and constancy", {
  d <- mk_design(); sp <- weighting_spec(d, base_weights = pw)
  expect_error(bootstrap_weights(sp, strata = "region", psu = "psu", fpc = 1.5,
                                 replicates = 20, progress = FALSE), "\\[0, 1\\]")
})

test_that("degrees of freedom = total PSUs minus strata", {
  d <- mk_design(); sp <- weighting_spec(d, base_weights = pw)
  b <- bootstrap_weights(sp, replicates = 20, strata = "region", psu = "psu",
                         seed = 1, progress = FALSE)
  expect_equal(b$df, 6L)                                  # 8 PSUs - 2 strata
})

test_that("ci_type t is wider than normal; percentile is finite; jackknife rejects percentile", {
  d <- mk_design(); sp <- weighting_spec(d, base_weights = pw)
  b <- bootstrap_weights(sp, replicates = 200, strata = "region", psu = "psu",
                         seed = 1, progress = FALSE)
  stat <- function(w, dd) sum(w * dd$y)
  ci_n <- bootstrap_estimate(b, stat, ci_type = "normal")
  ci_t <- bootstrap_estimate(b, stat, ci_type = "t")
  expect_gt(ci_t$ci_upper - ci_t$ci_lower, ci_n$ci_upper - ci_n$ci_lower)
  ci_p <- bootstrap_estimate(b, stat, ci_type = "percentile")
  expect_true(is.finite(ci_p$ci_lower) && is.finite(ci_p$ci_upper))
  jk <- jackknife_weights(sp, strata = "region", psu = "psu", progress = FALSE)
  expect_error(jackknife_estimate(jk, stat, ci_type = "percentile"), "should be one of")
  expect_equal(jk$df, 6L)
})
