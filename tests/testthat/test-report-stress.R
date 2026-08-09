# Stress cases for the HTML report found in the blindaje rounds.

test_that("report survives a single-covariate logit propensity (C5)", {
  set.seed(1); n <- 300L
  d <- data.frame(edad = rnorm(n), resp = rbinom(n, 1, 0.7), pw = runif(n, 1, 2))
  fit <- prep(weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "propensity", engine = "logit",
                     formula = ~ edad, num_classes = NULL))
  f <- tempfile(fileext = ".html")
  expect_error(report_weighting(fit, file = f, open = FALSE, plots = FALSE), NA)
  expect_true(file.exists(f))
  # the importance table still lists the single predictor by name (not NA)
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_false(grepl("<td>NA</td>", html))
})

test_that("infeasible trim bounds raise a mass-loss alert and an honest narrative", {
  set.seed(2); n <- 500L
  d <- data.frame(pw = runif(n, 8, 12), x = seq_len(n))   # sum ~ 5000
  fit <- weighting_spec(d, base_weights = pw) |>
    step_trim_weights(lower = 0, upper = 6) |>             # n*6 = 3000 < sum -> mass falls
    prep()
  expect_true(any(grepl("reduced the weight total", fit$alerts)))
  f <- tempfile(fileext = ".html")
  report_weighting(fit, file = f, open = FALSE, plots = FALSE, narrative = TRUE)
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_true(grepl("weight total fell by", html))
  expect_false(grepl("preserving the weight total", html))   # no contradiction
})

test_that("a feasible trim keeps the preserve-the-total narrative and no mass alert", {
  set.seed(3); n <- 500L
  d <- data.frame(pw = c(runif(n - 5, 8, 12), rep(60, 5)), x = seq_len(n))  # a few outliers
  fit <- weighting_spec(d, base_weights = pw) |>
    step_trim_weights(lower = 0, upper = 30) |>            # feasible: room to redistribute
    prep()
  expect_false(any(grepl("reduced the weight total", fit$alerts)))
  f <- tempfile(fileext = ".html")
  report_weighting(fit, file = f, open = FALSE, plots = FALSE, narrative = TRUE)
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_true(grepl("preserving the weight total", html))
  expect_false(grepl("Tukey", html))                       # manual bounds: no rule named
})
