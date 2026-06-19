# Automatic weight trimming (survey-style)

Caps weights into `[lower, upper]` and redistributes the change among
the untrimmed units to preserve the total, mirroring
survey::trimWeights(). By default no weight may fall below 1, and the
upper cap is set by an automatic empirical rule (Tukey far-out fence:
Q3 + 3\*IQR).

## Usage

``` r
step_trim_weights(spec, lower = 1, upper = NULL, strict = TRUE, maxit = 50L)
```

## Arguments

- spec:

  a weighting_spec.

- lower:

  numeric. Lower floor (default 1: no weight below 1).

- upper:

  numeric or NULL. Upper cap. If NULL, automatic rule Q3 + 3\*IQR of the
  active weights.

- strict:

  logical. If TRUE (default), iterate cap+redistribution until no weight
  is outside `[lower, upper]` (like survey's strict = TRUE). If FALSE, a
  single pass (redistribution may push some weights slightly past the
  cap).

- maxit:

  integer. Maximum iterations when strict = TRUE.

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  step_trim_weights(lower = 1, strict = TRUE) |> prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 1575 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)
#>   2. auto weight trimming
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                      stage n_active sum_wts cv_wts deff_kish n_eff
#>                       base     1575   15182  0.229     1.053  1496
#>   stage_1_step_nonresponse      927   15182  0.195     1.038   893
#>  stage_2_step_trim_weights      927   15182  0.195     1.038   893
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
