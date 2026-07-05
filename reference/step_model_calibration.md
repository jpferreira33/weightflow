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
  x_totals = NULL,
  count = "Freq",
  cluster = NULL,
  equal_within_cluster = FALSE,
  crossfit = NULL,
  crossfit_seed = NULL
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
  variables are not needed; they are predicted). Always required: the
  model-assisted block predicts each y over every population unit, which
  cannot be done from aggregated totals.

- x_totals:

  optional population totals for the consistency auxiliaries
  (`x_formula`), for when they come from an external source rather than
  from `population` (e.g. an official control total, a variable not
  present in the frame). Two shapes, the same as
  `step_calibrate(method = "linear")`: the tidy format, a named list
  matching the formula terms with a data frame (all categories + a
  counts column named by `count`) per factor and a single number per
  continuous total; or the classic model-matrix vector (intercept plus
  treatment contrasts). When NULL (default) the X totals are taken from
  `population`. When given, the X totals no longer require `x_formula`
  columns to exist in `population` (only in the sample), and
  `population` is used only for the model predictions.

- count:

  name of the counts column in the tidy `x_totals` data frames. Only
  used when `x_totals` is given in the tidy (data-frame) format.

- cluster:

  name of the cluster id column (e.g. "household"), for equal weights
  within the cluster.

- equal_within_cluster:

  logical. If TRUE, integrative calibration: a single weight per
  cluster. Requires `cluster` and that the incoming weight be uniform
  within the cluster.

- crossfit:

  integer or NULL. If given (K \>= 2 folds), the outcome models are
  fitted by K-fold cross-fitting: the sample predictions are out-of-fold
  (each unit predicted by a model that did not see it), which avoids
  overfitting with flexible engines; the population total of the
  predictions uses the full model. Folds are formed by `cluster` when
  given. NULL (default) fits and predicts in-sample.

- crossfit_seed:

  integer or NULL. Seed for reproducible fold assignment.

## Value

The input `weighting_spec` with this step appended to its recipe. The
step is recorded only; it is evaluated when
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
is called.

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

# with cross-fitting (out-of-fold predictions, avoids overfitting)
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  step_model_calibration(
    x_formula  = ~ sex + region,
    models     = list(income = y_model(income ~ age + sex, engine = "glm")),
    population = population, crossfit = 5, crossfit_seed = 1) |>
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

# consistency totals from an external source (tidy format): a data frame per
# factor and a single number per continuous total. `population` is still used
# for the model predictions. Adjust for nonresponse first, since the outcome
# is only observed for respondents.
m_region <- as.data.frame(table(region = population$region))
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  step_model_calibration(
    x_formula  = ~ region + age,
    models     = list(income = y_model(income ~ age + sex, engine = "glm")),
    population = population,
    x_totals   = list(region = m_region, age = sum(population$age)),
    count      = "Freq") |>
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
