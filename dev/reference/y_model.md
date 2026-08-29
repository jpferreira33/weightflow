# Specify a working model for a study variable y

Declares the working model that
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/dev/reference/step_model_calibration.md)
fits for one study variable: a formula, a learner (a linear/`glm` model
or a machine-learning method such as a regression tree, a random forest
or gradient boosting) and, for `glm`, a family. It builds no model and
touches no data – it records the specification that the calibration step
will fit on the sample and predict over the population.

## Usage

``` r
y_model(formula, engine = c("glm", "tree", "forest", "boost"), family = NULL)
```

## Arguments

- formula:

  full formula, e.g. income ~ sex + age_g.

- engine:

  "glm", "tree" (rpart), "forest" (ranger) or "boost" (xgboost). The
  flexible learners run with fixed default settings (hyperparameters are
  not currently exposed): "tree"/"forest" use the 'rpart'/'ranger'
  defaults, and "boost" uses xgboost with nrounds = 150, max_depth = 4
  and eta = 0.1.

- family:

  for engine = "glm": "gaussian", "binomial" or "poisson". For
  tree/forest, regression vs classification is inferred from y.

## Value

a model specification list.

## Examples

``` r
y_model(income ~ age + sex, engine = "glm")
#> $formula
#> income ~ age + sex
#> <environment: 0x55e1e8904400>
#> 
#> $engine
#> [1] "glm"
#> 
#> $family
#> NULL
#> 
#> attr(,"class")
#> [1] "wf_y_model"
```
