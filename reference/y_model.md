# Specify a working model for a study variable y

Specify a working model for a study variable y

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
#> <environment: 0x55dcce1cb568>
#> 
#> $engine
#> [1] "glm"
#> 
#> $family
#> NULL
#> 
```
