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

test_that("phase-1 strata/psu are refused with a two-phase recipe (TP-02)", {
  df   <- .two_phase_df()
  df$stratum <- df$region
  spec <- weighting_spec(df, base_weights = w1) |>
    step_subsample(selected = sel2, prob = p2, psu = "hh")
  expect_error(
    bootstrap_weights(spec, replicates = 50L, psu = "hh", seed = 1, progress = FALSE),
    "not yet supported")
})
