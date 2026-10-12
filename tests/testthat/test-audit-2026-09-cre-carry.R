# VAR-20. wave_step() took the LAG-1 carry's replicate weights unconditionally
# (prev[[1L]]$reps) and passed no content fingerprint to the injection, so alignment was
# decided on the row count alone -- the very test VAR-12 removed from wave_bootstrap().
# A recipe whose step_cre() declares an EARLIER period as `previous` therefore received
# the immediately preceding period's replicate weights whenever the two happened to have
# the same number of rows: rows belonging to different units, counted as `injected`, with
# no warning. The carry now carries a fingerprint of its own data and wave_step() picks
# the carry that matches what the recipe asked for.

ccc_fixture <- function(n = 400) {
  mk <- function(k) {
    d <- subset(panel_ine, wave == k & disposition == "R")
    d <- utils::head(d, n); d$sex <- factor(d$sex); d
  }
  w <- lapply(1:3, mk)
  list(w = w, Xtot = function(d) colSums(d$pw * stats::model.matrix(~ sex, data = d)))
}

ccc_seed <- function(fx) weighting_spec(fx$w[[1]], base_weights = pw) |>
  step_cre(previous = NULL, status = lf_status, formula = ~ sex,
           totals = fx$Xtot(fx$w[[1]]), status_ref = "inact")

# a composite recipe on wave `k` that declares `prv` (a prepped recipe) as its previous
ccc_comp <- function(fx, k, prv) weighting_spec(fx$w[[k]], base_weights = pw) |>
  step_cre(previous = prv, status = lf_status, composite = list(NULL),
           id_unit = c("household_id", "person_no"), formula = ~ sex,
           totals = fx$Xtot(fx$w[[1]]), alpha = 2/3, status_ref = "inact")

ccc_wave <- function(sp, previous, period, seed)
  suppressWarnings(wave_step(sp, previous = previous, replicates = 6, strata = "stratum",
                             psu = "psu", period = period, seed = seed, progress = FALSE))

test_that("VAR-20: a carry fingerprints its own period", {
  skip_on_cran()
  fx <- ccc_fixture()
  s1 <- ccc_wave(ccc_seed(fx), NULL, "t1", 1)
  s2 <- ccc_wave(ccc_comp(fx, 2, prep(ccc_seed(fx), warn = FALSE)), wave_carry(s1), "t2", 2)
  f1 <- wave_carry(s1)$data_fp; f2 <- wave_carry(s2)$data_fp
  expect_true(is.character(f1) && length(f1) == 1L && nzchar(f1))
  expect_false(identical(f1, f2))                  # same row count, different period
  expect_equal(nrow(fx$w[[1]]), nrow(fx$w[[2]]))   # the collision the row count misses
})

test_that("VAR-20: wave_step injects from the carry the recipe asked for, not from lag 1", {
  skip_on_cran()
  fx <- ccc_fixture()
  p1 <- prep(ccc_seed(fx), warn = FALSE)
  s1 <- ccc_wave(ccc_seed(fx), NULL, "t1", 1)
  s2 <- ccc_wave(ccc_comp(fx, 2, p1), wave_carry(s1), "t2", 2)
  c1 <- wave_carry(s1); c2 <- wave_carry(s2)

  # period 3 points TWO periods back, on purpose, and both carries are on the chain
  s3 <- ccc_wave(ccc_comp(fx, 3, p1), list(c2, c1), "t3", 3)
  expect_gte(s3$n_cre_injected, 1L)                # found t1 by content
  expect_equal(s3$n_cre_skipped, 0L)

  # and the Zhat* really varies across replicates: it is not held at the fixed point
  expect_gt(stats::sd(apply(s3$carry$reps, 2L, sum)), 0)
})

test_that("VAR-20: the declared period missing from the chain is refused, not substituted", {
  skip_on_cran()
  fx <- ccc_fixture()
  p1 <- prep(ccc_seed(fx), warn = FALSE)
  s1 <- ccc_wave(ccc_seed(fx), NULL, "t1", 1)
  s2 <- ccc_wave(ccc_comp(fx, 2, p1), wave_carry(s1), "t2", 2)

  # only the lag-1 carry is passed, and it has exactly the row count the step expects.
  # Before VAR-20 that was silently injected; now Zhat is held fixed and it says so.
  sp3 <- ccc_comp(fx, 3, p1)
  msg <- testthat::capture_warnings(
    wave_step(sp3, previous = wave_carry(s2), replicates = 6, strata = "stratum",
              psu = "psu", period = "t3", seed = 3, progress = FALSE))
  expect_true(any(grepl("held FIXED", msg)))
  s3 <- ccc_wave(sp3, wave_carry(s2), "t3", 3)
  expect_equal(s3$n_cre_injected, 0L)
  expect_gte(s3$n_cre_skipped, 1L)
})
