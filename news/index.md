# Changelog

## weightflow 0.1.0

First release.

A dependency-free, pipeable API to compute survey weights from design
base weights through a chain of hierarchical adjustment stages. Build a
recipe lazily, estimate it with
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md),
and extract the weights with
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md).

### Adjustment steps

- [`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md)
  — redistribute the weight of unknown-eligibility cases to the known
  ones (person- or household-level via `cluster`).
- [`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md)
  — zero out out-of-scope units.
- [`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md)
  — within-household selection (unequal `prob` or equal `n_eligible`).
- [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
  — weighting-class or propensity adjustment, at the person or household
  level (`cluster`).
- [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  — raking, post-stratification and linear/GREG calibration, with
  bounded (Deville-Särndal) and integrative cluster options.
- [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
  — Wu-Sitter model calibration.
- [`step_trim()`](https://jpferreira33.github.io/weightflow/reference/step_trim.md),
  [`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md),
  [`step_round()`](https://jpferreira33.github.io/weightflow/reference/step_round.md),
  [`step_rescale()`](https://jpferreira33.github.io/weightflow/reference/step_rescale.md)
  — trimming, rounding and rescaling.
- [`step_assert()`](https://jpferreira33.github.io/weightflow/reference/step_assert.md)
  — quality checkpoint (deff, weight ratio, effective n).

### Inspection and reporting

- [`summary()`](https://rdrr.io/r/base/summary.html),
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html) and
  [`weight_factors()`](https://jpferreira33.github.io/weightflow/reference/weight_factors.md)
  for per-stage diagnostics.
- [`design_effect()`](https://jpferreira33.github.io/weightflow/reference/design_effect.md)
  for the Kish design effect and effective sample size.
- [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
  builds a self-contained HTML report with a pipeline diagram, the
  variables used, per-stage summaries and per-step visuals.

### Data

- Bundled example datasets `population`, `sample_survey` (take-all
  roster) and `sample_one` (multistage select-one design).

This package produces weights only; for variance estimation, export the
final weights to the `survey` package.
