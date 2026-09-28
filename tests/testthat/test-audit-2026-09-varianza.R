# Round-4 audit (2026-09), variance module. The one that mattered: panel_estimate()
# aborted with an internal message on an object change_estimate() handled fine,
# because the jackknife branch of .wave_cov() lacked the is.finite() filter its two
# siblings already had. Plus the delete-one rescaling, the Monte Carlo error of the
# bootstrap SE, and the intervals that could not be asked for.

mk_panel_wave <- function(wave, seed = 10) {
  set.seed(seed); H <- 4; P <- 6; n <- H * P * 10
  d <- data.frame(str = rep(seq_len(H), each = P * 10),
                  upm = rep(seq_len(H * P), each = 10),
                  w0 = 12)
  d$grp <- "A"
  d$grp[d$upm == 1] <- "Z"            # deleting PSU 1 empties this calibration cell
  d$y <- stats::rnorm(n, 100 + 5 * wave, 15)
  d
}
spec_of <- function(d) {
  tot <- as.data.frame(table(grp = d$grp) * 12)
  weighting_spec(d, base_weights = w0) |>
    step_calibrate(method = "poststratify",
                   margins = list(grp = stats::setNames(tot$Freq, tot$grp)))
}
mean_y <- function(w, d) stats::weighted.mean(d$y, w)

test_that("VAR9-01: panel_estimate() survives a failed delete-one, like change_estimate()", {
  wj <- suppressWarnings(wave_jackknife(
    list(t1 = spec_of(mk_panel_wave(1)), t2 = spec_of(mk_panel_wave(2))),
    strata = "str", psu = "upm", refit_steps = "all", progress = FALSE))

  ce <- suppressWarnings(change_estimate(wj, mean_y))
  pe <- suppressWarnings(panel_estimate(wj, mean_y, contrast = c(-1, 1)))
  expect_true(is.finite(pe$se))                   # used to abort: "missing value where..."
  expect_true(is.finite(pe$V))
  expect_lt(abs(pe$se - ce$se), 1e-6)             # same contrast, same answer
  wmsg <- testthat::capture_warnings(panel_estimate(wj, mean_y, contrast = c(-1, 1)))
  expect_true(any(grepl("delete-one replicate\\(s\\).*dropped", wmsg)))
})

test_that("VAR9-02: a dropped delete-one replicate rescales the stratum by (n_h-1)/m_h", {
  set.seed(7); n <- 600
  d <- data.frame(str = rep(1:3, each = 200), upm = rep(1:15, each = 40),
                  w0 = 20, y = stats::rnorm(600, 50, 10))
  j <- jackknife_weights(prep(weighting_spec(d, base_weights = w0), warn = FALSE),
                         strata = "str", psu = "upm", progress = FALSE)
  full <- jack_mean(j, "y")$se
  j2 <- j; j2$replicates[, 1] <- NA_real_         # one replicate fails
  part <- suppressWarnings(jack_mean(j2, "y")$se)
  # the rescaling keeps the two within a few percent; unrescaled it would drop by
  # roughly sqrt(1 - 1/n_h) of the stratum contribution and bias the SE low
  expect_lt(abs(part / full - 1), 0.25)
  expect_warning(jack_mean(j2, "y"), "non-finite replicate")
  expect_warning(jack_mean(j2, "y"), "rescaled")
})

test_that("VAR9-03: the bootstrap reports its own Monte Carlo error", {
  set.seed(4); n <- 800
  d <- data.frame(str = rep(1:4, each = 200), upm = rep(1:20, each = 40),
                  w0 = 25, y = stats::rnorm(800, 100, 20))
  p <- prep(weighting_spec(d, base_weights = w0), warn = FALSE)
  b <- bootstrap_weights(p, replicates = 200, strata = "str", psu = "upm",
                         seed = 1, progress = FALSE)
  est <- boot_mean(b, "y")
  expect_equal(attr(est, "mcse"), est$se / sqrt(2 * attr(est, "replicates")),
               tolerance = 1e-12)
  expect_output(print(b), "MCSE\\(SE\\)")
  expect_output(print(b), "5\\.0% of any SE")        # 100/sqrt(2*200)
  # the jackknife is deterministic: no Monte Carlo error at all
  j <- jackknife_weights(p, strata = "str", psu = "upm", progress = FALSE)
  expect_equal(attr(jack_mean(j, "y"), "mcse"), 0)
})

test_that("VAR9-04: the convenience wrappers can ask for a t interval on the design df", {
  set.seed(4); n <- 800
  d <- data.frame(str = rep(1:4, each = 200), upm = rep(1:20, each = 40),
                  w0 = 25, y = stats::rnorm(800, 100, 20))
  p <- prep(weighting_spec(d, base_weights = w0), warn = FALSE)
  b <- bootstrap_weights(p, replicates = 200, strata = "str", psu = "upm",
                         seed = 1, progress = FALSE)
  j <- jackknife_weights(p, strata = "str", psu = "upm", progress = FALSE)
  expect_equal(j$df, 16)

  wid <- function(e) e$ci_upper - e$ci_lower
  for (o in list(list(b, boot_mean), list(j, jack_mean), list(b, boot_total),
                 list(j, jack_total))) {
    z <- o[[2]](o[[1]], "y"); t <- o[[2]](o[[1]], "y", ci_type = "t")
    expect_equal(wid(t) / wid(z), stats::qt(.975, 16) / stats::qnorm(.975),
                 tolerance = 1e-8)                 # 1.0816: the z interval is 8% short
  }
  # an explicit df overrides the design one
  expect_equal(wid(jack_mean(j, "y", ci_type = "t", df = 6)) / wid(jack_mean(j, "y")),
               stats::qt(.975, 6) / stats::qnorm(.975), tolerance = 1e-8)
})

test_that("VAR9-05: a percentile interval is refused on the deterministic jackknife", {
  wj <- suppressWarnings(wave_jackknife(
    list(t1 = spec_of(mk_panel_wave(1)), t2 = spec_of(mk_panel_wave(2))),
    strata = "str", psu = "upm", refit_steps = "all", progress = FALSE))
  expect_error(suppressWarnings(change_estimate(wj, mean_y, ci_type = "percentile")),
               "deterministic")
})

test_that("VAR9-06: boot_mean() reports that the two-phase mean is not exact", {
  # the vignette used to say the factor "self-centres ... and the variance is right";
  # it self-centres only to first order, and boot_mean() now says so. Asserted through
  # behaviour, not by reading the vignette (not shipped with the installed package).
  set.seed(8); n <- 1200
  d <- data.frame(w0 = 20, hh = rep(seq_len(n / 2), each = 2),
                  y = stats::rnorm(n, 50, 10))
  d$keep <- d$hh %in% sample(unique(d$hh), length(unique(d$hh)) * 0.3)
  sp <- weighting_spec(d, base_weights = w0) |>
    step_subsample(selected = keep, prob = 0.3, psu = "hh")
  b  <- bootstrap_weights(prep(sp, warn = FALSE), replicates = 30, seed = 1, progress = FALSE)
  expect_true(isTRUE(b$two_phase))
  expect_message(boot_mean(b, "y"), "mildly conservative")
  expect_message(boot_mean(b, "y"), "upper bound")
})
