# Round-4 audit (2026-09), panel module. step_cre() built its augmented system from two
# different population scales: `Zhat` is a TOTAL estimated with the previous wave's
# weights (so it lives on Nhat_{t-1}) while the demographic block fixes this wave's N_t.
# The identity that keeps the composite block a smoother assumes the two agree; when
# they do not, the whole gap is discharged onto the labour-status estimate -- with every
# constraint met to 1e-6, converged = TRUE and not one warning. Measured with the totals
# of the function's own @examples.

cre_fixture <- function() {
  t1 <- subset(panel_ine, wave == 1 & disposition == "R")
  t2 <- subset(panel_ine, wave == 2 & disposition == "R")
  t1$sex <- factor(t1$sex); t2$sex <- factor(t2$sex)
  Xtot <- function(d) colSums(d$pw * stats::model.matrix(~ sex, data = d))
  seed <- weighting_spec(t1, base_weights = pw) |>
    step_cre(previous = NULL, status = lf_status, formula = ~ sex,
             totals = Xtot(t1), status_ref = "inact") |> prep(warn = FALSE)
  list(t1 = t1, t2 = t2, Xtot = Xtot, seed = seed,
       r1 = stats::weighted.mean(t1$lf_status == "emp", seed$final_weight))
}
cre_wave2 <- function(fx, totals, rescale = FALSE)
  weighting_spec(fx$t2, base_weights = pw) |>
    step_cre(previous = fx$seed, status = lf_status, composite = list(NULL, "sex"),
             id_unit = c("household_id", "person_no"), formula = ~ sex, totals = totals,
             alpha = 2/3, status_ref = "inact", rescale_previous = rescale) |>
    prep(warn = FALSE)
emp2 <- function(fx, f) stats::weighted.mean(fx$t2$lf_status == "emp", f$final_weight)

test_that("PAN9-01: mixing two population scales in step_cre() is reported", {
  fx <- cre_fixture()
  N1 <- unname(fx$Xtot(fx$t1)[1]); N2 <- unname(fx$Xtot(fx$t2)[1])
  expect_gt(abs(N2 / N1 - 1), 0.10)                 # the datasets really do drift

  expect_warning(cre_wave2(fx, fx$Xtot(fx$t2)), "differs by 12\\.9% from the population")
  expect_warning(cre_wave2(fx, fx$Xtot(fx$t2)), "rescale_previous = TRUE")

  # the size of the thing the warning is about
  off <- suppressWarnings(cre_wave2(fx, fx$Xtot(fx$t2)))
  aligned <- cre_wave2(fx, fx$Xtot(fx$t1))          # one projection for both waves
  expect_gt(emp2(fx, off) - fx$r1, 0.06)            # +7 points, out of nowhere
  expect_lt(abs(emp2(fx, aligned) - fx$r1), 0.01)   # against +0.1 with the scales aligned

  # and the reason it was invisible: everything looks perfect
  dg <- off$steps[[1]]$diagnostics
  expect_true(isTRUE(attr(dg, "converged")))
  expect_lt(max(abs(dg$achieved - dg$target) / pmax(abs(dg$target), 1)), 1e-6)

  # aligned scales must not warn at all
  expect_warning(cre_wave2(fx, fx$Xtot(fx$t1)), NA)
})

test_that("PAN9-02: rescale_previous puts the composite block on this wave's scale", {
  fx <- cre_fixture()
  r <- cre_wave2(fx, fx$Xtot(fx$t2), rescale = TRUE)
  expect_warning(cre_wave2(fx, fx$Xtot(fx$t2), rescale = TRUE), NA)
  # it recovers what aligning the projections would have given
  expect_equal(emp2(fx, r), emp2(fx, cre_wave2(fx, fx$Xtot(fx$t1))), tolerance = 5e-3)
  expect_lt(abs(emp2(fx, r) - fx$r1), 0.01)
  # the constraints still hold exactly: this rescales the target, it does not relax it
  dg <- r$steps[[1]]$diagnostics
  expect_true(isTRUE(attr(dg, "converged")))
  expect_lt(max(abs(dg$achieved - dg$target) / pmax(abs(dg$target), 1)), 1e-6)
  # and it still calibrates to the wave's own demographic totals
  expect_equal(sum(collect_weights(r, drop_zero = FALSE)$.weight),
               unname(fx$Xtot(fx$t2)[1]), tolerance = 1e-6)
})

