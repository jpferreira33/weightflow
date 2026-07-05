# External X (consistency) totals for step_model_calibration: the totals of the
# x_formula auxiliaries may be supplied from an outside source instead of the
# population frame, in the same two shapes as step_calibrate(method = "linear").
#
# The working model uses a predictor (`edu`) that is NOT among the consistency
# auxiliaries, so the model-assisted column is not collinear with X.

make_pop <- function(N = 1500, seed = 1) {
  set.seed(seed)
  reg  <- sample(c("A", "B", "C"), N, TRUE)
  age  <- rnorm(N, 45, 12)
  edu  <- rnorm(N, 12, 3)
  inc  <- 100 + 5 * (reg == "B") + 0.5 * age + 2 * edu + rnorm(N, 0, 5)
  data.frame(region = reg, age = age, edu = edu, income = inc)
}

test_that("tidy x_totals from the frame reproduce the default (frame) weights", {
  pop  <- make_pop()
  idx  <- sample(nrow(pop), 400)
  samp <- pop[idx, ]; samp$pw <- nrow(pop) / 400

  m_region <- as.data.frame(table(region = pop$region))

  w_frame <- weighting_spec(samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region + age,
      models     = list(income = y_model(income ~ edu + region, engine = "glm")),
      population = pop) |>
    prep() |> (\(x) x$final_weight)()

  w_ext <- weighting_spec(samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region + age,
      models     = list(income = y_model(income ~ edu + region, engine = "glm")),
      population = pop,
      x_totals   = list(region = m_region, age = sum(pop$age)),
      count      = "Freq") |>
    prep() |> (\(x) x$final_weight)()

  expect_equal(w_ext, w_frame, tolerance = 1e-6)
})

test_that("calibrated weights hit both the X and the model targets exactly", {
  pop  <- make_pop(seed = 2)
  idx  <- sample(nrow(pop), 400)
  samp <- pop[idx, ]; samp$pw <- nrow(pop) / 400
  m_region <- as.data.frame(table(region = pop$region))

  fitted <- weighting_spec(samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region + age,
      models     = list(income = y_model(income ~ edu + region, engine = "glm")),
      population = pop,
      x_totals   = list(region = m_region, age = sum(pop$age)),
      count      = "Freq") |>
    prep()

  d <- fitted$steps[[1]]$diagnostics
  expect_equal(d$achieved, d$target, tolerance = 1e-3)

  # the continuous external total is reproduced by the weighted sample
  w <- fitted$final_weight
  expect_equal(sum(w[w > 0] * samp$age), sum(pop$age), tolerance = 1e-3)
})

test_that("the classic model-matrix vector format also works and matches tidy", {
  pop  <- make_pop(seed = 3)
  idx  <- sample(nrow(pop), 400)
  samp <- pop[idx, ]; samp$pw <- nrow(pop) / 400
  m_region <- as.data.frame(table(region = pop$region))

  vec <- c("(Intercept)" = nrow(pop),
           regionB = sum(pop$region == "B"),
           regionC = sum(pop$region == "C"),
           age     = sum(pop$age))

  w_vec <- weighting_spec(samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region + age,
      models     = list(income = y_model(income ~ edu + region, engine = "glm")),
      population = pop, x_totals = vec) |>
    prep() |> (\(x) x$final_weight)()

  w_tidy <- weighting_spec(samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region + age,
      models     = list(income = y_model(income ~ edu + region, engine = "glm")),
      population = pop,
      x_totals   = list(region = m_region, age = sum(pop$age)), count = "Freq") |>
    prep() |> (\(x) x$final_weight)()

  expect_equal(w_vec, w_tidy, tolerance = 1e-6)
})

test_that("an x_formula variable absent from population works with x_totals", {
  pop  <- make_pop(seed = 4)
  idx  <- sample(nrow(pop), 400)
  samp <- pop[idx, ]; samp$pw <- nrow(pop) / 400
  # z exists only in the sample; its total comes from outside the frame
  samp$z <- rnorm(nrow(samp), 10, 2)
  m_region <- as.data.frame(table(region = pop$region))
  z_total  <- nrow(pop) * 10                     # an external control total

  expect_no_error(
    fitted <- weighting_spec(samp, base_weights = pw) |>
      step_model_calibration(
        x_formula  = ~ region + z,
        models     = list(income = y_model(income ~ edu + region, engine = "glm")),
        population = pop,                          # pop has no `z` column
        x_totals   = list(region = m_region, z = z_total), count = "Freq") |>
      prep()
  )
  w <- fitted$final_weight
  expect_equal(sum(w[w > 0] * samp$z), z_total, tolerance = 1e-3)
})

test_that("x_totals not covering every x_formula term errors", {
  pop  <- make_pop(seed = 5)
  idx  <- sample(nrow(pop), 400)
  samp <- pop[idx, ]; samp$pw <- nrow(pop) / 400
  m_region <- as.data.frame(table(region = pop$region))

  expect_error(
    weighting_spec(samp, base_weights = pw) |>
      step_model_calibration(
        x_formula  = ~ region + age,
        models     = list(income = y_model(income ~ edu + region, engine = "glm")),
        population = pop,
        x_totals   = list(region = m_region), count = "Freq") |>   # no `age`
      prep()
  )
})

test_that("a malformed x_totals is rejected at construction", {
  pop  <- make_pop(seed = 6)
  samp <- pop[sample(nrow(pop), 400), ]; samp$pw <- nrow(pop) / 400
  expect_error(
    weighting_spec(samp, base_weights = pw) |>
      step_model_calibration(
        x_formula  = ~ region,
        models     = list(income = y_model(income ~ edu, engine = "glm")),
        population = pop, x_totals = "not valid"),
    "x_totals"
  )
})
