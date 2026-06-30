# Changelog

## weightflow 0.1.0

CRAN release: 2026-06-30

First release.

A dependency-free, pipeable API to compute survey weights from design
base weights through a chain of hierarchical adjustment stages. Build a
recipe lazily, estimate it with
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md),
and extract the weights with
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md).
Separating *define* from *apply* makes the whole process reproducible
and auditable, and lets the bootstrap re-run the entire cascade on each
replicate.

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
  bounded (Deville-Särndal) and integrative (one weight per household)
  cluster options.
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

### Variance estimation

- [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  resamples PSUs within strata (Rao-Wu rescaling) and re-applies the
  whole recipe on each replicate, so the replicate weights carry the
  variability of every adjustment.
- [`boot_mean()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  and
  [`boot_total()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  return the estimate, standard error and CI.
- [`as_svydesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md),
  [`as_svrepdesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
  and
  [`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_replicate_weights.md)
  bridge to the `survey` and `srvyr` packages for design-based
  inference.

### Data

- Bundled example datasets `population`, `sample_survey` (take-all
  roster) and `sample_one` (multistage select-one design), all with
  stratum, PSU and design weight.

### Development version

The following are available in the development version on GitHub and are
planned for a future CRAN release:

- **Machine-learning response propensities** (CART, random forest and
  gradient boosting via `xgboost`) for
  [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
  and
  [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md).
- **k-fold cross-fitting** (`crossfit`) to estimate each unit
  out-of-sample, with folds formed by cluster to avoid leakage.
- **Ridge (penalized) calibration** (`penalty`) to keep weights stable
  with many auxiliaries.
- **Potter MSE-optimal trimming** (`method = "potter"`), a data-driven
  cutoff.

Install with `remotes::install_github("jpferreira33/weightflow")` to use
them today.
