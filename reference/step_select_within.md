# Within-household selection adjustment

When one (or a subsample) of the eligible persons is selected within
each household, the selected person represents all eligible persons, so
the weight is multiplied by the inverse of the within-household
selection probability. Apply it after the (household-level) eligibility
adjustment and before the nonresponse adjustment.

## Usage

``` r
step_select_within(spec, prob = NULL, n_eligible = NULL)
```

## Arguments

- spec:

  a weighting_spec.

- prob:

  unquoted column with the within-household selection probability of the
  selected person (need not be 1/n_eligible). The weight is multiplied
  by 1/prob.

- n_eligible:

  unquoted column with the number of eligible persons in the household,
  for simple random selection of one person. The weight is multiplied by
  n_eligible (equivalent to prob = 1/n_eligible).

## Examples

``` r
# simple random selection of one eligible person per household
df <- transform(sample_survey,
                n_elig = ave(person_id, household_id, FUN = length))
weighting_spec(df, base_weights = pw) |>
  step_select_within(n_eligible = n_elig)
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 1575 cases
#> Base wts: pw
#> Steps   :
#>   1. within-household selection
#> Status  : not estimated
#> 
```
