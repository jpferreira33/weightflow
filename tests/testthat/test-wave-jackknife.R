# Coordinated delete-one jackknife: the deterministic oracle for panel change.
# It shares change_estimate()/change_mean() with the bootstrap, so the same two
# limiting cases pin the coordination -- full overlap of identical waves gives
# Var(change) = 0 (rho = 1); disjoint PSUs give no covariance (rho ~ 0). Being
# deterministic, the disjoint case here is EXACT (V == V1 + V2), not approximate.

strat_data <- function(seed = 1, npsu = 40, per = 6, psu_offset = 0, shift = 0) {
  set.seed(seed)
  psu <- rep(seq_len(npsu) + psu_offset, each = per)
  str <- rep(rep(1:4, length.out = npsu), each = per)
  data.frame(psu = psu, str = str,
             y = rnorm(npsu * per, 10 + shift, 3), pw = 1)
}

test_that("wave_jackknife returns the expected structure", {
  d  <- strat_data()
  sp <- weighting_spec(d, base_weights = pw)
  wj <- wave_jackknife(list(T1 = sp, T2 = sp), strata = "str", psu = "psu", progress = FALSE)
  expect_s3_class(wj, "weightflow_wave_jack")
  expect_identical(wj$waves, c("T1", "T2"))
  expect_identical(length(wj$union_psu), 40L)
  expect_equal(dim(wj$reps$T1), c(nrow(d), 40L))
})

test_that("full overlap of identical waves gives zero change variance (rho = 1)", {
  d  <- strat_data()
  sp <- weighting_spec(d, base_weights = pw)
  wj <- wave_jackknife(list(T1 = sp, T2 = sp), strata = "str", psu = "psu", progress = FALSE)
  ch <- change_mean(wj, "y")
  expect_equal(ch$estimate, 0)
  expect_equal(ch$V, 0)
  expect_equal(ch$rho, 1)
  expect_true(ch$V1 > 0 && ch$V2 > 0)
  expect_match(capture.output(print(ch))[1], "jackknife")
})

test_that("disjoint PSUs give EXACTLY no covariance (V == V1 + V2)", {
  d1 <- strat_data(seed = 1)
  d2 <- strat_data(seed = 2, psu_offset = 1000, shift = 0.5)   # disjoint PSU ids
  wj <- wave_jackknife(list(T1 = weighting_spec(d1, base_weights = pw),
                            T2 = weighting_spec(d2, base_weights = pw)),
                       strata = "str", psu = "psu", progress = FALSE)
  ch <- change_mean(wj, "y")
  expect_equal(ch$cov, 0)                 # deterministic: no shared PSU -> exactly 0
  expect_equal(ch$rho, 0)
  expect_equal(ch$V, ch$Vind)
})

test_that("full-overlap jackknife equals the plain delete-one JK of the difference", {
  # oracle-of-the-oracle: with all PSUs shared and same strata, the coordinated
  # jackknife must reproduce the textbook stratified delete-one JK applied to the
  # per-PSU difference d = y2 - y1. Compute that by hand and compare.
  d1 <- strat_data(seed = 1)
  d2 <- d1; set.seed(9); d2$y <- d2$y + rnorm(nrow(d2), 0.5, 1)   # same PSUs
  wj <- wave_jackknife(list(T1 = weighting_spec(d1, base_weights = pw),
                            T2 = weighting_spec(d2, base_weights = pw)),
                       strata = "str", psu = "psu", progress = FALSE)
  ch <- change_mean(wj, "y")

  # hand-rolled stratified delete-one JK of theta2 - theta1 (means). Must use the
  # SAME per-replicate estimator as the implementation: delete PSU g and reweight its
  # stratum mates by n_h/(n_h-1) (standard survey delete-one-cluster jackknife).
  psu <- d1$psu; str <- d1$str
  hat <- mean(d2$y) - mean(d1$y)
  upsu <- unique(psu); ps <- str[match(upsu, psu)]
  nh_str <- table(ps)
  Dg <- sapply(upsu, function(g) {
    h  <- ps[match(g, upsu)]; nh <- as.integer(nh_str[as.character(h)])
    w  <- rep(1, nrow(d1))
    w[str == h] <- nh / (nh - 1)          # reweight stratum mates
    w[psu == g] <- 0                       # delete this PSU
    sum(w * d2$y) / sum(w) - sum(w * d1$y) / sum(w)
  })
  Vh <- 0
  for (h in unique(ps)) {
    idx <- ps == h; nh <- sum(idx)
    Vh <- Vh + (nh - 1) / nh * sum((Dg[idx] - mean(Dg[idx]))^2)
  }
  expect_equal(ch$estimate, hat, tolerance = 1e-8)
  expect_equal(ch$V, Vh, tolerance = 1e-6)      # coordinated JK == textbook JK of the difference
})

test_that("overlap lowers the variance of change below independence", {
  d1 <- strat_data(seed = 1)
  d2 <- d1; set.seed(3); d2$y <- d2$y + rnorm(nrow(d2), 0.5, 1)
  wj <- wave_jackknife(list(T1 = weighting_spec(d1, base_weights = pw),
                            T2 = weighting_spec(d2, base_weights = pw)),
                       strata = "str", psu = "psu", progress = FALSE)
  ch <- change_mean(wj, "y")
  expect_true(ch$rho > 0.5)                     # strong positive correlation
  expect_lt(ch$V, ch$Vind)
})
