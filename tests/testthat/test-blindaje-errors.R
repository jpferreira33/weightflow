# Blindaje: los mensajes de error se disparan cuando deben, con el texto que deben.
# Cada test fija un contrato de la API: si un refactor cambia o silencia el error,
# estos tests lo detectan.

make_d <- function(n = 300, seed = 11) {
  set.seed(seed)
  data.frame(id = 1:n,
             x = factor(sample(c("A", "B"), n, TRUE)),
             g = factor(sample(c("u", "v"), n, TRUE)),
             z = rnorm(n), w = runif(n, 1, 3),
             resp = rbinom(n, 1, 0.7) == 1, y = rnorm(n, 10))
}

test_that("negative base weights are rejected at construction", {
  d <- make_d(); d$w[1] <- -0.5
  expect_error(weighting_spec(d, base_weights = w), "cannot be negative")
})

test_that("num_classes < 2 is rejected at construction with a clear message", {
  d <- make_d()
  sp <- weighting_spec(d, base_weights = w)
  expect_error(step_nonresponse(sp, respondent = resp, method = "propensity",
                                formula = ~x, num_classes = 1),
               "single integer >= 2")
  expect_error(step_nonresponse(sp, respondent = resp, method = "propensity",
                                formula = ~x, num_classes = 0),
               "single integer >= 2")
})

test_that("a nonexistent `by` cell variable errors at prep with its name", {
  d <- make_d()
  sp <- weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "nope")
  expect_error(suppressMessages(prep(sp)), "nope")
})

test_that("classic `margins` with a variable not in the data errors at construction", {
  d <- make_d()
  expect_error(step_calibrate(weighting_spec(d, base_weights = w),
                              method = "raking", margins = list(nope = c(a = 1))),
               "not columns of the data")
})

test_that("classic linear calibration with NA auxiliaries errors (no silent recycling)", {
  d <- make_d(); d$z[3] <- NA
  sp <- weighting_spec(d, base_weights = w) |>
    step_calibrate(method = "linear", formula = ~z,
                   totals = c("(Intercept)" = 600, z = 10))
  expect_error(suppressMessages(prep(sp)), "missing values")
})

test_that("invalid bounds c(L, U) with L > 1 error at construction", {
  d <- make_d()
  expect_error(step_calibrate(weighting_spec(d, base_weights = w), method = "linear",
                              formula = ~x, totals = c("(Intercept)" = 600, xB = 300),
                              bounds = c(2, 0.5)),
               "L < 1 < U")
})

test_that("tidy totals: count column missing from a totals data frame errors at construction", {
  d <- make_d()
  tot <- data.frame(x = c("A", "B"), N = c(300, 320))   # columna se llama N, no Freq
  expect_error(step_calibrate(weighting_spec(d, base_weights = w),
                              method = "raking", totals = list(tot), count = "Freq"),
               "Freq")
})

test_that("step_select_within with invalid probabilities errors", {
  d <- make_d(); d$p_sel <- 1.5
  sp <- weighting_spec(d, base_weights = w) |> step_select_within(prob = p_sel)
  expect_error(suppressMessages(prep(sp)))
})

test_that("equal_within_cluster without cluster errors at construction", {
  d <- make_d()
  expect_error(step_calibrate(weighting_spec(d, base_weights = w), method = "linear",
                              formula = ~x, totals = c("(Intercept)" = 600, xB = 300),
                              equal_within_cluster = TRUE))
})

test_that("NSE conditions can use variables from the calling environment", {
  d <- make_d()
  cutoff <- 0L   # variable externa: el bug I4 original
  d$rnum <- as.integer(d$resp)
  sp <- weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = rnum > cutoff, method = "weighting_class", by = "x")
  expect_s3_class(suppressMessages(prep(sp)), "prepped_weighting_spec")
})
