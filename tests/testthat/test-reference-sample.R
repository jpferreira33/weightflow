# reference_sample(): use a WEIGHTED reference survey as the calibration
# `population` for step_model_calibration(). Point-estimate feature (the
# reference sampling variance is not propagated yet).

make_pop_rs <- function(N = 1500, seed = 7) {
  set.seed(seed)
  reg <- sample(c("A", "B", "C"), N, TRUE)
  age <- stats::rnorm(N, 45, 12)
  edu <- stats::rnorm(N, 12, 3)
  inc <- 100 + 5 * (reg == "B") + 0.5 * age + 2 * edu + stats::rnorm(N, 0, 5)
  data.frame(region = reg, age = age, edu = edu, income = inc)
}

rs_recipe <- function(samp, popn) {
  weighting_spec(samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region + age,
      models     = list(income = y_model(income ~ edu + region, engine = "glm")),
      population = popn) |>
    prep()
}

test_that("reference_sample with all weights = 1 reproduces the plain-frame path exactly", {
  pop  <- make_pop_rs()
  idx  <- sample(nrow(pop), 400)
  samp <- pop[idx, ]; samp$pw <- nrow(pop) / 400

  w_frame <- rs_recipe(samp, pop)$final_weight
  w_ref1  <- rs_recipe(samp, reference_sample(pop, weights = rep(1, nrow(pop))))$final_weight
  expect_equal(w_ref1, w_frame, tolerance = 1e-8)
})

test_that("the reference weights actually matter (different weights -> different result)", {
  pop  <- make_pop_rs(seed = 3)
  idx  <- sample(nrow(pop), 400)
  samp <- pop[idx, ]; samp$pw <- nrow(pop) / 400

  w1 <- rs_recipe(samp, reference_sample(pop, weights = rep(1, nrow(pop))))$final_weight
  # tilt the reference weights by region -> the projected totals change
  wv <- ifelse(pop$region == "B", 3, 1)
  w2 <- rs_recipe(samp, reference_sample(pop, weights = wv))$final_weight
  expect_false(isTRUE(all.equal(w1, w2)))
})

test_that("reference_sample validates its weights", {
  pop <- make_pop_rs(N = 60)
  expect_error(reference_sample(pop, weights = rep(-1, nrow(pop))), "positive")
  expect_error(reference_sample(pop, weights = c(NA_real_, rep(1, nrow(pop) - 1))), "positive")
  expect_error(reference_sample(pop, weights = "nope"), "not found")
  expect_error(reference_sample(pop, weights = rep(1, 3)), "one value per row")
  pop$wv <- 1
  rs <- reference_sample(pop, weights = "wv")
  expect_equal(attr(rs, "wf_ref_weights"), rep(1, nrow(pop)))
  expect_true(is.data.frame(rs))
})
