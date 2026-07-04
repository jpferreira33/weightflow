test_that("poststratify (tidy) with one variable equals the classic margins", {
  set.seed(1)
  n   <- 400
  dat <- data.frame(region = sample(c("N", "S", "E"), n, TRUE),
                    pw = runif(n, 1, 5))
  tot <- data.frame(region = c("N", "S", "E"), Freq = c(3000, 5000, 2000))

  w_tidy <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "poststratify", totals = tot, count = "Freq") |>
    prep() |> (\(x) x$final_weight)()

  w_classic <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "poststratify",
                   margins = list(region = c(N = 3000, S = 5000, E = 2000))) |>
    prep() |> (\(x) x$final_weight)()

  expect_equal(w_tidy, w_classic, tolerance = 1e-8)
  expect_equal(sum(w_tidy), 10000, tolerance = 1e-6)
})

test_that("poststratify (tidy) crosses several category columns automatically", {
  set.seed(2)
  n   <- 500
  dat <- data.frame(region = sample(c("N", "S"), n, TRUE),
                    sex    = sample(c("M", "F"), n, TRUE),
                    pw     = runif(n, 1, 5))
  tot <- expand.grid(region = c("N", "S"), sex = c("M", "F"))
  tot$Freq <- c(2000, 3000, 2500, 2500)   # N-M, S-M, N-F, S-F

  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "poststratify", totals = tot, count = "Freq") |>
    prep()
  w <- fitted$final_weight

  expect_equal(sum(w), sum(tot$Freq), tolerance = 1e-6)
  # each cell reproduces its target
  for (i in seq_len(nrow(tot))) {
    idx <- dat$region == tot$region[i] & dat$sex == tot$sex[i]
    expect_equal(sum(w[idx]), tot$Freq[i], tolerance = 1e-6)
  }
})

test_that("poststratify (tidy) errors when a sample cell has no population total", {
  dat <- data.frame(region = c("N", "S", "E"), pw = c(1, 1, 1))
  tot <- data.frame(region = c("N", "S"), Freq = c(10, 10))   # E missing
  expect_error(
    weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "poststratify", totals = tot, count = "Freq") |>
      prep(),
    "no population total"
  )
})

test_that("poststratify (tidy) warns when a population cell has no sample units", {
  dat <- data.frame(region = c("N", "N", "S"), pw = c(1, 1, 1))
  tot <- data.frame(region = c("N", "S", "E"), Freq = c(10, 10, 10))  # E unused
  expect_warning(
    weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "poststratify", totals = tot, count = "Freq") |>
      prep(),
    "no units in the sample"
  )
})

test_that("raking (tidy) list of margins equals the classic margins", {
  set.seed(3)
  n   <- 400
  dat <- data.frame(sex    = sample(c("M", "F"), n, TRUE),
                    region = sample(c("N", "S"), n, TRUE),
                    pw     = runif(n, 1, 5))
  m_sex    <- data.frame(sex = c("M", "F"), Freq = c(600, 400))
  m_region <- data.frame(region = c("N", "S"), Freq = c(550, 450))

  w_tidy <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "raking",
                   totals = list(m_sex, m_region), count = "Freq") |>
    prep() |> (\(x) x$final_weight)()

  w_classic <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(sex = c(M = 600, F = 400),
                                  region = c(N = 550, S = 450))) |>
    prep() |> (\(x) x$final_weight)()

  expect_equal(w_tidy, w_classic, tolerance = 1e-6)
})

