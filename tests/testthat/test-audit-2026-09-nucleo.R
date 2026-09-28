# Round-4 audit (2026-09), core/DSL. N3: a recipe is an ordered list and some steps undo
# what an earlier one did, but each step's diagnostics only ever describe the moment that
# step ran. A calibration that met its totals exactly still printed target == achieved
# after a later step had thrown those totals away, with no alert anywhere.

test_that("N3: a step that discards an earlier calibration's totals is reported", {
  set.seed(1); n <- 400
  d <- data.frame(w0 = 3, reg = factor(sample(c("N", "S"), n, TRUE)))
  tot <- c("(Intercept)" = 1570, regS = 800)
  cal <- function(sp) step_calibrate(sp, method = "linear", formula = ~ reg, totals = tot)

  # the recipe as intended: nothing to report
  ok <- prep(cal(weighting_spec(d, base_weights = w0)), warn = FALSE)
  expect_length(weighting_alerts(ok), 0L)
  expect_equal(sum(collect_weights(ok, drop_zero = FALSE)$.weight), 1570)

  # the same recipe with a rescale after it
  bad <- prep(cal(weighting_spec(d, base_weights = w0)) |> step_rescale(), warn = FALSE)
  al  <- weighting_alerts(bad)
  expect_true(any(grepl("calibrated the weights to a population of 1,570", al)))
  expect_true(any(grepl("FINAL weights sum to 400", al)))
  expect_true(any(grepl("step_rescale", al)))         # names the step that broke it
  expect_true(any(grepl("-74\\.5%", al)))             # and the size of the damage

  # the point of the finding: the calibration's own table still reads clean
  dg <- bad$steps[[1]]$diagnostics
  expect_equal(dg$achieved, dg$target, tolerance = 1e-6)
  expect_true(isTRUE(attr(dg, "converged")))

  # with warn = TRUE it also surfaces as a warning
  expect_warning(prep(cal(weighting_spec(d, base_weights = w0)) |> step_rescale(), warn = TRUE),
                 "did not preserve the totals it fixed")
})

test_that("N3: steps that legitimately preserve the total stay silent", {
  set.seed(2); n <- 500
  d <- data.frame(w0 = 4, g = factor(sample(c("a", "b"), n, TRUE)))
  tot <- c("(Intercept)" = 2600, gb = 1300)
  cal <- function(sp) step_calibrate(sp, method = "linear", formula = ~ g, totals = tot)

  keep <- prep(cal(weighting_spec(d, base_weights = w0)) |>
                 step_round(method = "preserve_total", digits = 0), warn = FALSE)
  expect_equal(sum(collect_weights(keep, drop_zero = FALSE)$.weight), 2600)
  expect_false(any(grepl("did not preserve the totals", weighting_alerts(keep))))

  # a calibration in last position has nothing after it to check
  last <- prep(weighting_spec(d, base_weights = w0) |> step_rescale() |> cal(), warn = FALSE)
  expect_false(any(grepl("did not preserve the totals", weighting_alerts(last))))
})

test_that("N3: the check covers raking and post-stratification too", {
  set.seed(3); n <- 600
  d <- data.frame(w0 = 5, a = factor(sample(c("p", "q"), n, TRUE)),
                  b = factor(sample(c("u", "v"), n, TRUE)))
  ta <- c(p = 1500, q = 1500); tb <- c(u = 1400, v = 1600)
  for (m in c("raking", "poststratify")) {
    mar <- if (m == "raking") list(a = ta, b = tb) else list(a = ta)
    f <- prep(weighting_spec(d, base_weights = w0) |>
                step_calibrate(method = m, margins = mar) |> step_rescale(), warn = FALSE)
    expect_true(any(grepl("population of 3,000", weighting_alerts(f))),
                info = paste("method =", m))
  }
})
