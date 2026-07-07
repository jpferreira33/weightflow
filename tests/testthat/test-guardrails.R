# Verify that the safety guardrails fire: inconsistent margins warn, missing
# values error, absent totals cells warn, and the vector-valued-statistic paths
# in the variance estimators work.

test_that("raking warns when the margins are mutually inconsistent", {
  m_region <- c(table(population$region))
  m_sex    <- c(table(population$sex)); m_sex[1] <- m_sex[1] + 500   # sums to N + 500
  expect_warning(
    prep(weighting_spec(sample_survey, base_weights = pw) |>
      step_calibrate(method = "raking", margins = list(region = m_region, sex = m_sex))))
})

test_that("a calibration variable with NA is an error", {
  d <- sample_survey
  d$region <- as.character(d$region); d$region[1:3] <- NA
  rt <- as.data.frame(table(region = population$region))
  expect_error(
    prep(weighting_spec(d, base_weights = pw) |>
      step_calibrate(method = "poststratify", totals = rt, count = "Freq")))
})

test_that("a totals cell absent from the sample warns (weights fall short of N)", {
  rt <- as.data.frame(table(region = population$region)); rt$region <- as.character(rt$region)
  rt <- rbind(rt, data.frame(region = "Zzz", Freq = 100))          # cell with no sample units
  expect_warning(
    prep(weighting_spec(sample_survey, base_weights = pw) |>
      step_calibrate(method = "poststratify", totals = rt, count = "Freq")))
})

test_that("bootstrap_estimate handles a vector-valued statistic", {
  spec <- weighting_spec(sample_one, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
  boot <- bootstrap_weights(spec, replicates = 30, strata = "region", psu = "psu",
                            seed = 1, progress = FALSE)
  est <- bootstrap_estimate(boot, function(w, d) {
    ok <- !is.na(d$responded)
    c(total = sum(w[ok] * d$responded[ok]),
      mean  = sum(w[ok] * d$responded[ok]) / sum(w[ok]))
  })
  expect_equal(nrow(est), 2L)
  expect_true(all(is.finite(est$se)))
})

test_that("jackknife_estimate handles a vector-valued statistic", {
  spec <- weighting_spec(sample_one, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
  jk <- jackknife_weights(spec, strata = "region", psu = "psu", progress = FALSE)
  est <- jackknife_estimate(jk, function(w, d)
    c(a = sum(w * d$responded, na.rm = TRUE), b = sum(w, na.rm = TRUE)))
  expect_equal(nrow(est), 2L)
  expect_true(all(is.finite(est$se)))
})
