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

## Examples

``` r
fitted <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  prep()
head(collect_weights(fitted))
#>    person_id household_id region sex age        pw unknown_elig responded
#> 2         25           11   East   F  66  8.333333            0         1
#> 3         26           11   East   M  64  8.333333            0         1
#> 5         28           12  North   M  37 12.500000            0         1
#> 8         31           12  North   M  20 12.500000            0         1
#> 10        37           15  North   M  75 12.500000            0         1
#> 11        42           17  South   M  29 10.000000            0         1
#>    income employed  .weight
#> 2   12242        1 13.44086
#> 3   16431        1 13.44086
#> 5   35585        0 20.78901
#> 8   29802        0 20.78901
#> 10  18973        0 20.78901
#> 11  38444        1 16.31579
```
