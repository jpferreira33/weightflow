# Regression: step_nonresponse(num_classes=) used to fail with
# "invalid number of intervals" when the fitted propensities were nearly
# constant (the quantile cut-points collapsed to a single break, which cut()
# misreads as a count of intervals). Now the classes collapse to one adjustment
# cell and a quality alert is raised. Found by the variance-validation
# simulation (S2b), fixed with this regression test.

test_that("num_classes collapses (not errors) when propensities are ~constant", {
  set.seed(1)
  n  <- 500L
  df <- data.frame(pw = runif(n, 1, 2), x = rnorm(n),
                   resp = rbinom(n, 1, 0.7))          # response independent of x
  # intercept-only propensity -> constant p-hat -> quantile breaks collapse
  expect_no_error(
    fit <- weighting_spec(df, base_weights = pw) |>
      step_nonresponse(resp, method = "propensity", formula = ~ 1,
                       num_classes = 5) |>
      prep()
  )
  st <- fit$steps[[1]]
  expect_true(isTRUE(attr(st$diagnostics, "classes_collapsed")))
  expect_equal(nrow(st$diagnostics), 1L)                 # a single adjustment class
  expect_true(any(grepl("nearly constant", fit$alerts)))
  w <- collect_weights(fit, drop_zero = FALSE)$.weight
  expect_true(all(is.finite(w)))
})

test_that("the collapse is deterministic (no jitter): two runs give identical weights", {
  # Contrast with implementations that jitter the propensities to avoid the
  # degenerate cut(): those never fail but fabricate classes from noise and are
  # not reproducible across runs. weightflow collapses deterministically.
  set.seed(1)
  n  <- 500L
  df <- data.frame(pw = runif(n, 1, 2), x = rnorm(n), resp = rbinom(n, 1, 0.7))
  run <- function() collect_weights(
    prep(step_nonresponse(weighting_spec(df, base_weights = pw), resp,
                          method = "propensity", formula = ~ 1, num_classes = 5)),
    drop_zero = FALSE)$.weight
  expect_identical(run(), run())
})

test_that("num_classes collapse is handled at household (cluster) level too", {
  set.seed(2)
  H  <- 300L
  hh <- data.frame(hid = seq_len(H))
  members <- hh[rep(seq_len(H), sample(1:3, H, TRUE)), , drop = FALSE]
  members$pw   <- runif(nrow(members), 1, 2)
  members$resp <- rbinom(nrow(members), 1, 0.7)
  expect_no_error(
    weighting_spec(members, base_weights = pw) |>
      step_nonresponse(resp, method = "propensity", formula = ~ 1,
                       cluster = "hid", num_classes = 4) |>
      prep()
  )
})

test_that("a genuine gradient still forms the requested classes", {
  set.seed(3)
  n  <- 2000L
  x  <- rnorm(n)
  df <- data.frame(pw = runif(n, 1, 2), x = x,
                   resp = rbinom(n, 1, plogis(-0.2 + 1.2 * x)))   # real signal
  fit <- weighting_spec(df, base_weights = pw) |>
    step_nonresponse(resp, method = "propensity", formula = ~ x,
                     num_classes = 5) |>
    prep()
  st <- fit$steps[[1]]
  expect_null(attr(st$diagnostics, "classes_collapsed"))
  expect_equal(nrow(st$diagnostics), 5L)                 # five propensity classes
})
