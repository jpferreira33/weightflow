# weightflow's calibration must reproduce the survey package on the shared
# methods. Skipped when 'survey' is not installed.

skip_if_no_survey <- function() testthat::skip_if_not_installed("survey")

test_that("post-stratification matches survey::postStratify", {
  skip_if_no_survey()
  d  <- sample_survey
  wf <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "poststratify",
                   margins = list(region = c(table(population$region)))) |>
    prep()
  des <- survey::svydesign(ids = ~1, weights = ~pw, data = d)
  pr  <- data.frame(region = names(table(population$region)),
                    Freq = as.numeric(table(population$region)))
  des_ps <- survey::postStratify(des, ~region, pr)
  expect_equal(unname(wf$final_weight), unname(stats::weights(des_ps)),
               tolerance = 1e-8)
})

test_that("linear (GREG) calibration matches survey::calibrate", {
  skip_if_no_survey()
  d      <- sample_survey
  totals <- colSums(stats::model.matrix(~ region + sex, population))
  wf <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ region + sex, totals = totals) |>
    prep()
  des     <- survey::svydesign(ids = ~1, weights = ~pw, data = d)
  des_cal <- survey::calibrate(des, ~ region + sex, population = totals,
                               calfun = "linear")
  expect_equal(unname(wf$final_weight), unname(stats::weights(des_cal)),
               tolerance = 1e-8)
})

test_that("raking matches survey::rake", {
  skip_if_no_survey()
  d  <- sample_survey
  wf <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(region = c(table(population$region)),
                                  sex    = c(table(population$sex)))) |>
    prep()
  des <- survey::svydesign(ids = ~1, weights = ~pw, data = d)
  pr  <- data.frame(region = names(table(population$region)),
                    Freq = as.numeric(table(population$region)))
  ps  <- data.frame(sex = names(table(population$sex)),
                    Freq = as.numeric(table(population$sex)))
  des_rk <- survey::rake(des, list(~region, ~sex), list(pr, ps),
                         control = list(epsilon = 1e-10, maxit = 100))
  expect_equal(unname(wf$final_weight), unname(stats::weights(des_rk)),
               tolerance = 1e-6)
})
