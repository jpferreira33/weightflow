# Extract the data with the computed weights

Returns the sample as a `data.frame` with the final analysis weight
attached as a column, ready to hand to an estimation routine. By default
the units that left the cascade (weight 0) are dropped, so what comes
back is the responding, in-scope sample and its weights.

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

## See also

Other cascade audit:
[`as_sae_input()`](https://jpferreira33.github.io/weightflow/dev/reference/as_sae_input.md),
[`collect_propensities()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_propensities.md),
[`collect_step_detail()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_step_detail.md),
[`domain_summary()`](https://jpferreira33.github.io/weightflow/dev/reference/domain_summary.md),
[`weight_factors()`](https://jpferreira33.github.io/weightflow/dev/reference/weight_factors.md),
[`weighting_alerts()`](https://jpferreira33.github.io/weightflow/dev/reference/weighting_alerts.md)

## Examples

``` r
fitted <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  prep()
head(collect_weights(fitted))
#>    person_id household_id psu region sex age   pw unknown_elig responded income
#> 1          8            3   1  North   F  28 12.5            0         1  52146
#> 5        195           92   5  North   M  18 12.5            0         1  28263
#> 6        198           94   6  North   M  40 12.5            0         1  33898
#> 8        248          117   7  North   F  32 12.5            0         1   8929
#> 9        249          117   7  North   F  50 12.5            0         1  33598
#> 10       250          117   7  North   F  58 12.5            0         1  25242
#>    employed  .weight
#> 1         0 19.07051
#> 5         0 19.07051
#> 6         0 19.07051
#> 8         0 19.07051
#> 9         1 19.07051
#> 10        1 19.07051
```
