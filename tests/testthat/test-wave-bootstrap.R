# Coordinated bootstrap for panel change. The two limiting cases pin the coordination:
# full PSU overlap with identical waves -> Var(change) = 0 (rho = 1); disjoint PSUs ->
# no covariance (rho ~ 0). Structure and print are checked too. Full variance recovery
# is proven by Monte Carlo in weightflow_pruebas/prototipo_bootstrap_coordinado.py.

strat_data <- function(seed = 1, npsu = 40, per = 6, psu_offset = 0, shift = 0) {
  set.seed(seed)
  psu <- rep(seq_len(npsu) + psu_offset, each = per)
  str <- rep(rep(1:4, length.out = npsu), each = per)
  data.frame(psu = psu, str = str,
             y = rnorm(npsu * per, 10 + shift, 3), pw = 1)
}

test_that("wave_bootstrap returns the expected structure", {
  skip_on_cran()
  d <- strat_data()
  sp <- weighting_spec(d, base_weights = pw)
  wb <- wave_bootstrap(list(T1 = sp, T2 = sp), replicates = 100,
                       strata = "str", psu = "psu", seed = 7, progress = FALSE)
  expect_s3_class(wb, "weightflow_wave_boot")
  expect_identical(wb$waves, c("T1", "T2"))
  expect_equal(dim(wb$reps$T1), c(nrow(d), 100L))
})

test_that("full overlap of identical waves gives zero change variance (rho = 1)", {
  skip_on_cran()
  d <- strat_data()
  sp <- weighting_spec(d, base_weights = pw)
  wb <- wave_bootstrap(list(T1 = sp, T2 = sp), replicates = 100,
                       strata = "str", psu = "psu", seed = 7, progress = FALSE)
  ch <- change_mean(wb, "y")
  expect_equal(ch$estimate, 0)              # same data -> no change
  expect_equal(ch$V, 0)                     # coordinated identical replicates cancel
  expect_equal(ch$rho, 1)
  expect_true(ch$V1 > 0 && ch$V2 > 0)       # each wave still has its own variance
})

test_that("step_assert is a no-op inside panel replicates (VAR-06)", {
  skip_on_cran()
  # A tight max_deff passes on the (uniform) point weights but every Rao-Wu replicate has
  # a structurally higher deff. Without the wf_replicate flag the assert errored on all
  # replicates -> every column NA. It must be skipped in replicates, leaving a finite SE.
  mk <- function(d) weighting_spec(d, base_weights = pw) |>
    step_assert(max_deff = 1.02, on_fail = "error")
  wb <- wave_bootstrap(list(T1 = mk(strat_data(1)), T2 = mk(strat_data(2, shift = 0.3))),
                       replicates = 30, strata = "str", psu = "psu", seed = 1,
                       progress = FALSE)
  ch <- change_mean(wb, "y")
  expect_true(is.finite(ch$se) && ch$se > 0)
})

test_that("wave_bootstrap restores the caller's RNG state (VAR-10)", {
  skip_on_cran()
  d <- strat_data()
  sp <- weighting_spec(d, base_weights = pw)
  set.seed(123); r1 <- runif(1)
  set.seed(123)
  invisible(wave_bootstrap(list(T1 = sp, T2 = sp), replicates = 30, strata = "str",
                           psu = "psu", seed = 99, progress = FALSE))
  r2 <- runif(1)
  expect_equal(r1, r2)                      # the internal set.seed() did not leak
})

