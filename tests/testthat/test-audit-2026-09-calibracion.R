# Round-4 audit (2026-09), calibration engine. Two silent failures: a cluster split
# across domains under `by` (the one-weight-per-cluster promise breaks with no signal),
# and a model-calibration system whose model column lies in the span of `x_formula`
# (the constraint is empty, yet the diagnostics show an exact fit and converged = TRUE).

test_that("CAL9-01: a cluster spanning two domains is refused, not silently split", {
  set.seed(1); H <- 20
  hh  <- rep(seq_len(H), each = 3)
  reg <- ifelse(hh <= 10, "N", "S")
  reg[hh == 10][2:3] <- "S"          # two households straddle the border
  reg[hh == 11][1:2] <- "N"
  d <- data.frame(w0 = 10, hh = factor(hh), reg = reg,
                  sexo = factor(sample(c("F", "M"), H * 3, TRUE)))
  mk <- function(rg, kF, kM) data.frame(
    reg = rg, sexo = c("F", "M"),
    Freq = c(sum(d$reg == rg & d$sexo == "F") * kF,
             sum(d$reg == rg & d$sexo == "M") * kM))
  tot <- rbind(mk("N", 12, 18), mk("S", 30, 22))   # domains inflate very differently
  cal <- function(...) prep(weighting_spec(d, base_weights = w0) |>
    step_calibrate(method = "linear", formula = ~ sexo, totals = list(sexo = tot),
                   count = "Freq", by = "reg", ...), warn = FALSE)

  expect_error(cal(cluster = "hh", equal_within_cluster = TRUE),
               "2 of 20 cluster\\(s\\) span more than one domain: 10, 11")
  # the weights it used to return: the straddling households got two g factors
  expect_error(cal(cluster = "hh", equal_within_cluster = TRUE), "one weight per 'hh'")

  # nest the cluster inside the domain and the same recipe runs, one weight per hh
  d2 <- d; d2$reg <- ifelse(as.integer(as.character(d2$hh)) <= 10, "N", "S")
  tot2 <- rbind(mk("N", 12, 18), mk("S", 30, 22))
  p <- prep(weighting_spec(d2, base_weights = w0) |>
              step_calibrate(method = "linear", formula = ~ sexo, totals = list(sexo = tot2),
                             count = "Freq", by = "reg", cluster = "hh",
                             equal_within_cluster = TRUE), warn = FALSE)
  cw <- collect_weights(p, drop_zero = FALSE)
  spread <- tapply(cw$.weight, as.character(cw$hh), function(z) max(z) - min(z))
  expect_true(all(spread < 1e-8))

  # without `by` nothing changes: the guard is specific to the partition
  expect_error(prep(weighting_spec(d, base_weights = w0) |>
    step_calibrate(method = "linear", formula = ~ sexo,
                   totals = c("(Intercept)" = 720, sexoM = 300),
                   cluster = "hh", equal_within_cluster = TRUE), warn = FALSE), NA)
})

test_that("CAL9-01b: the same guard covers step_model_calibration(by = )", {
  set.seed(3); N <- 3000
  U <- data.frame(dep = rep(c("A", "B"), each = N / 2), x = stats::rnorm(N))
  U$y <- 1 + 2 * U$x + stats::rnorm(N)
  s <- U[sample(N, 600), ]; s$w0 <- N / 600
  s$hh <- rep(seq_len(300), each = 2)
  s$dep[s$hh == 1] <- c("A", "B")                  # one household across domains
  expect_error(prep(weighting_spec(s, base_weights = w0) |>
    step_model_calibration(population = U, x_formula = ~ x,
                           models = list(mu = y_model(y ~ x, engine = "glm",
                                                      family = "gaussian")),
                           by = "dep", cluster = "hh", equal_within_cluster = TRUE),
    warn = FALSE), "span more than one domain")
})

test_that("CAL9-02: a model prediction inside span(x_formula) is reported, not hidden", {
  set.seed(11); np <- 5000
  pop <- data.frame(x = stats::rnorm(np), z = stats::rnorm(np))
  pop$y <- 2 + 3 * pop$x + stats::rnorm(np)
  smp <- pop[sample(np, 500), ]; smp$w0 <- np / 500
  mc <- function(fo) prep(weighting_spec(smp, base_weights = w0) |>
    step_model_calibration(population = pop, x_formula = ~ x,
      models = list(mu = y_model(fo, engine = "glm", family = "gaussian"))), warn = FALSE)

  # muffle the pre-existing generic "collinear auxiliaries" warning from the solver
  no_sing <- function(e) withCallingHandlers(e, warning = function(w)
    if (grepl("Singular calibration", conditionMessage(w))) invokeRestart("muffleWarning"))
  expect_warning(no_sing(mc(y ~ x)), "degraded to a plain GREG")
  f <- suppressWarnings(mc(y ~ x))
  al <- weighting_alerts(f)
  expect_true(any(grepl("redundant model constraint\\(s\\): mu", al)))
  expect_true(any(grepl("rank 2 on 3 column", al)))
  # the point of the finding: everything else still looks perfect
  dg <- f$steps[[1]]$diagnostics
  expect_true(isTRUE(attr(dg, "converged")))
  expect_equal(dg$achieved, dg$target, tolerance = 1e-6)

  # a predictor outside x_formula keeps the system full rank: no false positive
  expect_warning(mc(y ~ x + z), NA)
  expect_length(weighting_alerts(mc(y ~ x + z)), 0L)
})

