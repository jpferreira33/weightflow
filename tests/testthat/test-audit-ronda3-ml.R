# Round-3 audit, the machine-learning engines: what a cross-fitting fold decides on its
# own (ML-01) and what the 1e-6 propensity floor hides (ML-02).

test_that("ML-01: regression vs classification is decided once, not fold by fold", {
  skip_if_not_installed("rpart")
  set.seed(11); n <- 500
  d <- data.frame(x = stats::rnorm(n))
  d$y <- ifelse(stats::runif(n) < 0.4, 0, 1000)
  d$y[7] <- 500                       # ONE rare value: absent from exactly one training set
  fold <- rep(1:5, length.out = n)[order(stats::runif(n))]

  m  <- y_model(y ~ x, engine = "tree")
  m$classify <- .wf_is_class(d$y, m$family)
  mu <- vapply(1:5, function(k) {
    tr <- which(fold != k); te <- which(fold == k)
    mean(.model_predict(m, d[tr, , drop = FALSE], rep(1, length(tr)),
                        list(d[te, , drop = FALSE]))[[1]])
  }, numeric(1))
  # every fold on the E[y] scale; the odd one used to come back as P(y = 1000) in [0, 1]
  expect_true(all(mu > 100))
  expect_lt(max(mu) / min(mu), 2)
  expect_lt(abs(mean(mu) - mean(d$y)) / mean(d$y), 0.2)
})

test_that("ML-01: an explicit `family` is honoured", {
  y2 <- c(rep(0, 40), rep(1000, 60))               # numeric with exactly two values
  expect_false(.wf_is_class(y2, "gaussian"))       # used to be TRUE: the heuristic won
  expect_true(.wf_is_class(y2, "binomial"))
  expect_true(.wf_is_class(y2, NULL))              # unchanged default
  expect_true(.wf_is_class(factor(c("a", "b", "c")), NULL))
  expect_false(.wf_is_class(c(1, 2, 3, 4), NULL))
})

test_that("ML-02: the 0/1 boundary is refused where a raw 1/p would use it", {
  set.seed(3); n <- 404
  dd <- data.frame(w0 = 250,
                   region = factor(c(rep("A", 200), rep("B", 200), rep("RARA", 4))),
                   x = stats::rnorm(n))
  dd$resp <- stats::rbinom(n, 1, 0.7)
  dd$resp[dd$region == "RARA"] <- c(0, 0, 0, 1)    # the fold that trains on the 3 NRs
  mk <- function(nc) weighting_spec(dd, base_weights = w0) |>
    step_nonresponse(respondent = resp == 1, method = "propensity",
                     formula = ~ region + x, engine = "logit",
                     crossfit = 5, num_classes = nc)

  # Both paths must SAY it -- a real warning(), which prep(warn = FALSE) does not
  # suppress, not only a quality alert nobody prints. The message names what the
  # step will actually do with those propensities.
  expect_warning(prep(mk(NULL), warn = FALSE), "multiplied by up to 1e6")
  expect_warning(p <- prep(mk(5L), warn = FALSE), "0/1 boundary")
  expect_warning(prep(mk(5L), warn = FALSE), "num_classes. binning keeps")
  # and with the default binning the weighted total is still preserved exactly
  expect_equal(sum(collect_weights(p, drop_zero = FALSE)$.weight), sum(dd$w0),
               tolerance = 1e-8)

  # a non-finite propensity is a broken fit, not a small number: that one stops
  expect_error(
    .estimate_propensity("logit", ~ region + x,
                         transform(dd, .y = resp), rep(1, n),
                         crossfit = NULL, raw_inverse = TRUE) |> suppressWarnings(),
    NA)
})

test_that("ML-02: a fold that cannot be fitted says so", {
  set.seed(3); n <- 404
  dd <- data.frame(w0 = 250,
                   region = factor(c(rep("A", 200), rep("B", 200), rep("RARA", 4))),
                   x = stats::rnorm(n))
  dd$resp <- 1; dd$resp[50] <- 0                   # a single nonrespondent
  for (eng in c("logit", "tree")) {
    if (eng == "tree") skip_if_not_installed("rpart")
    expect_error(
      prep(weighting_spec(dd, base_weights = w0) |>
             step_nonresponse(respondent = resp == 1, method = "propensity",
                              formula = ~ region + x, engine = eng,
                              crossfit = 5, crossfit_seed = 7, num_classes = 5L),
           warn = FALSE),
      "training set contains only respondents")
  }
})
