# Quality alerts computed by prep(): negative / sub-1 weights, g-factors outside
# the Deville-Sarndal bounds, small adjustment cells and excessive adjustment
# factors. Alerts are always stored on $alerts (and per step); prep(warn = TRUE)
# also raises them as warnings.

test_that("calibration negative-weight and g-bound alerts fire and land in $alerts", {
  # one outlier plus a low x-total forces the outlier's g (and weight) negative
  dat    <- data.frame(x = c(rep(2, 19), 40), pw = rep(1, 20))
  totals <- c("(Intercept)" = 20, x = 30)
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ x, totals = totals) |>
    prep()
  w <- fitted$final_weight
  expect_true(any(w < 0))                                    # construction sanity
  expect_true(any(grepl("negative weight", fitted$alerts)))
  expect_true(any(grepl("Deville-Sarndal bounds", fitted$alerts)))
  expect_true(any(grepl("negative weight", fitted$steps[[1]]$alerts)))  # stored per step
})

test_that("sub-1 weight alert fires under raking", {
  dat    <- data.frame(sex = rep("F", 100), pw = rep(1, 100))
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(sex = c(F = 50))) |>
    prep()
  expect_true(all(abs(fitted$final_weight - 0.5) < 1e-6))    # each weight = 0.5
  expect_true(any(grepl("below 1", fitted$alerts)))
})

test_that("excessive adjustment-factor alert fires for a large but low-response cell", {
  # 200 units, 60 respondents -> factor 200/60 = 3.33 (> 2.5); cell not small (>= 30)
  dat <- data.frame(region  = rep("A", 200),
                    resp    = c(rep(TRUE, 60), rep(FALSE, 140)),
                    pw      = rep(1, 200))
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "region") |>
    prep()
  expect_true(any(grepl("adjustment factor", fitted$alerts)))
  expect_false(any(grepl("fewer than", fitted$alerts)))
})

test_that("small-cell alert fires for a fully responding small cell", {
  dat <- data.frame(region = rep("A", 10), resp = rep(TRUE, 10), pw = rep(1, 10))
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "region") |>
    prep()
  expect_true(any(grepl("fewer than 30", fitted$alerts)))
  expect_false(any(grepl("adjustment factor", fitted$alerts)))  # factor = 1
})

test_that("warn = TRUE raises the alerts; the default prep() is silent about them", {
  dat  <- data.frame(region = rep("A", 10), resp = rep(TRUE, 10), pw = rep(1, 10))
  spec <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "region")
  expect_warning(prep(spec, warn = TRUE), "fewer than 30")
  expect_warning(prep(spec), NA)          # default: no warning emitted
})

test_that("min_cell_n = NULL and max_factor = NULL disable the cell alerts", {
  dat  <- data.frame(region = rep("A", 10), resp = rep(TRUE, 10), pw = rep(1, 10))
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "region") |>
    prep(min_cell_n = NULL, max_factor = NULL)
  expect_length(fitted$alerts, 0)
})

test_that("step_rescale does not raise cell alerts (it is not a cell step)", {
  set.seed(6)
  dat    <- data.frame(pw = runif(120, 1, 9))
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_rescale(to = "total", total = 1e6) |>
    prep()
  expect_false(any(grepl("adjustment factor", fitted$alerts)))
})