test_that("CAL9-02b: the rank warning names the domain under `by`", {
  set.seed(4); N <- 6000
  U <- data.frame(dep = sample(c("A", "B"), N, TRUE), x = stats::rnorm(N))
  U$y <- 1 + 2 * U$x + stats::rnorm(N)
  s <- U[sample(N, 1000), ]; s$w0 <- N / 1000
  f <- suppressWarnings(prep(weighting_spec(s, base_weights = w0) |>
    step_model_calibration(population = U, x_formula = ~ x,
      models = list(mu = y_model(y ~ x, engine = "glm", family = "gaussian")),
      by = "dep"), warn = FALSE))
  expect_true(any(grepl("in domain '(A|B)'", weighting_alerts(f))))
})

test_that("CAL9-03: margins that disagree cannot be mixed with a continuous total", {
  set.seed(3); m <- 400
  d <- data.frame(w0 = 3, reg = factor(sample(c("N", "S"), m, TRUE)),
                  sex = factor(sample(c("F", "M"), m, TRUE)),
                  inc = stats::rnorm(m, 100, 20))
  mr  <- data.frame(reg = c("N", "S"), Freq = c(600, 600))   # N = 1200
  ms  <- data.frame(sex = c("F", "M"), Freq = c(650, 650))   # N = 1300
  ms2 <- data.frame(sex = c("F", "M"), Freq = c(600, 600))   # N = 1200
  cal <- function(tot, fo) prep(weighting_spec(d, base_weights = w0) |>
    step_calibrate(method = "linear", formula = fo, totals = tot, count = "Freq"),
    warn = FALSE)

  # the mixed case: the continuous total used to ride through unscaled, leaving an
  # implicit mean of 92.31 where the user declared 100
  expect_error(cal(list(reg = mr, sex = ms, inc = 120000), ~ reg + sex + inc),
               "cannot be reconciled with them automatically")
  expect_error(cal(list(reg = mr, sex = ms, inc = 120000), ~ reg + sex + inc),
               "'reg' \\(x1\\.0833\\)")

  # margins that disagree WITHOUT a continuous total keep the documented behaviour
  expect_error(cal(list(reg = mr, sex = ms), ~ reg + sex), NA)
  expect_message(cal(list(reg = mr, sex = ms), ~ reg + sex), "Kept the largest")

  # margins that agree plus a continuous total: unaffected, and the declared mean holds
  p <- cal(list(reg = mr, sex = ms2, inc = 120000), ~ reg + sex + inc)
  cw <- collect_weights(p, drop_zero = FALSE)
  expect_equal(sum(cw$.weight), 1200)
  expect_equal(sum(cw$.weight * cw$inc) / sum(cw$.weight), 100, tolerance = 1e-8)
})

test_that("CAL9-04: raking reports the cell factor, as post-stratification does", {
  set.seed(6); n <- 600
  a <- sample(c("p", "q"), n, TRUE); a[1:3] <- "r"      # a cell with 3 units
  d <- data.frame(w0 = 10, a = factor(a, levels = c("p", "q", "r")),
                  b = factor(sample(c("u", "v"), n, TRUE)))
  ta <- c(p = sum(a == "p") * 10, q = sum(a == "q") * 10, r = 50000)
  tb <- c(u = sum(d$b == "u") * 10, v = sum(d$b == "v") * 10)
  tb <- tb * (sum(ta) / sum(tb))

  # classic named-vector margins
  p <- prep(weighting_spec(d, base_weights = w0) |>
              step_calibrate(method = "raking", margins = list(a = ta, b = tb)), warn = FALSE)
  dg <- p$steps[[1]]$diagnostics
  expect_true(all(c("prev_total", "factor") %in% names(dg)))
  expect_equal(dg$factor[dg$category == "r"], 50000 / 30, tolerance = 1e-6)
  expect_true(any(grepl("adjustment factor > 2.50 \\(max 1666.67\\)", weighting_alerts(p))))

  # tidy totals route: same columns, same alert
  m1 <- data.frame(a = c("p", "q", "r"), Freq = as.numeric(ta))
  m2 <- data.frame(b = c("u", "v"), Freq = as.numeric(tb))
  p2 <- prep(weighting_spec(d, base_weights = w0) |>
               step_calibrate(method = "raking", totals = list(a = m1, b = m2),
                              count = "Freq"), warn = FALSE)
  expect_true(all(c("prev_total", "factor") %in% names(p2$steps[[1]]$diagnostics)))
  expect_true(any(grepl("adjustment factor", weighting_alerts(p2))))
})

