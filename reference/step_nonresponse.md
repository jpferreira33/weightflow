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
  num_classes = 5L
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
