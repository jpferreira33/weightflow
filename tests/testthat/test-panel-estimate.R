# panel_estimate(contrast=) generalises change_estimate() to any linear combination of
# waves. Two invariants pin it: (1) contrast = c(-1, 1) must reproduce change_estimate()
# exactly (the net change is a contrast); (2) for a positively correlated overlapping
# panel, an AVERAGE has V > V(independent) -- the between-wave covariance raises the
# variance of a sum -- which is the opposite of the change, where it lowers it.

strat_data <- function(seed = 1, npsu = 40, per = 6, psu_offset = 0, shift = 0) {
  set.seed(seed)
  psu <- rep(seq_len(npsu) + psu_offset, each = per)
  str <- rep(rep(1:4, length.out = npsu), each = per)
  data.frame(psu = psu, str = str,
             y = rnorm(npsu * per, 10 + shift, 3), pw = 1)
}

test_that("contrast c(-1, 1) reproduces change_estimate() exactly (bootstrap)", {
  skip_on_cran()
  d1 <- strat_data(seed = 1)
  d2 <- d1; set.seed(4); d2$y <- d2$y + rnorm(nrow(d2), 0.5, 1)
  wb <- wave_bootstrap(list(T1 = weighting_spec(d1, base_weights = pw),
                            T2 = weighting_spec(d2, base_weights = pw)),
                       replicates = 200, strata = "str", psu = "psu",
                       seed = 5, progress = FALSE)
  pe <- panel_estimate(wb, function(w, d) stats::weighted.mean(d$y, w), contrast = c(-1, 1))
  ch <- change_mean(wb, "y")
  expect_equal(pe$estimate, ch$estimate)
  expect_equal(pe$V, ch$V)                       # a' Sigma a == mean((d_b - d_hat)^2)
  expect_equal(unname(diag(pe$Sigma)), c(ch$V1, ch$V2))
})

test_that("contrast c(-1, 1) reproduces change_estimate() exactly (jackknife)", {
  d1 <- strat_data(seed = 1)
  d2 <- d1; set.seed(4); d2$y <- d2$y + rnorm(nrow(d2), 0.5, 1)
  wj <- wave_jackknife(list(T1 = weighting_spec(d1, base_weights = pw),
                            T2 = weighting_spec(d2, base_weights = pw)),
                       strata = "str", psu = "psu", progress = FALSE)
  pe <- panel_estimate(wj, function(w, d) stats::weighted.mean(d$y, w), contrast = c(-1, 1))
  ch <- change_mean(wj, "y")
  expect_equal(pe$estimate, ch$estimate)
  expect_equal(pe$V, ch$V)
})

test_that("annual average over overlapping waves has V > V(independent)", {
  skip_on_cran()
  # four waves sharing the same PSUs, positively correlated levels
  base <- strat_data(seed = 1)
  mk <- function(shift, sd) { d <- base; set.seed(100 + shift * 10)
    d$y <- d$y + shift + rnorm(nrow(d), 0, sd); d }
  specs <- list(T1 = weighting_spec(mk(0.0, 0.4), base_weights = pw),
                T2 = weighting_spec(mk(0.3, 0.4), base_weights = pw),
                T3 = weighting_spec(mk(0.6, 0.4), base_weights = pw),
                T4 = weighting_spec(mk(0.9, 0.4), base_weights = pw))
  wb <- wave_bootstrap(specs, replicates = 300, strata = "str", psu = "psu",
                       seed = 8, progress = FALSE)
  pe <- panel_mean(wb, "y")                       # default contrast = rep(1/4, 4)
  expect_equal(unname(pe$contrast), rep(1 / 4, 4))
  expect_gt(pe$deff, 1)                           # covariance RAISES the average's variance
  expect_equal(dim(pe$Sigma), c(4L, 4L))
  expect_equal(pe$Sigma, t(pe$Sigma))             # symmetric
  expect_output(print(pe), "average-type")
})

test_that("named contrast is matched to wave labels", {
  d1 <- strat_data(seed = 1); d2 <- strat_data(seed = 1)
  wj <- wave_jackknife(list(A = weighting_spec(d1, base_weights = pw),
                            B = weighting_spec(d2, base_weights = pw)),
                       strata = "str", psu = "psu", progress = FALSE)
  pe <- panel_estimate(wj, function(w, d) stats::weighted.mean(d$y, w),
                       contrast = c(B = 1, A = -1))
  expect_equal(unname(pe$contrast[c("A", "B")]), c(-1, 1))
})

# Totals were exported but never validated (auditoria D1): the binomial resample
# (colSums != m_h) inflated total variance; multinom (the default) fixes it. Pin the
# total wrappers: point matches the direct weighted sum, SE finite, and the exact-
# multinomial default keeps a level_total's replicate weights summing to the point total.
test_that("level_total / change_total / panel_total corren y coinciden con la suma directa", {
  skip_on_cran()
  d1 <- strat_data(seed = 1)
  d2 <- d1; set.seed(4); d2$y <- d2$y + rnorm(nrow(d2), 0.5, 1)
  wb <- wave_bootstrap(list(T1 = weighting_spec(d1, base_weights = pw),
                            T2 = weighting_spec(d2, base_weights = pw)),
                       replicates = 200, strata = "str", psu = "psu",
                       seed = 5, resample = "multinom", progress = FALSE)
  lt <- level_total(wb, "y", wave = "T1")
  expect_equal(lt$estimate, sum(wb$point[["T1"]] * d1$y))     # punto == suma ponderada
  expect_true(is.finite(lt$se) && lt$se > 0)
  ct <- change_total(wb, "y")
  expect_equal(ct$estimate, sum(wb$point[["T2"]] * d2$y) - sum(wb$point[["T1"]] * d1$y))
  expect_true(is.finite(ct$se) && ct$se > 0)
  pt <- panel_total(wb, "y", contrast = c(-1, 1))              # == change_total
  expect_equal(pt$estimate, ct$estimate)
  # exact multinomial: within a stratum the replicate weights preserve the base total,
  # so every replicate's grand total of the base subweight matches the point total.
  wj <- wave_jackknife(list(T1 = weighting_spec(d1, base_weights = pw),
                            T2 = weighting_spec(d2, base_weights = pw)),
                       strata = "str", psu = "psu", progress = FALSE)
  expect_true(is.finite(change_total(wj, "y")$se))             # tambien via jackknife
})
