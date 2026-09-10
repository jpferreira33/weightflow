# Package index

## Overview

- [`weightflow`](https://jpferreira33.github.io/weightflow/reference/weightflow-package.md)
  [`weightflow-package`](https://jpferreira33.github.io/weightflow/reference/weightflow-package.md)
  : weightflow: declarative survey weighting
- [`weightflow-concepts`](https://jpferreira33.github.io/weightflow/reference/weightflow-concepts.md)
  : Conventions shared by every weightflow step
- [`weightflow-alerts`](https://jpferreira33.github.io/weightflow/reference/weightflow-alerts.md)
  : Quality alerts raised while preparing a recipe

## Build and run a recipe

Define the recipe, estimate it, and pull the weights out.

- [`weighting_spec()`](https://jpferreira33.github.io/weightflow/reference/weighting_spec.md)
  : Start a weighting specification
- [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
  : Estimate the weighting cascade
- [`weighting_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md)
  [`has_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md)
  : Quality alerts recorded while preparing a recipe
- [`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md)
  : Extract the data with the computed weights
- [`y_model()`](https://jpferreira33.github.io/weightflow/reference/y_model.md)
  : Specify a working model for a study variable y
- [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
  : Use a weighted survey as the calibration reference instead of a
  frame
- [`write_recipe()`](https://jpferreira33.github.io/weightflow/reference/write_recipe.md)
  : Write a weighting recipe to a YAML file
- [`read_recipe()`](https://jpferreira33.github.io/weightflow/reference/read_recipe.md)
  : Read a weighting recipe from a YAML file

## Adjustment steps

The staged adjustments, applied in the order you pipe them.

- [`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md)
  : Unknown-eligibility adjustment
- [`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md)
  : Drop ineligible (out-of-scope) units
- [`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md)
  : Within-cluster selection adjustment
- [`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md)
  : Second-phase subsampling (two-phase sampling)
- [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
  : Nonresponse adjustment
- [`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/reference/step_pseudoweight.md)
  : Pseudo-weights for a non-probability sample against a reference
- [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  : Calibration to population totals
- [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
  : Model-assisted calibration (Wu and Sitter 2001)
- [`step_trim()`](https://jpferreira33.github.io/weightflow/reference/step_trim.md)
  : Trim extreme weights against a ratio
- [`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md)
  : Automatic weight trimming to an absolute band
- [`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md)
  : Trimmed calibration (range-restricted, totals-preserving)
- [`step_round()`](https://jpferreira33.github.io/weightflow/reference/step_round.md)
  : Round the final weights
- [`step_rescale()`](https://jpferreira33.github.io/weightflow/reference/step_rescale.md)
  : Rescale the weights to a fixed sum
- [`step_assert()`](https://jpferreira33.github.io/weightflow/reference/step_assert.md)
  : Assert quality conditions on the weights
- [`step_nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/step_nr_sensitivity.md)
  : Sensitivity of a mean to nonignorable nonresponse or selection
- [`step_cross_sectional()`](https://jpferreira33.github.io/weightflow/reference/step_cross_sectional.md)
  [`step_longitudinal()`](https://jpferreira33.github.io/weightflow/reference/step_cross_sectional.md)
  : Declare the recipe's scope: cross-sectional or longitudinal weights
- [`step_panel_overlap()`](https://jpferreira33.github.io/weightflow/reference/step_panel_overlap.md)
  : Adjust base weights by the panel-selection probability (CEPAL ch.
  XVI)
- [`step_attrition()`](https://jpferreira33.github.io/weightflow/reference/step_attrition.md)
  : Attrition adjustment for panel waves
- [`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
  : Composite regression estimator (CRE / regression composite
  estimation)

## Diagnostics and reporting

Inspect, summarise and report the cascade.

- [`summary(`*`<prepped_weighting_spec>`*`)`](https://jpferreira33.github.io/weightflow/reference/summary.prepped_weighting_spec.md)
  : Detailed per-step diagnostics
- [`plot(`*`<prepped_weighting_spec>`*`)`](https://jpferreira33.github.io/weightflow/reference/plot.prepped_weighting_spec.md)
  : Diagnostic plots for the weights
- [`weight_factors()`](https://jpferreira33.github.io/weightflow/reference/weight_factors.md)
  : Per-unit adjustment factors table
- [`collect_propensities()`](https://jpferreira33.github.io/weightflow/reference/collect_propensities.md)
  : Recover the fitted response propensities of a nonresponse step
- [`collect_step_detail()`](https://jpferreira33.github.io/weightflow/reference/collect_step_detail.md)
  : Per-unit detail of one step of the cascade
- [`domain_summary()`](https://jpferreira33.github.io/weightflow/reference/domain_summary.md)
  : Per-domain weight summary at every stage of the cascade
- [`design_effect()`](https://jpferreira33.github.io/weightflow/reference/design_effect.md)
  : Kish design effect from unequal weighting
- [`data_defect()`](https://jpferreira33.github.io/weightflow/reference/data_defect.md)
  : Data-defect diagnostics for a non-probability sample
- [`disclosure_risk()`](https://jpferreira33.github.io/weightflow/reference/disclosure_risk.md)
  : Flag re-identification risk from outlier weights within a
  publication cell
- [`nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/nr_sensitivity.md)
  : Read the nonresponse-sensitivity analysis from a prepped recipe
- [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
  : Self-contained HTML quality report for a weighting recipe

## Variance estimation

Bootstrap and jackknife that re-apply the recipe, plus survey/srvyr
bridges.

- [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  : Recipe-aware bootstrap replicate weights
- [`two_phase_variance()`](https://jpferreira33.github.io/weightflow/reference/two_phase_variance.md)
  : Decompose a two-phase variance into V = V1 + V2
- [`bootstrap_estimate()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  [`boot_total()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  [`boot_mean()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  : Bootstrap estimate, standard error and confidence interval
- [`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)
  : Recipe-aware delete-a-PSU jackknife replicate weights
- [`jackknife_estimate()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)
  [`jack_total()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)
  [`jack_mean()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)
  : Jackknife estimate, standard error and confidence interval
- [`as_svydesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
  [`as_svrepdesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
  : Export weightflow weights to a survey design
- [`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_replicate_weights.md)
  : Collect replicate weights into a data frame ready for srvyr
- [`as_sae_input()`](https://jpferreira33.github.io/weightflow/reference/as_sae_input.md)
  : Direct estimates and design SEs per domain, ready for small-area
  estimation
- [`print(`*`<weightflow_boot>`*`)`](https://jpferreira33.github.io/weightflow/reference/print.weightflow_boot.md)
  : Print a bootstrap replicate-weight object
- [`print(`*`<weightflow_jack>`*`)`](https://jpferreira33.github.io/weightflow/reference/print.weightflow_jack.md)
  : Print a jackknife replicate-weight object

## Panels

Rotating and pure panels – structure, net change, chaining and gross
flows.

- [`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)
  : Describe the rotating-panel structure of a survey
- [`panel_merge()`](https://jpferreira33.github.io/weightflow/reference/panel_merge.md)
  : Build the wide longitudinal file from per-wave surveys
- [`panel_pr()`](https://jpferreira33.github.io/weightflow/reference/panel_pr.md)
  : Panel-selection probability for a set of combined waves
- [`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md)
  : Coordinated bootstrap across panel waves
- [`wave_jackknife()`](https://jpferreira33.github.io/weightflow/reference/wave_jackknife.md)
  : Coordinated delete-one jackknife across panel waves
- [`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md)
  [`change_mean()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md)
  [`change_total()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md)
  : Net change between two panel waves, with honest variance
- [`level_estimate()`](https://jpferreira33.github.io/weightflow/reference/level_estimate.md)
  [`level_mean()`](https://jpferreira33.github.io/weightflow/reference/level_estimate.md)
  [`level_total()`](https://jpferreira33.github.io/weightflow/reference/level_estimate.md)
  : Level estimate for a single panel wave, with its replicate variance
- [`panel_estimate()`](https://jpferreira33.github.io/weightflow/reference/panel_estimate.md)
  [`panel_mean()`](https://jpferreira33.github.io/weightflow/reference/panel_estimate.md)
  [`panel_total()`](https://jpferreira33.github.io/weightflow/reference/panel_estimate.md)
  : Linear combination of panel waves, with honest between-wave variance
- [`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
  : One period of a coordinated panel bootstrap, chained from the
  previous ones
- [`wave_carry()`](https://jpferreira33.github.io/weightflow/reference/wave_carry.md)
  : Extract the carry artifact of a period
- [`wave_contrast()`](https://jpferreira33.github.io/weightflow/reference/wave_contrast.md)
  : Linear combination of an estimand across a chain of periods
- [`transition_matrix()`](https://jpferreira33.github.io/weightflow/reference/transition_matrix.md)
  : Gross-flow transition matrix between two panel waves
- [`boot_transition()`](https://jpferreira33.github.io/weightflow/reference/boot_transition.md)
  : Transition matrix with per-cell bootstrap standard errors
- [`boot_flows()`](https://jpferreira33.github.io/weightflow/reference/boot_flows.md)
  : Gross-flow TOTALS with standard errors, plus net flows and margins
- [`report_panel()`](https://jpferreira33.github.io/weightflow/reference/report_panel.md)
  : Panel / longitudinal HTML report

## Estimation grammar

Declare domains and estimands once, read them off a saved replicate
object.

- [`step_domain()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md)
  [`step_filter()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md)
  [`step_estimate()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md)
  [`step_transition()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md)
  : Declarative estimation over a coordinated panel object
- [`collect_estimates()`](https://jpferreira33.github.io/weightflow/reference/collect_estimates.md)
  : Evaluate an estimation pipeline

## Example data

- [`population`](https://jpferreira33.github.io/weightflow/reference/population.md)
  : Synthetic target population (sampling frame)
- [`sample_survey`](https://jpferreira33.github.io/weightflow/reference/sample_survey.md)
  : Synthetic person sample with a take-all household roster
- [`sample_one`](https://jpferreira33.github.io/weightflow/reference/sample_one.md)
  : Synthetic address sample with one selected person per household
- [`panel_puro`](https://jpferreira33.github.io/weightflow/reference/panel_datasets.md)
  [`panel_cl`](https://jpferreira33.github.io/weightflow/reference/panel_datasets.md)
  [`panel_ine`](https://jpferreira33.github.io/weightflow/reference/panel_datasets.md)
  [`panel_us`](https://jpferreira33.github.io/weightflow/reference/panel_datasets.md)
  : Synthetic rotating- and pure-panel datasets
