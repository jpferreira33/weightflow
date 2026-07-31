# Regression tests for report_weighting(). The report is assembled with a large
# hand-written sprintf(), so the main risk is a placeholder / argument mismatch
# that silently corrupts the HTML. These tests simply render the report under
# the different argument combinations and assert that each optional block
# (metadata card, AAPOR fieldwork-outcomes card, executive summary / narrative,
# per-step visuals) appears or is omitted as expected -- in both languages.

# A small recipe that exercises the eligibility + nonresponse + calibration
# branches, so every optional card has something to show.
.report_fixture <- function() {
  d <- sample_survey
  set.seed(1)
  d$unk  <- as.integer(runif(nrow(d)) < 0.03)                 # unknown eligibility
  d$inel <- ifelse(d$unk == 0L, as.integer(runif(nrow(d)) < 0.05), 0L)
  mreg <- c(xtabs(pw ~ region, data = d))
  weighting_spec(d, base_weights = pw) |>
    step_unknown_eligibility(unknown = unk, by = "region") |>
    step_drop_ineligible(ineligible = inel) |>
    step_nonresponse(respondent = responded, method = "weighting_class",
                     by = "region") |>
    step_calibrate(method = "raking", margins = list(region = mreg)) |>
    prep()
}

.render <- function(...) {
  f <- report_weighting(..., open = FALSE)
  paste(readLines(f), collapse = "\n")
}

test_that("report renders all optional cards (English, defaults)", {
  fit  <- .report_fixture()
  html <- .render(fit, metadata = list(survey = "Test Survey",
                                        totals_source = "Register"))
  expect_match(html, "Fieldwork outcomes")          # AAPOR card
  expect_match(html, "AAPOR Standard Definitions")  # AAPOR footnote
  expect_match(html, "AAPOR RR1")                   # cota conservadora (todos los U)
  expect_match(html, "AAPOR RR3, CASRO")            # e-ajustada
  expect_match(html, "AAPOR RR5")                   # cota menos conservadora (U excluidos)
  expect_match(html, "Reference metadata")          # metadata card
  expect_match(html, "Test Survey")                 # metadata woven in
  expect_match(html, "Executive summary")           # narrative on by default
})

test_that("report renders in Spanish (lang = 'es')", {
  fit  <- .report_fixture()
  html <- .render(fit, lang = "es", metadata = list(survey = "Encuesta"))
  expect_match(html, "Resultados del trabajo de campo")  # AAPOR card (es)
  expect_match(html, "Metadatos de referencia")          # metadata card (es)
  expect_match(html, "Resumen ejecutivo")                # narrative (es)
})

test_that("narrative = FALSE and plots = FALSE drop their blocks", {
  fit  <- .report_fixture()
  html <- .render(fit, narrative = FALSE, plots = FALSE)
  expect_false(grepl("Executive summary", html, fixed = TRUE))
  expect_false(grepl("class='viz'", html, fixed = TRUE))
  # the report still renders its core structure
  expect_match(html, "Per-stage summary")
})

test_that("AAPOR card is omitted when the recipe has no nonresponse step", {
  fit <- weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(region = c(xtabs(pw ~ region, data = sample_survey)))) |>
    prep()
  html <- .render(fit)
  expect_false(grepl("Fieldwork outcomes", html, fixed = TRUE))
})

test_that("metadata card is omitted when no metadata is supplied", {
  fit  <- .report_fixture()
  html <- .render(fit)
  expect_false(grepl("Reference metadata", html, fixed = TRUE))
})
