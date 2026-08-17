# Contract for collect_step_detail() / the unit_detail interface, plus the new
# .factor/.class columns of collect_propensities().

test_that("collect_step_detail: .weight_in * .factor reproduces the output weight", {
  fit <- suppressMessages(prep(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_nonresponse(respondent = responded, method = "propensity",
                       formula = ~ sex + region, engine = "logit", num_classes = NULL) |>
      step_calibrate(method = "raking",
                     margins = list(region = c(table(population$region))))))
  ns   <- length(fit$steps)
  wfin <- collect_weights(fit, drop_zero = FALSE)$.weight
  d    <- collect_step_detail(fit, step = ns)          # last step -> final weights
  ok   <- is.finite(d$.factor)
  expect_equal((d$.weight_in * d$.factor)[ok], wfin[ok], tolerance = 1e-8)
})

test_that("collect_step_detail: works for a step without native detail, and errors on bad index", {
  fit <- suppressMessages(prep(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_nonresponse(respondent = responded, method = "propensity",
                       formula = ~ sex + region, engine = "logit", num_classes = NULL) |>
      step_calibrate(method = "raking",
                     margins = list(region = c(table(population$region))))))
  # step 2 (calibrate) exposes no native columns, but central columns still come out
  d2 <- collect_step_detail(fit, step = 2)
  expect_true(all(c(".weight_in", ".factor") %in% names(d2)))
  expect_false(".propensity" %in% names(d2))
  expect_error(collect_step_detail(fit, step = 9), "1\\.\\.2")
})

test_that("every step satisfies the unit_detail contract and the accessor runs per step", {
  fit <- suppressMessages(prep(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_nonresponse(respondent = responded, method = "propensity",
                       formula = ~ sex + region, engine = "logit", num_classes = 4L) |>
      step_calibrate(method = "raking",
                     margins = list(region = c(table(population$region))))))
  n <- nrow(fit$data)
  for (k in seq_along(fit$steps)) {
    ud <- attr(fit$steps[[k]]$diagnostics, "unit_detail")
    if (!is.null(ud)) expect_true(weightflow:::.wf_validate_unit_detail(ud, n))
    expect_s3_class(collect_step_detail(fit, step = k), "data.frame")
  }
})

test_that("collect_propensities: .factor is the applied multiplier (1/p only without classes)", {
  # continuous 1/p per unit
  fit <- suppressMessages(prep(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_nonresponse(respondent = responded, method = "propensity",
                       formula = ~ sex + region, engine = "logit", num_classes = NULL)))
  p <- collect_propensities(fit)
  expect_false(".class" %in% names(p))
  r  <- which(p$.status == "eligible respondent")
  nr <- which(p$.status == "eligible nonrespondent")
  expect_equal(p$.factor[r], 1 / p$.propensity[r], tolerance = 1e-8)
  expect_true(all(p$.factor[nr] == 0))                 # nonrespondents zeroed

  # class-based: .class present, and 1/p does NOT reconstruct the applied factor
  fitc <- suppressMessages(prep(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_nonresponse(respondent = responded, method = "propensity",
                       formula = ~ sex + region, engine = "logit", num_classes = 4L)))
  pc <- collect_propensities(fitc)
  expect_true(".class" %in% names(pc))
  rc <- which(pc$.status == "eligible respondent")
  expect_false(isTRUE(all.equal(pc$.factor[rc], 1 / pc$.propensity[rc])))
})

test_that("domain_summary: missing domain becomes an explicit (missing) row, order respected", {
  d <- sample_survey
  d$region <- as.character(d$region)
  d$region[1:5] <- NA
  fit <- suppressMessages(prep(
    weighting_spec(d, base_weights = pw) |>
      step_nonresponse(respondent = responded, method = "weighting_class", by = "sex")))
  ds <- domain_summary(fit, by = "region")
  expect_true("(missing)" %in% levels(ds$domain))
  expect_true(any(ds$domain == "(missing)" & ds$n_active > 0))
})
