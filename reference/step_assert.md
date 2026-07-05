# Assert conditions on the weights at this point of the cascade

A checkpoint that does NOT change the weights; it verifies conditions
and fails (error) or warns if they are not met. Useful to guard a
production pipeline (tidymodels-style tests inside the recipe).

## Usage

``` r
step_assert(
  spec,
  max_deff = NULL,
  max_weight_ratio = NULL,
  min_n_eff = NULL,
  on_fail = c("error", "warning")
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

## Value

The input `weighting_spec` with this checkpoint appended to its recipe.
The check is recorded only; it is evaluated when
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
is called and does not modify the weights.

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_assert(max_deff = 5, on_fail = "warning") |> prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. assert (checkpoint)
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
