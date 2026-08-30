# Documentation-only topic: the catalogue of quality alerts raised by prep().

#' Quality alerts raised while preparing a recipe
#'
#' [prep()] computes non-fatal *quality alerts* at every stage of the cascade,
#' not only at the end. Each alert names a specific risk, its trigger and a
#' remedy. Alerts are always stored on the prepped object (read them with
#' [weighting_alerts()] / [has_alerts()]) and shown in the HTML report; with
#' `prep(warn = TRUE)` they are also raised as R warnings. Every alert is tagged
#' with the step that produced it, e.g. `"[step_calibrate] ..."`.
#'
#' This page catalogues the alerts by theme. Thresholds are the [prep()] defaults
#' unless noted; `min_cell_n` and `max_factor` are arguments of [prep()].
#'
#' @section Weight distribution:
#' - *Negative calibration weights*: an unbounded linear/GREG calibration
#'   produced weight(s) below zero. They stay active (the totals are honest), but
#'   a negative survey weight is rarely wanted and makes the estimator erratic.
#'   Use a bounded distance (`calfun = "logit"` with `bounds`) or
#'   [step_trim_calibrated()].
#' - *Sub-one weights*: unit(s) with a final weight below 1, so they represent
#'   less than themselves. Usually a sign of an over-aggressive adjustment.
#' - *Extreme g-factors*: a calibration adjustment factor outside the
#'   Deville-Sarndal range `[0.1, 10]`. Consider bounds, a ridge `penalty`, or
#'   coarser auxiliaries.
#'
#' @section Adjustment cells:
#' - *Small cells*: an adjustment cell (weighting class or post-stratum) with
#'   fewer than `min_cell_n` (default 30, Kalton and Flores-Cervantes 2003)
#'   cases. Collapse cells or switch to raking.
#' - *Empty cells*: a cell with no unit to adjust to (no respondents, or all of
#'   unknown eligibility); the affected units are set to weight 0.
#' - *Large adjustment factors*: a per-cell factor above `max_factor` (default
#'   2.5), which inflates the variance.
#'
#' @section Nonresponse and response propensities:
#' - *Tiny propensities*: a minimum fitted response propensity below 0.01 blows
#'   up the `1/p` weights; check the model or trim.
#' - *Collapsed propensity classes*: the fitted propensities were nearly
#'   constant, so the requested `num_classes` could not be formed and the class
#'   correction did nothing.
#' - *Miscalibrated propensities*: a calibration slope far from 1; honest
#'   probabilities matter for `1/p`. Use `num_classes` (rank-robust) or revise
#'   the model.
#' - *Non-positive nonresponse g-weights*: an implied response probability of
#'   zero or below; use a bounded distance or other auxiliaries.
#'
#' @section Calibration:
#' - *Ill-conditioned system*: near-collinear auxiliaries (large condition
#'   number) make the weights unstable; drop a redundant auxiliary or set a ridge
#'   `penalty`.
#' - *Did not converge*: raking, linear or bounded calibration stopped without
#'   meeting every target; increase `maxit` or check the margins are mutually
#'   consistent.
#' - *Reconciled control totals*: the tidy `totals` did not all sum to the same
#'   population size and were rescaled to a common N (informative, not an error).
#'
#' @section Machine-learning adjustments:
#' - *Learner without cross-fitting*: a flexible learner (tree / forest / boost)
#'   run without `crossfit` can understate the variance through same-sample
#'   prediction. Add `crossfit` to estimate each unit out of sample.
#'
#' @section Two-phase (double) sampling:
#' - *Few phase-2 sampling units*: fewer than 30 units were subsampled at the
#'   second phase. The recipe-aware bootstrap resamples the phase-2 variance
#'   component (V2) at this level, so few units leave V2 with few degrees of
#'   freedom and an unstable phase-2 standard error. Inspect the split with
#'   [two_phase_variance()].
#' - *Tiny phase-2 probability*: a minimum phase-2 selection probability below
#'   0.02 expands the subsampled weights sharply (up to `1/pi2`), inflating V2.
#'   Check the phase-2 design or trim the expanded weights.
#'
#' @section Finalising:
#' - *Rounded to zero*: rounding pushed a small or negative weight to exactly 0,
#'   so the unit left the active set and [collect_weights()]; round to more
#'   decimals or resolve those weights first.
#'
#' @seealso [prep()], [weighting_alerts()], [has_alerts()], [step_assert()] for a
#'   hard quality gate, and `vignette("inspecting-auditing")` for the full
#'   programmatic quality-control workflow.
#' @name weightflow-alerts
NULL
