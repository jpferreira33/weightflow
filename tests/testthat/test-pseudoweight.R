# step_pseudoweight(): pseudo-weighting a non-probability sample against a
# probability reference, and the nonprob = TRUE semantics of weighting_spec().

test_that("weighting_spec requires nonprob = TRUE when base_weights is NULL", {
  expect_error(weighting_spec(sample_survey, base_weights = NULL), "nonprob = TRUE")
  sp <- weighting_spec(sample_survey, base_weights = NULL, nonprob = TRUE)
  expect_true(isTRUE(sp$nonprob))
  expect_true(all(sp$data[[sp$base_weights]] == 1))       # base weight 1
})

test_that("step_pseudoweight is only for a non-probability spec", {
  sp  <- weighting_spec(sample_survey, base_weights = pw)   # probability
  ref <- reference_sample(data.frame(region = c("North", "South"), d = c(5, 5)), "d")
  expect_error(step_pseudoweight(sp, reference = ref, formula = ~ region),
               "NON-probability")
})

test_that("step_pseudoweight builds inverse-propensity pseudo-weights and cuts bias", {
  set.seed(1)
  N   <- nrow(population)
  # volunteer (non-probability) sample: men over-participate -> biased on income
  p   <- plogis(-2 + 0.9 * (population$sex == "M"))
  vol <- population[runif(N) < p, c("region", "sex", "income")]
  # probability reference: SRS with design weights summing to N
  idx <- sample(N, 800)
  ref <- population[idx, c("region", "sex")]; ref$d <- N / 800

  fit <- suppressWarnings(
    weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
      step_pseudoweight(reference = reference_sample(ref, "d"),
                        formula = ~ region + sex, engine = "logit") |>
      prep())
  w <- fit$final_weight
  expect_true(all(is.finite(w) & w > 0))
  # the (1 - p)/p pseudo-weights sum to the population size N (a 1/p mistake would
  # sum to N + n, ~15-20% too high); allow only single-draw sampling noise
  expect_equal(sum(w), N, tolerance = 0.1)
  # bias on the income mean is reduced versus the naive volunteer mean
  truth <- mean(population$income)
  naive <- mean(vol$income)
  psw   <- weighted.mean(vol$income, w)
  expect_lt(abs(psw - truth), abs(naive - truth))
})

test_that("step_pseudoweight runs inside the recipe-aware bootstrap", {
  set.seed(2)
  N   <- nrow(population)
  vol <- population[rbinom(N, 1, plogis(-2 + 0.9 * (population$sex == "M"))) == 1,
                    c("region", "sex", "income")]
  ref <- population[sample(N, 600), c("region", "sex")]; ref$d <- N / 600
  spec <- weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
    step_pseudoweight(reference = reference_sample(ref, "d"),
                      formula = ~ region + sex, engine = "logit")
  boot <- suppressWarnings(
    bootstrap_weights(spec, replicates = 30, seed = 1, progress = FALSE))
  est <- boot_mean(boot, "income")
  expect_true(is.finite(est$se) && est$se > 0)
})
