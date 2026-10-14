# N-02. step_pseudoweight() treats the reference as fixed when it carries no replicate
# weights, which is an assumption about the REFERENCE rather than a property of the
# bootstrap -- and a strong one here, because the reference is not just a source of totals:
# every reference unit is a row of the pooled participation fit. Measured against a Monte
# Carlo oracle, a nominal 95% interval covered 76% with a reference of 500 and 88% with
# one of 3,000, against 94% with the reference's own replicates paired in. The recipe
# cannot build those replicates (it would need the reference's strata, PSUs, fpc and
# control totals), so they stay an input and the variance functions name the assumption
# instead of inventing one. The jackknife is a separate case: it never re-estimates the
# reference, so passing `replicates` does not help it.

n02_fx <- function(nref = 1500L, R = 20L, seed = 5) {
  set.seed(seed); Npop <- 20000L
  pop <- data.frame(x1 = stats::rnorm(Npop))
  inc <- stats::runif(Npop) < stats::plogis(-3.6 + 0.6 * pop$x1)
  ri  <- sample(Npop, nref)
  rf  <- pop[ri, , drop = FALSE]; rf$w <- Npop / nref
  reps <- matrix(rf$w, nrow = nref, ncol = R) *
    matrix(stats::rexp(nref * R), nrow = nref)       # stand-in for a published replicate file
  list(np = pop[inc, , drop = FALSE], rf = rf, reps = reps)
}

n02_spec <- function(fx, replicates = NULL)
  weighting_spec(fx$np, nonprob = TRUE) |>
    step_pseudoweight(reference = reference_sample(fx$rf, weights = "w",
                                                   replicates = replicates),
                      formula = ~ x1)

test_that("N-02: prep() says which assumption a variance would rest on", {
  skip_on_cran()
  fx <- n02_fx()
  f  <- suppressWarnings(prep(n02_spec(fx), warn = FALSE))
  a  <- grep("reference sample carries no replicate weights", f$alerts, value = TRUE)
  expect_length(a, 1L)
  expect_match(a, "treat the reference as the POPULATION")
  expect_match(a, "frame or a census, that is correct")
  expect_match(a, "standard errors will be underestimated")
  expect_match(a, "reference_sample\\(replicates =\\)")

  # the weights themselves are the same either way: this is a note, not a defect
  g <- suppressWarnings(prep(n02_spec(fx, fx$reps), warn = FALSE))
  expect_equal(f$final_weight, g$final_weight, tolerance = 1e-12)
  expect_false(any(grepl("reference sample carries", g$alerts)))
})

test_that("N-02: bootstrap_weights() names the assumption, and is quiet once it is met", {
  skip_on_cran()
  fx <- n02_fx()
  w <- testthat::capture_warnings(
    bootstrap_weights(n02_spec(fx), replicates = 4L, progress = FALSE))
  hit <- grep("bootstrap_weights\\(\\): step_pseudoweight", w, value = TRUE)
  expect_length(hit, 1L)
  expect_match(hit, "treat the reference as the population")
  expect_match(hit, "correct for a frame or a census")
  expect_match(hit, "standard errors are underestimated")
  expect_match(hit, "replicates = R")

  w2 <- testthat::capture_warnings(
    bootstrap_weights(n02_spec(fx, fx$reps), replicates = 4L, progress = FALSE))
  expect_false(any(grepl("no replicate weights", w2)))
})

test_that("N-02: the jackknife warns even WITH reference replicates", {
  skip_on_cran()
  fx <- n02_fx()
  for (reps in list(NULL, fx$reps)) {
    w <- testthat::capture_warnings(
      jackknife_weights(n02_spec(fx, reps), groups = 10L, seed = 1L, progress = FALSE))
    hit <- grep("jackknife_weights\\(\\): this recipe has a step_pseudoweight", w, value = TRUE)
    expect_length(hit, 1L)
    expect_match(hit, "even when `replicates` is supplied")
    expect_match(hit, "missing rather than approximated")
    expect_match(hit, "use bootstrap_weights\\(\\)")
  }
})

test_that("N-02: a recipe with no pseudo-weighting step is untouched", {
  skip_on_cran()
  set.seed(2); n <- 400
  d <- data.frame(pw = stats::runif(n, 5, 20), y = stats::rnorm(n),
                  str = rep(1:4, length.out = n), psu = rep(1:40, each = 10))
  sp <- weighting_spec(d, base_weights = pw)
  expect_false(any(grepl("reference as the population",
    testthat::capture_warnings(bootstrap_weights(sp, replicates = 4L, strata = "str",
                                                 psu = "psu", progress = FALSE)))))
  expect_false(any(grepl("step_pseudoweight",
    testthat::capture_warnings(jackknife_weights(sp, strata = "str", psu = "psu",
                                                 progress = FALSE)))))
})

test_that("N-02: the reference replicates are what moves the SE, and they widen it", {
  skip_on_cran()
  fx <- n02_fx()
  se <- function(reps) {
    b <- suppressWarnings(bootstrap_weights(n02_spec(fx, reps), replicates = 60L,
                                            seed = 7L, progress = FALSE))
    suppressWarnings(boot_mean(b, "x1")$se)
  }
  s_fixed <- se(NULL); s_full <- se(fx$reps)
  expect_true(is.finite(s_fixed) && is.finite(s_full))
  # holding the reference fixed drops a component, so it can only be the smaller of the two
  expect_lt(s_fixed, s_full)
})
