# Round the final weights

Optional step, typically the last one (after calibration). Simple
rounding ("nearest") slightly breaks the calibrated totals;
"preserve_total" uses the largest-remainder method to keep the exact
total.

## Usage

``` r
step_round(spec, digits = 0L, method = c("nearest", "preserve_total"))
```

## Arguments

- spec:

  a weighting_spec.

- digits:

  integer. Decimals to keep (0 = integers).

- method:

  "nearest" (simple rounding) or "preserve_total" (keeps the sum of
  weights). Note: "preserve_total" can break equality of weights within
  a cluster; if you need integer and equal weights per household, use
  "nearest".

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_round(digits = 0) |> prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. rounding (nearest, 0 decimals)
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>               stage n_active sum_wts cv_wts deff_kish n_eff
#>                base      467    4371  0.236     1.056   442
#>  stage_1_step_round      467    4323  0.211     1.045   447
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
