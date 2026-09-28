# EST-04. The estimation DSL used to protect only half of its verbs: mean(), total()
# and quantile() went through .estimand_value(), while prop() and ratio() kept the raw
# eval() that .estimand_value() was written to replace. Each test below is a number the
# DSL used to publish with a standard error and a confidence interval.

mk3 <- function(seed, npsu = 24, per = 6) {
  set.seed(seed)
  n <- npsu * per
  d <- data.frame(
    psu    = rep(seq_len(npsu), each = per),
    str    = rep(rep(1:3, length.out = npsu), each = per),
    region = rep(rep(c("N", "S"), length.out = npsu), each = per),
    type   = rep(rep(c("A", "B"), length.out = npsu), each = per),
    y      = rnorm(n, 10, 3),
    emp    = rbinom(n, 1, 0.6),
    pw     = 1)
  d$fct <- factor(sample(c("a", "b", "c"), n, TRUE))
  d$num <- rlnorm(n, 3, 0.5)
  d$den <- rlnorm(n, 4, 0.5)
  d$num[seq_len(30)] <- NA          # missing in the NUMERATOR only
  d
}
wb3 <- function(R = 40)
  wave_bootstrap(list(T1 = weighting_spec(mk3(11), base_weights = pw),
                      T2 = weighting_spec(mk3(12), base_weights = pw)),
                 replicates = R, strata = "str", psu = "psu", seed = 3, progress = FALSE)

test_that("ratio() refuses an estimand that is not one value per unit", {
  wb <- wb3()
  # ratio(1, 2) used to return 0.5 with se 0 and a CI of [0.5, 0.5].
  expect_warning(
    expect_error(collect_estimates(wb |> step_estimate(ratio(1, 2), over = "level")),
                 "every estimate failed"),
    "one value per unit")
})

test_that("prop() on a factor is refused, not averaged over the integer codes", {
  wb <- wb3()
  # prop(fct) used to average the codes 1/2/3 and report a "proportion" near 1.8.
  expect_warning(
    expect_error(collect_estimates(wb |> step_estimate(prop(fct), over = "level")),
                 "every estimate failed"),
    "prop\\(\\) takes a condition")
  # the correct spelling still works and is a proportion
  ok <- collect_estimates(wb |> step_estimate(prop(fct == "a"), over = "level"))
  expect_true(ok$table$estimate > 0 && ok$table$estimate < 1)
})

test_that("ratio() uses the common domain, matching svyratio(na.rm = TRUE)", {
  skip_if_not_installed("survey")
  wb <- wb3()
  got <- collect_estimates(
    wb |> step_estimate(ratio(num, den), over = "level", waves = "T1"))$table$estimate
  d1  <- mk3(11)
  des <- survey::svydesign(~psu, strata = ~str, weights = ~pw, data = d1, nest = TRUE)
  ref <- as.numeric(stats::coef(survey::svyratio(~num, ~den, des, na.rm = TRUE)))
  expect_equal(got, ref, tolerance = 1e-12)
  # and it is NOT the old per-sum na.rm, which summed two different domains
  ok  <- !is.na(d1$num) & !is.na(d1$den)
  old <- sum(d1$pw * d1$num, na.rm = TRUE) / sum(d1$pw * d1$den, na.rm = TRUE)
  expect_false(isTRUE(all.equal(got, old, tolerance = 1e-6)))
  expect_equal(got, sum(d1$pw[ok] * d1$num[ok]) / sum(d1$pw[ok] * d1$den[ok]),
               tolerance = 1e-12)
})

test_that("quantile(var, p) requires p in [0, 1]", {
  wb <- wb3()
  # .wf_wtd_quantile() saturates (approx rule = 2), so p = 150 used to return the
  # maximum -- with a bootstrap SE on it.
  expect_error(collect_estimates(wb |> step_estimate(quantile(y, 150), over = "level")),
               "probability in \\[0, 1\\]")
  expect_error(collect_estimates(wb |> step_estimate(quantile(y, -3), over = "level")),
               "probability in \\[0, 1\\]")
  expect_error(collect_estimates(wb |> step_estimate(quantile(y, c(.25, .75)), over = "level")),
               "single probability")
  q <- collect_estimates(wb |> step_estimate(quantile(y, 0.5), over = "level"))
  expect_true(is.finite(q$table$estimate))
})

test_that("step_estimate() validates `level`", {
  wb <- wb3()
  expect_error(step_estimate(wb, mean(y), over = "level", level = 95), "not 95")
  expect_error(step_estimate(wb, mean(y), over = "level", level = -1), "between 0 and 1")
  r <- collect_estimates(wb |> step_estimate(mean(y), over = "level", level = 0.9))
  expect_true(is.finite(r$table$ci_lower) && is.finite(r$table$ci_upper))
})

test_that("a domain may not shadow a result column", {
  wb <- wb3()
  # the table is cbind(estimand/over/type, <domains>, estimate/se/ci_*/rho); a domain
  # called `type` produced two columns of that name and `$` took the first.
  expect_error(step_domain(wb, type), "cannot be used as a domain")
  r <- collect_estimates(wb |> step_domain(region) |> step_estimate(mean(y), over = "level"))
  expect_equal(sum(names(r$table) == "estimate"), 1L)
  expect_true(is.numeric(r$table$estimate))
  expect_setequal(r$table$region, c("N", "S"))
})

test_that("the weighted quantile is type 5 with unit weights, as documented", {
  x <- sort(stats::rnorm(101)); u <- rep(1, 101); p <- seq(0.05, 0.95, by = 0.05)
  expect_equal(.wf_wtd_quantile(x, u, p), as.numeric(stats::quantile(x, p, type = 5)),
               tolerance = 1e-12)
})
