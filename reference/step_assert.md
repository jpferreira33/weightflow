# Assert quality conditions on the weights

A checkpoint that leaves the weights untouched and instead verifies that
they meet quality thresholds at this point of the cascade, raising an
error or a warning when they do not. Use it to stop a production
pipeline before bad weights are published, in the spirit of a validation
step inside a recipe.

## Usage

``` r
step_assert(
  spec,
  max_deff = NULL,
  max_weight_ratio = NULL,
  min_n_eff = NULL,
  on_fail = c("error", "warning"),
  id = NULL
)
```

## Arguments

- spec:

  a weighting_spec.

- max_deff:

  numeric or NULL. Maximum acceptable Kish design effect.

- max_weight_ratio:

  numeric or NULL. Maximum allowed final/base weight ratio (per active
  unit).

- min_n_eff:

  numeric or NULL. Minimum acceptable effective sample size.

- on_fail:

  "error" (stop the cascade) or "warning".

- id:

  optional string: a stable identifier for this step, shown in the
  recipe print-out; defaults to a derived `"<class>_<k>"`.

## Value

The input `weighting_spec` with this checkpoint appended to its recipe.
The check is recorded only; it is evaluated when
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
is called and does not modify the weights.

## See also

Other weighting steps:
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md),
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md),
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md),
[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md),
[`step_nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/step_nr_sensitivity.md),
[`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/reference/step_pseudoweight.md),
[`step_rescale()`](https://jpferreira33.github.io/weightflow/reference/step_rescale.md),
[`step_round()`](https://jpferreira33.github.io/weightflow/reference/step_round.md),
[`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md),
[`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md),
[`step_trim()`](https://jpferreira33.github.io/weightflow/reference/step_trim.md),
[`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md),
[`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md),
[`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md)

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_assert(max_deff = 5, on_fail = "warning") |> prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. assert (checkpoint)  [assert_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                stage n_active sum_wts cv_wts deff_kish n_eff
#>                 base      467    4371  0.236     1.056   442
#>  stage_1_step_assert      467    4371  0.236     1.056   442
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
