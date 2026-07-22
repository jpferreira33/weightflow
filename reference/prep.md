# Estimate the weighting cascade

Walks the steps in the order they were added, starting from the base
weights. Each step multiplies the current weight by its adjustment
factor.

## Usage

``` r
prep(spec, min_cell_n = 30, max_factor = 2.5, warn = FALSE)
```

## Arguments

- spec:

  a weighting_spec.

- min_cell_n:

  integer. Minimum number of cases per adjustment cell (weighting class,
  poststratum). Cells below this raise a (non-fatal) warning
  recommending collapsing or switching to raking. Default 30, following
  Kalton and Flores-Cervantes (2003). Set to NULL to disable.

- max_factor:

  numeric. Adjustment factor above which a cell is flagged as excessive.
  Default 2.5. Set to NULL to disable.

- warn:

  logical. If TRUE, the quality alerts are also raised as R warnings
  during prep(). Default FALSE: alerts are always computed, stored on
  the object (`$alerts`) and shown in the HTML report, but not raised as
  warnings, so they do not flood bootstrap/jackknife replicate fits.

## Value

a "prepped_weighting_spec" object.

## Examples

``` r
rec <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region")
prep(rec)
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base      467    4371  0.236     1.056   442
#>  stage_1_step_nonresponse      270    4371  0.144     1.021   265
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
