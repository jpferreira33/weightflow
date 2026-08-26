# Unit tests for R/report-narrative.R: the bilingual prose builders. Steps are
# hand-built lists with the right class, so every branch of .step_short() and
# .step_narrative() is reachable without running a whole report.

nde1 <- design_effect(c(1, 2, 3))
nde2 <- design_effect(c(1, 1, 1))

mkstep <- function(cls, ...) structure(list(label = cls, ...),
                                       class = c(cls, "weighting_step"))
narr <- function(step, ri = NULL, last = FALSE, lang = "en")
  .step_narrative(step, nde1, nde2, ri, last, lang)

# ---------------------------------------------------------------------------
# .t(), .narr_vars(), .deff_phrase(), .aux_vars(), .vars_phrase()
# ---------------------------------------------------------------------------

test_that(".t picks the language variant", {
  expect_equal(.t("yes", "si", "en"), "yes")
  expect_equal(.t("yes", "si", "es"), "si")
  expect_equal(.t("yes", "si", "fr"), "yes")     # anything else falls back to English
})

test_that(".narr_vars falls back to a generic phrase when there is nothing", {
  expect_equal(.narr_vars(list(), "en"), "the auxiliary variables")
  expect_equal(.narr_vars(list(), "es"), "las variables auxiliares")
})

test_that(".narr_vars lists the auxiliaries with a language-aware conjunction", {
  expect_equal(.narr_vars(list(by = "region"), "en"), "<strong>region</strong>")
  out <- .narr_vars(list(formula = ~ region + sex), "en")
  expect_equal(out, "<strong>region</strong> and <strong>sex</strong>")
  expect_match(.narr_vars(list(formula = ~ a + b + c), "en"),
               "<strong>a</strong>, <strong>b</strong> and <strong>c</strong>",
               fixed = TRUE)
  expect_match(.narr_vars(list(formula = ~ region + sex), "es"), " y ",
               fixed = TRUE)
})

test_that(".narr_vars merges formula, by and margin names without duplicates", {
  out <- .narr_vars(list(formula = ~ region, by = "region",
                         margins = list(sex = 1)), "en")
  expect_equal(lengths(regmatches(out, gregexpr("region", out))), 1L)
  expect_match(out, "sex")
})

test_that(".deff_phrase reports both design effects", {
  expect_match(.deff_phrase(nde1, nde2, "en"), "went from 1.167 to 1.000")
  expect_match(.deff_phrase(nde1, nde2, "es"), "pas")
})

test_that(".aux_vars prefers margins, then the formula terms", {
  expect_equal(.aux_vars(list(margins = list(sex = 1, region = 2))),
               c("sex", "region"))
  expect_equal(.aux_vars(list(formula = ~ age + region)), c("age", "region"))
  expect_equal(.aux_vars(list()), character(0))
})

test_that(".vars_phrase joins a list of names", {
  expect_equal(.vars_phrase(character(0), "en"), "")
  expect_equal(.vars_phrase("sex", "en"), "sex")
  expect_equal(.vars_phrase(c("sex", "region"), "en"), "sex and region")
  expect_equal(.vars_phrase(c("sex", "region"), "es"), "sex y region")
})

# ---------------------------------------------------------------------------
# .step_short()
# ---------------------------------------------------------------------------

test_that(".step_short names the simple steps in both languages", {
  cases <- list(
    step_unknown_eligibility = c("unknown-eligibility", "elegibilidad desconocida"),
    step_drop_ineligible     = c("ineligible units",    "no elegibles"),
    step_select_within       = c("within-cluster",      "dentro del conglomerado"),
    step_model_calibration   = c("model-assisted",      "asistida por modelo"),
    step_trim_calibrated     = c("calibration-preserving", "preserva la calibraci"),
    step_trim_weights        = c("weight trimming",     "recorte de pesos"),
    step_round               = c("rounding",            "redondeo"),
    step_rescale             = c("rescaling",           "reescalado"),
    step_assert              = c("quality checkpoint",  "punto de control"))
  for (cls in names(cases)) {
    st <- mkstep(cls)
    expect_match(.step_short(st, "en"), cases[[cls]][1])
    expect_match(.step_short(st, "es"), cases[[cls]][2])
  }
})

test_that(".step_short describes each nonresponse method", {
  wc <- mkstep("step_nonresponse", method = "weighting_class")
  expect_match(.step_short(wc, "en"), "weighting classes")

  pr <- mkstep("step_nonresponse", method = "propensity", engine = "forest")
  expect_match(.step_short(pr, "en"), "response-propensity adjustment \\(random forest\\)")

  cal <- mkstep("step_nonresponse", method = "calibration", formula = ~ region + sex)
  expect_match(.step_short(cal, "en"), "nonresponse calibration to region and sex")

  bare <- mkstep("step_nonresponse", method = "calibration")
  expect_match(.step_short(bare, "en"), "nonresponse adjustment \\(calibration\\)")
})

