# Round-4 audit (2026-09), variance. With `psu = NULL` the jackknife deletes one UNIT at
# a time, which is the right estimator for a direct sample but costs one full re-prep and
# one replicate column per unit: an n x n matrix, 80 GB at n = 100,000. `groups` adds the
# standard device for that case, the delete-a-group jackknife (Kott 2001; Rust and Rao
# 1996): G random groups within each stratum, one deleted per replicate.

jkg_fixture <- function(n = 4000, seed = 9) {
  set.seed(seed)
  d <- data.frame(str = rep(1:4, each = n / 4), w0 = 25, y = stats::rnorm(n, 100, 20))
  list(d = d, p = prep(weighting_spec(d, base_weights = w0), warn = FALSE))
}

test_that("JK9-01: delete-a-group gives G replicates per stratum, not one per unit", {
  fx <- jkg_fixture()
  j1 <- jackknife_weights(fx$p, strata = "str", progress = FALSE)
  jg <- jackknife_weights(fx$p, strata = "str", groups = 50, seed = 1, progress = FALSE)

  expect_equal(j1$R, 4000L)                       # one per unit, as before
  expect_equal(jg$R, 200L)                        # 4 strata x 50 groups
  expect_equal(ncol(jg$replicates), 200L)
  expect_lt(object.size(jg$replicates), object.size(j1$replicates) / 15)
  expect_equal(jg$df, 200L - 4L)                  # G total minus strata
  expect_equal(jg$groups, 50L)

  # balanced groups within each stratum, and the partition is per stratum
  expect_output(print(jg), "delete-a-group, G = 50")
  expect_output(print(jg), "random groups")
})

test_that("JK9-02: the delete-a-group variance tracks the delete-one one", {
  fx <- jkg_fixture()
  se1  <- jack_mean(jackknife_weights(fx$p, strata = "str", progress = FALSE), "y")$se
  # stratified SRS, self-weighting: SE = sqrt(sum_h (n_h/n)^2 s_h^2 / n_h)
  nh   <- table(fx$d$str); n <- nrow(fx$d)
  s2   <- tapply(fx$d$y, fx$d$str, stats::var)
  se_a <- sqrt(sum((as.numeric(nh) / n)^2 * s2 / as.numeric(nh)))
  expect_equal(se1, se_a, tolerance = 0.05)       # delete-one matches the closed form

  for (G in c(50, 100)) {
    seg <- jack_mean(jackknife_weights(fx$p, strata = "str", groups = G, seed = 1,
                                       progress = FALSE), "y")$se
    expect_equal(seg, se1, tolerance = 0.15)      # same estimator, noisier at small G
  }
})

test_that("JK9-03: groups is reproducible, exclusive with psu, and leaves the RNG alone", {
  fx <- jkg_fixture(n = 800)
  a <- jackknife_weights(fx$p, strata = "str", groups = 20, seed = 1, progress = FALSE)
  b <- jackknife_weights(fx$p, strata = "str", groups = 20, seed = 1, progress = FALSE)
  expect_identical(a$replicates, b$replicates)
  c3 <- jackknife_weights(fx$p, strata = "str", groups = 20, seed = 2, progress = FALSE)
  expect_false(identical(a$replicates, c3$replicates))

  expect_error(jackknife_weights(fx$p, groups = 10, psu = "str", progress = FALSE),
               "mutually exclusive")
  expect_error(jackknife_weights(fx$p, groups = 1, progress = FALSE), "groups")

  # the caller's stream is restored, as the rest of the package does (VAR-10)
  set.seed(123); before <- stats::runif(1)
  set.seed(123); invisible(jackknife_weights(fx$p, strata = "str", groups = 20, seed = 7,
                                             progress = FALSE))
  expect_equal(stats::runif(1), before)
})

test_that("JK9-04: a large direct sample is pointed at groups, not scolded", {
  fx <- jkg_fixture(n = 6000)
  w <- testthat::capture_warnings(
    jackknife_weights(fx$p, strata = "str", groups = 40, seed = 1, progress = FALSE))
  expect_length(w, 0L)                             # using groups: nothing to say
  # the unit-level path on a big sample explains the cost and names the alternative
  msg <- testthat::capture_warnings(
    jackknife_weights(fx$p, strata = "str", progress = FALSE))
  expect_true(any(grepl("delete-a-group jackknife: pass groups = 50", msg)))
  expect_true(any(grepl("right estimator for a direct sample", msg)))
})
