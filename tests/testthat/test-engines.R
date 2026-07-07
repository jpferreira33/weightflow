# Cover the machine-learning engines and cross-fitting branches. The base-R
# paths (logit + cross-fitting, glm + cross-fitting) run always; the tree/forest/
# boost paths are skipped when their optional package is not installed.

test_that("cross-fitting runs with the base-R logit engine", {
  rec <- prep(weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "propensity",
                     formula = ~ region + sex + age, engine = "logit",
                     num_classes = 5, crossfit = 5, crossfit_seed = 1))
  expect_true(all(is.finite(rec$final_weight)))
})

test_that("nonresponse propensity runs with the tree engine (rpart)", {
  skip_if_not_installed("rpart")
  rec <- prep(weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "propensity",
                     formula = ~ region + sex + age, engine = "tree", num_classes = 5))
  expect_true(all(is.finite(rec$final_weight)))
})

test_that("nonresponse propensity runs with the forest engine (ranger)", {
  skip_if_not_installed("ranger")
  rec <- prep(weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "propensity",
                     formula = ~ region + sex + age, engine = "forest",
                     num_classes = 5, crossfit = 3, crossfit_seed = 1))
  expect_true(all(is.finite(rec$final_weight)))
})

test_that("nonresponse propensity runs with the boosting engine (xgboost)", {
  skip_if_not_installed("xgboost")
  rec <- prep(weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "propensity",
                     formula = ~ region + sex + age, engine = "boost", num_classes = 5))
  expect_true(all(is.finite(rec$final_weight)))
})

test_that("model calibration runs with cross-fitting (glm)", {
  rec <- prep(weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    step_model_calibration(
      x_formula  = ~ region + sex,
      models     = list(income = y_model(income ~ age + sex, engine = "glm")),
      population = population, crossfit = 5, crossfit_seed = 1))
  expect_true(all(is.finite(rec$final_weight)))
})

test_that("model calibration runs with the forest engine (ranger)", {
  skip_if_not_installed("ranger")
  rec <- prep(weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    step_model_calibration(
      x_formula  = ~ region + sex,
      models     = list(income = y_model(income ~ age + sex, engine = "forest")),
      population = population))
  expect_true(all(is.finite(rec$final_weight)))
})

test_that("as_svrepdesign bridges a jackknife object", {
  skip_if_not_installed("survey")
  spec <- weighting_spec(sample_one, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
  jk <- jackknife_weights(spec, strata = "region", psu = "psu", progress = FALSE)
  rd <- as_svrepdesign(jk)
  expect_s3_class(rd, "svyrep.design")
})

test_that("a single-PSU stratum warns in the bootstrap and does not crash", {
  d <- data.frame(pw = rep(1, 6),
                  region = c("A", "A", "A", "A", "B", "B"),   # B has only one PSU
                  psu = c(1, 1, 2, 2, 3, 3), y = 1:6)
  spec <- weighting_spec(d, base_weights = pw) |> step_rescale(to = "n")
  expect_warning(
    bootstrap_weights(spec, replicates = 10, strata = "region", psu = "psu",
                      seed = 1, progress = FALSE),
    "single PSU")
})
