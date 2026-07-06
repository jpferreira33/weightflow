# Package index

## Overview

- [`weightflow`](https://jpferreira33.github.io/weightflow/reference/weightflow-package.md)
  [`weightflow-package`](https://jpferreira33.github.io/weightflow/reference/weightflow-package.md)
  : weightflow: declarative survey weighting

## Build and run a recipe

Define the recipe, estimate it, and pull the weights out.

- [`weighting_spec()`](https://jpferreira33.github.io/weightflow/reference/weighting_spec.md)
  : Start a weighting specification
- [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
  : Estimate the weighting cascade
- [`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md)
  : Extract the data with the computed weights
- [`y_model()`](https://jpferreira33.github.io/weightflow/reference/y_model.md)
  : Specify a working model for a study variable y

## Adjustment steps

The staged adjustments, applied in the order you pipe them.

- [`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md)
  : Unknown-eligibility adjustment
- [`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md)
  : Drop ineligible (out-of-scope) units
- [`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md)
  : Within-household selection adjustment
- [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
  : Nonresponse adjustment
- [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  : Calibration to population totals
- [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
  : Model calibration (model-assisted, Wu & Sitter 2001)
- [`step_trim()`](https://jpferreira33.github.io/weightflow/reference/step_trim.md)
  : Trim extreme weights
- [`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md)
  : Automatic weight trimming (survey-style)
- [`step_round()`](https://jpferreira33.github.io/weightflow/reference/step_round.md)
  : Round the final weights
- [`step_rescale()`](https://jpferreira33.github.io/weightflow/reference/step_rescale.md)
  : Rescale (normalize) the weights
- [`step_assert()`](https://jpferreira33.github.io/weightflow/reference/step_assert.md)
  : Assert conditions on the weights at this point of the cascade

## Diagnostics and reporting

Inspect, summarise and report the cascade.

- [`summary(`*`<prepped_weighting_spec>`*`)`](https://jpferreira33.github.io/weightflow/reference/summary.prepped_weighting_spec.md)
  : Detailed per-step diagnostics
- [`plot(`*`<prepped_weighting_spec>`*`)`](https://jpferreira33.github.io/weightflow/reference/plot.prepped_weighting_spec.md)
  : Diagnostic plots for the weights
- [`weight_factors()`](https://jpferreira33.github.io/weightflow/reference/weight_factors.md)
  : Per-unit adjustment factors table
- [`design_effect()`](https://jpferreira33.github.io/weightflow/reference/design_effect.md)
  : Kish design effect from unequal weighting
- [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
  : Build a nice HTML report of the weighting recipe

## Variance estimation

Bootstrap and jackknife that re-apply the recipe, plus survey/srvyr
bridges.

- [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  : Bootstrap replicate weights that re-apply the recipe
- [`bootstrap_estimate()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  [`boot_total()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  [`boot_mean()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  : Bootstrap estimate, standard error and confidence interval
- [`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)
  : Delete-a-PSU jackknife replicate weights that re-apply the recipe
- [`jackknife_estimate()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)
  [`jack_total()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)
  [`jack_mean()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)
  : Jackknife estimate, standard error and confidence interval
- [`as_svydesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
  [`as_svrepdesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
  : Export weightflow weights to a survey design
- [`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_replicate_weights.md)
  : Collect replicate weights into a data frame ready for srvyr

## Example data

- [`population`](https://jpferreira33.github.io/weightflow/reference/population.md)
  : Example target population for weightflow
- [`sample_survey`](https://jpferreira33.github.io/weightflow/reference/sample_survey.md)
  : Example survey sample (take-all roster)
- [`sample_one`](https://jpferreira33.github.io/weightflow/reference/sample_one.md)
  : Example survey sample (select-one-person, multistage)
