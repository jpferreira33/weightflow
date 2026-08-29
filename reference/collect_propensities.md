# Recover the fitted response propensities of a nonresponse step

A `step_nonresponse(method = "propensity")` step fits a
response-propensity model and adjusts the weights by \\1/\hat p\\.
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
keeps the full per-unit propensity vector \\\hat p\\ (out-of-fold when
cross-fitting is used) on the step, but it is not returned by
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md).
This accessor extracts it aligned to the sample, so you can inspect its
distribution and confirm the nonresponse model is well fitted before
trusting the adjusted weights. It works the same way whether the
adjustment was made at the unit level or, through `cluster`, at the
household level (there the household propensity is broadcast to its
members).

## Usage

``` r
collect_propensities(object, step = NULL)
```

## Arguments

- object:

  a prepped `weighting_spec` (the output of
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)).

- step:

  optional integer, which step to read when the recipe has more than one
  propensity step. If `NULL` (default) and there is a single propensity
  step it is used; with several, the last one is used with a message.

## Value

The sample `data.frame` with columns appended: `.propensity` (the fitted
response propensity \\\hat p\\, `NA` for units outside the model, i.e.
ineligible / already dropped), `.responded` (the response indicator the
model used), `.weight_in` (the weight reaching the step, see below),
`.factor` (the multiplier the step actually applied to the unit),
`.status` (a factor that labels each unit as `"eligible respondent"`,
`"eligible nonrespondent"` or `"not in propensity model"`), and, when
the step uses propensity classes (`num_classes`), `.class` (the assigned
class). Units not in the propensity model carry `NA` in the per-unit
columns. `.weight_in` is the weight *reaching* the nonresponse step – it
already carries any earlier adjustment (unknown-eligibility
redistribution, within-cluster selection), not the raw base weight. At
the unit level it is also the weight the propensity model is fitted with
(unless `weight_model = FALSE`); with `cluster`, the model is fitted at
the household level with the household weight, which equals `.weight_in`
only when weights are uniform within the household. `.factor` equals
\\1/\hat p\\ only when `num_classes = NULL`; with propensity classes it
is the class-level adjustment, so `1/.propensity` does not reconstruct
the applied factor – use `.factor`. The stage-by-stage weights are
available through
[`weight_factors()`](https://jpferreira33.github.io/weightflow/reference/weight_factors.md)
and
[`domain_summary()`](https://jpferreira33.github.io/weightflow/reference/domain_summary.md).

## See also

[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md),
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md)

Other cascade audit:
[`as_sae_input()`](https://jpferreira33.github.io/weightflow/reference/as_sae_input.md),
[`collect_step_detail()`](https://jpferreira33.github.io/weightflow/reference/collect_step_detail.md),
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md),
[`domain_summary()`](https://jpferreira33.github.io/weightflow/reference/domain_summary.md),
[`weight_factors()`](https://jpferreira33.github.io/weightflow/reference/weight_factors.md),
[`weighting_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md)

## Examples

``` r
fit <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "propensity",
                   formula = ~ sex + region, engine = "logit") |>
  prep()
p <- collect_propensities(fit)
summary(p$.propensity)
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>  0.5111  0.5304  0.5846  0.5782  0.6460  0.6654 
```
