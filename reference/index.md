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

## Example data

- [`population`](https://jpferreira33.github.io/weightflow/reference/population.md)
  : Synthetic target population (sampling frame)
- [`sample_survey`](https://jpferreira33.github.io/weightflow/reference/sample_survey.md)
  : Synthetic person sample with a take-all household roster
- [`sample_one`](https://jpferreira33.github.io/weightflow/reference/sample_one.md)
  : Synthetic address sample with one selected person per household
