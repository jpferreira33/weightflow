# Per-unit detail of one step of the cascade

A generic companion to
[`collect_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_weights.md)
that returns, for a single step, the weight it received and the
multiplier it applied to every unit, plus any quantities that step
computed internally (for a propensity step, the fitted propensity and
its class). `.weight_in` and `.factor` are read from the stage-by-stage
weights that
[`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md)
already stores, so `.weight_in * .factor` equals the weight leaving the
step by construction, for any step. Native columns (those a step exposes
on its own) are `NA` for units the step did not touch.

## Usage

``` r
collect_step_detail(object, step = NULL)
```

## Arguments

- object:

  a prepped `weighting_spec` (the output of
  [`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md)).

- step:

  optional: which step to inspect, as an integer position (1 for the
  first piped step) or a step id string (e.g. "calibrate_1"; see the
  recipe print-out). If `NULL` (default): a single step exposing native
  detail is used; if several do, or if none do and the recipe has more
  than one step, an error lists the steps so you can choose.

## Value

The sample `data.frame` with `.weight_in` (the weight reaching the step,
carrying every earlier adjustment) and `.factor` (the multiplier the
step applied to each unit, `NA` where the incoming weight is zero)
appended, plus any native columns of the chosen step (for a propensity
step: `.propensity`, `.responded`, and `.class` when propensity classes
are used), which are `NA` outside the units the step covers. Here
`.factor` is defined for every unit with a nonzero incoming weight, so
an active unit the step did not touch reports `.factor = 1`; this
differs from
[`collect_propensities()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_propensities.md),
where `.factor` is `NA` outside the propensity model (see its
`.status`).

## See also

[`collect_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_weights.md),
[`collect_propensities()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_propensities.md),
[`weight_factors()`](https://jpferreira33.github.io/weightflow/dev/reference/weight_factors.md)

## Examples

``` r
fit <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "propensity",
                   formula = ~ sex + region, engine = "logit") |>
  prep()
d <- collect_step_detail(fit, step = 1)
head(d[!is.na(d$.factor), c(".weight_in", ".factor", ".propensity")])
#>   .weight_in  .factor .propensity
#> 1       12.5 1.526316   0.6653748
#> 2       12.5 0.000000   0.6653748
#> 3       12.5 0.000000   0.6460371
#> 4       12.5 0.000000   0.6460371
#> 5       12.5 1.614706   0.6460371
#> 6       12.5 1.614706   0.6460371
```
