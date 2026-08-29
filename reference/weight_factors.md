# Per-unit adjustment factors table

Unrolls the cascade into a `data.frame`: the weight of every unit at
every stage, plus the factor each step applied to it. This is the tidy
form of
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)'s
`$history`, and the starting point for any diagnostic that
[plot()](https://jpferreira33.github.io/weightflow/reference/plot.prepped_weighting_spec.md)
does not already draw.

## Usage

``` r
weight_factors(object)
```

## Arguments

- object:

  a prepped object (output of prep()).

## Value

data.frame with one weight column per stage and one factor per step.

## See also

Other cascade audit:
[`as_sae_input()`](https://jpferreira33.github.io/weightflow/reference/as_sae_input.md),
[`collect_propensities()`](https://jpferreira33.github.io/weightflow/reference/collect_propensities.md),
[`collect_step_detail()`](https://jpferreira33.github.io/weightflow/reference/collect_step_detail.md),
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md),
[`domain_summary()`](https://jpferreira33.github.io/weightflow/reference/domain_summary.md),
[`weighting_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md)

## Examples

``` r
fitted <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  prep()
head(weight_factors(fitted))
#>   base stage_1_step_nonresponse factor_stage_1_step_nonresponse
#> 1 12.5                 19.07051                        1.525641
#> 2 12.5                  0.00000                        0.000000
#> 3 12.5                  0.00000                        0.000000
#> 4 12.5                  0.00000                        0.000000
#> 5 12.5                 19.07051                        1.525641
#> 6 12.5                 19.07051                        1.525641
```
