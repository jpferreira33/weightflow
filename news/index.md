# Changelog

## weightflow (development version)

### Bug fixes

- `step_calibrate(equal_within_cluster = TRUE)` now implements the
  genuine Lemaitre-Dufour (1987) integrative method: each unit’s
  auxiliaries are replaced by their household mean before a person-level
  calibration, so the per-household penalty scales with household size.
  This matches `survey`’s `calibrate(aggregate.stage = )` (Vanderhoeft
  2001), ReGenesees and Statistics Canada’s GES. The previous
  implementation used a household-level distance (summed auxiliaries,
  uniform per-household penalty), a different (non-standard) method.
  Integrative-calibration weights will change; totals are still met
  exactly and weights remain constant within household.

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

- [`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md):
  redistribute the weight of unknown-eligibility cases to the known ones
  (person- or household-level via `cluster`).
- [`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md):
  zero out out-of-scope units.
- [`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md):
  within-household selection (unequal `prob` or equal `n_eligible`).
- [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md):
  weighting-class or propensity adjustment, at the person or household
  level (`cluster`).
- [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md):
  raking, post-stratification and linear/GREG calibration, with bounded
  (Deville-Särndal) and integrative (one weight per household) cluster
  options.
- [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md):
  Wu-Sitter model calibration.
- [`step_trim()`](https://jpferreira33.github.io/weightflow/reference/step_trim.md),
  [`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md),
  [`step_round()`](https://jpferreira33.github.io/weightflow/reference/step_round.md),
  [`step_rescale()`](https://jpferreira33.github.io/weightflow/reference/step_rescale.md):
  trimming, rounding and rescaling.
- [`step_assert()`](https://jpferreira33.github.io/weightflow/reference/step_assert.md):
  quality checkpoint (deff, weight ratio, effective n).

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

- **Tidy population totals for
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md).**
  In addition to the classic `margins`/`totals` inputs (which keep
  working unchanged), calibration targets can now be given as tidy data
  frames, paired with the new `count` argument that names the counts
  column:
  - *Post-stratification*: a data frame with one or more category
    columns plus a counts column. Several category columns are crossed
    automatically, so there is no need to build a collapsed cell
    variable by hand.
  - *Raking*: a list of data frames, one per margin.
  - *Linear/GREG*: a named list matching the formula terms, with a data
    frame (all categories) for each factor and a single number for each
    continuous total; weightflow builds the model.matrix totals
    internally, so the user never drops a reference category or handles
    the intercept. Calibration also reports clearer diagnostics and
    warnings: post-stratification flags cells in the sample but missing
    from the totals (error) or in the totals but absent from the sample
    (warning); raking warns on mutually inconsistent margins or
    non-convergence; linear calibration warns when the constraints are
    not fully satisfied; and calibration variables with missing values
    raise an informative error.
- **Subsampling of more than one person per household in
  [`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md).**
  A new `n_selected` argument (a single number or an unquoted column)
  works alongside `n_eligible` for simple random selection of a
  subsample: the weight is multiplied by `n_eligible / n_selected`
  (equivalent to `prob = n_selected/n_eligible`). It defaults to 1, so
  selecting a single person keeps working unchanged.
- **External consistency totals for
  [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md).**
  The totals of the `x_formula` auxiliaries can now be supplied through
  the new `x_totals` argument, in the same two shapes as
  `step_calibrate(method = "linear")`: the tidy format (a named list
  with a data frame per factor, paired with `count`, and a single number
  per continuous total) or the classic model-matrix vector. This covers
  the common case where the X control totals come from an external
  source rather than from the frame; the auxiliaries then need to be
  present only in the sample, not in `population`. When `x_totals` is
  `NULL` (default) the X totals are still taken from `population`, so
  existing code is unchanged. `population` remains required, because the
  model-assisted block predicts each outcome over every population unit.
  Model calibration now also warns, like linear calibration, when the
  achieved totals do not fully satisfy the constraints (collinear or
  ill-conditioned auxiliaries).
- **Delete-a-PSU jackknife variance (recipe-aware).**
  [`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)
  builds jackknife replicate weights by deleting one PSU at a time and
  re-running the whole recipe on each replicate, so the replicate
  weights carry the variability of every adjustment. It is the
  stratified jackknife (JKn) with `strata`/`psu`, the unstratified
  jackknife (JK1) with `strata = NULL`, and the delete-one-unit
  jackknife with `psu = NULL`.
  [`jackknife_estimate()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)
  (plus
  [`jack_total()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)
  /
  [`jack_mean()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md))
  summarise a statistic with the JKn variance and match `survey`’s
  replicate jackknife for totals.
  [`as_svrepdesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
  now also accepts a jackknife object, so the recipe-aware replicate
  weights flow into `survey`/`srvyr` for any estimand and any domain.
- **Domain (partitioned) calibration in
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md).**
  A new `by` argument names a domain (partition) column; the weights are
  then calibrated **independently within each domain**, each to its own
  totals (partitioned / domain calibration). The tidy totals carry the
  domain as a column, and a continuous total becomes a data frame
  `domain, value` (one total per domain); the domain variable does not
  go in the formula/margins. It composes with `calfun`, `bounds`,
  `penalty` and `equal_within_cluster`, applied within each domain, and
  reproduces every domain’s benchmarks. `by = NULL` (default) calibrates
  globally, unchanged.
- **Exponential (raking) distance for
  `step_calibrate(method = "linear")`.** `calfun` now also accepts
  `"raking"` (the multiplicative distance g = exp(u)), next to
  `"linear"` and `"logit"`. It keeps the calibration weights positive
  without needing explicit `bounds` and still satisfies the constraints
  exactly, and works on mixed categorical and continuous auxiliaries as
  well as with the integrative option (`equal_within_cluster`, one
  weight per cluster). Matches `survey::calibrate(calfun = "raking")`.
- **R-indicator of response representativity (automatic diagnostic).**
  When the recipe includes a nonresponse adjustment,
  [`summary()`](https://rdrr.io/r/base/summary.html) and
  [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
  now report the R-indicator (Schouten, Cobben & Bethlehem), R = 1 -
  2\*S, with S the design-weighted standard deviation of the estimated
  response propensities over the eligible sample: closer to 1 means a
  more representative response and less nonresponse-bias risk. The
  report also shows the unconditional partial R-indicators by auxiliary,
  pointing to which variable drives the lack of representativity. It is
  computed on the auxiliaries of the nonresponse step and needs no new
  function or user action; recipes without a nonresponse step are
  unaffected.
- **New `disposition` column in the `sample_one` example data.** A
  single factor with the full field disposition (eligible respondent,
  eligible nonrespondent, household nonresponse, ineligible, unknown
  eligibility), recoded from the existing indicator columns (which are
  kept). It gives a tidy single-column view of the dispositions and can
  be used directly via logical conditions in the steps.
- **New vignette “Preparing the sample: eligibility and response before
  weighting”**, on how the input sample should be classified (the
  disposition tree), how it is sized (eligibility and response
  inflation) and how the dispositions map to the adjustment steps.
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
