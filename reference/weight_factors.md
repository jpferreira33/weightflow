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
