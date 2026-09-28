# step_cre(): composite regression estimator (LFS ch.6 / ECH sec.8.4)

# Build a wave from panel_ine: respondents only, with a 3-level labour status.
cre_wave <- function(t) {
  d <- subset(panel_ine, wave == t & disposition == "R")
  d$lf_status <- ifelse(is.na(d$employed), "inact",
                 ifelse(d$employed == 1L, "emp",
                 ifelse(d$unemployed == 1L, "unemp", "inact")))
  d
}
# design-weighted model.matrix totals for a formula on a wave (so calibration is feasible)
cre_totals <- function(d, formula) {
  X <- stats::model.matrix(formula, data = d)
  colSums(d$pw * X)
}

test_that("seed wave (previous = NULL) equals an ordinary linear calibration", {
  d  <- cre_wave(1)
  f  <- ~ sex
  tt <- cre_totals(d, f)

  fit_cre <- weighting_spec(d, base_weights = pw) |>
    step_cre(previous = NULL, status = lf_status, formula = f, totals = tt) |>
    prep()
  fit_cal <- weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "linear", formula = f, totals = tt) |>
    prep()

  expect_equal(unname(fit_cre$final_weight), unname(fit_cal$final_weight), tolerance = 1e-8)
})

test_that("composite wave reproduces BOTH the demographic totals X and the composite totals Zhat", {
  d1 <- cre_wave(1); d2 <- cre_wave(2)
  f  <- ~ sex
  fit1 <- weighting_spec(d1, base_weights = pw) |>
    step_cre(previous = NULL, status = lf_status, formula = f, totals = cre_totals(d1, f)) |>
    prep()

  fit2 <- weighting_spec(d2, base_weights = pw) |>
    step_cre(previous = fit1, rescale_previous = TRUE, status = lf_status,
             composite = list(NULL, "sex"),
             id_unit = c("household_id", "person_no"),
             formula = f, totals = cre_totals(d2, f)) |>
    prep()

  diag <- fit2$steps[[1]]$diagnostics
  # every constraint (x block AND z block) is met
  expect_true(isTRUE(attr(diag, "converged")))
  expect_equal(diag$achieved, diag$target, tolerance = 1e-4)
  # there are composite (z) columns, and Zhat matches the previous-wave weighted totals
  expect_true(any(diag$block == "z"))
  expect_gt(sum(diag$block == "z"), 0L)
})

test_that("alpha = 0 (MR1/level) and alpha = 1 (MR2/change) both run and satisfy the constraints", {
  d1 <- cre_wave(1); d2 <- cre_wave(2)
  f  <- ~ sex
  fit1 <- weighting_spec(d1, base_weights = pw) |>
    step_cre(previous = NULL, status = lf_status, formula = f, totals = cre_totals(d1, f)) |>
    prep()
  mk <- function(a) weighting_spec(d2, base_weights = pw) |>
    step_cre(previous = fit1, rescale_previous = TRUE, status = lf_status, composite = list(NULL),
             id_unit = c("household_id", "person_no"), formula = f, totals = cre_totals(d2, f),
             alpha = a) |>
    prep()
  for (a in c(0, 1)) {
    fit <- mk(a)
    expect_true(isTRUE(attr(fit$steps[[1]]$diagnostics, "converged")))
    expect_true(all(is.finite(fit$final_weight)))
  }
})

test_that("integrated method: equal_within_cluster gives one weight per household", {
  d1 <- cre_wave(1); d2 <- cre_wave(2)
  f  <- ~ sex
  fit1 <- weighting_spec(d1, base_weights = pw) |>
    step_cre(previous = NULL, status = lf_status, formula = f, totals = cre_totals(d1, f),
             cluster = "household_id", equal_within_cluster = TRUE) |>
    prep()
  fit2 <- weighting_spec(d2, base_weights = pw) |>
    step_cre(previous = fit1, rescale_previous = TRUE, status = lf_status, composite = list(NULL, "sex"),
             id_unit = c("household_id", "person_no"), formula = f, totals = cre_totals(d2, f),
             cluster = "household_id", equal_within_cluster = TRUE) |>
    prep()
  w  <- collect_weights(fit2, drop_zero = FALSE)
  # within each household the final weight is constant
  spread <- tapply(fit2$final_weight, d2$household_id, function(z) max(z) - min(z))
  expect_true(max(abs(spread), na.rm = TRUE) < 1e-6)
})