test_that("CAL9-05: an empty factor level no longer blocks nonresponse calibration", {
  set.seed(12); n <- 400
  d <- data.frame(w0 = 5,
                  grp = factor(sample(c("a", "b"), n, TRUE), levels = c("a", "b", "c")),
                  resp = stats::rbinom(n, 1, .7))
  p <- prep(weighting_spec(d, base_weights = w0) |>
              step_nonresponse(respondent = resp == 1, method = "calibration",
                               formula = ~ grp,
                               totals = c("(Intercept)" = n * 5,
                                          grpb = sum(d$grp == "b") * 5)), warn = FALSE)
  dg <- p$steps[[1]]$diagnostics
  expect_setequal(dg$variable, c("(Intercept)", "grpb"))   # no phantom grpc column
  expect_equal(dg$achieved, dg$target, tolerance = 1e-6)
})

test_that("CAL9-06: the conditioning number measures the system that is solved", {
  set.seed(2); n <- 500
  d <- data.frame(w0 = 8, income = stats::rlnorm(n, 13, .6),
                  sex = factor(sample(c("F", "M"), n, TRUE)))
  tv <- c("(Intercept)" = n * 8, income = sum(d$income) * 8 * 1.03,
          sexM = sum(d$sex == "M") * 8 * 0.97)
  cal <- function(dd, tt) prep(weighting_spec(dd, base_weights = w0) |>
    step_calibrate(method = "linear", formula = ~ income + sex, totals = tt), warn = FALSE)

  # a continuous auxiliary in natural units is NOT collinear: no alert, small kappa
  h <- cal(d, tv)
  expect_lt(attr(h$steps[[1]]$diagnostics, "calibrate")$cond, 1e4)
  expect_length(weighting_alerts(h), 0L)
  dg <- h$steps[[1]]$diagnostics
  expect_equal(dg$achieved, dg$target, tolerance = 1e-8)

  # genuine near-collinearity still fires
  set.seed(21); m <- 400
  bad <- data.frame(w0 = 5, a = stats::rlnorm(m, 15, .3))
  bad$b <- bad$a * (1 + stats::rnorm(m, 0, 1e-7))
  tb <- c("(Intercept)" = m * 5, a = sum(bad$a) * 5 * 1.01, b = sum(bad$b) * 5 * 1.01)
  hb <- suppressWarnings(prep(weighting_spec(bad, base_weights = w0) |>
    step_calibrate(method = "linear", formula = ~ a + b, totals = tb), warn = FALSE))
  expect_true(any(grepl("ill-conditioned", weighting_alerts(hb))))

  # the closed form is now scale-invariant, and `penalty` is untouched by this change
  d2 <- d; d2$income <- d2$income / 1000
  tv2 <- tv; tv2["income"] <- tv["income"] / 1000
  expect_equal(cal(d2, tv2)$final_weight, h$final_weight, tolerance = 1e-10)
  pr <- prep(weighting_spec(d, base_weights = w0) |>
    step_calibrate(method = "linear", formula = ~ income + sex, totals = tv, penalty = 1),
    warn = FALSE)
  dr <- pr$steps[[1]]$diagnostics
  expect_equal(unname(dr$achieved / dr$target), c(1.0158, 0.9927, 1.0469), tolerance = 1e-3)
})

test_that("CAL9-07: the non-convergence warning names the distance, not `bounds`", {
  set.seed(5); n <- 200
  X <- cbind("(Intercept)" = 1, x = stats::rnorm(n, 10, 2))
  Tv <- c(n * 4 * 3, sum(X[, 2]) * 4 * 8)          # needs more than one Newton step
  expect_warning(.calib_ds(X, rep(4, n), Tv, calfun = "raking", maxit = 1L),
                 "raking calibration did not fully converge")
  expect_warning(.calib_ds(X, rep(4, n), Tv, calfun = "raking", maxit = 1L),
                 "Raise `maxit`")                  # not `bounds`: none were given
  expect_warning(.calib_ds(matrix(1, nrow = 10, ncol = 1), rep(1, 10), 100,
                           calfun = "linear", bounds = c(0.5, 2), maxit = 5L),
                 "Widen `bounds`")

  # and the solver's own flag is no longer discarded for an unbounded raking solve
  set.seed(5); n <- 200
  d <- data.frame(w0 = 4, x = stats::rnorm(n, 10, 2))
  tv <- c("(Intercept)" = n * 4 * 3, x = sum(d$x) * 4 * 3)
  f <- suppressWarnings(prep(weighting_spec(d, base_weights = w0) |>
    step_calibrate(method = "linear", formula = ~ x, totals = tv,
                   calfun = "raking", maxit = 1L), warn = FALSE))
  expect_false(isTRUE(attr(f$steps[[1]]$diagnostics, "converged")))
})
