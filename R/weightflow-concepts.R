#' Conventions shared by every weightflow step
#'
#' Five things behave the same way in all twelve `step_*()` functions and are
#' easier to learn once than twelve times: what the *active set* is and how a unit
#' leaves it, why the order of the cascade is not arbitrary, the three different
#' scales on which weight bounds are expressed, which arguments take a bare column
#' name and which take a string, and how to read the diagnostics that `prep()`
#' stores.
#'
#' @details
#' **The active set.** A unit is *active* when its weight is finite and non-zero
#' (`is.finite(w) & w != 0`). A weight of exactly `0` is the "dropped" marker:
#' [step_drop_ineligible()] sets out-of-scope units to zero, an empty adjustment
#' cell collapses to zero, and a unit that leaves the active set takes no part in
#' any later step and is not returned by [collect_weights()]. A *negative* weight,
#' by contrast, is a valid (if unusual) output of unbounded linear/GREG
#' calibration and stays active: it is counted by [collect_weights()], the stage
#' funnel and [design_effect()], so the reported totals match the weights actually
#' returned. (One caveat: the Kish design effect assumes non-negative weights, so
#' with negatives present its value is inflated -- see [design_effect()].)
#'
#' **Why the order is not arbitrary.** Each step multiplies the *current* weight,
#' i.e. the weight leaving the previous step, so the cascade is read top to bottom.
#' The methodological order of a household survey is: resolve unknown eligibility
#' ([step_unknown_eligibility()]) while the ineligible units are still present,
#' then drop the ineligible ([step_drop_ineligible()]), undo any within-cluster
#' subsampling ([step_select_within()]), adjust for nonresponse
#' ([step_nonresponse()]), calibrate to population totals ([step_calibrate()]),
#' and finally trim, round or rescale for delivery. Putting calibration before a
#' trim, or a trim before the nonresponse adjustment, changes the estimator, which
#' is why the steps are explicit rather than inferred.
#'
#' **Three scales for weight bounds.** Bounds are expressed on three different
#' scales, and mixing them up is the most common mistake for users coming from
#' `survey`:
#' * [step_trim()] `max_ratio` / `min_ratio` are a **ratio** to a reference (each
#'   unit's base weight, the group median, or an absolute value): `max_ratio = 3`
#'   caps a weight at three times its reference.
#' * [step_trim_weights()] and [step_trim_calibrated()] `lower` / `upper` are
#'   **absolute weights**: `upper = 400` caps the weight itself at 400.
#' * [step_calibrate()] `bounds = c(L, U)` bound the calibration **g-factor**
#'   `w_new / d` (the multiplicative adjustment), not the weight.
#'
#' **Bare column name vs string.** Arguments that name a single variable to be
#' *evaluated on the data* take an unquoted (bare) column name or condition:
#' `base_weights` in [weighting_spec()], and `respondent`, `unknown`, `ineligible`,
#' `prob`, `n_eligible`, `n_selected` in the steps. Arguments that name *grouping
#' or design structure* take character strings: `by`, `cluster`, and `strata` /
#' `psu` in the variance functions. So it is `step_nonresponse(respondent =
#' responded, by = "region")` -- `responded` bare, `"region"` quoted.
#'
#' **The same concept, different argument names.** A few concepts are named
#' differently across functions for historical reasons. The correspondence, so
#' you do not have to guess:
#' * *Weight bounds*: [step_trim()] uses `max_ratio` / `min_ratio` (a ratio),
#'   while [step_trim_weights()] and [step_trim_calibrated()] use `upper` /
#'   `lower` (absolute weights). See "Three scales for weight bounds" above.
#' * *Primary sampling unit*: [as_svydesign()] names it `ids`, while
#'   [bootstrap_weights()] and [jackknife_weights()] name it `psu`. Both mean the
#'   cluster identifier.
#' * *Calibration form vs distance*: in [step_calibrate()], `method` selects the
#'   family ("raking", "poststratify", "linear"); `calfun` selects the distance
#'   function ("linear", "logit", "raking") and applies only when `method =
#'   "linear"`. So `method = "linear"` and `calfun = "linear"` are not the same
#'   knob.
#'
#' **Reading the diagnostics.** [prep()] returns an object that carries the weight
#' at every stage (`$history`, a named list of vectors), one entry per step
#' (`$steps`, each with its own `$diagnostics` table and `$alerts`), and the
#' recipe-level `$alerts`. Rather than read those directly, use [summary()] for the
#' stage-by-stage audit, [weighting_alerts()] / [has_alerts()] for the quality
#' incidents, [plot()] for the visual cascade, [weight_factors()] for the per-unit
#' factor table, [design_effect()] for the Kish design effect, and
#' [report_weighting()] for the full self-contained HTML report.
#'
#' @name weightflow-concepts
NULL
