# Automatic weight trimming to an absolute band

Caps the weights into an absolute interval `[lower, upper]` and hands
the removed mass back to the units that were not capped, so the weighted
total is preserved. This is the step to use when you have **not
calibrated yet** (or will calibrate afterwards) and you want the cutoff
chosen from the data rather than argued for: with `upper = NULL` it
picks one by the Tukey far-out fence or by Potter's MSE rule.

## Usage

``` r
step_trim_weights(
  spec,
  lower = 1,
  upper = NULL,
  method = c("tukey", "potter"),
  redistribute = c("proportional", "uniform"),
  strict = TRUE,
  maxit = 50L,
  id = NULL
)
```

## Arguments

- spec:

  a weighting_spec.

- lower:

  numeric. Lower floor (default 1: no weight below 1).

- upper:

  numeric or NULL. Upper cap. If NULL, the cap is chosen automatically
  by `method`.

- method:

  rule for the automatic cap when `upper = NULL`: "tukey" (default, Q3 +
  3\*IQR far-out fence) or "potter" (Potter's MSE-optimal cutoff, which
  over a grid of candidate cutoffs minimizes an estimate of bias^2 +
  variance and so balances the bias of trimming against the variance
  from extreme weights). Ignored when `upper` is supplied.

- redistribute:

  how the trimmed mass is shared among the untrimmed units:
  "proportional" (default; in proportion to their weights, preserving
  relative sizes) or "uniform" (an equal amount to each untrimmed unit,
  and units already trimmed are not reused, exactly reproducing
  survey::trimWeights()).

- strict:

  logical. If TRUE (default), iterate cap+redistribution until no weight
  is outside `[lower, upper]` (like survey's strict = TRUE). If FALSE, a
  single pass (redistribution may push some weights slightly past the
  cap).

- maxit:

  integer. Maximum iterations when strict = TRUE.

- id:

  optional string: a stable identifier for this step, shown in the
  recipe print-out and usable to select it in
  [`collect_step_detail()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_step_detail.md);
  defaults to a derived `"<class>_<k>"`.

## Value

The input `weighting_spec` with this step appended to its recipe. The
step is recorded only; it is evaluated when
[`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md)
is called.

## See also

Other weighting steps:
[`step_assert()`](https://jpferreira33.github.io/weightflow/dev/reference/step_assert.md),
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/dev/reference/step_calibrate.md),
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/dev/reference/step_drop_ineligible.md),
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/dev/reference/step_model_calibration.md),
[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/dev/reference/step_nonresponse.md),
[`step_nr_sensitivity()`](https://jpferreira33.github.io/weightflow/dev/reference/step_nr_sensitivity.md),
[`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/dev/reference/step_pseudoweight.md),
[`step_rescale()`](https://jpferreira33.github.io/weightflow/dev/reference/step_rescale.md),
[`step_round()`](https://jpferreira33.github.io/weightflow/dev/reference/step_round.md),
[`step_select_within()`](https://jpferreira33.github.io/weightflow/dev/reference/step_select_within.md),
[`step_subsample()`](https://jpferreira33.github.io/weightflow/dev/reference/step_subsample.md),
[`step_trim()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim.md),
[`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim_calibrated.md),
[`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/dev/reference/step_unknown_eligibility.md)

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  step_trim_weights(lower = 1, strict = TRUE) |> prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)  [nonresponse_1]
#>   2. auto weight trimming  [trim_weights_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                      stage n_active sum_wts cv_wts deff_kish n_eff
#>                       base      467    4371  0.236     1.056   442
#>   stage_1_step_nonresponse      270    4371  0.144     1.021   265
#>  stage_2_step_trim_weights      270    4371  0.144     1.021   265
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 

# Potter MSE-optimal cutoff chosen from the data
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  step_trim_weights(method = "potter") |> prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)  [nonresponse_1]
#>   2. auto weight trimming (Potter MSE)  [trim_weights_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                      stage n_active sum_wts cv_wts deff_kish n_eff
#>                       base      467    4371  0.236     1.056   442
#>   stage_1_step_nonresponse      270    4371  0.144     1.021   265
#>  stage_2_step_trim_weights      270    4371  0.137     1.019   265
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