test_that("PAN9-03: the recipe the documentation teaches raises no scale warning", {
  # The @examples and the vignette now share ONE population vector across waves. That
  # is a behavioural claim, so assert it by running that recipe rather than by reading
  # the source file (which is not shipped with the installed package).
  fx <- cre_fixture()
  expect_warning(cre_wave2(fx, fx$Xtot(fx$t1)), NA)
  expect_lt(abs(emp2(fx, cre_wave2(fx, fx$Xtot(fx$t1))) - fx$r1), 0.01)
})

test_that("PAN9-04: a broken linkage key is no longer indistinguishable from a rotation", {
  # With `birth = NULL` -- the default, and what the examples, the vignette and the tests
  # all use -- every unlinked unit is classified as the incoming rotation group. The
  # CRE-06 guard fires on `n_missing_prev`, which is 0 by construction in that branch, so
  # it was dead code: a fully broken key gave delta = 1e-6, 100% births in a design whose
  # nominal incoming group is 1/6, converged = TRUE and not one warning.
  fx <- cre_fixture()
  break_key <- function(frac, seed = 1) {
    d <- fx$t2
    if (frac >= 1) { d$person_no <- paste0("X", d$person_no); return(d) }
    set.seed(seed); i <- sample(nrow(d), round(frac * nrow(d)))
    d$person_no[i] <- paste0("X", d$person_no[i]); d
  }
  run <- function(d2) weighting_spec(d2, base_weights = pw) |>
    step_cre(previous = fx$seed, status = lf_status, composite = list(NULL, "sex"),
             id_unit = c("household_id", "person_no"), formula = ~ sex,
             totals = fx$Xtot(fx$t1), alpha = 2/3, status_ref = "inact") |> prep(warn = FALSE)

  # an intact key: delta near the design's 5/6, nothing to report
  ok <- run(fx$t2)
  expect_warning(run(fx$t2), NA)
  expect_gt(attr(ok$steps[[1]]$diagnostics, "cre_link")$delta, 0.7)

  # a fully broken key is now fatal, and the message names the cause and the key
  expect_error(run(break_key(1)), "No rotating design overlaps that little")
  expect_error(run(break_key(1)), "household_id, person_no")

  # most of it broken: a warning that says what was classified as a birth
  expect_warning(run(break_key(0.7)), "classified as the incoming rotation group")
  expect_warning(run(break_key(0.7)), "INDISTINGUISHABLE")
  lk <- attr(suppressWarnings(run(break_key(0.7)))$steps[[1]]$diagnostics, "cre_link")
  expect_lt(lk$delta, 0.3)
  expect_true(lk$birth_inferred)

  # declaring `overlap` makes the check real instead of a heuristic: 30% broken slips
  # under the bare 0.5 threshold but not under nominal - 0.10
  expect_warning(run(break_key(0.3)), NA)
  with_nom <- function(d2) weighting_spec(d2, base_weights = pw) |>
    step_cre(previous = fx$seed, status = lf_status, composite = list(NULL, "sex"),
             id_unit = c("household_id", "person_no"), formula = ~ sex,
             totals = fx$Xtot(fx$t1), alpha = 2/3, status_ref = "inact",
             overlap = 5/6) |> prep(warn = FALSE)
  expect_warning(with_nom(break_key(0.3)), "links to `previous`")

  # and when `birth` IS declared, the inferred-birth check stays quiet: the two
  # categories are separated, and the pre-existing CRE-06 guard takes over
  key <- function(d) paste(d$household_id, d$person_no)
  # `isnew` from the TRUE key, so the broken units are declared non-birth AND fail to
  # link -- which is exactly what `missing_prev` is for
  d3 <- break_key(0.7); d3$isnew <- !(key(fx$t2) %in% key(fx$t1))
  f3 <- suppressWarnings(weighting_spec(d3, base_weights = pw) |>
    step_cre(previous = fx$seed, status = lf_status, composite = list(NULL, "sex"),
             id_unit = c("household_id", "person_no"), birth = isnew, formula = ~ sex,
             totals = fx$Xtot(fx$t1), alpha = 2/3, status_ref = "inact") |> prep(warn = FALSE))
  expect_false(attr(f3$steps[[1]]$diagnostics, "cre_link")$birth_inferred)
  expect_gt(attr(f3$steps[[1]]$diagnostics, "cre_link")$n_missing_prev, 0)
})
