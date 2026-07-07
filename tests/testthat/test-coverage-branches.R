# Exercise the less-travelled branches of adjustments.R and variance.R:
# propensity engines (base-R logit), bounded/logit and ridge calibration,
# Potter trimming, rounding/rescale/assert, model calibration, and the
# survey/srvyr bridges. Optional-package branches are skipped when absent.

test_that("propensity nonresponse (logit) runs, with classes and direct 1/p", {
  r1 <- prep(weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "propensity",
                     formula = ~ region + sex, engine = "logit", num_classes = 5))
  expect_true(all(r1$final_weight >= 0) && sum(r1$final_weight) > 0)
  r2 <- prep(weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "propensity",
                     formula = ~ region + sex, engine = "logit", num_classes = NULL))
  expect_true(all(is.finite(r2$final_weight)))
})

test_that("logit calfun with bounds keeps the g-weights inside the bounds", {
  tot <- colSums(model.matrix(~ region + sex, population))
  rec <- prep(weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ region + sex, totals = tot,
                   calfun = "logit", bounds = c(0.5, 2)))
  act <- rec$final_weight > 0
  g <- rec$final_weight[act] / sample_survey$pw[act]
  expect_true(all(g >= 0.5 - 1e-6 & g <= 2 + 1e-6))
})

test_that("ridge (penalized) calibration runs and stays finite", {
  tot <- colSums(model.matrix(~ region + sex, population))
  rec <- prep(weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ region + sex, totals = tot, penalty = 1))
  expect_true(all(is.finite(rec$final_weight)))
})

test_that("Potter trimming, preserve-total rounding, rescale-by and assert all run", {
  base <- weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
  w0 <- sum(prep(base)$final_weight)
  expect_error(prep(base |> step_trim_weights(method = "potter")), NA)
  wr <- prep(base |> step_round(digits = 0, method = "preserve_total"))$final_weight
  expect_equal(sum(wr), round(w0))
  expect_error(prep(base |> step_rescale(to = "n", by = "region")), NA)
  expect_error(prep(base |> step_assert(max_deff = 100, min_n_eff = 1, on_fail = "error")), NA)
})

test_that("model calibration (glm) runs after a nonresponse step", {
  rec <- prep(weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    step_model_calibration(
      x_formula  = ~ region + sex,
      models     = list(income = y_model(income ~ age + sex, engine = "glm")),
      population = population))
  expect_true(all(is.finite(rec$final_weight)))
})

test_that("jackknife estimators and the print method run", {
  spec <- weighting_spec(sample_one, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
  jk <- jackknife_weights(spec, strata = "region", psu = "psu", progress = FALSE)
  expect_output(print(jk))
  expect_true(is.finite(jack_total(jk, "responded")$estimate))
  expect_true(is.finite(jack_mean(jk, "responded")$se))
})

test_that("survey/srvyr bridges and replicate collection work", {
  skip_if_not_installed("survey")
  spec <- weighting_spec(sample_one, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
  rec  <- prep(spec)
  boot <- bootstrap_weights(spec, replicates = 30, strata = "region", psu = "psu",
                            seed = 1, progress = FALSE)
  df <- collect_replicate_weights(boot)
  expect_true(".weight" %in% names(df))
  expect_equal(attr(df, "R"), 30L)
  des <- as_svydesign(rec, ids = "psu", strata = "region")
  expect_s3_class(des, "survey.design")
  rd <- as_svrepdesign(boot)
  expect_s3_class(rd, "svyrep.design")
  est <- bootstrap_estimate(boot, function(w, d) sum(w * d$responded, na.rm = TRUE))
  expect_true(is.finite(est$estimate) && est$se > 0)
})
