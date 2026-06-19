# Nonresponse adjustment

Nonresponse adjustment

## Usage

``` r
step_nonresponse(
  spec,
  respondent,
  method = c("weighting_class", "propensity"),
  by = NULL,
  formula = NULL,
  engine = c("logit", "tree", "forest"),
  num_classes = 5L,
  cluster = NULL
)
```

## Arguments

- spec:

  a weighting_spec.

- respondent:

  a 0/1 dummy column (1 = responded) or any logical condition (unquoted)
  TRUE for respondents. Eligible cases that are not respondents are
  treated as nonresponse.

- method:

  "weighting_class" (cells) or "propensity" (predictive model).

- by:

  character. Adjustment cells for method = "weighting_class".

- formula:

  predictor formula (right-hand side only), e.g. ~ age + region, used
  when method = "propensity".

- engine:

  engine to estimate the propensity when method = "propensity": "logit"
  (logistic regression, base R), "tree" (CART via package 'rpart') or
  "forest" (random forest via package 'ranger'). 'rpart' and 'ranger'
  are optional: only needed if you pick that engine.

- num_classes:

  integer or NULL. Controls how propensities are used: an integer forms
  that many propensity classes (cell adjustment within each class); NULL
  applies the direct factor 1/p to each unit.

- cluster:

  character or NULL. If given, the adjustment is done at the cluster
  (e.g. household) level for whole-household nonresponse: each household
  counts once with its (uniform) weight; in "weighting_class" the
  redistribution is between responding and nonresponding households
  within the cells, and in "propensity" the model is fitted with one row
  per household (household auxiliaries), predicting the household
  response. The resulting factor is assigned to every member;
  nonresponding households go to zero. As always, only active units
  (weight \> 0) take part, so units already dropped (unknown
  eligibility, ineligible) are excluded automatically.

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = "region")
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)
#> Status  : not estimated
#> 

# household-level nonresponse (whole household responds or not)
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = "region", cluster = "household_id") |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class, by household_id)
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base      467    4371  0.236     1.056   442
#>  stage_1_step_nonresponse      111    3047  0.253     1.064   104
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
