# Hardening: haven_labelled columns (the SPSS .sav import flow). Skipped where
# haven is not installed. Labelled columns are fine for `by` cells and 0/1
# dispositions (grouped by their codes), but must error when named by their
# labels in a margin, or used as a continuous term in a model formula.

haven_d <- function(n = 400, seed = 41) {
  set.seed(seed)
  d <- data.frame(id = 1:n,
                  w  = runif(n, 10, 30),
                  y  = rnorm(n, 50, 8))
  d$sex_lab    <- haven::labelled(sample(c(1, 2), n, TRUE),
                                  labels = c(Hombre = 1, Mujer = 2),
                                  label  = "Sexo")
  d$region_lab <- haven::labelled(sample(1:3, n, TRUE),
                                  labels = c(Norte = 1, Centro = 2, Sur = 3),
                                  label  = "Region")
  d$resp_lab   <- haven::labelled(rbinom(n, 1, 0.75),
                                  labels = c(No = 0, Si = 1),
                                  label  = "Respondio")
  # versiones convertidas (lo que hace un usuario cuidadoso con as_factor)
  d$sex_f    <- haven::as_factor(d$sex_lab)
  d$region_f <- haven::as_factor(d$region_lab)
  d$resp     <- unclass(d$resp_lab) == 1
  d
}

# total por CODIGO subyacente (independiente de si labelled "funciona")
.tot_by_code <- function(d, var, f = 1.05) {
  codes <- sort(unique(unclass(d[[var]])))
  setNames(vapply(codes, function(k) sum(d$w[unclass(d[[var]]) == k]), 0) * f,
           as.character(codes))
}

test_that("labelled column as `by` in step_nonresponse gives the same weights as its as_factor version", {
  skip_if_not_installed("haven")
  d <- haven_d()
  w_lab <- collect_weights(suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_nonresponse(respondent = resp, method = "weighting_class",
                       by = "sex_lab"))), drop_zero = FALSE)$.weight
  w_fac <- collect_weights(suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_nonresponse(respondent = resp, method = "weighting_class",
                       by = "sex_f"))), drop_zero = FALSE)$.weight
  # the partition by codes (1/2) and by labels (Male/Female) is the same
  # bijection -> the weights must be identical. If this FAILS with an error of
  # as.character sobre haven_labelled, reportarlo: seria un guard de conversion.
  expect_equal(w_lab, w_fac)
})

test_that("raking margins on a labelled variable, NAMED BY THE UNDERLYING CODES, hit the targets", {
  skip_if_not_installed("haven")
  d <- haven_d()
  m_reg <- .tot_by_code(d, "region_lab")          # nombres "1","2","3"
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = "sex_lab") |>
      step_calibrate(method = "raking", margins = list(region_lab = m_reg))))
  cw  <- collect_weights(p)
  ach <- vapply(names(m_reg),
                function(k) sum(cw$.weight[as.character(unclass(cw$region_lab)) == k]), 0)
  expect_lt(max(abs(ach - m_reg) / m_reg), 1e-6)
})

test_that("raking margins named by the labels (not the codes) error, listing observed levels", {
  skip_if_not_installed("haven")
  d <- haven_d()
  m_reg <- .tot_by_code(d, "region_lab")
  names(m_reg) <- c("Norte", "Centro", "Sur")   # how an SPSS user would name them
  expect_error(suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_calibrate(method = "raking", margins = list(region_lab = m_reg)))),
    "match no active unit")
})

test_that("a labelled variable inside a calibration formula is rejected (would enter as codes)", {
  skip_if_not_installed("haven")
  d <- haven_d()
  expect_error(suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_calibrate(method = "linear", formula = ~ region_lab,
                     totals = c(`(Intercept)` = sum(d$w), region_lab = 2)))),
    "haven_labelled")
})

test_that("a raw labelled 0/1 respondent gives the same weights as the logical version", {
  skip_if_not_installed("haven")
  d <- haven_d()
  w_ref <- collect_weights(suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_nonresponse(respondent = resp, method = "weighting_class",
                       by = "sex_f"))), drop_zero = FALSE)$.weight
  w_lab <- collect_weights(suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_nonresponse(respondent = resp_lab, method = "weighting_class",
                       by = "sex_f"))), drop_zero = FALSE)$.weight
  expect_equal(w_lab, w_ref)
})

test_that("end-to-end smoke: an ECH-like recipe over labelled data preps, reports, and keeps the labelled columns", {
  skip_if_not_installed("haven")
  d <- haven_d()
  m_reg <- .tot_by_code(d, "region_lab")
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_nonresponse(respondent = resp, method = "weighting_class",
                       by = c("sex_lab", "region_lab")) |>
      step_calibrate(method = "raking", margins = list(region_lab = m_reg)) |>
      step_round(digits = 0, method = "preserve_total")))
  cw <- collect_weights(p)
  expect_true(all(cw$.weight == floor(cw$.weight)))
  # the labelled columns survive the cascade with their class and labels
  expect_s3_class(cw$sex_lab, "haven_labelled")
  expect_false(is.null(attr(cw$region_lab, "labels")))
  # and the report renders without choking on the vctrs classes
  f <- tempfile(fileext = ".html")
  suppressMessages(report_weighting(p, file = f, open = FALSE))
  expect_true(file.exists(f) && file.size(f) > 0)
})