test_that("recursion over three waves runs and stays finite", {
  f  <- ~ sex
  d1 <- cre_wave(1); d2 <- cre_wave(2); d3 <- cre_wave(3)
  fit1 <- weighting_spec(d1, base_weights = pw) |>
    step_cre(previous = NULL, status = lf_status, formula = f, totals = cre_totals(d1, f)) |>
    prep()
  fit2 <- weighting_spec(d2, base_weights = pw) |>
    step_cre(previous = fit1, rescale_previous = TRUE, status = lf_status, composite = list(NULL),
             id_unit = c("household_id", "person_no"), formula = f, totals = cre_totals(d2, f)) |>
    prep()
  fit3 <- weighting_spec(d3, base_weights = pw) |>
    step_cre(previous = fit2, rescale_previous = TRUE, status = lf_status, composite = list(NULL),
             id_unit = c("household_id", "person_no"), formula = f, totals = cre_totals(d3, f)) |>
    prep()
  expect_true(all(is.finite(fit3$final_weight)))
  expect_true(isTRUE(attr(fit3$steps[[1]]$diagnostics, "converged")))
})

test_that("rotation_group adds equal-representation constraints (each group weights to N/G)", {
  d  <- cre_wave(1)
  f  <- ~ sex
  tt <- cre_totals(d, f)                      # (Intercept) target = N
  fit <- weighting_spec(d, base_weights = pw) |>
    step_cre(previous = NULL, status = lf_status, formula = f, totals = tt,
             rotation_group = "rotation_group", n_groups = 6) |>
    prep()
  w   <- fit$final_weight
  by_g <- tapply(w, d$rotation_group, sum)
  N    <- unname(tt[["(Intercept)"]]); G <- length(by_g)
  # every rotation group weights to the same working-age total N/G
  expect_equal(as.numeric(by_g), rep(N / G, G), tolerance = 1e-4)
})

test_that("step_cre input validation", {
  d <- cre_wave(1)
  expect_error(
    weighting_spec(d, base_weights = pw) |>
      step_cre(previous = NULL, status = lf_status, formula = ~ sex,
               totals = cre_totals(d, ~ sex), composite = list(1)),
    "NULL or a character")
  expect_error(
    weighting_spec(d, base_weights = pw) |>
      step_cre(previous = NULL, status = lf_status, formula = ~ sex,
               totals = cre_totals(d, ~ sex), alpha = 2),
    "alpha")
})

# CRE-07. G is a property of the design. Read off the active sample it moves with who
# answered, and the equal-representation target N/G moves with it -- silently, because
# N/G_present is the only reading that is feasible with the intercept pinned at N.

test_that("step_cre() refuses to infer G from the wave when a rotation group is absent", {
  d  <- cre_wave(1)
  f  <- ~ sex
  tt <- cre_totals(d, f)                       # population totals: they do NOT shrink
  d5 <- subset(d, rotation_group != "g6")      # one group answered nobody

  # declared through n_groups
  expect_error(
    weighting_spec(d5, base_weights = pw) |>
      step_cre(previous = NULL, status = lf_status, formula = f, totals = tt,
               rotation_group = "rotation_group", n_groups = 6) |> prep(),
    "design has 6 group\\(s\\) but only 5")

  # declared through the factor's levels, which survive a level going empty
  df <- d5; df$rotation_group <- factor(df$rotation_group, levels = paste0("g", 1:6))
  expect_error(
    weighting_spec(df, base_weights = pw) |>
      step_cre(previous = NULL, status = lf_status, formula = f, totals = tt,
               rotation_group = "rotation_group") |> prep(),
    "missing: g6")

  # and it is not a false alarm: with all six present it calibrates each to exactly N/6
  fit <- weighting_spec(d, base_weights = pw) |>
    step_cre(previous = NULL, status = lf_status, formula = f, totals = tt,
             rotation_group = "rotation_group", n_groups = 6) |> prep()
  expect_equal(as.numeric(tapply(fit$final_weight, d$rotation_group, sum)),
               rep(unname(tt[["(Intercept)"]]) / 6, 6), tolerance = 1e-6)
})

test_that("a character rotation column with no n_groups says G was read off the wave", {
  d  <- cre_wave(1); f <- ~ sex
  expect_warning(
    weighting_spec(d, base_weights = pw) |>
      step_cre(previous = NULL, status = lf_status, formula = f, totals = cre_totals(d, f),
               rotation_group = "rotation_group") |> prep(),
    "not a factor and `n_groups` was not given")
})

test_that("n_groups is validated and only means something with rotation_group", {
  d <- cre_wave(1)
  sp <- weighting_spec(d, base_weights = pw)
  expect_error(step_cre(sp, previous = NULL, status = lf_status, formula = ~ sex,
                        totals = cre_totals(d, ~ sex), n_groups = 6),
               "only means anything with `rotation_group`")
  expect_error(step_cre(sp, previous = NULL, status = lf_status, formula = ~ sex,
                        totals = cre_totals(d, ~ sex),
                        rotation_group = "rotation_group", n_groups = 1),
               "whole number >= 2")
})
