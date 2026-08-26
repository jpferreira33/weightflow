# step_nr_sensitivity(): proxy pattern-mixture sensitivity (Andridge-Little 2011).

test_that("PPMM recovers the true mean at the generating phi", {
  # Build data that satisfies the PPMM exactly at phi0: respondents ~ N(0, Sigma),
  # nonrespondents shifted along Sigma %*% (1-phi0, phi0) -- the selection-on-V
  # direction. Then mu(phi0) must recover the true full-sample mean of Y.
  set.seed(11)
  rho <- 0.6; phi0 <- 0.5; nR <- 6000L; nNR <- 3000L
  Sig <- matrix(c(1, rho, rho, 1), 2L)
  L   <- chol(Sig)
  rmvn <- function(n, mu) sweep(matrix(stats::rnorm(n * 2L), n, 2L) %*% L, 2L, mu, "+")
  del  <- 0.8 * as.numeric(Sig %*% c(1 - phi0, phi0))    # nonrespondent mean shift
  Rd   <- rmvn(nR, c(0, 0)); NRd <- rmvn(nNR, del)
  x    <- c(Rd[, 1], NRd[, 1]); yv <- c(Rd[, 2], NRd[, 2])
  resp <- c(rep(TRUE, nR), rep(FALSE, nNR))
  truth <- mean(yv)                                       # true full-sample mean

  dat <- data.frame(xaux = x, y = ifelse(resp, yv, NA_real_), pw = 1)
  fit <- weighting_spec(dat, base_weights = pw) |>
    step_nr_sensitivity(y = y, formula = ~ xaux, phi = c(0, phi0, 1)) |>
    prep()
  s <- nr_sensitivity(fit)

  mu_phi0 <- s$table$mu[s$table$phi == phi0]
  expect_equal(mu_phi0, truth, tolerance = 0.03)          # recovers truth at generating phi
  # phi is interior and mu(phi) is monotone, so truth lies inside the ignorance interval
  expect_true(s$ignorance[1] - 1e-8 <= truth && truth <= s$ignorance[2] + 1e-8)
  # phi = 0 (MAR) understates the shift: it is closer to the respondent mean than truth
  expect_lt(abs(s$mu_mar - 0), abs(truth - 0) + 0.05)
})

test_that("step_nr_sensitivity is a no-op that returns an ignorance analysis", {
  base <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region")
  fit0 <- prep(base)
  fit  <- prep(base |> step_nr_sensitivity(y = income, formula = ~ region + sex + age))

  expect_equal(fit$final_weight, fit0$final_weight, tolerance = 1e-12)   # weights untouched
  s <- nr_sensitivity(fit)
  expect_s3_class(s, "weightflow_nr_sensitivity")
  expect_true(all(c("phi", "mu") %in% names(s$table)))
  expect_true(s$ignorance[1] <= s$mu_mar && s$mu_mar <= s$ignorance[2])
  expect_output(print(s), "proxy pattern-mixture")
})

test_that("m(phi) hits the theoretical endpoints rho and 1/rho", {
  # With a pure proxy shift, mu(phi) - ybar_r = (1-pi)(s_y/s_x) m(phi) dx, so the
  # ratio of the phi=1 to phi=0 shifts is m(1)/m(0) = (1/rho)/rho = 1/rho^2. This is
  # a genuine check of the endpoint multipliers, not a tautology.
  set.seed(3)
  rho <- 0.5; n <- 6000L
  x  <- stats::rnorm(n); yv <- rho * x + sqrt(1 - rho^2) * stats::rnorm(n)
  resp <- rep(c(TRUE, FALSE), c(4000, 2000))
  x[!resp] <- x[!resp] + 1.5                       # nonrespondents shifted in the proxy only
  dat <- data.frame(xaux = x, y = ifelse(resp, yv, NA_real_), pw = 1)
  fit <- weighting_spec(dat, base_weights = pw) |>
    step_nr_sensitivity(y = y, formula = ~ xaux, phi = c(0, 1)) |>
    prep()
  s   <- nr_sensitivity(fit)
  mu0 <- s$table$mu[s$table$phi == 0]; mu1 <- s$table$mu[s$table$phi == 1]
  ratio <- (mu1 - s$ybar_r) / (mu0 - s$ybar_r)
  expect_equal(ratio, 1 / s$rho^2, tolerance = 0.03)
})

test_that("eligible excludes out-of-scope units from the nonrespondent set (S-01)", {
  set.seed(7); n <- 3000L
  x <- stats::rnorm(n); yv <- 0.6 * x + sqrt(1 - 0.36) * stats::rnorm(n)
  grp <- rep(c("resp", "enr", "inelig"), c(2000, 500, 500))
  x[grp == "enr"]    <- x[grp == "enr"]    + 1     # eligible nonrespondents: modest shift
  x[grp == "inelig"] <- x[grp == "inelig"] + 8     # out-of-scope: far-off proxy
  dat <- data.frame(xaux = x, y = ifelse(grp == "resp", yv, NA_real_),
                    elig = grp != "inelig", pw = 1)
  s_all  <- nr_sensitivity(suppressWarnings(weighting_spec(dat, base_weights = pw) |>
    step_nr_sensitivity(y = y, formula = ~ xaux) |> prep()))
  s_elig <- nr_sensitivity(suppressWarnings(weighting_spec(dat, base_weights = pw) |>
    step_nr_sensitivity(y = y, formula = ~ xaux, eligible = elig) |> prep()))
  expect_equal(s_elig$n_nonresp, 500L)             # only the eligible nonrespondents
  expect_equal(s_all$n_nonresp, 1000L)             # default wrongly counts the ineligibles
  expect_false(isTRUE(all.equal(s_elig$ignorance, s_all$ignorance)))
})
