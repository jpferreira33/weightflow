# Rescale (normalize) the weights

Rescale (normalize) the weights

## Usage

``` r
step_rescale(spec, to = c("n", "total"), total = NULL, by = NULL)
```

## Arguments

- spec:

  a weighting_spec.

- to:

  "n" (weights sum to the number of active units, i.e. mean weight 1) or
  "total" (weights sum to `total`).

- total:

  numeric. Target sum when to = "total".

- by:

  character. Rescale within these groups (optional). With to = "n", each
  group sums to its own active count.

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_rescale(to = "n") |> prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 1575 cases
#> Base wts: pw
#> Steps   :
#>   1. rescale (to n)
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                 stage n_active sum_wts cv_wts deff_kish n_eff
#>                  base     1575   15182  0.229     1.053  1496
#>  stage_1_step_rescale     1575    1575  0.229     1.053  1496
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
