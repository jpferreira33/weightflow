# Quality alerts raised while preparing a recipe

[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
computes non-fatal *quality alerts* at every stage of the cascade, not
only at the end. Each alert names a specific risk, its trigger and a
remedy. Alerts are always stored on the prepped object (read them with
[`weighting_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md)
/
[`has_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md))
and shown in the HTML report; with `prep(warn = TRUE)` they are also
raised as R warnings. Every alert is tagged with the step that produced
it, e.g. `"[step_calibrate] ..."`.

## Details

This page catalogues the alerts by theme. Thresholds are the
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
defaults unless noted; `min_cell_n` and `max_factor` are arguments of
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md).

## Weight distribution

- *Negative calibration weights*: an unbounded linear/GREG calibration
  produced weight(s) below zero. They stay active (the totals are
  honest), but a negative survey weight is rarely wanted and makes the
  estimator erratic. Use a bounded distance (`calfun = "logit"` with
  `bounds`) or
  [`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md).

- *Sub-one weights*: unit(s) with a final weight below 1, so they
  represent less than themselves. Usually a sign of an over-aggressive
  adjustment.

- *Extreme g-factors*: a calibration adjustment factor outside the
  Deville-Sarndal range `[0.1, 10]`. Consider bounds, a ridge `penalty`,
  or coarser auxiliaries.

## Adjustment cells

- *Small cells*: an adjustment cell (weighting class or post-stratum)
  with fewer than `min_cell_n` (default 30, Kalton and
  Flores-Cervantes 2003) cases. Collapse cells or switch to raking.

- *Empty cells*: a cell with no unit to adjust to (no respondents, or
  all of unknown eligibility); the affected units are set to weight 0.

- *Large adjustment factors*: a per-cell factor above `max_factor`
  (default 2.5), which inflates the variance.

## Nonresponse and response propensities

- *Tiny propensities*: a minimum fitted response propensity below 0.01
  blows up the `1/p` weights; check the model or trim.

- *Collapsed propensity classes*: the fitted propensities were nearly
  constant, so the requested `num_classes` could not be formed and the
  class correction did nothing.

- *Miscalibrated propensities*: a calibration slope far from 1; honest
  probabilities matter for `1/p`. Use `num_classes` (rank-robust) or
  revise the model.

- *Non-positive nonresponse g-weights*: an implied response probability
  of zero or below; use a bounded distance or other auxiliaries.

## Calibration

- *Ill-conditioned system*: near-collinear auxiliaries (large condition
  number) make the weights unstable; drop a redundant auxiliary or set a
  ridge `penalty`.

- *Did not converge*: raking, linear or bounded calibration stopped
  without meeting every target; increase `maxit` or check the margins
  are mutually consistent.

- *Reconciled control totals*: the tidy `totals` did not all sum to the
  same population size and were rescaled to a common N (informative, not
  an error).

## Machine-learning adjustments

- *Learner without cross-fitting*: a flexible learner (tree / forest /
  boost) run without `crossfit` can understate the variance through
  same-sample prediction. Add `crossfit` to estimate each unit out of
  sample.

## Finalising

- *Rounded to zero*: rounding pushed a small or negative weight to
  exactly 0, so the unit left the active set and
  [`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md);
  round to more decimals or resolve those weights first.

## See also

[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md),
[`weighting_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md),
[`has_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md),
[`step_assert()`](https://jpferreira33.github.io/weightflow/reference/step_assert.md)
for a hard quality gate, and
[`vignette("inspecting-auditing")`](https://jpferreira33.github.io/weightflow/articles/inspecting-auditing.md)
for the full programmatic quality-control workflow.
