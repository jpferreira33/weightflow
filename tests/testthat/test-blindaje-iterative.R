# The iterative recipe-refinement workflow.
# prep() -> inspect the realized weights -> choose bounds from that
# information -> add the trim step -> prep() again, reusing the recipe.

iter_d <- function(n = 500, seed = 21) {
  set.seed(seed)
  data.frame(id = 1:n,
             x = factor(sample(c("A", "B", "C"), n, TRUE)),
             w = exp(rnorm(n, 1, 0.6)),                # pesos con cola derecha
             resp = rbinom(n, 1, 0.6) == 1, y = rnorm(n, 10))
}

test_that("adding a step to a prepped recipe downgrades it with a message (no stale results)", {
  d <- iter_d()
  rec <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  expect_s3_class(rec, "prepped_weighting_spec")
  expect_message(rec2 <- step_rescale(rec, to = "n"), "previous results cleared")
  expect_false(inherits(rec2, "prepped_weighting_spec"))   # degradado
  expect_s3_class(rec2, "weighting_spec")
  expect_error(collect_weights(rec2), "prep")              # sin resultados rancios
  expect_length(rec2$steps, 2L)                            # el paso quedo agregado
})

test_that("the full iterative workflow works: prep, choose bounds from the weights, trim, re-prep", {
  d <- iter_d()
  marg <- setNames(as.numeric(tapply(d$w, d$x, sum)) * 1.06, levels(d$x))
  # 1) initial recipe and first pass
  rec <- suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = "x") |>
      step_calibrate(method = "raking", margins = list(x = marg))))
  w1 <- collect_weights(rec)$.weight
  # 2) bounds chosen by looking at the realized distribution
  lo <- as.numeric(quantile(w1, 0.05)); up <- as.numeric(quantile(w1, 0.95))
  # 3) reuse the recipe: add the calibrated trim and re-prep
  rec2 <- suppressMessages(step_trim_calibrated(rec, formula = ~x,
                                                lower = lo, upper = up))
  rec2 <- suppressMessages(prep(rec2))
  w2 <- collect_weights(rec2)$.weight
  # 4) contracts: bounds respected and calibration totals preserved
  expect_true(all(w2 >= lo - 1e-8 & w2 <= up + 1e-8))
  tot2 <- tapply(collect_weights(rec2)$.weight, collect_weights(rec2)$x, sum)
  expect_lt(max(abs(as.numeric(tot2[names(marg)]) - marg) / marg), 1e-6)
})

test_that("re-prepping an untouched recipe reproduces the same weights (recipe reuse)", {
  d <- iter_d()
  spec <- weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")
  w1 <- collect_weights(suppressMessages(prep(spec)), drop_zero = FALSE)$.weight
  w2 <- collect_weights(suppressMessages(prep(spec)), drop_zero = FALSE)$.weight
  expect_identical(w1, w2)
})
