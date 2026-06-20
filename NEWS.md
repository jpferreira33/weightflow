# weightflow 0.1.0

First release.

A dependency-free, pipeable API to compute survey weights from design base
weights through a chain of hierarchical adjustment stages. Build a recipe
lazily, estimate it with `prep()`, and extract the weights with
`collect_weights()`.

## Adjustment steps

* `step_unknown_eligibility()` — redistribute the weight of unknown-eligibility
  cases to the known ones (person- or household-level via `cluster`).
* `step_drop_ineligible()` — zero out out-of-scope units.
* `step_select_within()` — within-household selection (unequal `prob` or equal
  `n_eligible`).
* `step_nonresponse()` — weighting-class or propensity adjustment, at the person
  or household level (`cluster`).
* `step_calibrate()` — raking, post-stratification and linear/GREG calibration,
  with bounded (Deville-Särndal) and integrative cluster options.
* `step_model_calibration()` — Wu-Sitter model calibration.
* `step_trim()`, `step_trim_weights()`, `step_round()`, `step_rescale()` —
  trimming, rounding and rescaling.
* `step_assert()` — quality checkpoint (deff, weight ratio, effective n).

## Inspection and reporting

* `summary()`, `plot()` and `weight_factors()` for per-stage diagnostics.
* `design_effect()` for the Kish design effect and effective sample size.
* `report_weighting()` builds a self-contained HTML report with a pipeline
  diagram, the variables used, per-stage summaries and per-step visuals.

## Data

* Bundled example datasets `population`, `sample_survey` (take-all roster) and
  `sample_one` (multistage select-one design).

This package produces weights only; for variance estimation, export the final
weights to the `survey` package.
