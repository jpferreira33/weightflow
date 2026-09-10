# weightflow 1.3.0

## New features

* **Rotating and pure panels.** `panel_design()` reads the unit x wave structure and
  the rotation calendar; `panel_merge()` builds the longitudinal file;
  `panel_pr()` and `step_panel_overlap()` apply the panel-selection probability;
  `step_attrition()` is the panel-facing nonresponse adjustment; and
  `step_longitudinal()` / `step_cross_sectional()` declare which weight a recipe is
  building.

* **Net change with a coordinated variance.** `wave_bootstrap()` and
  `wave_jackknife()` resample PSUs *coordinately* across waves, so the sample
  overlap shows up as covariance instead of being ignored. `change_estimate()`
  (with `change_mean()` / `change_total()`, absolute or relative, optionally by
  domain), `level_estimate()` and `panel_estimate(contrast = )` read the estimates
  off those replicates.

* **Chained production: `wave_step()`, `wave_carry()`, `wave_contrast()`.** One
  period at a time, as an office actually publishes: each run leaves a compact
  *carry* that the next one needs, and `wave_contrast()` estimates any linear
  combination over a chain (a rolling quarter, an annual average) from the saved
  carries alone.

* **Composite (regression composite) estimation: `step_cre()`.** The MR1/MR2
  estimator of the Canadian LFS and Uruguay's ECH, including the equal-representation
  constraints across rotation groups, with `Zhat` re-estimated inside every
  replicate.

* **Gross flows.** `transition_matrix()`, `boot_transition()` and `boot_flows()`
  give the weighted flow between states across waves, as conditional or joint
  distributions and as population totals with standard errors and net flows.

* **A declarative estimation grammar.** `step_domain()`, `step_filter()`,
  `step_estimate()` and `collect_estimates()` run over a saved replicate object, so
  the expensive replicate build happens once and many estimates are read off it.

* **`report_panel()`**, a self-contained HTML quality report for a panel run, and
  new panel alerts (`PN-01` to `PN-07`) plus an alert when a nonresponse adjustment
  stops preserving the eligible total.

* **Exact multinomial PSU resampling** is now the default in the panel engines
  (`resample = "multinom"`): the per-stratum resample counts sum to `m_h`, which
  removes an ~8-10% inflation of the composite change SE seen in simulation.

* Smaller additions: `bounds` and `calfun` for `step_model_calibration()`,
  `step_trim_calibrated()` after a model-calibration step, and `refit_steps` to
  choose which steps are re-run per replicate.

* Four new vignettes: *Rotating panels*, *Pure panels*, *Coordinated replication*
  and *Composite estimation*. The change variance is now also validated against an
  analytic estimator from a different family (Berger and Priam 2016, via
  `ReGenesees::svyDelta()`), with the reference values frozen in the test suite.

## Bug fixes

* **Response-propensity models diverged under production design weights
  (NR-PROP-01).** In a binomial GLM the prior weights are the *number of trials*, so
  large design weights pushed the starting values to the boundary and the fitted
  propensities collapsed. Model weights are now normalized to mean 1 (which leaves
  the estimates invariant) wherever a weighted binomial model is fitted. Recipes
  with a high response rate and large weights could produce materially wrong
  adjustments; the fix is covered by a regression test that fails on the old code.

* **The rotation-pattern parser misread several real designs**, including the CPS
  `4-8-4` form and the ECLAC `n(m)k` form. Patterns are now expanded into a full
  calendar and an overlap profile by lag, not just the adjacent lag.

* **`read_recipe()` no longer executes code from a recipe file by default**, and
  `write_recipe()` no longer serializes the previous wave's microdata for a
  `step_cre()` recipe.

* The single-sample `bootstrap_weights()` / `jackknife_weights()` now warn on a
  `step_cre()` recipe, and `boot_total()` warns that the two-phase total variance is
  conservative: both were silently anticonservative or conservative before.

* A round of validation and robustness fixes across calibration, trimming,
  nonresponse, the machine-learning engines and the HTML reports -- degenerate
  cells, empty factor levels, non-numeric or incomplete control totals, lost weight
  mass, and report claims that were not actually checked. Each is covered by a
  regression test.

# weightflow 1.2.0

## New features

* **Two-phase (double) sampling.** `step_subsample()` records a second phase and the
  bootstrap returns the variance split into its two components (`V = V1 + V2`).
* **Non-probability samples.** `step_pseudoweight()` (pseudo-weighting, mass
  imputation and doubly robust estimators), `step_nr_sensitivity()` for
  nonignorable nonresponse, and `data_defect()` for the Meng (2018) view.
* **Calibrate to a reference survey** with `reference_sample()`, propagating the
  reference's own sampling error.
* **Recipes as files.** `write_recipe()` / `read_recipe()` serialize the method (not
  the data) to a versionable YAML manifest.
