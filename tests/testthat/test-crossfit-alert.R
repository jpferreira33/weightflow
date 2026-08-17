# A flexible learner (tree / forest / boost) without cross-fitting can understate
# the design-based variance even under recipe-aware replication (same-sample
# predictions keep each unit in its own training set). prep() raises a quality
# alert; cross-fitting or a glm engine does not.

test_that("a flexible propensity learner without cross-fitting raises a variance alert", {
  skip_if_not_installed("ranger")
  set.seed(1); n <- 300L
  d <- data.frame(pw = runif(n, 1, 2), x = rnorm(n), resp = rbinom(n, 1, 0.7))
  f <- function(...) suppressMessages(prep(weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "propensity", formula = ~ x,
                     num_classes = NULL, ...)))$alerts

  expect_true(any(grepl("cross-fitting", f(engine = "forest"))))            # flexible, no CF
  # CF (with a seed) clears the variance alert and, being seeded, the
  # reproducibility alert too -- no cross-fitting mention of either kind.
  expect_false(any(grepl("cross-fitting", f(engine = "forest", crossfit = 5, crossfit_seed = 1))))
  expect_false(any(grepl("cross-fitting", f(engine = "logit"))))            # glm never triggers
  # R5-FIX6: cross-fitting WITHOUT a seed is not reproducible -> its own alert.
  expect_true(any(grepl("reproducible", f(engine = "forest", crossfit = 5))))
})
