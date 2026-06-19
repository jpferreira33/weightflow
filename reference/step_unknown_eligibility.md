# Unknown-eligibility adjustment

Redistributes the weight of unknown-eligibility cases among the
known-eligibility cases, within the cells defined by `by`.

## Usage

``` r
step_unknown_eligibility(spec, unknown, by = NULL, cluster = NULL)
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

- cluster:

  character. Cluster (e.g. household) id column. If given, the
  redistribution is done at the cluster level: each cluster counts once
  with its (uniform) weight, the weight of unknown-eligibility clusters
  is redistributed among the known ones, and the adjusted weight is
  assigned to every member. Use this when unknown-eligibility units have
  no roster (one row per address) while resolved units are expanded by
  person.

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_unknown_eligibility(unknown = unknown_elig, by = "region")
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. unknown eligibility
#> Status  : not estimated
#> 

# household-level redistribution (unknown units without roster)
weighting_spec(sample_survey, base_weights = pw) |>
  step_unknown_eligibility(unknown = unknown_elig, by = "region",
                           cluster = "household_id")
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. unknown eligibility (by household_id)
#> Status  : not estimated
#> 
```
