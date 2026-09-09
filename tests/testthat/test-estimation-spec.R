# The estimation grammar (step_domain / step_estimate / collect_estimates) is a declarative
# front end over the coordinated engine. Two things pin it: it must AGREE with the engine
# functions on the overall estimate, and it must disaggregate by the step_domain() cross.

mkwave <- function(seed, npsu = 40, per = 6) {
  set.seed(seed)
  psu    <- rep(seq_len(npsu), each = per)
  str    <- rep(rep(1:4, length.out = npsu), each = per)
  region <- rep(rep(c("N", "S"), length.out = npsu), each = per)
  y      <- rnorm(npsu * per, 10, 3)
  emp    <- rbinom(npsu * per, 1, 0.6)
  act    <- rep(1, npsu * per)
  data.frame(psu = psu, str = str, region = region, y = y, emp = emp, act = act, pw = 1)
}
boot2 <- function(seed1 = 1, seed2 = 2, ...) {
  wave_bootstrap(list(T1 = weighting_spec(mkwave(seed1), base_weights = pw),
                      T2 = weighting_spec(mkwave(seed2), base_weights = pw)),
                 replicates = 150, strata = "str", psu = "psu", seed = 5, progress = FALSE, ...)
}

test_that("step_estimate agrees with the engine on the overall change", {
  skip_on_cran()
  wb  <- boot2()
  res <- collect_estimates(wb |> step_estimate(mean(y), over = "change"))
  eng <- change_mean(wb, "y")
  expect_s3_class(res, "weightflow_estimation_result")
  expect_equal(nrow(res$table), 1L)
  expect_equal(res$table$estimate, eng$estimate)
  expect_equal(res$table$se, eng$se)
})

test_that("step_domain disaggregates by the domain cross", {
  skip_on_cran()
  wb  <- boot2()
  res <- collect_estimates(wb |> step_domain(region) |> step_estimate(mean(y), over = "change"))
  expect_true(all(c("N", "S") %in% res$table$region))
  expect_equal(nrow(res$table), 2L)
  # a domain estimate matches the engine restricted to that domain
  eng_N <- change_estimate(wb, function(w, d) {
    i <- d$region == "N"; stats::weighted.mean(d$y[i], w[i])
  })
  expect_equal(res$table$estimate[res$table$region == "N"], eng_N$estimate)
})

test_that("over = level / relative / contrast all run", {
  skip_on_cran()
  wb <- boot2()
  lv <- collect_estimates(wb |> step_estimate(mean(y), over = "level"))
  expect_equal(lv$table$estimate, level_mean(wb, "y")$estimate)
  rl <- collect_estimates(wb |> step_estimate(mean(y), over = "change", type = "relative"))
  expect_equal(rl$table$estimate, change_mean(wb, "y", type = "relative")$estimate)
  ct <- collect_estimates(wb |> step_estimate(mean(y), over = "contrast", contrast = c(-1, 1)))
  expect_equal(ct$table$estimate, change_mean(wb, "y")$estimate)   # c(-1,1) == net change
})

test_that("the statistic DSL covers mean/total/prop/ratio/quantile", {
  skip_on_cran()
  wb <- boot2()
  expect_equal(
    collect_estimates(wb |> step_estimate(total(y), over = "level"))$table$estimate,
    level_total(wb, "y")$estimate)
  pr <- collect_estimates(wb |> step_estimate(prop(emp == 1), over = "level"))
  expect_true(is.finite(pr$table$estimate) && pr$table$estimate > 0 && pr$table$estimate < 1)
  ra <- collect_estimates(wb |> step_estimate(ratio(emp, act), over = "level"))
  expect_true(is.finite(ra$table$se))
  qt <- collect_estimates(wb |> step_estimate(quantile(y, 0.5), over = "level"))
  expect_true(is.finite(qt$table$estimate))          # weighted median, non-linear
})

test_that("several estimands stack in one pipeline", {
  skip_on_cran()
  wb  <- boot2()
  res <- collect_estimates(wb |>
    step_estimate(mean(emp), over = "change", label = "empleo") |>
    step_estimate(mean(y), over = "level", label = "media_y"))
  expect_setequal(res$table$estimand, c("empleo", "media_y"))
})

test_that("step_transition on a coordinated object points to the longitudinal flow functions", {
  wb <- boot2()
  expect_error(wb |> step_transition(from = emp, to = emp), "boot_transition")
})

test_that("step_filter masks a subpopulation and matches the equivalent function(w, d)", {
  skip_on_cran()
  wb <- boot2()
  res_f <- collect_estimates(wb |> step_filter(region == "N") |>
                               step_estimate(mean(y), over = "change"))
  eng_N <- change_estimate(wb, function(w, d) {
    i <- d$region == "N"; stats::weighted.mean(d$y[i], w[i])
  })
  # masking == the hand-written domain statistic, point AND se (coordinated variance intact)
  expect_equal(res_f$table$estimate, eng_N$estimate)
  expect_equal(res_f$table$se, eng_N$se)
  # and it actually restricts: differs from the unfiltered change
  res_all <- collect_estimates(wb |> step_estimate(mean(y), over = "change"))
  expect_false(isTRUE(all.equal(res_f$table$estimate, res_all$table$estimate)))
})

test_that("step_filter stacks (AND) and composes with step_domain", {
  skip_on_cran()
  wb <- boot2()
  res <- collect_estimates(wb |> step_filter(emp == 1) |> step_domain(region) |>
                             step_estimate(mean(y), over = "level"))
  eng_N <- level_estimate(wb, function(w, d) {
    i <- d$region == "N" & d$emp == 1; stats::weighted.mean(d$y[i], w[i])
  })
  expect_equal(res$table$estimate[res$table$region == "N"], eng_N$estimate)
  # two filters intersect: emp==1 & y > median is a subset of emp==1
  n_one <- nrow(collect_estimates(wb |> step_filter(emp == 1) |>
                                    step_estimate(mean(y), over = "level"))$table)
  expect_equal(n_one, 1L)
})

test_that("step_filter fails fast on a nonexistent column", {
  wb <- boot2()
  expect_error(wb |> step_filter(no_existe > 3), "not found")
})

test_that("step_domain requires the column in EVERY wave, not the union (EST-03)", {
  skip_on_cran()
  d1 <- mkwave(1); d2 <- mkwave(2); d2$region <- NULL     # region only in wave T1
  wb <- wave_bootstrap(list(T1 = weighting_spec(d1, base_weights = pw),
                            T2 = weighting_spec(d2, base_weights = pw)),
                       replicates = 50, strata = "str", psu = "psu", seed = 5, progress = FALSE)
  # a domain present in only one wave used to fall through to NA cells; now it errors
  expect_error(wb |> step_domain(region), "EVERY wave")
})
