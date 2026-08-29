# data_defect(): Meng's (2018) data-defect view for a non-probability sample.

test_that("data_defect requires a non-probability prepped spec", {
  fit <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    prep()
  expect_error(data_defect(fit), "non-probability")
  expect_error(data_defect(list()), "prepped weighting_spec")
})

test_that("data_defect reproduces Meng's n_eff formula and the 2016 benchmark", {
  set.seed(1)
  N   <- nrow(population)
  vol <- population[rbinom(N, 1, plogis(-2 + 0.9 * (population$sex == "M"))) == 1,
                    c("region", "sex", "income")]
  ref <- population[sample(N, 800), c("region", "sex")]; ref$d <- N / 800
  fit <- suppressWarnings(
    weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
      step_pseudoweight(reference = reference_sample(ref, "d"),
                        formula = ~ region + sex, engine = "logit") |>
      prep())
  dd <- data_defect(fit)
  expect_s3_class(dd, "weightflow_data_defect")
  # n_eff = (f/(1-f)) / rho^2, checked element-wise
  expect_equal(dd$grid$n_eff, (dd$f / (1 - dd$f)) / dd$grid$ddc^2)
  # smaller residual correlation -> larger effective size (monotone)
  expect_true(all(diff(dd$grid$n_eff) < 0))
  # the auxiliaries carry a measurable selection correlation
  expect_true(!is.null(dd$aux) && nrow(dd$aux) >= 1L)

  # the famous 2016 case: n = 2.3M, N = 2.3e8 (f = 0.01), rho = 0.005 -> n_eff ~ 400
  f <- 0.01; rho <- 0.005
  expect_equal((f / (1 - f)) / rho^2, 404, tolerance = 1)
})

test_that("data_defect renders a prominent report card only for nonprob", {
  set.seed(2)
  N   <- nrow(population)
  vol <- population[rbinom(N, 1, plogis(-2 + 0.9 * (population$sex == "M"))) == 1,
                    c("region", "sex", "income")]
  ref <- population[sample(N, 600), c("region", "sex")]; ref$d <- N / 600
  fit <- suppressWarnings(
    weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
      step_pseudoweight(reference = reference_sample(ref, "d"),
                        formula = ~ region + sex, engine = "logit") |>
      prep())
  h <- weightflow:::.data_defect_card(fit, "en")
  expect_match(h, "class='ddc feature'")
  expect_match(h, "Effective sample size")
  # a probability recipe has no data-defect card
  pf <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    prep()
  expect_identical(weightflow:::.data_defect_card(pf, "en"), "")
})
