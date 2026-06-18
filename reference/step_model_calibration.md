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
