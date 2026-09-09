# refit_steps is the "what is re-run per replicate" axis that makes wave_bootstrap a
# superset of the world's NSOs: "all" (our honest recipe-aware default, every step
# re-prepped) vs "calibration" (Statistics Canada LFS: freeze the subweights, re-run only
# calibration). The point estimate must never depend on it; only the replicate variance.
#
# Note on masking: a FINAL calibration to fixed totals largely absorbs the perturbation of
# frozen earlier steps, so refit_steps = "calibration" can give a variance close to "all"
# (this is a true property of calibration, not a bug). To show that freezing genuinely
# changes the variance, the second block uses a recipe ending in a NON-absorbing step
# (step_trim), where the frozen nonresponse clearly matters.

mkwave <- function(seed, shift = 0, npsu = 30, per = 6) {
  set.seed(seed)
  psu   <- rep(seq_len(npsu), each = per)
  str   <- rep(rep(1:3, length.out = npsu), each = per)
  x     <- rnorm(npsu * per, 10 + shift, 3)
  y     <- 0.7 * x + rnorm(npsu * per, 0, 2)      # analysis var: correlated with x but free
  p_psu <- rep(runif(npsu, 0.55, 0.98), each = per)   # response varies strongly BY PSU
  data.frame(psu = psu, str = str, x = x, y = y,
             resp = rbinom(npsu * per, 1, p_psu), pw = 1)
}
rec_cal <- function(d) {                          # nonresponse -> linear calibration (absorbs)
  tot <- c("(Intercept)" = sum(d$pw), x = sum(d$pw * d$x))
  weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "str") |>
    step_calibrate(method = "linear", formula = ~ x, totals = tot)
}
rec_trim <- function(d) {                         # nonresponse -> trim (non-absorbing, ~identity)
  weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "str") |>
    step_trim(max_ratio = 1e6, reference = "value", redistribute = FALSE)
}

test_that("refit_steps is recorded, StatCan mode prints, and the point estimate is invariant", {
  skip_on_cran()
  specs <- list(T1 = rec_cal(mkwave(1)), T2 = rec_cal(mkwave(1, shift = 0.4)))
  wb_all <- wave_bootstrap(specs, replicates = 100, strata = "str", psu = "psu",
                           seed = 7, refit_steps = "all", progress = FALSE)
  wb_cal <- wave_bootstrap(specs, replicates = 100, strata = "str", psu = "psu",
                           seed = 7, refit_steps = "calibration", progress = FALSE)
  expect_identical(wb_all$refit_steps, "all")
  expect_identical(wb_cal$refit_steps, "calibration")
  expect_equal(change_mean(wb_all, "y")$estimate, change_mean(wb_cal, "y")$estimate)
  expect_output(print(wb_cal), "StatCan")
})

test_that("freezing the nonresponse step changes the variance when the suffix does not absorb it", {
  skip_on_cran()
  # DIFFERENT seeds per wave: shared PSU ids (so the bootstrap coordinates) but genuinely
  # different data. Same-seed waves make the freeze effect cancel in the CHANGE (it is
  # perfectly correlated across near-identical waves) -- so we check a LEVEL variance (V1),
  # where re-fitting vs freezing the nonresponse step pushes through directly.
  specs <- list(T1 = rec_trim(mkwave(10)), T2 = rec_trim(mkwave(11)))
  v_all <- change_mean(wave_bootstrap(specs, replicates = 400, strata = "str", psu = "psu",
                                      seed = 3, refit_steps = "all", progress = FALSE), "y")
  v_fro <- change_mean(wave_bootstrap(specs, replicates = 400, strata = "str", psu = "psu",
                                      seed = 3, refit_steps = "step_trim", progress = FALSE), "y")
  expect_true(v_all$se > 0 && v_fro$se > 0)
  expect_false(isTRUE(all.equal(v_all$V1, v_fro$V1)))   # re-fitting NR vs freezing it must differ
})

test_that("with a calibration-only recipe, 'all' and 'calibration' are identical", {
  skip_on_cran()
  # no prefix to freeze -> the split is a no-op -> bit-identical replicate weights
  cal_only <- function(d) {
    tot <- c("(Intercept)" = sum(d$pw), x = sum(d$pw * d$x))
    weighting_spec(d, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ x, totals = tot)
  }
  specs <- list(T1 = cal_only(mkwave(4)), T2 = cal_only(mkwave(4, shift = 0.3)))
  v_all <- change_mean(wave_bootstrap(specs, replicates = 150, strata = "str", psu = "psu",
                                      seed = 9, refit_steps = "all", progress = FALSE), "y")$V
  v_cal <- change_mean(wave_bootstrap(specs, replicates = 150, strata = "str", psu = "psu",
                                      seed = 9, refit_steps = "calibration", progress = FALSE), "y")$V
  expect_equal(v_all, v_cal)
})

test_that("refit_steps that matches no step errors informatively", {
  specs <- list(T1 = rec_trim(mkwave(5)), T2 = rec_trim(mkwave(5, shift = 0.2)))
  expect_error(
    wave_bootstrap(specs, replicates = 20, strata = "str", psu = "psu",
                   seed = 1, refit_steps = "step_poststratify", progress = FALSE),
    "matches no step")
})

test_that("wave_jackknife also honours refit_steps", {
  # different seeds per wave -> non-degenerate change (rho < 1) -> se > 0
  specs <- list(T1 = rec_trim(mkwave(12)), T2 = rec_trim(mkwave(13)))
  wj <- wave_jackknife(specs, strata = "str", psu = "psu",
                       refit_steps = "step_trim", progress = FALSE)
  ch <- change_mean(wj, "y")
  expect_true(ch$se > 0)
})
