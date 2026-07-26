# step_trim_calibrated(): range-restricted, totals-preserving trimming.

test_that("weights land in [lower, upper] AND the calibration totals are kept", {
  set.seed(1)
  n      <- 300
  region <- factor(sample(c("a", "b", "c"), n, replace = TRUE,
                          prob = c(.6, .3, .1)))
  d      <- data.frame(region = region, pw = runif(n, 1, 6))
  tot    <- 5 * c(table(region))                 # mean weight 5 per region

  cal <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "poststratify", margins = list(region = tot)) |>
    prep()
  w_cal    <- collect_weights(cal, drop_zero = FALSE)$.weight
  T_region <- tapply(w_cal, region, sum)         # totals to preserve

  lo <- 2; up <- 7
  expect_true(min(w_cal) < lo || max(w_cal) > up) # trimming is really needed

  tc <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "poststratify", margins = list(region = tot)) |>
    step_trim_calibrated(~ region, lower = lo, upper = up) |>
    prep()
  w_tc <- collect_weights(tc, drop_zero = FALSE)$.weight

  # (a) every weight inside the absolute range
  expect_true(all(w_tc >= lo - 1e-6 & w_tc <= up + 1e-6))
  # (b) region totals (and the overall N) preserved
  expect_equal(as.numeric(tapply(w_tc, region, sum)),
               as.numeric(T_region), tolerance = 1e-5)
  expect_equal(sum(w_tc), sum(w_cal), tolerance = 1e-6)
})

test_that("no-op when the calibrated weights already lie in the range", {
  set.seed(2)
  n   <- 120
  d   <- data.frame(region = factor(sample(c("a", "b"), n, replace = TRUE)),
                    pw = runif(n, 2, 4))
  tot <- 3 * c(table(d$region))

  base <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "poststratify", margins = list(region = tot)) |>
    prep()
  w0 <- collect_weights(base, drop_zero = FALSE)$.weight
  expect_true(all(w0 >= 1 & w0 <= 100))          # comfortably inside [1, 100]

  tc <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "poststratify", margins = list(region = tot)) |>
    step_trim_calibrated(~ region, lower = 1, upper = 100) |>
    prep()
  w1 <- collect_weights(tc, drop_zero = FALSE)$.weight
  expect_equal(w1, w0, tolerance = 1e-8)         # unchanged
})

test_that("calfun = 'raking' also stays in range and preserves totals", {
  set.seed(3)
  n      <- 250
  region <- factor(sample(c("a", "b", "c"), n, replace = TRUE,
                          prob = c(.5, .3, .2)))
  d      <- data.frame(region = region, pw = runif(n, 1, 5))
  tot    <- 6 * c(table(region))                 # mean weight 6 per region

  cal <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "poststratify", margins = list(region = tot)) |>
    prep()
  w_cal <- collect_weights(cal, drop_zero = FALSE)$.weight
  Tr    <- tapply(w_cal, region, sum)

  lo <- 3; up <- 8
  tc <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "poststratify", margins = list(region = tot)) |>
    step_trim_calibrated(~ region, lower = lo, upper = up, calfun = "raking") |>
    prep()
  w <- collect_weights(tc, drop_zero = FALSE)$.weight

  expect_true(all(w >= lo - 1e-6 & w <= up + 1e-6))
  expect_true(all(w > 0))                        # multiplicative distance stays positive
  expect_equal(as.numeric(tapply(w, region, sum)),
               as.numeric(Tr), tolerance = 1e-5)
})

test_that("step_trim_calibrated validates its arguments", {
  d <- data.frame(region = factor(c("a", "b")), pw = c(1, 1))
  s <- weighting_spec(d, base_weights = pw)
  expect_error(step_trim_calibrated(s, ~ region), "at least one")
  expect_error(step_trim_calibrated(s, ~ region, lower = 5, upper = 2),
               "strictly below")
  expect_error(step_trim_calibrated(s, "region", lower = 1), "formula")
  expect_error(step_trim_calibrated(s, ~ region, lower = 1,
                                    equal_within_cluster = TRUE),
               "requires .cluster.")
})

test_that("integrative trimming keeps weights constant within household", {
  # Household design: integrative calibration first (one weight per household),
  # then integrative trimming must keep that within-household constancy, land in
  # range, and preserve the sex/reg totals.
  set.seed(41)
  n_hh  <- 500
  sizes <- sample(1:4, n_hh, replace = TRUE)
  hh    <- rep(seq_len(n_hh), sizes)
  N     <- length(hh)
  dat   <- data.frame(
    hh  = hh,
    sex = factor(sample(c("F", "M"),      N, replace = TRUE)),
    reg = factor(sample(c("a", "b", "c"), N, replace = TRUE)),
    pw  = 10
  )
  # skewed population margins -> spread of household calibration weights
  Npop <- 60000L
  pop2 <- data.frame(
    sex = factor(sample(c("F", "M"),      Npop, TRUE, prob = c(.6, .4))),
    reg = factor(sample(c("a", "b", "c"), Npop, TRUE, prob = c(.5, .3, .2)))
  )
  pop_tot <- colSums(model.matrix(~ sex + reg, pop2))

  calib <- function(spec) spec |>
    step_calibrate(method = "linear", calfun = "raking", formula = ~ sex + reg,
                   totals = pop_tot, cluster = "hh", equal_within_cluster = TRUE)

  w_cal <- collect_weights(calib(weighting_spec(dat, base_weights = pw)) |> prep(),
                           drop_zero = FALSE)$.weight
  hh_w  <- tapply(w_cal, dat$hh, function(z) z[1])       # household weights
  lo    <- as.numeric(quantile(hh_w, 0.05))
  up    <- as.numeric(quantile(hh_w, 0.95))

  fit <- calib(weighting_spec(dat, base_weights = pw)) |>
    step_trim_calibrated(~ sex + reg, lower = lo, upper = up,
                         cluster = "hh", equal_within_cluster = TRUE, maxit = 200L) |>
    prep()
  w <- collect_weights(fit, drop_zero = FALSE)$.weight

  # (a) still constant within household
  const <- tapply(w, dat$hh, function(z) diff(range(z)))
  expect_true(all(const < 1e-6))
  # (b) all household weights within [lo, up]
  expect_true(all(w >= lo - 1e-6 & w <= up + 1e-6))
  # (c) sex/reg totals preserved (equal to the pre-trim calibrated totals)
  X  <- model.matrix(~ sex + reg, dat)
  expect_equal(unname(colSums(w * X)), unname(colSums(w_cal * X)), tolerance = 1e-5)
})
