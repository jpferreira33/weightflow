# Changelog

## weightflow 1.3.0

### New features

- **Rotating and pure panels.**
  [`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)
  reads the unit x wave structure and the rotation calendar;
  [`panel_merge()`](https://jpferreira33.github.io/weightflow/reference/panel_merge.md)
  builds the longitudinal file;
  [`panel_pr()`](https://jpferreira33.github.io/weightflow/reference/panel_pr.md)
  and
  [`step_panel_overlap()`](https://jpferreira33.github.io/weightflow/reference/step_panel_overlap.md)
  apply the panel-selection probability;
  [`step_attrition()`](https://jpferreira33.github.io/weightflow/reference/step_attrition.md)
  is the panel-facing nonresponse adjustment; and
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
  replicates.

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
  `Zhat` re-estimated inside every replicate.

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
  happens once and many estimates are read off it.

- **[`report_panel()`](https://jpferreira33.github.io/weightflow/reference/report_panel.md)**,
  a self-contained HTML quality report for a panel run, and new panel
  alerts (`PN-01` to `PN-07`) plus an alert when a nonresponse
  adjustment stops preserving the eligible total.

- **Exact multinomial PSU resampling** is now the default in the panel
  engines (`resample = "multinom"`): the per-stratum resample counts sum
  to `m_h`, which removes an ~8-10% inflation of the composite change SE
  seen in simulation.

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

- **Response-propensity models diverged under production design weights
  (NR-PROP-01).** In a binomial GLM the prior weights are the *number of
  trials*, so large design weights pushed the starting values to the
  boundary and the fitted propensities collapsed. Model weights are now
  normalized to mean 1 (which leaves the estimates invariant) wherever a
  weighted binomial model is fitted. Recipes with a high response rate
  and large weights could produce materially wrong adjustments; the fix
  is covered by a regression test that fails on the old code.

- **The rotation-pattern parser misread several real designs**,
  including the CPS `4-8-4` form and the ECLAC `n(m)k` form. Patterns
  are now expanded into a full calendar and an overlap profile by lag,
  not just the adjacent lag.

- **[`read_recipe()`](https://jpferreira33.github.io/weightflow/reference/read_recipe.md)
  no longer executes code from a recipe file by default**, and
  [`write_recipe()`](https://jpferreira33.github.io/weightflow/reference/write_recipe.md)
  no longer serializes the previous wave’s microdata for a
  [`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
  recipe.

- The single-sample
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  /
  [`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)
  now warn on a
  [`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
  recipe, and
  [`boot_total()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  warns that the two-phase total variance is conservative: both were
  silently anticonservative or conservative before.

- A round of validation and robustness fixes across calibration,
  trimming, nonresponse, the machine-learning engines and the HTML
  reports – degenerate cells, empty factor levels, non-numeric or
  incomplete control totals, lost weight mass, and report claims that
  were not actually checked. Each is covered by a regression test.

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
