# NP-08. The two extreme-propensity alerts on the pseudo-weight path were both reading the
# wrong thing.
#
# (a) The 0/1-boundary warning counted every row of the POOLED fit. Only the non-prob
#     sample's p becomes a weight -- the reference's fitted p is computed and discarded --
#     and a reference unit at p ~ 0 is the shape the fit must have when the sample is a
#     small slice of the pool. Measured on a correctly specified logit: 7 units flagged,
#     0 of them in the sample, followed by four remedies for nothing.
#
# (b) The "very small propensities" alert used the absolute p < 0.01 inherited from the
#     nonresponse path. For the participation odds the LEVEL of p is the participation
#     fraction (p estimates n(x)/(n(x)+N(x))), so with a sample 6% of the pool every p is
#     near 0.06 and (1 - p)/p ~ 15 for every unit: the correct inflation, costing nothing.
#     Over a grid of correctly specified fits (participation fraction 8% to 82%, genuine
#     heterogeneity none to strong) the old rule fired on 9 of 20 -- including fits where
#     every unit got the same factor (deff 1.00) -- and stayed silent where the factor
#     alone cost nearly half the effective sample size (deff 1.86). It fired on the level
#     and not on the dispersion, which is the opposite of what it claims to detect.

np8_pop <- function(Npop = 40000, b = 0.7, a = -5.0, seed = 7) {
  set.seed(seed)
  # a small category, as a real auxiliary has: it is what sends a few units of the POOL to
  # the 0/1 boundary, and almost all of them belong to the reference
  g <- sample(c(rep("rare", 60L), rep("a", Npop / 2),
                rep("b", Npop - Npop / 2 - 60L)))
  pop <- data.frame(x1 = stats::rnorm(Npop), g = factor(g))
  inc <- stats::runif(Npop) < stats::plogis(a + b * pop$x1)
  ri  <- sample(Npop, 5000)
  ref <- pop[ri, , drop = FALSE]; ref$w <- Npop / 5000
  list(np = pop[inc, , drop = FALSE], ref = ref)
}

np8_fit <- function(d, engine = "logit", ...) {
  sp <- weighting_spec(d$np, nonprob = TRUE) |>
    step_pseudoweight(reference = reference_sample(d$ref, weights = "w"),
                      formula = ~ x1 + g, engine = engine, ...)
  prep(sp, warn = FALSE)
}

test_that("NP-08(a): the boundary warning ignores reference units, whose p is never used", {
  skip_on_cran()
  d <- np8_pop()
  w <- testthat::capture_warnings(f <- np8_fit(d))
  expect_false(any(grepl("0/1 boundary", w)))        # it used to fire here: 7 units, 0 in the sample

  # and the units it used to count are really there, really at the boundary, and really
  # not the sample's: the warning was describing the reference
  pr <- attr(f$steps[[1L]]$diagnostics, "propensity")
  on_floor <- pr$p < 1e-4
  expect_gt(sum(on_floor), 0L)                        # the boundary units exist
  expect_equal(sum(on_floor & pr$resp), 0L)           # none of them is in the sample
})

test_that("NP-08(a): a boundary unit IN the sample still warns", {
  skip_on_cran()
  d <- np8_pop()
  # a covariate cell the reference never reaches: those sample units are separated, their
  # p goes to 1, and the odds (1 - p)/p take their weight to ~0 without dropping them
  lv <- c("a", "b", "rare", "zz")
  d$np$g  <- factor(c(rep("zz", 12L), as.character(d$np$g)[-(1:12)]), levels = lv)
  d$ref$g <- factor(as.character(d$ref$g), levels = lv)
  w <- testthat::capture_warnings(np8_fit(d))
  expect_true(any(grepl("0/1 boundary", w)))
  expect_true(any(grepl("in the non-probability sample", w)))
})

test_that("NP-08(b): the dispersion alert follows the spread, not the participation level", {
  skip_on_cran()
  fired <- function(b, a) {
    set.seed(11); Npop <- 30000
    pop <- data.frame(x1 = stats::rnorm(Npop))
    inc <- stats::runif(Npop) < stats::plogis(a + b * pop$x1)
    ri  <- sample(Npop, 4000); rf <- pop[ri, , drop = FALSE]; rf$w <- Npop / 4000
    sp <- weighting_spec(pop[inc, , drop = FALSE], nonprob = TRUE) |>
      step_pseudoweight(reference = reference_sample(rf, weights = "w"), formula = ~ x1)
    f  <- suppressWarnings(prep(sp, warn = FALSE))
    dg <- f$steps[[1L]]$diagnostics
    list(deff = attr(dg, "psw_deff"), f = attr(dg, "psw_f"), p_min = attr(dg, "p_min"),
         alert = any(grepl("dispersed enough to cost sample size", f$alerts)))
  }
  # no heterogeneity: every unit gets the same inflation, whatever the level
  flat_low  <- fired(0, -5.0)       # small sample: p ~ 0.01 by construction
  flat_high <- fired(0, -1.0)       # large sample: p ~ 0.25
  expect_lt(flat_low$deff, 1.05)
  expect_lt(flat_high$deff, 1.05)
  expect_false(flat_low$alert)      # the old rule fired here, on the level alone
  expect_false(flat_high$alert)
  expect_lt(flat_low$p_min, 0.01)   # and the quantity it fired on is still small
  expect_lt(flat_low$f, flat_high$f)

  # strong heterogeneity: a few units carry the sample, and now it speaks
  spread <- fired(1.2, -4.2)
  expect_gt(spread$deff, 1.5)
  expect_true(spread$alert)
})

test_that("NP-08(b): the alert reports the deff, the ratio and the fraction", {
  skip_on_cran()
  d  <- np8_pop(b = 1.2, a = -4.2)
  f  <- np8_fit(d)
  dg <- f$steps[[1L]]$diagnostics
  expect_true(is.finite(attr(dg, "psw_deff")))
  expect_true(is.finite(attr(dg, "psw_ratio")))
  expect_true(attr(dg, "psw_f") > 0 && attr(dg, "psw_f") < 1)
  expect_identical(attr(dg, "n_np"), nrow(d$np))

  a <- grep("dispersed enough", f$alerts, value = TRUE)
  expect_length(a, 1L)
  expect_match(a, "design effect of")
  expect_match(a, "effective sample size")
  expect_match(a, "participation fraction")
  expect_match(a, "would cost nothing")           # names the level it is NOT firing on
})

test_that("NP-08: the nonresponse path keeps the absolute threshold and its wording", {
  skip_on_cran()
  set.seed(3); n <- 1200
  d <- data.frame(pw = 10, x = stats::rnorm(n), g = factor(sample(c("a", "b"), n, TRUE)))
  # a response model that really does drive some propensities under 0.01
  d$r <- stats::runif(n) < stats::plogis(-1.2 + 2.6 * d$x)
  d$disp <- ifelse(d$r, "R", "NR")
  f <- suppressWarnings(prep(weighting_spec(d, base_weights = pw) |>
    step_nonresponse(respondent = disp == "R", method = "propensity", formula = ~ x + g),
    warn = FALSE))
  dg <- f$steps[[1L]]$diagnostics
  expect_false(isTRUE(attr(dg, "odds")))          # a raw 1/p, not the odds
  expect_null(attr(dg, "psw_deff"))               # the dispersion rule is not used here
  if (attr(dg, "p_min") < 0.01)
    expect_true(any(grepl("Very small response propensities", f$alerts)))
})
