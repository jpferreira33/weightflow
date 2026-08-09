# SPSS/Stata imports (haven): a haven_labelled column is fine for `by` cells and
# 0/1 dispositions (they go by the codes), but two natural mistakes must be caught
# loudly: (1) a classic margin named by the labels while the data holds the codes,
# and (2) a labelled variable used in a model formula (enters as continuous codes).

# minimal haven_labelled without needing the haven package installed
.lab <- function(codes, labels)
  structure(codes, labels = labels, class = "haven_labelled")

test_that("a labelled variable in a model formula is an error (would enter as codes)", {
  set.seed(1); n <- 80L
  d <- data.frame(pw = runif(n, 1, 2), resp = rbinom(n, 1, 0.7))
  d$region <- .lab(sample(1:3, n, TRUE), c(N = 1, S = 2, E = 3))
  expect_error(prep(weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "propensity",
                     formula = ~ region, num_classes = NULL)),
    "haven_labelled")
  expect_error(prep(weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ region,
                   totals = c(`(Intercept)` = n, region = 2))),
    "haven_labelled")
})

test_that("a classic margin named by labels on a labelled column errors, showing observed levels", {
  set.seed(2); n <- 90L
  d <- data.frame(pw = runif(n, 1, 2))
  d$region <- .lab(sample(1:3, n, TRUE), c(Norte = 1, Sur = 2, Este = 3))
  err <- tryCatch(prep(weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(region = c(Norte = 30, Sur = 30, Este = 30)))),
    error = function(e) conditionMessage(e))
  expect_true(grepl("match no active unit", err))
  expect_true(grepl("Observed level", err))   # lists the codes the user actually has
})

test_that("labelled is fine for `by` cells (grouping goes by the codes)", {
  set.seed(3); n <- 200L
  d <- data.frame(pw = runif(n, 1, 2), resp = rbinom(n, 1, 0.7))
  d$region <- .lab(sample(1:3, n, TRUE), c(N = 1, S = 2, E = 3))
  expect_error(prep(weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "region")),
    NA)
})
