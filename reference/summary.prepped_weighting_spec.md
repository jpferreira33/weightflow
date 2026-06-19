# Detailed per-step diagnostics

Detailed per-step diagnostics

## Usage

``` r
# S3 method for class 'prepped_weighting_spec'
summary(object, ...)
```

## Arguments

- object:

  a prepped object (output of prep()).

- ...:

  ignored.

## Value

(invisibly) the prepped object.

## Examples

``` r
fitted <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  prep()
summary(fitted)
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
#> --- Step 1: nonresponse (weighting class) ---
#>   cell n_respondents n_nonresponse   factor
#>   East           186           114 1.612903
#>  North           282           187 1.663121
#>  South           266           168 1.631579
#>   West           193           179 1.927461
#> Kish deff: 1.053 -> 1.038   |   n_eff: 1496 -> 893
#> 
```
