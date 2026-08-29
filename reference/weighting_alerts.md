# Quality alerts recorded while preparing a recipe

`weighting_alerts()` returns the character vector of quality incidents
recorded by
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md),
each tagged with the step that produced it. `has_alerts()` is a
convenience predicate. Every incident is captured here, including
warnings a step raises internally (for example a calibration that could
not meet its constraints), so this is the reliable channel for
programmatic quality control even when warnings were suppressed.

## Usage

``` r
weighting_alerts(object)

has_alerts(object)
```

## Arguments

- object:

  a prepped_weighting_spec, as returned by
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md).

## Value

`weighting_alerts()`: a character vector (empty if the recipe ran
clean). `has_alerts()`: a single logical.

## See also

Other cascade audit:
[`as_sae_input()`](https://jpferreira33.github.io/weightflow/reference/as_sae_input.md),
[`collect_propensities()`](https://jpferreira33.github.io/weightflow/reference/collect_propensities.md),
[`collect_step_detail()`](https://jpferreira33.github.io/weightflow/reference/collect_step_detail.md),
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md),
[`domain_summary()`](https://jpferreira33.github.io/weightflow/reference/domain_summary.md),
[`weight_factors()`](https://jpferreira33.github.io/weightflow/reference/weight_factors.md)

## Examples

``` r
fit <- weighting_spec(sample_survey, base_weights = pw) |>
  step_trim(max_ratio = 3) |>
  prep()
weighting_alerts(fit)
#> character(0)
has_alerts(fit)
#> [1] FALSE
```
