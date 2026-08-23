# Quality alerts recorded while preparing a recipe

`weighting_alerts()` returns the character vector of quality incidents
recorded by
[`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md),
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
  [`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md).

## Value

`weighting_alerts()`: a character vector (empty if the recipe ran
clean). `has_alerts()`: a single logical.

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
