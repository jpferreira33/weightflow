# Automatic weight trimming (survey-style)

Caps weights into `[lower, upper]` and redistributes the change among
the untrimmed units to preserve the total, mirroring
survey::trimWeights(). By default no weight may fall below 1, and the
upper cap is chosen by an automatic rule: the Tukey far-out fence (Q3 +
3\*IQR) or, with `method = "potter"`, Potter's MSE-optimal cutoff.

## Usage

``` r
step_trim_weights(
  spec,
  lower = 1,
  upper = NULL,
  method = c("tukey", "potter"),
  strict = TRUE,
  maxit = 50L
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

- strict:

  logical. If TRUE (default), iterate cap+redistribution until no weight
  is outside `[lower, upper]` (like survey's strict = TRUE). If FALSE, a
  single pass (redistribution may push some weights slightly past the
  cap).

- maxit:

  integer. Maximum iterations when strict = TRUE.

## Value

The input `weighting_spec` with this step appended to its recipe. The
step is recorded only; it is evaluated when
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
is called.

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
#>   1. nonresponse (weighting class)
#>   2. auto weight trimming
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
#>   1. nonresponse (weighting class)
#>   2. auto weight trimming (Potter MSE)
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
