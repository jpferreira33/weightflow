# Per-unit adjustment factors table

Returns a data.frame with the weight at each stage and the factor of
each step (stage weight / previous-stage weight), handy for custom
plots.

## Usage

``` r
weight_factors(object)
```

## Arguments

- object:

  a prepped object (output of prep()).

## Value

data.frame with one weight column per stage and one factor per step.

## Examples

``` r
fitted <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  prep()
head(weight_factors(fitted))
#>        base stage_1_step_nonresponse factor_stage_1_step_nonresponse
#> 1  8.333333                  0.00000                        0.000000
#> 2  8.333333                 13.44086                        1.612903
#> 3  8.333333                 13.44086                        1.612903
#> 4  8.333333                  0.00000                        0.000000
#> 5 12.500000                 20.78901                        1.663121
#> 6 12.500000                  0.00000                        0.000000
```
