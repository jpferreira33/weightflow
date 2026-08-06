# Regression tests for silent-wrong-result bugs on degenerate data.

test_that("weighting_class drops nonrespondents even in a cell with no respondents (C1)", {
  dat <- data.frame(region    = c("A", "A", "B", "B"),
                    responded = c(1,   0,   0,   0),   # region B has NO respondents
                    pw        = c(10,  10,  10,  10))
  fit <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    prep()
  w <- fit$final_weight
  expect_equal(w[3], 0)                 # region B nonrespondents must be zeroed, not leak
  expect_equal(w[4], 0)
  expect_equal(w[2], 0)                 # region A nonrespondent zeroed
  expect_gt(w[1], 0)                    # region A respondent inflated
  # the empty cell is flagged for the report
  al <- unlist(lapply(fit$steps, function(s) s$alerts))
  expect_true(any(grepl("no units to adjust", al)))
})

test_that("linear/GREG calibration errors on NA auxiliaries (C2)", {
  set.seed(1)
  dat <- data.frame(region = c("A", "A", "B", "B", "A"),
                    x      = c(1, 2, NA, 4, 5),         # NA auxiliary
                    pw     = runif(5, 1, 2))
  tot <- c("(Intercept)" = 100, x = 50)                 # classic named-vector totals
  expect_error(
    weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ x, totals = tot) |>
      prep(),
    "missing values")
})

test_that("as_svrepdesign drops failed (NA) replicates (#7)", {
  skip_if_not_installed("survey")
  spec <- weighting_spec(sample_one, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(region = c(table(population$region))))
  bw <- bootstrap_weights(spec, replicates = 10, strata = "region", psu = "psu",
                          progress = FALSE)
  bw$replicates[, 3] <- NA                          # simulate a failed replicate
  expect_warning(rd <- as_svrepdesign(bw), "dropped")
  expect_true(inherits(rd, "svyrep.design"))
})

test_that("partial-response households are flagged (#5)", {
  dat <- data.frame(hh        = c(1, 1, 2, 2),
                    responded = c(1, 1, 1, 0),      # hh 2 responded only partially
                    pw        = c(10, 10, 10, 10))
  fit <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class",
                     cluster = "hh") |>
    prep()
  al <- unlist(lapply(fit$steps, function(s) s$alerts))
  expect_true(any(grepl("responded only partially", al)))
  expect_equal(fit$final_weight[3], 0)              # hh 2 zeroed, incl. its responder
  expect_equal(fit$final_weight[4], 0)
})

test_that("very small response propensities raise a quality alert (#4)", {
  set.seed(1)
  n <- 300
  x <- rnorm(n)
  responded <- rbinom(n, 1, plogis(3 * x))        # steep dependence on x
  x[1] <- -6; responded[1] <- 1                    # a respondent with ~0 propensity
  dat <- data.frame(x = x, responded = responded, pw = rep(1, n))
  fit <- suppressWarnings(
    weighting_spec(dat, base_weights = pw) |>
      step_nonresponse(respondent = responded, method = "propensity",
                       engine = "logit", formula = ~ x, num_classes = NULL) |>
      prep())
  al <- unlist(lapply(fit$steps, function(s) s$alerts))
  expect_true(any(grepl("small response propensities", al, ignore.case = TRUE)))
})

test_that("step conditions resolve variables from the caller's environment (#3)", {
  dat <- data.frame(prob = c(0.9, 0.1, 0.5), pw = c(1, 1, 1))
  cutoff <- 0.4                                   # defined in the caller, not the data
  fit <- weighting_spec(dat, base_weights = pw) |>
    step_drop_ineligible(ineligible = prob < cutoff) |>
    prep()
  expect_equal(fit$final_weight[2], 0)            # prob 0.1 < 0.4 -> dropped
  expect_gt(fit$final_weight[1], 0)               # prob 0.9 -> kept
})

test_that("step_calibrate errors on a misspelled margins variable (#1)", {
  dat <- data.frame(region = c("A", "B"), pw = c(1, 1))
  expect_error(
    weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "raking", margins = list(reginon = c(A = 1, B = 1))),
    "not columns of the data")
})

test_that("constructors validate base weights and num_classes (#9)", {
  expect_error(weighting_spec(data.frame(pw = c(1, -1)), base_weights = pw), "negative")
  expect_error(
    step_nonresponse(weighting_spec(data.frame(r = c(1, 0), pw = c(1, 1)), base_weights = pw),
                     respondent = r, method = "propensity", formula = ~ 1, num_classes = 0),
    "num_classes")
})

test_that("lonely-PSU collapse keeps distinct PSUs distinct (C3)", {
  # two strata, each a single PSU, whose ids collide ("1" in both)
  dat <- data.frame(stratum = c("A", "A", "B", "B"),
                    psu     = c("1", "1", "1", "1"),
                    pw      = c(1, 1, 1, 1))
  spec <- weighting_spec(dat, base_weights = pw)
  bw <- bootstrap_weights(spec, replicates = 20, strata = "stratum", psu = "psu",
                          lonely_psu = "collapse", seed = 1, progress = FALSE)
  # the two collapsed PSUs are now distinct, so they get resampled: at least one
  # replicate must differ from the point weights (otherwise variance is zero).
  expect_true(any(bw$replicates != bw$weights))
})
