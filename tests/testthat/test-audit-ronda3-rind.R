# RIND-01. The R-indicator is the standard deviation of the FITTED response
# propensities, so the plug-in absorbs the model's own estimation error: under MCAR,
# where the truth is R = 1, it fell as the propensity model grew (0.98 with two
# auxiliary categories, 0.91 with ten, 0.81 with forty, 0.70 at n = 200). Two surveys
# with identical real representativity scored differently according to how many
# dummies their model had, and the partials named drivers of nonresponse in data with
# none. The estimator is now bias-adjusted (Schouten, Shlomo and Skinner 2011).

mcar_R <- function(n, K, reps, seed, w = NULL) {
  set.seed(seed)
  replicate(reps, {
    dat <- data.frame(w0 = if (is.null(w)) 10 else w(n),
                      g = factor(sample(seq_len(K), n, TRUE)))
    dat$resp <- stats::rbinom(n, 1, 0.6)          # MCAR: R = 1 exactly
    p <- suppressWarnings(prep(
      weighting_spec(dat, base_weights = w0) |>
        step_nonresponse(respondent = resp == 1, method = "propensity",
                         formula = ~ g, engine = "logit"), warn = FALSE))
    ri <- .r_indicator(p)
    if (is.null(ri)) NA_real_ else as.numeric(ri$R)
  })
}

test_that("RIND-01: the R-indicator is not driven down by the size of the model", {
  small <- mean(mcar_R(600,  4, 60, seed = 5), na.rm = TRUE)
  big   <- mean(mcar_R(600, 20, 60, seed = 7), na.rm = TRUE)
  # both near the truth (the plug-in gave about 0.89 for the 20-category model here)
  expect_gt(small, 0.95)
  expect_gt(big,   0.93)
  # and, the actual complaint, they must not disagree with each other
  expect_lt(abs(small - big), 0.05)
  expect_lte(big, 1)
})

test_that("RIND-01: unequal weights are handled by the sandwich, and equal ones are not changed", {
  # the inverse-information (hatvalues) form under-corrects when the weights vary
  unequal <- mean(mcar_R(600, 20, 60, seed = 11,
                         w = function(n) stats::rlnorm(n, 2, 0.8)), na.rm = TRUE)
  expect_gt(unequal, 0.90)

  # with equal weights the sandwich collapses to the hat diagonal: check it directly
  set.seed(3); n <- 500
  g <- factor(sample(c("a", "b", "c", "d"), n, TRUE)); y <- stats::rbinom(n, 1, 0.6)
  fit <- stats::glm(y ~ g, family = stats::binomial(), weights = rep(1, n))
  X <- stats::model.matrix(fit); rho <- as.numeric(stats::fitted(fit)); v <- rho * (1 - rho)
  A <- crossprod(X, X * v); B <- crossprod(X, X * v)
  q <- rowSums((X %*% (solve(A, B) %*% solve(A))) * X)
  expect_equal(unname(v^2 * q), as.numeric(stats::hatvalues(fit)) * v, tolerance = 1e-8)
})

test_that("RIND-01: a real departure from representativity is NOT corrected away", {
  # response 0.4 in half the cells and 0.8 in the other half: S = 0.2, so R = 0.600
  set.seed(13)
  v <- replicate(60, {
    dat <- data.frame(w0 = 10, g = factor(sample(seq_len(10), 2000, TRUE)))
    dat$resp <- stats::rbinom(2000, 1,
                              ifelse(as.integer(dat$g) %% 2 == 0, 0.4, 0.8))
    p <- suppressWarnings(prep(
      weighting_spec(dat, base_weights = w0) |>
        step_nonresponse(respondent = resp == 1, method = "propensity",
                         formula = ~ g, engine = "logit"), warn = FALSE))
    as.numeric(.r_indicator(p)$R)
  })
  expect_lt(abs(mean(v, na.rm = TRUE) - 0.6), 0.03)
})
