# Detailed per-step diagnostics

Prints the full audit of an estimated recipe: the stage-by-stage
evolution of the weights, then one block per step with that step's own
diagnostics table and the design effect before and after it, and finally
the R-indicator when the recipe adjusted for nonresponse. Where
[`print()`](https://rdrr.io/r/base/print.html) answers "what is in this
recipe?", [`summary()`](https://rdrr.io/r/base/summary.html) answers
"what did each step do, and what did it cost?".

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
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)  [nonresponse_1]
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
#> --- Step 1: nonresponse (weighting class) ---
#>   cell n_respondents n_nonresponse   factor
#>   East            52            44 1.846154
#>  North            78            41 1.525641
#>  South            72            49 1.680556
#>   West            68            63 1.926471
#> Kish deff: 1.056 -> 1.021   |   n_eff: 442 -> 265
#> 
#> R-indicator (representativity of response): 0.892  (on region)
```
