# Changelog

## weightflow 1.3.1 (in development)

### New features

- `step_round(method = "balanced")` takes `formula`, balancing on the
  calibration design rather than on the crossed cells of `by`.

- [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
  and
  [`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/reference/step_pseudoweight.md)
  take `by`, fitting and calibrating one domain at a time.

- [`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
  takes `n_groups`, so the equal-representation target comes from the
  design and not from the responding sample, and `rescale_previous` for
  a previous wave whose population differs from the current one.

- [`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)
  takes `groups` and `seed`, for a delete-a-group jackknife.

- `ci_type` and `df` on the estimation entry points, for Student t
  intervals when the design degrees of freedom are few.

- [`print()`](https://rdrr.io/r/base/print.html) on a bootstrap object
  reports the Monte Carlo error of its standard errors.

### Bug fixes

- Diagnostics and warnings across the pseudo-weighting, trimming,
  calibration and panel steps now fire in cases where they were silent,
  and several no longer claim more than the method delivers. Data values
  are escaped in the HTML report. Assorted documentation corrections.

## weightflow 1.3.0

CRAN release: 2026-09-11

### New features

- **Rotating and pure panels.**
  [`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)
  reads the unit x wave structure and the rotation calendar – and, given
  a `cluster`, the overlap at the cluster level too, which is the one
  the rotation calendar describes (the unit-level figure is that overlap
  net of within-household churn);
  [`panel_merge()`](https://jpferreira33.github.io/weightflow/reference/panel_merge.md)
  builds the longitudinal file;
  [`panel_pr()`](https://jpferreira33.github.io/weightflow/reference/panel_pr.md)
  and
  [`step_panel_overlap()`](https://jpferreira33.github.io/weightflow/reference/step_panel_overlap.md)
  apply the panel-selection probability;
  [`step_attrition()`](https://jpferreira33.github.io/weightflow/reference/step_attrition.md)
  is the panel-facing nonresponse adjustment and takes the full argument
  list of
  [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md),
  `crossfit` included; and
  [`step_longitudinal()`](https://jpferreira33.github.io/weightflow/reference/step_cross_sectional.md)
  /
  [`step_cross_sectional()`](https://jpferreira33.github.io/weightflow/reference/step_cross_sectional.md)
  declare which weight a recipe is building.

- **Net change with a coordinated variance.**
  [`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md)
  and
  [`wave_jackknife()`](https://jpferreira33.github.io/weightflow/reference/wave_jackknife.md)
  resample PSUs *coordinately* across waves, so the sample overlap shows
  up as covariance instead of being ignored.
  [`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md)
  (with
  [`change_mean()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md)
  /
  [`change_total()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md),
  absolute or relative, optionally by domain),
  [`level_estimate()`](https://jpferreira33.github.io/weightflow/reference/level_estimate.md)
  and `panel_estimate(contrast = )` read the estimates off those
  replicates. Both engines take `lonely_psu` as
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  does, because a stratum with a single PSU contributes no variance to a
  change either; the collapse map is built over all the waves at once so
  the replicate pairing survives it.

- **Chained production:
  [`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md),
  [`wave_carry()`](https://jpferreira33.github.io/weightflow/reference/wave_carry.md),
  [`wave_contrast()`](https://jpferreira33.github.io/weightflow/reference/wave_contrast.md).**
  One period at a time, as an office actually publishes: each run leaves
  a compact *carry* that the next one needs, and
  [`wave_contrast()`](https://jpferreira33.github.io/weightflow/reference/wave_contrast.md)
  estimates any linear combination over a chain (a rolling quarter, an
  annual average) from the saved carries alone.

- **Composite (regression composite) estimation:
  [`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md).**
  The MR1/MR2 estimator of the Canadian LFS and Uruguay’s ECH, including
  the equal-representation constraints across rotation groups, with
  `Zhat` re-estimated inside every replicate. The step reports the
  quality of the wave-to-wave link it depends on – the overlap rate, the
  births, and how many non-birth units failed to link – and warns when
  that failure rate gets high, because a broken linkage key attenuates
  the estimated change rather than announcing itself.

- **Gross flows.**
  [`transition_matrix()`](https://jpferreira33.github.io/weightflow/reference/transition_matrix.md),
  [`boot_transition()`](https://jpferreira33.github.io/weightflow/reference/boot_transition.md)
  and
  [`boot_flows()`](https://jpferreira33.github.io/weightflow/reference/boot_flows.md)
  give the weighted flow between states across waves, as conditional or
  joint distributions and as population totals with standard errors and
  net flows.

- **A declarative estimation grammar.**
  [`step_domain()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md),
  [`step_filter()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md),
  [`step_estimate()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md)
  and
  [`collect_estimates()`](https://jpferreira33.github.io/weightflow/reference/collect_estimates.md)
  run over a saved replicate object, so the expensive replicate build
  happens once and many estimates are read off it. Units whose domain
  value is missing are reported rather than quietly dropped, so it is
  visible when the cells will not add up to the overall figure. Every
  verb of the statistic DSL validates its arguments against the wave
  data, because a replicate object will put a standard error and a
  confidence interval on whatever number it is handed: an estimand must
  give one numeric or logical value per unit (so `prop()` takes a
  condition, `prop(status == "unemployed")`, and refuses a factor rather
  than averaging its integer codes), `p` in `quantile(var, p)` must be a
  probability in `[0, 1]` (`0.5`, not `50`), `level` must be a
  proportion, and `ratio(num, den)` is taken over the domain where both
  are observed – matching `survey::svyratio(na.rm = TRUE)` exactly –
  rather than dropping the missing rows of each sum independently. A
  domain column may not be named after one of the result table’s own
  columns.

- **[`report_panel()`](https://jpferreira33.github.io/weightflow/reference/report_panel.md)**,
  a self-contained HTML quality report for a panel run, and new panel
  alerts (`PN-01`, `PN-02`, `PN-06`, `PN-07`, `PN-08`) plus an alert
  when a nonresponse adjustment stops preserving the eligible total.

- **Exact multinomial PSU resampling** is the default in the panel
  engines (`resample = "multinom"`): the per-stratum resample counts sum
  to `m_h`, which removes an ~8-10% inflation of the composite change SE
  seen in simulation. Within a stratum the PSUs are ordered by how many
  waves they appear in, so the units that carry the overlap get the
  exactly-coordinated draws and the answer does not depend on which PSU
  ids happen to rotate out.

- Smaller additions: `bounds` and `calfun` for
  [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md),
  [`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md)
  after a model-calibration step, and `refit_steps` to choose which
  steps are re-run per replicate.

- Four new vignettes: *Rotating panels*, *Pure panels*, *Coordinated
  replication* and *Composite estimation*. The change variance is now
  also validated against an analytic estimator from a different family
  (Berger and Priam 2016, via `ReGenesees::svyDelta()`), with the
  reference values frozen in the test suite.

### Bug fixes

These are fixes against **1.2.0 as published**. The panel layer is new
in this release, so nothing about it appears here: what it does and what
it checks is described under New features.

- Response-propensity models could diverge under production design
  weights: a binomial GLM reads the prior weights as the number of
  trials, so large design weights started the fit at the separation
  boundary and the fitted propensities collapsed. Model weights are now
  normalized to mean 1 wherever a weighted binomial model is fitted,
  which leaves the estimates invariant.

- **Recipe files are safe to exchange.**
  [`read_recipe()`](https://jpferreira33.github.io/weightflow/reference/read_recipe.md)
  accepts only a whitelist of data-manipulation calls in the conditions
  and formulas a recipe stores, unless `allow_code = TRUE`; before, a
  hand-edited condition still ran on the first
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md).
  And
  [`write_recipe()`](https://jpferreira33.github.io/weightflow/reference/write_recipe.md)
  no longer serializes a `population =` data frame value by value: it is
  stored as a descriptor and asked back through `references =`, as
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
  already was.

- Adjustment cells are keyed unambiguously. A `by` value containing the
  `" | "` separator, or equal to the `"(missing)"` sentinel, used to
  collapse two different cells into one – with the wrong adjustment
  factor for both, and the “cell with no respondents” alert suppressed
  because the empty half was absorbed by the full one.

- Two publication gates that failed open are closed:
  [`disclosure_risk()`](https://jpferreira33.github.io/weightflow/reference/disclosure_risk.md)
  silently skipped cells with a missing value or a non-positive median
  weight, leaving those units out of the screen for weight dominance,
  and
  [`as_sae_input()`](https://jpferreira33.github.io/weightflow/reference/as_sae_input.md)
  rated both a missing-domain area and a zero-variance domain as
  publishable.

- `step_round("preserve_total")` breaks ties in the fractional part at
  random rather than by row order, which was moving mass systematically
  towards whatever the file was sorted by while reporting the grand
  total as preserved. Call
  [`set.seed()`](https://rdrr.io/r/base/Random.html) before
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
  for a reproducible result, as `method = "balanced"` already required.

- The model-assisted and propensity steps are steadier under
  cross-fitting: whether a
  [`y_model()`](https://jpferreira33.github.io/weightflow/reference/y_model.md)
  is a regression or a classification is decided once over the whole
  sample instead of inside each fold (and an explicit `family` is
  respected), propensities at the 0/1 boundary warn instead of being
  clamped in silence, and a fold whose training set has only respondents
  says so rather than failing inside the model engine.

- The HTML reports describe the active weights, negatives included, in
  the weight-distribution card and the matching Status check; a column
  name containing a space no longer aborts the whole report; and the
  trimming note names the direction the weight total moved when the
  bounds could not be met.

- [`boot_total()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  warns that the two-phase total variance is conservative, which it was
  silently before, and the wave engines reject `NA` or blank in `strata`
  / `psu`, as
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  has since 1.2.0 – those rows paste into one design key and were
  resampled as a single pseudo-PSU, understating the variance.

- Stricter validation and robustness fixes for degenerate and edge-case
  inputs across the cascade, trimming and the auxiliary outputs, each
  with a regression test.

## weightflow 1.2.0

CRAN release: 2026-08-30

### New features

- **Two-phase (double) sampling.**
  [`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md)
  records a second phase and the bootstrap returns the variance split
  into its two components (`V = V1 + V2`).
- **Non-probability samples.**
  [`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/reference/step_pseudoweight.md)
  (pseudo-weighting, mass imputation and doubly robust estimators),
  [`step_nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/step_nr_sensitivity.md)
  for nonignorable nonresponse, and
  [`data_defect()`](https://jpferreira33.github.io/weightflow/reference/data_defect.md)
  for the Meng (2018) view.
- **Calibrate to a reference survey** with
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md),
  propagating the reference’s own sampling error.
- **Recipes as files.**
  [`write_recipe()`](https://jpferreira33.github.io/weightflow/reference/write_recipe.md)
  /
  [`read_recipe()`](https://jpferreira33.github.io/weightflow/reference/read_recipe.md)
  serialize the method (not the data) to a versionable YAML manifest.
- **Confidentiality and hand-off.**
  `collect_replicate_weights(scramble = TRUE)`,
  [`disclosure_risk()`](https://jpferreira33.github.io/weightflow/reference/disclosure_risk.md),
  and
  [`as_sae_input()`](https://jpferreira33.github.io/weightflow/reference/as_sae_input.md)
  for small-area models.
- **Quality control.**
  [`weighting_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md)
  /
  [`has_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md)
  as a single programmatic channel, `domain_summary(min_n_eff = )` as an
  explicit publication gate, and stable `id`s on every step.
- **Finite-population correction** (`fpc`) and `t` / percentile
  confidence intervals in the replicate estimators.

### Bug fixes

- Cells for `by`-based steps are now built over the units still active,
  so units dropped earlier no longer raise spurious `(missing)` cells.
- **Behaviour change:** the mean estimators and replicate-weight exports
  keep active negative weights (a valid GREG output), matching the
  totals estimators and `survey`.
- Stricter, earlier argument validation across the step constructors and
  estimators, plus robustness fixes for malformed and edge-case inputs,
  each with a regression test.
- Documentation: `?weightflow-concepts` (argument correspondence with
  `survey`) and `?weightflow-alerts` (the alert catalogue).

## weightflow 1.1.0

CRAN release: 2026-08-19

### New features

- **Diagnostics report suite.**
  [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
  gains a per-step card reading the bias-variance trade-off of each
  adjustment, with quality alerts.
- **Honest variance for machine-learning adjustments**: a flexible
  learner run without `crossfit` now raises an alert.
- **Inspection accessors**:
  [`collect_propensities()`](https://jpferreira33.github.io/weightflow/reference/collect_propensities.md),
  [`collect_step_detail()`](https://jpferreira33.github.io/weightflow/reference/collect_step_detail.md)
  and
  [`domain_summary()`](https://jpferreira33.github.io/weightflow/reference/domain_summary.md).
- **Per-subgroup trimming** (`by` in
  [`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md)),
  and jackknife export through
  [`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_replicate_weights.md).
- Adding a step to a prepped recipe now clears the results, so stale
  weights cannot be read by accident.

### Bug fixes and documentation

- Robustness and correctness fixes for edge cases in the cascade, the
  replicate variance and the HTML report, each covered by a regression
  test.
- Help pages reviewed and rewritten, with estimator formulas in the
  details.

## weightflow 1.0.0

CRAN release: 2026-08-04

### New features

- **Nonresponse by calibration**
  (`step_nonresponse(method = "calibration")`) and unweighted propensity
  models (`weight_model = FALSE`).
- **Trimmed calibration**
  ([`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md)):
  trim calibrated weights into an absolute interval while preserving the
  calibration totals.
- **Tidy control totals that disagree on N now reconcile** instead of
  failing, with a message naming the rescaling.
- **Lonely-PSU handling and parallelism** in
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  and
  [`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md),
  and a `redistribute` argument for
  [`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md).
- **[`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
  becomes a full methodological quality report** (GSBPM 5.6 / ESS
  style), with a narrative mode, a per-domain reliability card and new
  charts.

### Bug fixes

- Cross-fitting no longer errors in a fresh session,
  [`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md)
  now trims negative weights, and the report’s before/after scatter is
  reproducible.

## weightflow 0.2.0

CRAN release: 2026-07-22

### New features

- **Tidy population totals** for
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md),
  alongside the classic `margins`/`totals` inputs.
- **Domain (partitioned) calibration** (`by`) and the **exponential
  (raking) distance** (`calfun = "raking"`) for linear calibration.
- **Delete-a-PSU jackknife** variance, recipe-aware like the bootstrap.
- **Machine-learning response propensities** (CART, random forest,
  xgboost) with **k-fold cross-fitting**, **ridge (penalized)
  calibration**, and **Potter MSE-optimal trimming**.
- **Quality alerts in
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)**,
  an **R-indicator** of response representativity, and a
  weight-distribution summary in the report.
- Subsampling more than one person per household (`n_selected`),
  external consistency totals for model calibration (`x_totals`), and a
  new vignette on preparing the sample.

### Bug fixes

- The optional machine-learning engines now run single-threaded by
  default, for reproducibility and to respect CRAN core limits.
- [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
  flags calibration steps that did not converge.
- `step_calibrate(equal_within_cluster = TRUE)` now implements the
  genuine Lemaitre-Dufour (1987) integrative method.

## weightflow 0.1.0

CRAN release: 2026-06-30

First release. The weighting cascade as a declarative recipe:

- **Adjustment steps**:
  [`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md),
  [`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md),
  [`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md),
  [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md),
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  (raking, post-stratification, linear/GREG, bounded and integrative),
  [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md),
  [`step_trim()`](https://jpferreira33.github.io/weightflow/reference/step_trim.md),
  [`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md),
  [`step_round()`](https://jpferreira33.github.io/weightflow/reference/step_round.md),
  [`step_rescale()`](https://jpferreira33.github.io/weightflow/reference/step_rescale.md)
  and
  [`step_assert()`](https://jpferreira33.github.io/weightflow/reference/step_assert.md).
- **Inspection and reporting**:
  [`summary()`](https://rdrr.io/r/base/summary.html),
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html),
  [`weight_factors()`](https://jpferreira33.github.io/weightflow/reference/weight_factors.md),
  [`design_effect()`](https://jpferreira33.github.io/weightflow/reference/design_effect.md)
  and a self-contained HTML report from
  [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md).
- **Variance estimation**:
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  (Rao-Wu rescaling, re-applying the whole recipe on each replicate),
  [`boot_mean()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  /
  [`boot_total()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md),
  and bridges to `survey` / `srvyr` through
  [`as_svydesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md),
  [`as_svrepdesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
  and
  [`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_replicate_weights.md).
- **Example data**: `population`, `sample_survey` and `sample_one`.
