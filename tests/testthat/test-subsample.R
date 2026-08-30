# step_subsample(): phase-2 expansion, drop of the non-subsampled, and the
# two-phase bootstrap path in bootstrap_weights().

# A small two-phase frame: households in the first phase, a Poisson subsample of
# them in the second, with the phase-1 weight w1 and the phase-2 prob p2.
.two_phase_df <- function(seed = 1) {
  set.seed(seed)
  NH <- 400L; m <- 3L
  reg <- sample(c("A", "B"), NH, replace = TRUE)
  hh  <- rep(seq_len(NH), each = m)
  y   <- rnorm(NH * m, c(A = 10, B = 20)[rep(reg, each = m)], 4)
  p2h <- c(A = 0.3, B = 0.6)[reg]
  sel <- runif(NH) < p2h
  df  <- data.frame(hh = hh, region = rep(reg, each = m), y = y,
                    sel2 = as.integer(hh %in% which(sel)),
                    p2 = rep(p2h, each = m), w1 = 5)
  df$y[df$sel2 == 0] <- 0
  df
}

test_that("apply_step.step_subsample expands the subsample and drops the rest", {
  df <- .two_phase_df()
  fit <- weighting_spec(df, base_weights = w1) |>
    step_subsample(selected = sel2, prob = p2, psu = "hh") |>
    prep()
  w <- fit$final_weight
  # not-subsampled units leave the cascade
  expect_true(all(w[df$sel2 == 0] == 0))
  # subsampled units are expanded by 1 / p2
  sel <- df$sel2 == 1
  expect_equal(w[sel], (df$w1 * (1 / df$p2))[sel], tolerance = 1e-9)
})

test_that("step_subsample requires a psu and a usable selection", {
  df <- .two_phase_df()
  expect_error(
    weighting_spec(df, base_weights = w1) |> step_subsample(selected = sel2, prob = p2),
    "psu")
  # prob out of range is caught at prep()
  bad <- df; bad$p2 <- ifelse(bad$sel2 == 1, 1.4, bad$p2)
  expect_error(
    prep(weighting_spec(bad, base_weights = w1) |>
           step_subsample(selected = sel2, prob = p2, psu = "hh")),
    "0, 1")
})

test_that("bootstrap_weights takes the two-phase path and returns a positive SE", {
  df   <- .two_phase_df()
  spec <- weighting_spec(df, base_weights = w1) |>
    step_subsample(selected = sel2, prob = p2, psu = "hh")
  boot <- bootstrap_weights(spec, replicates = 100L, seed = 1, progress = FALSE)
  expect_true(isTRUE(boot$two_phase))
  expect_true(is.list(boot$design) && isTRUE(boot$design$two_phase))
  se <- boot_mean(boot, "y")$se
  expect_true(is.finite(se) && se > 0)
})

test_that("no replicate weight is negative or zero-by-factor (Gamma coupling)", {
  # TP-01: the two-phase factor is a strictly positive Gamma, so selected units
  # keep positive replicate weights and a downstream GLM/propensity step could run.
  df   <- .two_phase_df(seed = 4)
  spec <- weighting_spec(df, base_weights = w1) |>
    step_subsample(selected = sel2, prob = p2, psu = "hh")
  boot <- bootstrap_weights(spec, replicates = 200L, seed = 2, progress = FALSE)
  reps <- boot$replicates
  expect_true(all(reps >= 0, na.rm = TRUE))              # never negative
  sel  <- df$sel2 == 1
  expect_true(all(reps[sel, ] > 0))                       # selected units stay positive
})

test_that("the two-phase bootstrap is reproducible under a fixed seed", {
  df   <- .two_phase_df(seed = 5)
  spec <- weighting_spec(df, base_weights = w1) |>
    step_subsample(selected = sel2, prob = p2, psu = "hh")
  b1 <- bootstrap_weights(spec, replicates = 100L, seed = 11, progress = FALSE)
  b2 <- bootstrap_weights(spec, replicates = 100L, seed = 11, progress = FALSE)
  expect_equal(b1$replicates, b2$replicates)
})

test_that("jackknife_weights refuses a two-phase recipe (TP-03)", {
  df   <- .two_phase_df()
  spec <- weighting_spec(df, base_weights = w1) |>
    step_subsample(selected = sel2, prob = p2, psu = "hh")
  expect_error(jackknife_weights(spec, progress = FALSE), "two-phase")
})

test_that("step_subsample composes with reference_sample (calibrate to phase 1)", {
  # Two-phase regression estimator: calibrate the subsample to first-phase totals
  # estimated from the first-phase sample (as a reference with replicate weights).
  # Should run end to end and return a finite, positive SE (variance validated by
  # Monte Carlo in the two-phase methodology notes, not here).
  df <- .two_phase_df(seed = 9)
  df$x <- df$y + rnorm(nrow(df))                     # a phase-1 auxiliary
  # first-phase sample = all phase-1 rows, with its own bootstrap replicate weights
  ph1  <- data.frame(hh = df$hh, x = df$x, w1 = df$w1)
  reps <- matrix(df$w1 * stats::runif(nrow(df) * 20, 0.5, 1.5), ncol = 20)
  ref  <- reference_sample(ph1, "w1", replicates = reps)
  spec <- weighting_spec(df, base_weights = w1) |>
    step_subsample(selected = sel2, prob = p2, psu = "hh") |>
    step_calibrate(method = "linear", formula = ~ x, population = ref)
  boot <- bootstrap_weights(spec, replicates = 60L, seed = 1, progress = FALSE)
  se <- boot_total(boot, "y")$se
  expect_true(is.finite(se) && se > 0)
  expect_true(isTRUE(boot$two_phase))
})

