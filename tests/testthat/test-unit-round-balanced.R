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

# --- formula = : the balancing matrix is the calibration design -------------
# Reported by A. Gutierrez, 2026-09: with `by` the step crosses the variables into
# cells, which is a different -- and stricter -- problem than the one the recipe
# calibrated. These pin the formula route and the inheritance.

test_that("`formula` balances on the calibration design, not on crossed cells", {
  set.seed(21)
  n <- 1200
  d <- data.frame(region = factor(sample(paste0("R", 1:4), n, TRUE)),
                  sex    = factor(sample(c("M", "F"), n, TRUE)),
                  age    = factor(sample(paste0("A", 1:5), n, TRUE)))
  d$pw <- runif(n, 4, 40)
  f  <- ~ region + sex + age
  Xf <- model.matrix(f, data = d)

  dev <- function(w) max(abs(colSums(w * Xf) - colSums(d$pw * Xf)))
  wf <- weighting_spec(d, base_weights = "pw") |>
    step_round(digits = 0L, method = "balanced", formula = f) |> prep()
  wc <- weighting_spec(d, base_weights = "pw") |>
    step_round(digits = 0L, method = "balanced",
               by = c("region", "sex", "age")) |> prep()

  expect_true(all(abs(wf$final_weight - round(wf$final_weight)) < 1e-9))
  # the cube residual is bounded by about one unit per COLUMN of the balancing
  # matrix; the formula has 10, the crossing has 40, so the formula route holds the
  # calibration totals and the crossing spends its slack on cells nobody asked for.
  expect_lt(dev(wf$final_weight), ncol(Xf))
  expect_lt(dev(wf$final_weight), dev(wc$final_weight))
})

test_that("`formula` is inherited from the calibration step when neither is given", {
  set.seed(22)
  n <- 800
  d <- data.frame(x = rnorm(n), g = factor(sample(c("a", "b", "c"), n, TRUE)))
  d$pw <- runif(n, 3, 25)
  tot  <- colSums(d$pw * model.matrix(~ x + g, data = d))

  sp <- weighting_spec(d, base_weights = "pw") |>
    step_calibrate(method = "linear", formula = ~ x + g, totals = tot) |>
    step_round(digits = 0L, method = "balanced")
  st <- sp$steps[[length(sp$steps)]]
  expect_identical(st$basis, "inherited")
  expect_equal(deparse(st$formula), deparse(~ x + g))

  out <- prep(sp)
  X   <- model.matrix(~ x + g, data = d)
  # the calibration hits `tot` exactly; the rounding must not move it by more than
  # the grid allows (about one unit's weight per column).
  expect_lt(max(abs(colSums(out$final_weight * X) - tot)) /
              max(abs(tot)), 0.01)
})

test_that("the balancing basis is refused when it is ambiguous or unusable", {
  d <- data.frame(g = factor(rep(c("a", "b"), 50)), pw = 1.5)
  sp <- weighting_spec(d, base_weights = "pw")
  expect_error(step_round(sp, method = "balanced", by = "g", formula = ~ g),
               "not both")
  expect_error(step_round(sp, method = "balanced", formula = "~ g"),
               "one-sided formula")
  expect_error(step_round(sp, method = "balanced", formula = pw ~ g),
               "one-sided formula")
  # no `by`, no `formula`, and nothing to inherit from
  expect_error(step_round(sp, method = "balanced"), "no earlier step_calibrate")
  # a variable that is NA on active units cannot be balanced on
  d2 <- d; d2$h <- c(NA, rep(c("x", "y"), length.out = 99))
  expect_error(
    prep(weighting_spec(d2, base_weights = "pw") |>
           step_round(method = "balanced", formula = ~ h)),
    "dropped 1 of the 100 active units")
  # a term with nothing to contrast fails inside model.matrix(); name it
  d3 <- d; d3$k <- "solo"
  expect_error(
    prep(weighting_spec(d3, base_weights = "pw") |>
           step_round(method = "balanced", formula = ~ k)),
    "carries no constraint")
})
