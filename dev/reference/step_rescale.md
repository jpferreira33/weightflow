# Rescale the weights to a fixed sum

Multiplies the active weights by a single constant so that they add up
to a chosen total: either the number of active units (mean weight 1) or
an arbitrary number. Use it as a presentation step, when the analysis
wants normalized weights rather than population-scale ones.

## Usage

``` r
step_rescale(spec, to = c("n", "total"), total = NULL, by = NULL, id = NULL)
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

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_rescale(to = "n") |> prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. rescale (to n)  [rescale_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                 stage n_active sum_wts cv_wts deff_kish n_eff
#>                  base      467    4371  0.236     1.056   442
#>  stage_1_step_rescale      467     467  0.236     1.056   442
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
