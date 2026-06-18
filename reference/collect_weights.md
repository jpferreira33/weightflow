# Extract the data with the computed weights

Extract the data with the computed weights

## Usage

``` r
collect_weights(
  object,
  drop_zero = TRUE,
  keep_intermediate = FALSE,
  weight_name = ".weight"
)
```

## Arguments

- object:

  a prepped object (output of prep()).

- drop_zero:

  logical. If TRUE, drops rows with final weight 0 (ineligible /
  nonresponse). Default TRUE.

- keep_intermediate:

  logical. If TRUE, adds one column per stage.

- weight_name:

  name of the final weight column. Default ".weight".

## Value

data.frame.
