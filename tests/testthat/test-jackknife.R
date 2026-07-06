# Delete-a-PSU jackknife must reproduce survey's replicate-jackknife variance.
# For a total (a linear statistic) the stratum-mean centering equals centering
# at the point estimate, so weightflow's JKn/JK1 total SE matches survey exactly.

test_that("stratified jackknife (JKn) total SE matches survey", {
  skip_if_not_installed("survey")
  set.seed(1)
  strata <- rep(c("A", "B", "C"), each = 200)
  psu    <- paste0(strata, "_", rep(rep(1:5, each = 40), 3))   # 5 PSUs per stratum
  dat    <- data.frame(stratum = strata, psu = psu,
                       y = rbinom(600, 1, 0.4), w = runif(600, 1, 3))

  spec <- weighting_spec(dat, base_weights = w)                # pure design, no steps
  jk   <- jackknife_weights(spec, strata = "stratum", psu = "psu", progress = FALSE)
  se_wf <- jack_total(jk, "y")$se

  des <- survey::svydesign(ids = ~psu, strata = ~stratum, weights = ~w,
                           data = dat, nest = TRUE)
  rep <- survey::as.svrepdesign(des, type = "JKn")
  se_sv <- as.numeric(survey::SE(survey::svytotal(~y, rep)))

  expect_equal(as.numeric(se_wf), se_sv, tolerance = 1e-6)
})

test_that("unstratified jackknife (JK1) total SE matches survey", {
  skip_if_not_installed("survey")
  set.seed(2)
  dat <- data.frame(psu = paste0("p", rep(1:10, each = 60)),
                    y = rbinom(600, 1, 0.5), w = runif(600, 1, 3))

  spec <- weighting_spec(dat, base_weights = w)
  jk   <- jackknife_weights(spec, strata = NULL, psu = "psu", progress = FALSE)
  se_wf <- jack_total(jk, "y")$se

  des <- survey::svydesign(ids = ~psu, weights = ~w, data = dat)
  rep <- survey::as.svrepdesign(des, type = "JK1")
  se_sv <- as.numeric(survey::SE(survey::svytotal(~y, rep)))

  expect_equal(as.numeric(se_wf), se_sv, tolerance = 1e-6)
})

test_that("jackknife has one replicate per PSU and finite SEs", {
  set.seed(3)
  strata <- rep(c("A", "B"), each = 150)
  psu    <- paste0(strata, "_", rep(rep(1:3, each = 50), 2))   # 3 PSUs per stratum
  dat    <- data.frame(stratum = strata, psu = psu,
                       y = rnorm(300, 10, 2), w = runif(300, 1, 2))
  spec <- weighting_spec(dat, base_weights = w)
  jk   <- jackknife_weights(spec, strata = "stratum", psu = "psu", progress = FALSE)

  expect_equal(jk$R, 6L)                                # 2 strata x 3 PSUs
  est <- jack_total(jk, "y")
  expect_true(is.finite(est$se) && est$se > 0)
  expect_true(is.finite(jack_mean(jk, "y")$se))
})

test_that("a single-PSU stratum contributes no variance and warns", {
  dat <- data.frame(stratum = c(rep("A", 4), rep("B", 2)),
                    psu = c("A_1", "A_1", "A_2", "A_2", "B_1", "B_1"),
                    y = c(1, 0, 1, 1, 0, 1), w = rep(2, 6))
  spec <- weighting_spec(dat, base_weights = w)
  expect_warning(
    jackknife_weights(spec, strata = "stratum", psu = "psu", progress = FALSE),
    "single PSU"
  )
})
