# Integrative (Lemaitre-Dufour) option in step_model_calibration: one weight per
# household. The final weights must be constant within each cluster among its
# active members, while still reproducing the X totals (and the prediction total).

fit_hh <- prep(
  weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class",
                     by = "region") |>
    step_model_calibration(
      x_formula  = ~ sex + region,
      models     = list(income = y_model(income ~ age + sex, engine = "glm")),
      population  = population,
      cluster = "household_id", equal_within_cluster = TRUE)
)

test_that("equal_within_cluster gives one weight per household (active members)", {
  w   <- fit_hh$final_weight
  act <- w > 0
  spread <- tapply(w[act], sample_survey$household_id[act],
                   function(x) diff(range(x)))
  expect_lt(max(spread), 1e-6)
})

test_that("integrative model calibration still reproduces the X totals", {
  w   <- fit_hh$final_weight
  act <- w > 0
  X    <- model.matrix(~ sex + region, sample_survey[act, , drop = FALSE])
  Xpop <- colSums(model.matrix(~ sex + region, population))
  expect_equal(as.numeric(colSums(w[act] * X)), as.numeric(Xpop),
               tolerance = 1e-3)
})

test_that("equal_within_cluster = TRUE requires cluster", {
  expect_error(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_model_calibration(
        x_formula  = ~ sex + region,
        models     = list(income = y_model(income ~ age + sex, engine = "glm")),
        population  = population,
        equal_within_cluster = TRUE),
    "cluster"
  )
})
