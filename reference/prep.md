# Estimate the weighting cascade

Walks the steps in the order they were added, starting from the base
weights. Each step multiplies the current weight by its adjustment
factor.

## Usage

``` r
prep(spec)
```

## Arguments

- spec:

  a weighting_spec.

## Value

a "prepped_weighting_spec" object.

## Examples

``` r
rec <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region")
prep(rec)
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 1575 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base     1575   15182  0.229     1.053  1496
#>  stage_1_step_nonresponse      927   15182  0.195     1.038   893
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
