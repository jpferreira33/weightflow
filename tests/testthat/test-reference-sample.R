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

test_that("a replicate index re-estimates the totals from the paired reference replicate", {
  pop  <- make_pop_rs(seed = 5)
  idx  <- sample(nrow(pop), 400)
  samp <- pop[idx, ]; samp$pw <- nrow(pop) / 400

  # col 1 = the point weights (all 1); col 2 = tilted by region -> different totals
  reps <- cbind(rep(1, nrow(pop)), ifelse(pop$region == "B", 2, 1))
  ref  <- reference_sample(pop, weights = rep(1, nrow(pop)), replicates = reps)

  spec <- weighting_spec(samp, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ region + age,
      models     = list(income = y_model(income ~ edu + region, engine = "glm")),
      population = ref)

  w_point <- prep(spec)$final_weight

  # replicate 1 uses col 1 == point weights -> identical to the point estimate
  sp1 <- spec; attr(sp1$data, "wf_replicate_idx") <- 1L
  expect_equal(prep(sp1)$final_weight, w_point, tolerance = 1e-8)

  # replicate 2 uses the tilted column -> different targets -> different weights
  sp2 <- spec; attr(sp2$data, "wf_replicate_idx") <- 2L
  expect_false(isTRUE(all.equal(prep(sp2)$final_weight, w_point)))
})

test_that("reference_sample validates the replicates matrix", {
  pop <- make_pop_rs(N = 40)
  w1  <- rep(1, nrow(pop))
  expect_error(reference_sample(pop, w1, replicates = matrix(1, nrow(pop), 1)), "at least 2")
  expect_error(reference_sample(pop, w1, replicates = matrix(1, 10, 3)), "one row per")
  bad <- matrix(1, nrow(pop), 3); bad[1, 1] <- NA
  expect_error(reference_sample(pop, w1, replicates = bad), "non-negative")
  good <- reference_sample(pop, w1, replicates = matrix(1, nrow(pop), 4))
  expect_equal(ncol(attr(good, "wf_ref_replicates")), 4)
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
