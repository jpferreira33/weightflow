# N-07, N-08, N-11. Three ways the non-probability path accepted something meaningless
# without a word. They share a shape: the recipe runs, every step passes its own checks,
# and the only thing wrong is what the result is taken to mean.
#
#   N-07  as_svydesign() handed a volunteer sample to survey as a sampling design, so
#         svymean()/svytotal() computed standard errors from a randomization that never
#         happened (SRS with replacement, by default).
#   N-08  a recipe declaring nonprob = TRUE and adjusting nothing returned weights of 1
#         and no alert: the unweighted volunteer mean, presented as a weighted estimate.
#   N-11  two step_pseudoweight() in one recipe multiplied the two participation odds,
#         the second fit reading the first's pseudo-weights as design weights.

nps_fx <- function(seed = 3, N = 8000L) {
  set.seed(seed)
  pop <- data.frame(x = stats::rnorm(N), g = factor(sample(c("a", "b"), N, TRUE)))
  np  <- pop[stats::runif(N) < stats::plogis(-2.5 + 0.5 * pop$x), , drop = FALSE]
  ri  <- sample(N, 800L); rf <- pop[ri, , drop = FALSE]; rf$w <- N / 800
  list(np = np, rs = reference_sample(rf, weights = "w"))
}

test_that("N-11: a second step_pseudoweight() is refused", {
  skip_on_cran()
  fx <- nps_fx()
  one <- weighting_spec(fx$np, nonprob = TRUE) |>
    step_pseudoweight(reference = fx$rs, formula = ~ x)
  expect_error(step_pseudoweight(one, reference = fx$rs, formula = ~ g),
               "already has a step_pseudoweight")
  expect_error(step_pseudoweight(one, reference = fx$rs, formula = ~ g),
               "multiplies the two participation odds")
  # the legitimate routes it names still work
  expect_s3_class(step_calibrate(one, method = "poststratify", formula = ~ g,
                                 totals = data.frame(g = c("a", "b"), Freq = c(4000, 4000)),
                                 count = "Freq"),
                  "weighting_spec")
  expect_s3_class(weighting_spec(fx$np, nonprob = TRUE) |>
                    step_pseudoweight(reference = fx$rs, formula = ~ x, by = "g"),
                  "weighting_spec")
})

test_that("N-08: a non-probability recipe that adjusts nothing says so", {
  skip_on_cran()
  fx <- nps_fx()
  f <- suppressWarnings(prep(weighting_spec(fx$np, nonprob = TRUE)))
  expect_true(all(f$final_weight == 1))
  a <- grep("leaves its weights as they came in", f$alerts, value = TRUE)
  expect_length(a, 1L)
  expect_match(a, "unweighted sample mean")
  expect_match(a, "not self-weighting")
  expect_warning(prep(weighting_spec(fx$np, nonprob = TRUE), warn = TRUE),
                 "leaves its weights as they came in")

  # it is about the weights, not about the number of steps: a recipe that adjusts is quiet
  g <- suppressWarnings(prep(weighting_spec(fx$np, nonprob = TRUE) |>
                               step_pseudoweight(reference = fx$rs, formula = ~ x),
                             warn = FALSE))
  expect_false(any(grepl("leaves its weights as they came in", g$alerts)))

  # and a probability recipe with no steps is NOT this finding: its base weights carry
  # the design, so leaving them alone is a legitimate recipe
  d <- data.frame(pw = stats::runif(200, 5, 20))
  p <- suppressWarnings(prep(weighting_spec(d, base_weights = pw)))
  expect_false(any(grepl("leaves its weights as they came in", p$alerts)))
})

test_that("N-07: as_svydesign() says the design it is building does not exist", {
  skip_on_cran()
  skip_if_not_installed("survey")
  fx <- nps_fx()
  f <- suppressWarnings(prep(weighting_spec(fx$np, nonprob = TRUE) |>
                               step_pseudoweight(reference = fx$rs, formula = ~ x),
                             warn = FALSE))
  w <- testthat::capture_warnings(d <- as_svydesign(f, ids = ~ 1))
  hit <- grep("as_svydesign\\(\\): this recipe is a non-probability sample", w, value = TRUE)
  expect_length(hit, 1L)
  expect_match(hit, "simple random sampling with replacement")
  expect_match(hit, "bootstrap_weights\\(\\) and as_svrepdesign\\(\\)")

  # it still builds: the point estimates are the pseudo-weighted ones and are fine
  expect_s3_class(d, "survey.design")
  expect_equal(as.numeric(survey::svytotal(~ x, d)),
               sum(f$final_weight * fx$np$x), tolerance = 1e-8)

  # a probability recipe is untouched
  dd <- data.frame(pw = stats::runif(200, 5, 20), x = stats::rnorm(200))
  pf <- suppressWarnings(prep(weighting_spec(dd, base_weights = pw)))
  expect_false(any(grepl("non-probability sample",
                         testthat::capture_warnings(as_svydesign(pf, ids = ~ 1)))))
})
