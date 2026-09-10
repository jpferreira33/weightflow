# The fitted response propensity must not depend on the SCALE of the design weights. The
# estimating equation sum_i w_i (y_i - mu_i) x_i = 0 is invariant to a common positive
# rescaling of w, but glm's IRLS is not: binomial()$initialize builds
#   mustart = (w * y + 0.5) / (w + 1),
# so with weights on their natural survey scale (w ~ 100) the fit starts at mu = 0.997/0.003 --
# already at the separation boundary -- and the coefficients diverge to ~1e15 with
# converged = TRUE. Every fitted probability then collapses to exactly 1 (the 1/phi adjustment
# silently becomes a no-op and the nonresponse is never compensated) or to the 1e-6 floor
# (one unit carries 1e6 times its own weight, which wrecks a replicate). (NR-PROP-01)

mk_scale <- function(n = 2000L, seed = 11L, scale = 1) {
  set.seed(seed)
  x  <- stats::rnorm(n)
  g  <- factor(sample(c("a", "b", "c"), n, TRUE))
  data.frame(x = x, g = g,
             pw   = scale * stats::runif(n, 0.5, 1.5),
             resp = stats::rbinom(n, 1, stats::plogis(0.9 + 0.6 * x + 0.4 * (g == "b"))))
}

phi <- function(df) {
  p <- weighting_spec(df, base_weights = pw) |>
    step_nonresponse(resp, method = "propensity", formula = ~ x + g, num_classes = NULL) |>
    prep()
  collect_step_detail(p)$.propensity
}

test_that("the propensity fit is invariant to the scale of the design weights", {
  p1   <- phi(mk_scale(scale = 1))
  p150 <- phi(mk_scale(scale = 150))       # a real design weight, not a toy one
  expect_equal(p1, p150, tolerance = 1e-6)
})

test_that("natural-scale design weights do not collapse the propensities to 0 or 1", {
  p <- phi(mk_scale(scale = 150))
  expect_gt(min(p), 0.05)                  # not pinned at the 1e-6 floor
  expect_lt(max(p), 0.999)                 # and not the degenerate phi == 1 (adjustment a no-op)
  expect_gt(stats::sd(p), 0.01)            # the model still discriminates
})

test_that("the adjustment restores the eligible base total at any weight scale", {
  for (s in c(1, 150)) {
    df <- mk_scale(scale = s)
    f  <- weighting_spec(df, base_weights = pw) |>
      step_nonresponse(resp, method = "propensity", formula = ~ x + g, num_classes = NULL) |>
      prep()
    # 1/phi-hat weighting is approximately unbiased for the eligible total; with phi-hat == 1
    # it would instead return only the respondents' share of it.
    expect_equal(sum(f$final_weight), sum(df$pw), tolerance = 0.03)
  }
})

test_that("replicate weights stay on the scale of the point weights", {
  skip_on_cran()
  df <- mk_scale(scale = 150)
  df$str <- rep(1:8, length.out = nrow(df))
  df$psu <- rep(1:80, length.out = nrow(df))
  sp <- weighting_spec(df, base_weights = pw) |>
    step_nonresponse(resp, method = "propensity", formula = ~ x + g, num_classes = NULL)
  b  <- bootstrap_weights(sp, replicates = 40, strata = "str", psu = "psu", progress = FALSE)
  cs <- colSums(b$replicates)
  # a diverging replicate fit shows up here as a weight sum orders of magnitude off
  expect_true(all(cs > 0.5 * sum(b$weights) & cs < 2 * sum(b$weights)))
  expect_lt(max(b$replicates), 20 * max(b$weights))
})
