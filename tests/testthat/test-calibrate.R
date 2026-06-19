test_that("linear/GREG calibration hits the population totals", {
  set.seed(1)
  n   <- 200
  dat <- data.frame(x = rnorm(n, 10, 3), pw = runif(n, 1, 5))
  # targets moderately above the design totals (keeps g positive)
  totals <- c("(Intercept)" = sum(dat$pw) * 1.15,
              x             = sum(dat$pw * dat$x) * 1.15)
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ x, totals = totals) |>
    prep()
  w <- fitted$final_weight
  expect_equal(sum(w),         unname(totals[1]), tolerance = 1e-4)
  expect_equal(sum(w * dat$x), unname(totals[2]), tolerance = 1e-4)
})

test_that("bounded (logit) calibration keeps the g-weights inside the bounds", {
  set.seed(11)
  n   <- 300
  dat <- data.frame(x = rnorm(n, 10, 3), pw = runif(n, 1, 5))
  totals <- c("(Intercept)" = sum(dat$pw) * 1.10,
              x             = sum(dat$pw * dat$x) * 1.10)
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ x, totals = totals,
                   calfun = "logit", bounds = c(0.5, 2)) |>
    prep()
  g <- fitted$final_weight / fitted$history[["base"]]   # only one step => g
  expect_true(all(g >= 0.5 - 1e-6 & g <= 2 + 1e-6))
})

test_that("raking matches the requested margins", {
  set.seed(4)
  n   <- 400
  dat <- data.frame(sex = sample(c("M", "F"), n, TRUE), pw = runif(n, 1, 5))
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(sex = c(M = 600, F = 400))) |>
    prep()
  w <- fitted$final_weight
  expect_equal(sum(w[dat$sex == "M"]), 600, tolerance = 1e-4)
  expect_equal(sum(w[dat$sex == "F"]), 400, tolerance = 1e-4)
})

test_that("equal_within_cluster yields a single weight per household", {
  set.seed(2)
  nh  <- 50
  dat <- data.frame(
    hid = factor(rep(seq_len(nh), each = 3)),       # 3 members each
    x   = rnorm(150, 5),
    pw  = rep(runif(nh, 1, 4), each = 3)            # uniform within household
  )
  totals <- c("(Intercept)" = sum(dat$pw) * 1.1,
              x             = sum(dat$pw * dat$x) * 1.1)
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ x, totals = totals,
                   cluster = "hid", equal_within_cluster = TRUE) |>
    prep()
  w      <- fitted$final_weight
  spread <- tapply(w, dat$hid, function(z) max(z) - min(z))
  expect_true(all(spread < 1e-8))                   # identical within household
})