* **Confidentiality and hand-off.** `collect_replicate_weights(scramble = TRUE)`,
  `disclosure_risk()`, and `as_sae_input()` for small-area models.
* **Quality control.** `weighting_alerts()` / `has_alerts()` as a single programmatic
  channel, `domain_summary(min_n_eff = )` as an explicit publication gate, and
  stable `id`s on every step.
* **Finite-population correction** (`fpc`) and `t` / percentile confidence intervals
  in the replicate estimators.

## Bug fixes

* Cells for `by`-based steps are now built over the units still active, so units
  dropped earlier no longer raise spurious `(missing)` cells.
* **Behaviour change:** the mean estimators and replicate-weight exports keep active
  negative weights (a valid GREG output), matching the totals estimators and
  `survey`.
* Stricter, earlier argument validation across the step constructors and
  estimators, plus robustness fixes for malformed and edge-case inputs, each with a
  regression test.
* Documentation: `?weightflow-concepts` (argument correspondence with `survey`) and
  `?weightflow-alerts` (the alert catalogue).

# weightflow 1.1.0

## New features

* **Diagnostics report suite.** `report_weighting()` gains a per-step card reading
  the bias-variance trade-off of each adjustment, with quality alerts.
* **Honest variance for machine-learning adjustments**: a flexible learner run
  without `crossfit` now raises an alert.
* **Inspection accessors**: `collect_propensities()`, `collect_step_detail()` and
  `domain_summary()`.
* **Per-subgroup trimming** (`by` in `step_trim_calibrated()`), and jackknife export
  through `collect_replicate_weights()`.
* Adding a step to a prepped recipe now clears the results, so stale weights cannot
  be read by accident.

## Bug fixes and documentation

* Robustness and correctness fixes for edge cases in the cascade, the replicate
  variance and the HTML report, each covered by a regression test.
* Help pages reviewed and rewritten, with estimator formulas in the details.

# weightflow 1.0.0

## New features

* **Nonresponse by calibration** (`step_nonresponse(method = "calibration")`) and
  unweighted propensity models (`weight_model = FALSE`).
* **Trimmed calibration** (`step_trim_calibrated()`): trim calibrated weights into an
  absolute interval while preserving the calibration totals.
* **Tidy control totals that disagree on N now reconcile** instead of failing, with
  a message naming the rescaling.
* **Lonely-PSU handling and parallelism** in `bootstrap_weights()` and
  `jackknife_weights()`, and a `redistribute` argument for `step_trim_weights()`.
* **`report_weighting()` becomes a full methodological quality report** (GSBPM 5.6 /
  ESS style), with a narrative mode, a per-domain reliability card and new charts.

## Bug fixes

* Cross-fitting no longer errors in a fresh session, `step_trim_weights()` now trims
  negative weights, and the report's before/after scatter is reproducible.

# weightflow 0.2.0

## New features

* **Tidy population totals** for `step_calibrate()`, alongside the classic
  `margins`/`totals` inputs.
* **Domain (partitioned) calibration** (`by`) and the **exponential (raking)
  distance** (`calfun = "raking"`) for linear calibration.
* **Delete-a-PSU jackknife** variance, recipe-aware like the bootstrap.
* **Machine-learning response propensities** (CART, random forest, xgboost) with
  **k-fold cross-fitting**, **ridge (penalized) calibration**, and **Potter
  MSE-optimal trimming**.
* **Quality alerts in `prep()`**, an **R-indicator** of response representativity,
  and a weight-distribution summary in the report.
* Subsampling more than one person per household (`n_selected`), external
  consistency totals for model calibration (`x_totals`), and a new vignette on
  preparing the sample.

## Bug fixes

* The optional machine-learning engines now run single-threaded by default, for
  reproducibility and to respect CRAN core limits.
* `report_weighting()` flags calibration steps that did not converge.
* `step_calibrate(equal_within_cluster = TRUE)` now implements the genuine
  Lemaitre-Dufour (1987) integrative method.

# weightflow 0.1.0

First release. The weighting cascade as a declarative recipe:

* **Adjustment steps**: `step_unknown_eligibility()`, `step_drop_ineligible()`,
  `step_select_within()`, `step_nonresponse()`, `step_calibrate()` (raking,
  post-stratification, linear/GREG, bounded and integrative),
  `step_model_calibration()`, `step_trim()`, `step_trim_weights()`, `step_round()`,
  `step_rescale()` and `step_assert()`.
* **Inspection and reporting**: `summary()`, `plot()`, `weight_factors()`,
  `design_effect()` and a self-contained HTML report from `report_weighting()`.
* **Variance estimation**: `bootstrap_weights()` (Rao-Wu rescaling, re-applying the
  whole recipe on each replicate), `boot_mean()` / `boot_total()`, and bridges to
  `survey` / `srvyr` through `as_svydesign()`, `as_svrepdesign()` and
  `collect_replicate_weights()`.
* **Example data**: `population`, `sample_survey` and `sample_one`.