test_that(".step_short marks GREG calibration and falls back to the totals", {
  greg <- mkstep("step_calibrate", method = "linear", formula = ~ region + sex)
  expect_match(.step_short(greg, "en"), "GREG calibration to region and sex")

  rake <- mkstep("step_calibrate", method = "raking",
                 margins = list(sex = 1, region = 2))
  expect_match(.step_short(rake, "en"), "^calibration to sex and region")

  bare <- mkstep("step_calibrate", method = "raking")
  expect_match(.step_short(bare, "en"), "calibration to population totals")
})

test_that(".step_short falls back to the escaped label for an unknown step", {
  st <- structure(list(label = "custom <step>"), class = c("step_weird", "weighting_step"))
  expect_equal(.step_short(st, "en"), "custom &lt;step&gt;")
})

# ---------------------------------------------------------------------------
# .step_narrative() -- pre-calibration steps
# ---------------------------------------------------------------------------

test_that("the narrative is empty for a step type it does not know", {
  expect_equal(narr(mkstep("step_weird")), "")
})

test_that("unknown-eligibility mentions the level and the cells", {
  unit <- narr(mkstep("step_unknown_eligibility", by = "region"))
  expect_match(unit, "at the unit level")
  expect_match(unit, "by <strong>region</strong>")
  expect_match(unit, "methodological-note")

  hh <- narr(mkstep("step_unknown_eligibility", cluster = "household_id"))
  expect_match(hh, "at the household level")
  expect_match(narr(mkstep("step_unknown_eligibility"), lang = "es"),
               "elegibilidad desconocida")
})

test_that("dropping ineligibles and within-cluster selection are described", {
  expect_match(narr(mkstep("step_drop_ineligible")), "out of scope")
  expect_match(narr(mkstep("step_select_within")), "within-cluster selection")
  expect_match(narr(mkstep("step_select_within"), lang = "es"),
               "dentro del conglomerado")
})

# ---------------------------------------------------------------------------
# .step_narrative() -- nonresponse
# ---------------------------------------------------------------------------

test_that("weighting-class nonresponse names the adjustment cells", {
  out <- narr(mkstep("step_nonresponse", method = "weighting_class", by = "region"))
  expect_match(out, "weighting classes")
  expect_match(out, "<strong>region</strong>")
})

test_that("propensity nonresponse reports the engine, cross-fitting and classes", {
  out <- narr(mkstep("step_nonresponse", method = "propensity", engine = "forest",
                     formula = ~ region, crossfit = 5L, num_classes = 5L))
  expect_match(out, "<strong>forest</strong>")
  expect_match(out, "5-fold cross-fitting")
  expect_match(out, "grouped into 5 classes")
})

test_that("propensity nonresponse without classes describes the 1/p factor", {
  out <- narr(mkstep("step_nonresponse", method = "propensity", engine = "logit",
                     formula = ~ region, num_classes = NULL))
  expect_match(out, "inverse of its estimated propensity")
  expect_false(grepl("cross-fitting", out, fixed = TRUE))
})

test_that("calibration nonresponse distinguishes sample-level from population totals", {
  samp <- narr(mkstep("step_nonresponse", method = "calibration",
                      formula = ~ region, totals = NULL))
  expect_match(samp, "full-sample")
  expect_match(samp, "Sarndal-Lundstrom")

  pop <- narr(mkstep("step_nonresponse", method = "calibration",
                     formula = ~ region, totals = c(a = 1),
                     equal_within_cluster = TRUE))
  expect_match(pop, "supplied population totals")
  expect_match(pop, "one weight per household \\(integrative\\)")
})

