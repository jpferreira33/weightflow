# Diagnostic plots for the weights

Diagnostic plots for the weights

## Usage

``` r
# S3 method for class 'prepped_weighting_spec'
plot(x, type = c("all", "factors", "summary"), ...)
```

## Arguments

- x:

  a prepped object (output of prep()).

- type:

  "all" (default): per-step adjustment-factor histograms PLUS the
  summary panel (final weights, cumulative factor, base vs final, deff
  by stage), all in one grid. "factors": only the per-step factor
  histograms. "summary": only the summary panel.

- ...:

  ignored.

## Examples

``` r
fitted <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  prep()
plot(fitted)
```