test_that("a per-region fpc column (varying f1) is accepted in two-phase mode (TP-09)", {
  # The first-phase fraction f1 may legitimately vary across phase-2 units (the
  # `fpc` column the docs advertise), as long as it is constant within a phase-2
  # PSU. The single-phase stratum-constancy check must not run in two-phase mode.
  df <- .two_phase_df(seed = 3)
  df$f1 <- c(A = 0.05, B = 0.20)[df$region]   # f1 constant within hh, varies by region
  spec <- weighting_spec(df, base_weights = w1) |>
    step_subsample(selected = sel2, prob = p2, psu = "hh")
  boot <- bootstrap_weights(spec, replicates = 50L, fpc = "f1", seed = 1, progress = FALSE)
  se <- boot_mean(boot, "y")$se
  expect_true(is.finite(se) && se > 0)
  expect_true(isTRUE(boot$two_phase))
})

test_that("two_phase_variance() splits V = V1 + V2 (feature B)", {
  df   <- .two_phase_df(seed = 7)
  spec <- weighting_spec(df, base_weights = w1) |>
    step_subsample(selected = sel2, prob = p2, psu = "hh")
  tpv  <- two_phase_variance(spec, "y", replicates = 300L, seed = 3)
  expect_s3_class(tpv, "weightflow_tp_variance")
  expect_equal(tpv$V, tpv$V1 + tpv$V2, tolerance = 1e-12)   # identity
  expect_true(tpv$V1 > 0 && tpv$V2 > 0)
  expect_true(tpv$prop_phase2 >= 0 && tpv$prop_phase2 <= 1)
  # the decomposed total SE should be in the ballpark of the coupled bootstrap SE
  se_full <- boot_mean(bootstrap_weights(spec, replicates = 300L, seed = 3,
                                         progress = FALSE), "y")$se
  expect_true(abs(tpv$se - se_full) < 0.35 * se_full)
  expect_error(two_phase_variance(weighting_spec(df, base_weights = w1), "y"),
               "step_subsample")
})

test_that("the two-phase bootstrap SE tracks the Monte Carlo SE (C1: variance level)", {
  skip_on_cran()
  # A Poisson second phase (f1 = 0) of a small frame; compare the recipe-aware
  # bootstrap SE against the empirical SD of the estimator over Monte Carlo draws.
  set.seed(101)
  NH <- 300L; p2 <- 0.4
  reg <- sample(c("A", "B"), NH, replace = TRUE)
  y   <- stats::rnorm(NH, c(A = 10, B = 14)[reg], 3)
  frame <- data.frame(hh = seq_len(NH), region = reg, y = y, w1 = 4)
  emp <- replicate(200L, {
    sel <- stats::runif(NH) < p2
    d   <- frame; d$sel2 <- as.integer(sel); d$p2 <- p2
    d$y[!sel] <- 0
    w <- prep(weighting_spec(d, base_weights = w1) |>
                step_subsample(selected = sel2, prob = p2, psu = "hh"))$final_weight
    stats::weighted.mean(d$y, w)
  })
  sd_mc <- sd(emp)
  d0 <- frame; sel0 <- stats::runif(NH) < p2
  d0$sel2 <- as.integer(sel0); d0$p2 <- p2; d0$y[!sel0] <- 0
  spec0 <- weighting_spec(d0, base_weights = w1) |>
    step_subsample(selected = sel2, prob = p2, psu = "hh")
  se_boot <- boot_mean(bootstrap_weights(spec0, replicates = 400L, seed = 5,
                                         progress = FALSE), "y")$se
  expect_true(se_boot / sd_mc > 0.7 && se_boot / sd_mc < 1.4)   # ratio ~ 1
})

test_that("two-phase subsample raises quality alerts for few PSUs / tiny pi2 (C2)", {
  # Few phase-2 sampling units and a very small phase-2 probability should each
  # surface a non-fatal quality alert on the prepped object.
  set.seed(202)
  NH <- 20L                                        # < 30 phase-2 units -> few-PSU alert
  df  <- data.frame(hh = seq_len(NH), y = stats::rnorm(NH),
                    sel2 = 1L, p2 = 0.01, w1 = 5)  # min pi2 = 0.01 -> tiny-prob alert
  fit <- weighting_spec(df, base_weights = w1) |>
    step_subsample(selected = sel2, prob = p2, psu = "hh") |>
    prep()
  al <- weighting_alerts(fit)
  expect_true(any(grepl("phase-2 sampling unit", al)))
  expect_true(any(grepl("phase-2 selection probability", al)))

  # a well-sized two-phase design raises neither two-phase alert
  df2  <- .two_phase_df(seed = 8)
  fit2 <- weighting_spec(df2, base_weights = w1) |>
    step_subsample(selected = sel2, prob = p2, psu = "hh") |>
    prep()
  expect_false(any(grepl("phase-2 sampling unit|phase-2 selection probability",
                         weighting_alerts(fit2))))
})

test_that("phase-1 strata/psu are refused with a two-phase recipe (TP-02)", {
  # A clustered first phase is not folded into the coupling; refuse rather than
  # silently drop its intra-cluster variance. (For that case, calibrate the
  # subsample to the first-phase sample via reference_sample() instead.)
  df   <- .two_phase_df()
  df$stratum <- df$region
  spec <- weighting_spec(df, base_weights = w1) |>
    step_subsample(selected = sel2, prob = p2, psu = "hh")
  expect_error(
    bootstrap_weights(spec, replicates = 50L, strata = "stratum", psu = "hh",
                      seed = 1, progress = FALSE),
    "not supported")
})
