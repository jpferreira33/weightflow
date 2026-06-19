# Model calibration (model-assisted, Wu & Sitter 2001)

Fits a working model for each study variable y, predicts over the
population, and calibrates the weights so that the sample total of each
prediction equals its population total (model-assisted efficiency). It
also calibrates to the X totals (consistency with the auxiliary
controls).

## Usage

``` r
step_model_calibration(
  spec,
  x_formula,
  models,
  population,
  cluster = NULL,
  equal_within_cluster = FALSE
)
```

## Arguments

- spec:

  a weighting_spec.

- x_formula:

  formula of the consistency auxiliaries, e.g. ~ sex + region.

- models:

  named list of models created with y_model(). The names label the
  prediction constraints.

- population:

  population data.frame with the auxiliary and predictor columns (the y
  variables are not needed; they are predicted).

- cluster:

  name of the cluster id column (e.g. "household"), for equal weights
  within the cluster.

- equal_within_cluster:

  logical. If TRUE, integrative calibration: a single weight per
  cluster. Requires `cluster` and that the incoming weight be uniform
  within the cluster.

## Details

Requires COMPLETE auxiliary information: a data.frame `population` with
the `x_formula` columns and the model predictors for the whole
population (or a reference frame/census).

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  step_model_calibration(
    x_formula  = ~ sex + region,
    models     = list(income = y_model(income ~ age + sex, engine = "glm")),
    population = population) |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)
#>   2. model calibration (1 y variables)
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                           stage n_active sum_wts cv_wts deff_kish n_eff
#>                            base      467    4371  0.236     1.056   442
#>        stage_1_step_nonresponse      270    4371  0.144     1.021   265
#>  stage_2_step_model_calibration      270    4495  0.212     1.045   258
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
