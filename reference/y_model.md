# Specify a working model for a study variable y

Specify a working model for a study variable y

## Usage

``` r
y_model(formula, engine = c("glm", "tree", "forest"), family = NULL)
```

## Arguments

- formula:

  full formula, e.g. income ~ sex + age_g.

- engine:

  "glm", "tree" (rpart) or "forest" (ranger).

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
#> <environment: 0xab19d85b8>
#> 
#> $engine
#> [1] "glm"
#> 
#> $family
#> NULL
#> 
```
