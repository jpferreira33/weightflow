# Blindaje: propiedades algebraicas del pipeline, verificadas a precision de
# maquina. Son los invariantes que el paper enuncia; si una refactorizacion
# los rompe, la teoria del paquete deja de valer.

prop_d <- function(n = 600, seed = 2) {
  set.seed(seed)
  d <- data.frame(id = 1:n,
                  x = factor(sample(c("A", "B", "C"), n, TRUE)),
                  g = factor(sample(c("u", "v"), n, TRUE)),
                  w = runif(n, 1, 3),
                  resp = rbinom(n, 1, 0.65) == 1, y = rnorm(n, 10))
  d$cell <- interaction(d$x, d$g, drop = TRUE)
  d
}

test_that("absorption identity: class-NR on cells + raking to those cells equals raking respondents directly", {
  d <- prop_d()
  marg <- setNames(as.numeric(tapply(d$w, d$cell, sum)) * 1.07, levels(d$cell))
  # brazo 1: NR por clases sobre las celdas, luego raking a las mismas celdas
  w1 <- collect_weights(suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = c("x", "g")) |>
      step_calibrate(method = "raking", margins = list(cell = marg)))),
    drop_zero = FALSE)$.weight
  # arm 2: direct raking of the respondents with their base weights
  # (los ceros deliberados disparan la warning informativa del paquete: la fijamos)
  d2 <- d; d2$w2 <- ifelse(d$resp, d$w, 0)
  expect_warning(
    p2 <- suppressMessages(prep(
      weighting_spec(d2, base_weights = w2) |>
        step_calibrate(method = "raking", margins = list(cell = marg)))),
    "base weights are 0")
  w2 <- collect_weights(p2, drop_zero = FALSE)$.weight
  expect_lt(max(abs(w1 - w2)), 1e-10)
})

test_that("NR-by-calibration (InfoS) reproduces the full-sample base-weighted totals exactly", {
  d <- prop_d()
  sp <- suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_nonresponse(respondent = resp, method = "calibration", formula = ~ x + g)))
  wnr <- collect_weights(sp, drop_zero = FALSE)$.weight
  MM  <- model.matrix(~ x + g, d)
  expect_lt(max(abs(colSums(MM * wnr) - colSums(MM * d$w))), 1e-8)
  expect_true(all(wnr[!d$resp] == 0))
})

test_that("step_round(method = 'preserve_total') keeps the weight sum exactly", {
  d <- prop_d()
  sp0 <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  antes <- sum(collect_weights(sp0)$.weight)
  sp1 <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x") |>
    step_round(digits = 0, method = "preserve_total")))
  w1 <- collect_weights(sp1)$.weight
  expect_equal(sum(w1), round(antes), tolerance = 1e-9)
  expect_true(all(w1 == floor(w1)))    # enteros
})

test_that("the full cascade is invariant to row order", {
  d <- prop_d()
  marg <- setNames(as.numeric(tapply(d$w, d$x, sum)) * 1.05, levels(d$x))
  correr <- function(dd) {
    ww <- collect_weights(suppressMessages(prep(
      weighting_spec(dd, base_weights = w) |>
        step_nonresponse(respondent = resp, method = "weighting_class", by = "g") |>
        step_calibrate(method = "raking", margins = list(x = marg)))),
      drop_zero = FALSE)$.weight
    ww[order(dd$id)]
  }
  set.seed(9); perm <- sample(nrow(d))
  expect_lt(max(abs(correr(d) - correr(d[perm, ]))), 1e-10)
})

test_that("a fully-responding sample makes the NR step a no-op (factors all 1)", {
  d <- prop_d(); d$resp <- TRUE
  w1 <- collect_weights(suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = c("x", "g")))),
    drop_zero = FALSE)$.weight
  expect_lt(max(abs(w1 - d$w)), 1e-12)
})

test_that("a sample with no respondents preps without error and zeroes every weight (with alert)", {
  d <- prop_d(); d$resp <- FALSE
  sp <- weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")
  p <- suppressMessages(suppressWarnings(prep(sp)))
  expect_true(all(collect_weights(p, drop_zero = FALSE)$.weight == 0))
})
