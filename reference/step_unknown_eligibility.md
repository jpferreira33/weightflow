# Unknown-eligibility adjustment

Redistributes the weight of unknown-eligibility cases among the
known-eligibility cases, within the cells defined by `by`.

## Usage

``` r
step_unknown_eligibility(spec, unknown, by = NULL)
```

## Arguments

- spec:

  a weighting_spec.

- unknown:

  a 0/1 dummy column (1 = eligibility unknown) or any logical condition
  (unquoted) that is TRUE for unknown-eligibility cases. Evaluated on
  the data.

- by:

  character. Variables defining the adjustment cells (optional).

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_unknown_eligibility(unknown = unknown_elig, by = "region")
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 1575 cases
#> Base wts: pw
#> Steps   :
#>   1. unknown eligibility
#> Status  : not estimated
#> 
```