test_that("raking (tidy) warns on mutually inconsistent margins", {
  set.seed(4)
  n   <- 300
  dat <- data.frame(sex    = sample(c("M", "F"), n, TRUE),
                    region = sample(c("N", "S"), n, TRUE),
                    pw     = runif(n, 1, 5))
  m_sex    <- data.frame(sex = c("M", "F"), Freq = c(600, 400))       # N = 1000
  m_region <- data.frame(region = c("N", "S"), Freq = c(550, 550))    # N = 1100
  # inconsistent margins raise the consistency warning (and, because they cannot
  # be satisfied jointly, also a non-convergence warning); check the first one.
  ws <- character(0)
  withCallingHandlers(
    weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "raking",
                     totals = list(m_sex, m_region), count = "Freq") |>
      prep(),
    warning = function(w) {
      ws <<- c(ws, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_true(any(grepl("same population size", ws)))
})

test_that("linear (tidy) equals the classic model.matrix totals vector", {
  set.seed(5)
  n   <- 300
  dat <- data.frame(region = sample(c("N", "S", "E"), n, TRUE),
                    pw = runif(n, 1, 5))
  m_region <- data.frame(region = c("N", "S", "E"), Freq = c(3000, 5000, 2000))
  # classic vector: intercept = N, drop the reference level "E" (alphabetical? no:
  # factor order is N,S,E as they appear -> reference is the first level "N")
  # build it from model.matrix to be safe
  X   <- model.matrix(~ region, data = dat)
  ref <- setdiff(unique(dat$region), sub("region", "", grep("region", colnames(X), value = TRUE)))
  totvec <- c("(Intercept)" = 10000)
  for (cl in grep("region", colnames(X), value = TRUE)) {
    lev <- sub("region", "", cl)
    totvec[cl] <- m_region$Freq[m_region$region == lev]
  }

  w_tidy <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ region,
                   totals = list(region = m_region), count = "Freq") |>
    prep() |> (\(x) x$final_weight)()

  w_classic <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ region, totals = totvec) |>
    prep() |> (\(x) x$final_weight)()

  expect_equal(w_tidy, w_classic, tolerance = 1e-6)
})

test_that("linear (tidy) reproduces mixed categorical + continuous totals", {
  set.seed(6)
  n   <- 300
  dat <- data.frame(region = sample(c("N", "S"), n, TRUE),
                    x  = rnorm(n, 10, 3),
                    pw = runif(n, 1, 5))
  m_region <- data.frame(region = c("N", "S"), Freq = c(6000, 4000))
  x_total  <- 10000 * 10   # arbitrary population total for x

  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ region + x,
                   totals = list(region = m_region, x = x_total),
                   count = "Freq") |>
    prep()
  w <- fitted$final_weight

  expect_equal(sum(w), 10000, tolerance = 1e-4)                 # intercept = N
  expect_equal(sum(w[dat$region == "S"]), 4000, tolerance = 1e-4)
  expect_equal(sum(w * dat$x), x_total, tolerance = 1e-4)
})

test_that("linear (tidy) works with ridge and matches the classic vector", {
  set.seed(7)
  n   <- 300
  dat <- data.frame(region = sample(c("N", "S"), n, TRUE),
                    pw = runif(n, 1, 5))
  m_region <- data.frame(region = c("N", "S"), Freq = c(6000, 4000))
  totvec   <- c("(Intercept)" = 10000, regionS = 4000)

  w_tidy <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ region,
                   totals = list(region = m_region), count = "Freq",
                   penalty = 1) |>
    prep() |> (\(x) x$final_weight)()

  w_classic <- weighting_spec(dat, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ region,
                   totals = totvec, penalty = 1) |>
    prep() |> (\(x) x$final_weight)()

  expect_equal(w_tidy, w_classic, tolerance = 1e-6)
})

test_that("linear (tidy) errors on a calibration variable with NA", {
  set.seed(8)
  n   <- 100
  dat <- data.frame(region = sample(c("N", "S"), n, TRUE),
                    x  = c(NA, rnorm(n - 1, 10, 3)),
                    pw = runif(n, 1, 5))
  m_region <- data.frame(region = c("N", "S"), Freq = c(6000, 4000))
  expect_error(
    weighting_spec(dat, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ region + x,
                     totals = list(region = m_region, x = 100000),
                     count = "Freq") |>
      prep(),
    "missing values"
  )
})