test_that("PSU ids restarted per stratum do not collapse across strata (VAR-09)", {
  skip_on_cran()
  set.seed(1)
  str <- rep(1:4, each = 30); psu_loc <- rep(rep(1:5, each = 6), 4)   # ids 1..5 RESTART per stratum
  d1 <- data.frame(str = str, psu = psu_loc, psu_g = paste(str, psu_loc),
                   y = rnorm(120, 10, 3), pw = 1)
  set.seed(2); d2 <- d1; d2$y <- d2$y + rnorm(120, 0.3, 1)
  se_for <- function(pcol) change_estimate(
    wave_bootstrap(list(T1 = weighting_spec(d1, base_weights = pw),
                        T2 = weighting_spec(d2, base_weights = pw)),
                   replicates = 200, strata = "str", psu = pcol, seed = 5, progress = FALSE),
    function(w, d) weighted.mean(d$y, w))$se
  # nesting the PSU id within its stratum makes the restarted-id result match the
  # globally-unique one; without it the local ids collapsed and understated the SE.
  expect_lt(abs(se_for("psu") - se_for("psu_g")) / se_for("psu_g"), 0.05)
})

test_that("ci_type = 't' widens the panel interval and uses the design df (VAR-14)", {
  skip_on_cran()
  d1 <- strat_data(seed = 1); d2 <- strat_data(seed = 2, shift = 0.4)
  wb <- wave_bootstrap(list(T1 = weighting_spec(d1, base_weights = pw),
                            T2 = weighting_spec(d2, base_weights = pw)),
                       replicates = 100, strata = "str", psu = "psu", seed = 5, progress = FALSE)
  expect_true(is.finite(wb$df) && wb$df >= 1)
  st <- function(w, d) stats::weighted.mean(d$y, w)
  cn <- change_estimate(wb, st)                    # normal (z)
  ct <- change_estimate(wb, st, ci_type = "t")     # Student t
  expect_gt((ct$ci_upper - ct$ci_lower), (cn$ci_upper - cn$ci_lower))
})

test_that("coordination is invariant to row order (VAR-01, multinom default)", {
  skip_on_cran()
  d  <- strat_data()
  d2 <- d[sample(nrow(d)), ]                 # SAME wave, rows shuffled
  wb <- wave_bootstrap(list(T1 = weighting_spec(d, base_weights = pw),
                            T2 = weighting_spec(d2, base_weights = pw)),
                       replicates = 200, strata = "str", psu = "psu", seed = 7,
                       resample = "multinom", progress = FALSE)
  ch <- change_mean(wb, "y")
  # identical waves (bar row order): true change is 0 and so is its variance -- the
  # sequential multinomial must draw the same counts per PSU in both waves regardless
  # of the file's row order. Before the sort() fix this SE was materially > 0.
  expect_equal(ch$estimate, 0, tolerance = 1e-8)
  expect_lt(ch$se, 1e-6)
})

test_that("disjoint PSUs give no covariance (rho ~ 0, V ~ V1 + V2)", {
  skip_on_cran()
  d1 <- strat_data(seed = 1)
  d2 <- strat_data(seed = 2, psu_offset = 1000, shift = 0.5)   # disjoint PSU ids
  wb <- wave_bootstrap(list(T1 = weighting_spec(d1, base_weights = pw),
                            T2 = weighting_spec(d2, base_weights = pw)),
                       replicates = 300, strata = "str", psu = "psu",
                       seed = 3, progress = FALSE)
  ch <- change_mean(wb, "y")
  expect_lt(abs(ch$rho), 0.25)              # no shared PSU -> ~ independent
  expect_equal(ch$V, ch$Vind, tolerance = 0.25)
})

test_that("change_estimate reports the pieces and print works", {
  skip_on_cran()
  d1 <- strat_data(seed = 1)
  d2 <- d1; d2$y <- d2$y + rnorm(nrow(d2), 0.5, 1)             # same PSUs, correlated change
  wb <- wave_bootstrap(list(T1 = weighting_spec(d1, base_weights = pw),
                            T2 = weighting_spec(d2, base_weights = pw)),
                       replicates = 200, strata = "str", psu = "psu",
                       seed = 5, progress = FALSE)
  ch <- change_mean(wb, "y")
  expect_true(all(c("estimate", "se", "V", "V1", "V2", "cov", "rho", "deff_change") %in% names(ch)))
  expect_true(ch$se > 0)
  # overlap should help: Var(change) below the independence value
  expect_lt(ch$V, ch$Vind)
  expect_output(print(ch), "net change")
})