test_that("the last nonresponse step appends the R-indicator", {
  ri <- list(R = 0.873,
             partials = data.frame(variable = c("region", "sex", "age"),
                                   partial_R = c(0.021, 0.058, 0.010),
                                   stringsAsFactors = FALSE))
  out <- narr(mkstep("step_nonresponse", method = "weighting_class", by = "region"),
              ri = ri, last = TRUE)
  expect_match(out, "R-indicator is 0.873")
  expect_match(out, "<strong>sex</strong> \\(0.0580\\)")   # top partial first
  expect_false(grepl("age", out, fixed = TRUE))            # only the top two

  no_ri <- narr(mkstep("step_nonresponse", method = "weighting_class",
                       by = "region"), ri = ri, last = FALSE)
  expect_false(grepl("R-indicator", no_ri, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# .step_narrative() -- calibration family
# ---------------------------------------------------------------------------

test_that("each calibration method gets its own description", {
  rake <- narr(mkstep("step_calibrate", method = "raking",
                      margins = list(region = 1)))
  expect_match(rake, "iterative proportional fitting")
  expect_match(rake, "Kish design effect went from")

  ps <- narr(mkstep("step_calibrate", method = "poststratify",
                    margins = list(region = 1)))
  expect_match(ps, "post-stratification")

  lin <- narr(mkstep("step_calibrate", method = "linear", formula = ~ region))
  expect_match(lin, "linear \\(GREG\\) calibration")
})

test_that("calibration reports the distance, bounds, cluster and ridge options", {
  out <- narr(mkstep("step_calibrate", method = "linear", formula = ~ region,
                     calfun = "raking", bounds = c(0.5, 2),
                     equal_within_cluster = TRUE, penalty = 1))
  expect_match(out, "using the raking distance")
  expect_match(out, "stays in \\(0.50, 2.00\\)")
  expect_match(out, "integrative \\(one weight per household\\)")
  expect_match(out, "ridge-penalised")
})

test_that("model-assisted calibration cites Wu-Sitter", {
  expect_match(narr(mkstep("step_model_calibration")), "Wu-Sitter")
  expect_match(narr(mkstep("step_model_calibration"), lang = "es"), "Wu-Sitter")
})

# ---------------------------------------------------------------------------
# .step_narrative() -- trimming
# ---------------------------------------------------------------------------

test_that("calibration-preserving trimming reports a single range", {
  out <- narr(mkstep("step_trim_calibrated", formula = ~ region + sex,
                     lower = 50, upper = 400))
  expect_match(out, "into the range \\[50, 400\\]")
  expect_match(out, "<strong>region</strong>")
  expect_match(out, " and <strong>sex</strong>")
})

test_that("calibration-preserving trimming reports per-group bounds", {
  out <- narr(mkstep("step_trim_calibrated", formula = ~ region, by = "region",
                     lower = c(N = 50, S = 60), upper = c(N = 400, S = 380),
                     equal_within_cluster = TRUE))
  expect_match(out, "per-region bounds")
  expect_match(out, "N \\[50, 400\\]")
  expect_match(out, "S \\[60, 380\\]")
  expect_match(out, "one factor per household")
})

test_that("calibration-preserving trimming handles an open bound", {
  out <- narr(mkstep("step_trim_calibrated", formula = ~ region, upper = 400))
  expect_match(out, "\\[-Inf, 400\\]")
})

test_that("weight trimming names the rule only when the cutoff is automatic", {
  pot <- narr(mkstep("step_trim_weights", lower = 1, upper = NULL,
                     method = "potter",
                     diagnostics = data.frame(sum_before = 100, sum_after = 100)))
  expect_match(pot, "\\[1, auto\\]")
  expect_match(pot, "Potter's MSE-optimal rule")

  tuk <- narr(mkstep("step_trim_weights", lower = 1, upper = NULL,
                     method = "tukey",
                     diagnostics = data.frame(sum_before = 100, sum_after = 100)))
  expect_match(tuk, "Tukey fence rule")

  man <- narr(mkstep("step_trim_weights", lower = 1, upper = 5,
                     method = "tukey",
                     diagnostics = data.frame(sum_before = 100, sum_after = 100)))
  expect_match(man, "\\[1, 5\\]")
  expect_false(grepl("rule", man, fixed = TRUE))
})

test_that("weight trimming says whether the total was preserved", {
  ok <- narr(mkstep("step_trim_weights", lower = 1, upper = 5, method = "tukey",
                    diagnostics = data.frame(sum_before = 100, sum_after = 100)))
  expect_match(ok, "preserving the weight total")

  lost <- narr(mkstep("step_trim_weights", lower = 1, upper = 5, method = "tukey",
                      diagnostics = data.frame(sum_before = 100, sum_after = 90)))
  expect_match(lost, "bounds were infeasible")
  expect_match(lost, "fell by 10.0%")
})

# ---------------------------------------------------------------------------
# .step_narrative() -- final steps
# ---------------------------------------------------------------------------

test_that("rounding, rescaling and the checkpoint are described", {
  expect_match(narr(mkstep("step_round")), "rounded")
  expect_match(narr(mkstep("step_rescale")), "rescaled")
  expect_match(narr(mkstep("step_assert")), "quality checkpoint")
  expect_match(narr(mkstep("step_assert"), lang = "es"), "punto de control")
})
