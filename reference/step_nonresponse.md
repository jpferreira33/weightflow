# Nonresponse adjustment

Inflates the weights of respondents to represent the nonrespondents,
under the assumption that response is ignorable given the information
used. The response propensity can be estimated by weighting classes
(cells) or by a model ("propensity"), with engines ranging from logistic
regression to machine learning (regression tree, random forest, gradient
boosting). Optional K-fold cross-fitting estimates the propensity
out-of-sample to avoid the overfitting that flexible engines can
introduce. The adjustment can be applied at the person or, via
`cluster`, the household level.

## Usage

``` r
step_nonresponse(
  spec,
  respondent,
  method = c("weighting_class", "propensity"),
  by = NULL,
  formula = NULL,
  engine = c("logit", "tree", "forest", "boost"),
  num_classes = 5L,
  cluster = NULL,
  crossfit = NULL,
  crossfit_seed = NULL
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
  (logistic regression, base R), "tree" (CART via package 'rpart'),
  "forest" (random forest via package 'ranger') or "boost" (gradient
  boosting via package 'xgboost'). 'rpart', 'ranger' and 'xgboost' are
  optional: only needed if you pick that engine.

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

- crossfit:

  integer or NULL. If given (number of folds K \>= 2), the propensity is
  estimated by K-fold cross-fitting: for each fold the model is trained
  on the other folds and used to predict the held-out fold, so each
  unit's propensity comes from a model that did not see it. This avoids
  the overfitting that flexible engines (forest, boost) can produce,
  which would otherwise inflate the weights. Folds are formed by
  `cluster` when given (so correlated units stay together). NULL
  (default) fits and predicts in-sample.

- crossfit_seed:

  integer or NULL. Seed for reproducible fold assignment when `crossfit`
  is used.

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
# propensity with cross-fitting (out-of-sample, avoids overfitting)
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "propensity",
                   formula = ~ region + sex, engine = "logit",
                   num_classes = 5, crossfit = 5, crossfit_seed = 1) |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (propensity: logit, 5 classes)
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base      467    4371  0.236     1.056   442
#>  stage_1_step_nonresponse      270    4371  0.203     1.041   259
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 

# gradient boosting engine (requires the 'xgboost' package)
if (requireNamespace("xgboost", quietly = TRUE)) {
  weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "propensity",
                     formula = ~ region + sex + age, engine = "boost",
                     num_classes = 5, crossfit = 5) |>
    prep()
}
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (propensity: boost, 5 classes)
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base      467    4371  0.236     1.056   442
#>  stage_1_step_nonresponse      270    4371  0.252     1.063   254
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
