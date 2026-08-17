# Unknown-eligibility adjustment

Redistributes the weight of the cases whose eligibility was never
resolved onto the resolved cases of the same adjustment cell, so the
resolved units stand in for the unresolved share of the frame. Reach for
it as the first step of the cascade, while the known-ineligible units
are still in the data.

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

## Value

The input `weighting_spec` with this step appended to its recipe. The
step is recorded only; it is evaluated when
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
is called.

## Details

Within each cell \\c\\ the resolved cases are scaled up to also carry
the unresolved ones, \$\$w_i^{\mathrm{out}} = w_i \\ \frac{\sum\_{j \in
c} w_j}{\sum\_{j \in c,\\ \mathrm{resolved}} w_j},\$\$ with every weight
on the right the weight *entering* the step, so the ratio is one number
per cell, the cell total is conserved exactly, and the result does not
depend on the order in which units are updated.

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
