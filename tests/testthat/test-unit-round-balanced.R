test_that("balanced rounding keeps weights on the integer grid, +-1 of the input", {
  set.seed(1)
  w <- runif(300, 0.6, 5.4)
  Z <- cbind(1, model.matrix(~ g - 1, data.frame(g = factor(sample(4, 300, TRUE)))))
  r <- weightflow:::.wf_balanced_round(w, Z, digits = 0L)
  expect_true(all(abs(r - round(r)) < 1e-9))     # integers
  expect_true(all(r >= floor(w) - 1e-9 & r <= ceiling(w) + 1e-9))  # floor/ceiling only
})

test_that("balanced rounding preserves domain totals far better than nearest", {
  set.seed(2)
  n  <- 600
  dom <- factor(sample(c("a", "b", "c"), n, TRUE))
  w   <- runif(n, 0.5, 6)
  Z   <- model.matrix(~ dom)                      # intercept + 2 dummies
  rb  <- weightflow:::.wf_balanced_round(w, Z, digits = 0L)
  rn  <- round(w)
  tot <- function(r) tapply(r, dom, sum)
  true_tot <- tapply(w, dom, sum)
  dev_bal  <- max(abs(tot(rb) - true_tot))
  dev_near <- max(abs(tot(rn) - true_tot))
  # cube residual is bounded by ~1 unit per constraint; nearest drifts freely
  expect_lt(dev_bal, 1.5)
  expect_lt(dev_bal, dev_near)
})

test_that("step_round(method = 'balanced') runs end to end and preserves region totals", {
  data(sample_survey, package = "weightflow")
  set.seed(3)
  out <- weighting_spec(sample_survey, base_weights = "pw") |>
    step_round(digits = 0L, method = "balanced", by = "region") |>
    prep()
  w0 <- sample_survey$pw
  w1 <- out$final_weight
  expect_true(all(abs(w1 - round(w1)) < 1e-9))
  reg_dev <- max(abs(tapply(w1, sample_survey$region, sum) -
                     tapply(w0, sample_survey$region, sum)))
  expect_lt(reg_dev, 1.5)          # each region total held to < one unit
})

test_that("step_round(method = 'balanced') requires `by`", {
  expect_error(
    weighting_spec(sample_survey, base_weights = "pw") |>
      step_round(method = "balanced"),
    "by")
})
