# The report (lang = "es") must translate the compute-time diagnostics that
# prep()/apply_step() emit in English (quality alerts, calibration/trim note) and
# the target/achieved diagnostic headers.

test_that(".wf_translate renders the flagged quality alerts in Spanish", {
  a <- paste0("The response propensities look miscalibrated (calibration slope 0.75, ",
              "ideal 1). For 1/p weighting the probabilities must be honest, not just ",
              "discriminative. Set num_classes (e.g. 5) to bin by propensity quantiles ",
              "-- which use only the ranking of the propensities and so are robust to ",
              "this shrinkage -- or review the propensity model.")
  es <- weightflow:::.wf_translate(a, "es")
  expect_match(es, "mal calibradas")
  expect_match(es, "0.75", fixed = TRUE)          # slope preserved
  expect_identical(weightflow:::.wf_translate(a, "en"), a)   # English passthrough

  g <- "106 case(s) with a g-factor outside the Deville-Sarndal bounds [0.10, 10.00]: 6 below, 100 above."
  esg <- weightflow:::.wf_translate(g, "es")
  expect_match(esg, "factor g fuera de las cotas")
  expect_match(esg, "106", fixed = TRUE)
  expect_match(esg, "6 por debajo, 100 por encima", fixed = TRUE)
})

test_that(".wf_translate renders the trimmed / model calibration note in Spanish", {
  n <- paste0("trimmed calibration to [-Inf, by group] (calfun = linear); 0 weights raised to ",
              "lower, 51 capped at upper; f (adjustment) in [0.540, 1.369]")
  tr <- weightflow:::.wf_translate(n, "es")
  expect_match(tr, "^calibraci")                  # "calibracion recortada a"
  expect_match(tr, "recortados a la cota superior", fixed = TRUE)
  expect_match(tr, "f (ajuste) en", fixed = TRUE)

  m <- "g (calibration factor) in [0.540, 1.369], bounds [0.100, 10.000]"
  expect_match(weightflow:::.wf_translate(m, "es"), "factor de calibraci")

  # a string with no known pattern is returned unchanged
  expect_identical(weightflow:::.wf_translate("an unrelated note", "es"), "an unrelated note")
})

test_that(".with_reldiff translates the diagnostic column headers in Spanish", {
  df <- data.frame(constraint = "x1", type = "X (consistency)",
                   target = 100, achieved = 100, stringsAsFactors = FALSE)
  out <- weightflow:::.with_reldiff(df, "es")
  expect_true(all(c("restricci\u00f3n", "tipo", "objetivo", "logrado") %in% names(out)))
  expect_false(any(c("target", "achieved") %in% names(out)))
  # English keeps the original headers
  oute <- weightflow:::.with_reldiff(df, "en")
  expect_true(all(c("target", "achieved") %in% names(oute)))
})

test_that(".wf_translate leaves no quality alert in English (lang = 'es')", {
  # exact English (numbers interpolated) as prep()/apply_step() emit them
  catalogo <- c(
    "3 adjustment cell(s) had no units to adjust to (no respondents, or all of unknown eligibility); the affected units were set to weight 0. Consider collapsing cells or using a coarser grouping.",
    "5 unit(s) were rounded to weight 0 and left the active set (their magnitude was below half the rounding precision, e.g. a small or negative calibration weight); they no longer appear in collect_weights(). Round to more decimals, or resolve those weights before rounding.",
    "Very small response propensities (min p = 0.0031 among respondents) produce extreme 1/p weights (up to 322x). Check the propensity model, or trim with step_trim_weights().",
    "Near-certain participation (max p = 0.9970) drives the pseudo-weight (1 - p)/p toward 0, so those units all but leave the sample. This usually means poor overlap between the sample and the reference (a covariate cell the reference barely reaches); review the common support or simplify the propensity model.",
    "The response propensities were nearly constant, so the requested num_classes could not be formed (the quantile cut-points collapsed); all units were placed in a single adjustment class -- the class-based correction had no effect. Drop num_classes (use 1/p weighting) or revise the propensity model.",
    "12 respondent(s) have a non-positive calibration g-weight (implied response probability <= 0 or undefined). The nonresponse-calibration auxiliaries are ill-behaved; use a bounded distance (logit) or a different auxiliary vector.",
    "Only 18 phase-2 sampling unit(s) were subsampled. The two-phase bootstrap resamples the phase-2 variance component (V2) at this level, so few units give V2 few degrees of freedom and an unstable phase-2 standard error; inspect the split with two_phase_variance() and read the phase-2 SE with care.",
    "A very small phase-2 selection probability (min pi2 = 0.0100) expands the subsampled weights by up to 100x, which inflates the phase-2 variance component (V2). Check the phase-2 design or trim the expanded weights.",
    "The calibration system is ill-conditioned (condition number 3.4e+12): near-collinear auxiliaries can make the weights unstable. Drop a redundant auxiliary, or set penalty = <lambda> (ridge).",
    "7 unit(s) received a NEGATIVE calibration weight. They remain active (counted in the totals and collect_weights()), but a negative weight is rarely intended; set `bounds` to keep the calibration factor positive. Note that the Kish design effect assumes non-negative weights, so with negatives present its value is inflated and not interpretable as an effective-sample summary.",
    "Trimming reduced the weight total by 4.2% (from 12,000 to 11,496): the mass was not preserved (infeasible bounds absorbed, or a floor above the cap). The point estimates shift; check the bounds, or use step_trim_calibrated() to trim while preserving totals.",
    "9 household(s) responded only partially and were treated as whole-household nonresponse, discarding 14 responding member(s). If you meant person-level nonresponse, drop `cluster`.",
    "6 negative weight(s) after calibration. This can occur with linear/GREG calibration; consider a bounded distance (logit or truncated linear) and review the auxiliaries.",
    "23 weight(s) below 1 (under-weighting) after calibration. Consider bounds L<1<U (e.g. a logit distance) to avoid it.",
    "4 cell(s) with an adjustment factor > 6.00 (max 9.13). Large factors inflate variance; consider collapsing cells.",
    "5 cell(s) with fewer than 30 cases (smallest observed 11). Kalton and Flores-Cervantes (2003) recommend at least 30 per cell; consider collapsing cells or switching to raking.",
    "Flexible learner (forest) without cross-fitting: same-sample predictions can understate the variance even under recipe-aware replication, because each unit stays in the training set of its own prediction. Set crossfit = 5 to break it (Dagdoug, Goga and Haziza 2023; Chernozhukov et al. 2018).",
    "cross-fitting without `crossfit_seed` is not reproducible; set `crossfit_seed` for a stable result.")
  es <- weightflow:::.wf_translate(catalogo, "es")
  # every alert must change (none passes through in English)
  expect_false(any(es == catalogo))
  # a couple of interpolated numbers must survive the rewrite
  expect_true(grepl("322x", es[3], fixed = TRUE))
  expect_true(grepl("3.4e+12", es[9], fixed = TRUE))
  expect_true(grepl("12,000", es[11], fixed = TRUE) && grepl("11,496", es[11], fixed = TRUE))
  # English passthrough is untouched
  expect_identical(weightflow:::.wf_translate(catalogo, "en"), catalogo)
})
