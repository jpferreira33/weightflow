test_that("a raking with inconsistent margins does not converge", {
  set.seed(7)
  n   <- 300
  dat <- data.frame(sex = sample(c("M", "F"), n, TRUE),
                    age = sample(c("y", "o"), n, TRUE),
                    pw  = runif(n, 1, 5))
  # mutually inconsistent margins: sex sums to 1000, age sums to 800, so the
  # iterative proportional fitting oscillates and never converges.
  fitted <- suppressWarnings(
    weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "raking",
                     margins = list(sex = c(M = 500, F = 500),
                                    age = c(y = 400, o = 400))) |>
      prep()
  )
  cal <- fitted$steps[[1]]
  expect_false(isTRUE(attr(cal$diagnostics, "converged")))
})

test_that("report_weighting flags a raking that did not converge", {
  set.seed(7)
  n   <- 300
  dat <- data.frame(sex = sample(c("M", "F"), n, TRUE),
                    age = sample(c("y", "o"), n, TRUE),
                    pw  = runif(n, 1, 5))
  fitted <- suppressWarnings(
    weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "raking",
                     margins = list(sex = c(M = 500, F = 500),
                                    age = c(y = 400, o = 400))) |>
      prep()
  )

  tmp <- tempfile(fileext = ".html")
  suppressWarnings(report_weighting(fitted, file = tmp, open = FALSE, plots = FALSE))
  html <- paste(readLines(tmp), collapse = "\n")

  # the non-convergence alert is shown ...
  expect_match(html, "Did not converge")
  # ... and the report no longer claims the step converged
  expect_false(grepl("converged in [0-9]+ iterations", html))
  unlink(tmp)
})

test_that("report_weighting reports convergence when raking does converge", {
  set.seed(4)
  n   <- 300
  dat <- data.frame(sex = sample(c("M", "F"), n, TRUE), pw = runif(n, 1, 5))
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(sex = c(M = 600, F = 400))) |>
    prep()
  expect_true(isTRUE(attr(fitted$steps[[1]]$diagnostics, "converged")))

  tmp <- tempfile(fileext = ".html")
  report_weighting(fitted, file = tmp, open = FALSE, plots = FALSE)
  html <- paste(readLines(tmp), collapse = "\n")
  expect_false(grepl("Did not converge", html))
  unlink(tmp)
})
