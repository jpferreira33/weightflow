# N-10, N-09, N-03. Three small ones on the non-probability path: a type check that
# refused a conversion instead of making it, a diagnostic that printed a figure it cannot
# reach, and a documented claim that measurement contradicts.

test_that("N-10: the same number stored two ways is not a type conflict", {
  skip_on_cran()
  set.seed(4); N <- 6000L
  pop <- data.frame(age = sample(18:80, N, TRUE), g = factor(sample(c("a", "b"), N, TRUE)))
  np  <- pop[stats::runif(N) < stats::plogis(-2.4 + 0.02 * (pop$age - 45)), , drop = FALSE]
  ri  <- sample(N, 900L); rf <- pop[ri, , drop = FALSE]; rf$w <- N / 900

  # age arrives as integer from one file and as double from the other: the same variable
  np$age <- as.integer(np$age); rf$age <- as.numeric(rf$age)
  f <- suppressWarnings(prep(weighting_spec(np, nonprob = TRUE) |>
    step_pseudoweight(reference = reference_sample(rf, weights = "w"), formula = ~ age + g),
    warn = FALSE))
  expect_true(all(is.finite(f$final_weight)))
  expect_gt(sum(f$final_weight), 0)

  # and it is the same answer as harmonising by hand beforehand, which is the point
  np2 <- np; np2$age <- as.numeric(np2$age)
  g <- suppressWarnings(prep(weighting_spec(np2, nonprob = TRUE) |>
    step_pseudoweight(reference = reference_sample(rf, weights = "w"), formula = ~ age + g),
    warn = FALSE))
  expect_equal(f$final_weight, g$final_weight, tolerance = 1e-12)

  # a mismatch that changes the MEANING of the column is still refused
  np3 <- np; np3$g <- as.character(np3$g)
  expect_error(suppressWarnings(prep(weighting_spec(np3, nonprob = TRUE) |>
    step_pseudoweight(reference = reference_sample(rf, weights = "w"), formula = ~ age + g),
    warn = FALSE)), "has type")
})

test_that("N-09: data_defect marks the rows whose effective size cannot be reached", {
  skip_on_cran()
  set.seed(6); N <- 8000L
  pop <- data.frame(x = stats::rnorm(N))
  np  <- pop[stats::runif(N) < stats::plogis(-2.5 + 0.5 * pop$x), , drop = FALSE]
  ri  <- sample(N, 800L); rf <- pop[ri, , drop = FALSE]; rf$w <- N / 800
  f <- suppressWarnings(prep(weighting_spec(np, nonprob = TRUE) |>
    step_pseudoweight(reference = reference_sample(rf, weights = "w"), formula = ~ x),
    warn = FALSE))
  dd <- data_defect(f)

  expect_equal(dd$rho_srs, 1 / sqrt(dd$N))
  expect_true("below_srs" %in% names(dd$grid))
  expect_identical(dd$grid$below_srs, dd$grid$ddc < dd$rho_srs)
  # the formula itself is untouched: this is a reading mark, not a different number
  expect_equal(dd$grid$n_eff, (dd$f / (1 - dd$f)) / dd$grid$ddc^2)
  # the rows that are marked are exactly the ones that overshoot the sample
  expect_true(all(dd$grid$n_eff[dd$grid$below_srs] > dd$n))

  out <- paste(utils::capture.output(print(dd)), collapse = " ")
  if (any(dd$grid$below_srs)) {
    expect_match(out, "\\(\\*\\)")
    expect_match(out, "1/sqrt\\(N\\)")
    expect_match(out, "more representative than a random one")
  }
})

test_that("N-03: by = is the interacted national model, and the additive one is not", {
  skip_on_cran()
  set.seed(9); N <- 12000L
  pop <- data.frame(x = stats::rnorm(N), dom = factor(sample(c("n", "s", "e"), N, TRUE)))
  b <- c(n = 0.9, s = -0.8, e = 0.2); a <- c(n = -2.2, s = -3.0, e = -2.6)
  k <- as.character(pop$dom)
  np <- pop[stats::runif(N) < stats::plogis(a[k] + b[k] * pop$x), , drop = FALSE]
  ri <- sample(N, 2500L); rf <- pop[ri, , drop = FALSE]; rf$w <- N / 2500
  rs <- reference_sample(rf, weights = "w")
  fit <- function(fm, by = NULL) suppressWarnings(prep(
    weighting_spec(np, nonprob = TRUE) |>
      step_pseudoweight(reference = rs, formula = fm, by = by), warn = FALSE))

  w_by  <- fit(~ x, by = "dom")$final_weight
  w_int <- fit(~ dom * x)$final_weight
  w_add <- fit(~ dom + x)$final_weight

  # the documented claim: these two are the same estimator for engine = "logit"
  expect_equal(w_by, w_int, tolerance = 1e-6)

  # and the additive national model is the one that misses the domains
  truth <- as.numeric(table(pop$dom))
  err <- function(w) max(abs(as.numeric(tapply(w, np$dom, sum)) / truth - 1))
  expect_lt(err(w_by), 0.10)
  expect_gt(err(w_add), err(w_by))
})
