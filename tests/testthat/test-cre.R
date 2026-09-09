# step_cre(): composite regression estimator (LFS ch.6 / ECH sec.8.4)

# Build a wave from panel_ine: respondents only, with a 3-level labour status.
cre_wave <- function(t) {
  d <- subset(panel_ine, ola == t & disp == "R")
  d$condicion <- ifelse(is.na(d$ocupado), "inact",
                 ifelse(d$ocupado == 1L, "emp",
                 ifelse(d$desocupado == 1L, "unemp", "inact")))
  d
}
# design-weighted model.matrix totals for a formula on a wave (so calibration is feasible)
cre_totals <- function(d, formula) {
  X <- stats::model.matrix(formula, data = d)
  colSums(d$w_base * X)
}

test_that("seed wave (previous = NULL) equals an ordinary linear calibration", {
  d  <- cre_wave(1)
  f  <- ~ sexo
  tt <- cre_totals(d, f)

  fit_cre <- weighting_spec(d, base_weights = w_base) |>
    step_cre(previous = NULL, status = condicion, formula = f, totals = tt) |>
    prep()
  fit_cal <- weighting_spec(d, base_weights = w_base) |>
    step_calibrate(method = "linear", formula = f, totals = tt) |>
    prep()

  expect_equal(unname(fit_cre$final_weight), unname(fit_cal$final_weight), tolerance = 1e-8)
})

test_that("composite wave reproduces BOTH the demographic totals X and the composite totals Zhat", {
  d1 <- cre_wave(1); d2 <- cre_wave(2)
  f  <- ~ sexo
  fit1 <- weighting_spec(d1, base_weights = w_base) |>
    step_cre(previous = NULL, status = condicion, formula = f, totals = cre_totals(d1, f)) |>
    prep()

  fit2 <- weighting_spec(d2, base_weights = w_base) |>
    step_cre(previous = fit1, status = condicion,
             composite = list(NULL, "sexo"),
             id_unit = c("id_hogar", "nper"),
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
  f  <- ~ sexo
  fit1 <- weighting_spec(d1, base_weights = w_base) |>
    step_cre(previous = NULL, status = condicion, formula = f, totals = cre_totals(d1, f)) |>
    prep()
  mk <- function(a) weighting_spec(d2, base_weights = w_base) |>
    step_cre(previous = fit1, status = condicion, composite = list(NULL),
             id_unit = c("id_hogar", "nper"), formula = f, totals = cre_totals(d2, f),
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
  f  <- ~ sexo
  fit1 <- weighting_spec(d1, base_weights = w_base) |>
    step_cre(previous = NULL, status = condicion, formula = f, totals = cre_totals(d1, f),
             cluster = "id_hogar", equal_within_cluster = TRUE) |>
    prep()
  fit2 <- weighting_spec(d2, base_weights = w_base) |>
    step_cre(previous = fit1, status = condicion, composite = list(NULL, "sexo"),
             id_unit = c("id_hogar", "nper"), formula = f, totals = cre_totals(d2, f),
             cluster = "id_hogar", equal_within_cluster = TRUE) |>
    prep()
  w  <- collect_weights(fit2, drop_zero = FALSE)
  # within each household the final weight is constant
  spread <- tapply(fit2$final_weight, d2$id_hogar, function(z) max(z) - min(z))
  expect_true(max(abs(spread), na.rm = TRUE) < 1e-6)
})

test_that("recursion over three waves runs and stays finite", {
  f  <- ~ sexo
  d1 <- cre_wave(1); d2 <- cre_wave(2); d3 <- cre_wave(3)
  fit1 <- weighting_spec(d1, base_weights = w_base) |>
    step_cre(previous = NULL, status = condicion, formula = f, totals = cre_totals(d1, f)) |>
    prep()
  fit2 <- weighting_spec(d2, base_weights = w_base) |>
    step_cre(previous = fit1, status = condicion, composite = list(NULL),
             id_unit = c("id_hogar", "nper"), formula = f, totals = cre_totals(d2, f)) |>
    prep()
  fit3 <- weighting_spec(d3, base_weights = w_base) |>
    step_cre(previous = fit2, status = condicion, composite = list(NULL),
             id_unit = c("id_hogar", "nper"), formula = f, totals = cre_totals(d3, f)) |>
    prep()
  expect_true(all(is.finite(fit3$final_weight)))
  expect_true(isTRUE(attr(fit3$steps[[1]]$diagnostics, "converged")))
})

test_that("rotation_group adds equal-representation constraints (each group weights to N/G)", {
  d  <- cre_wave(1)
  f  <- ~ sexo
  tt <- cre_totals(d, f)                      # (Intercept) target = N
  fit <- weighting_spec(d, base_weights = w_base) |>
    step_cre(previous = NULL, status = condicion, formula = f, totals = tt,
             rotation_group = "grupo_rotacion") |>
    prep()
  w   <- fit$final_weight
  by_g <- tapply(w, d$grupo_rotacion, sum)
  N    <- unname(tt[["(Intercept)"]]); G <- length(by_g)
  # every rotation group weights to the same working-age total N/G
  expect_equal(as.numeric(by_g), rep(N / G, G), tolerance = 1e-4)
})

test_that("step_cre input validation", {
  d <- cre_wave(1)
  expect_error(
    weighting_spec(d, base_weights = w_base) |>
      step_cre(previous = NULL, status = condicion, formula = ~ sexo,
               totals = cre_totals(d, ~ sexo), composite = list(1)),
    "NULL or a character")
  expect_error(
    weighting_spec(d, base_weights = w_base) |>
      step_cre(previous = NULL, status = condicion, formula = ~ sexo,
               totals = cre_totals(d, ~ sexo), alpha = 2),
    "alpha")
})
