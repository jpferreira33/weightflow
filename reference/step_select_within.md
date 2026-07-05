# Within-household selection adjustment

When one (or a subsample) of the eligible persons is selected within
each household, the selected person represents all eligible persons, so
the weight is multiplied by the inverse of the within-household
selection probability. Apply it after the (household-level) eligibility
adjustment and before the nonresponse adjustment.

## Usage

``` r
step_select_within(spec, prob = NULL, n_eligible = NULL, n_selected = NULL)
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
  for simple random selection within the household. When a single person
  is selected (the default), the weight is multiplied by n_eligible
  (equivalent to prob = 1/n_eligible).

- n_selected:

  optional number of persons selected per household under simple random
  selection, when more than one person is subsampled. Either a single
  number (same subsample size in every household) or an unquoted column
  (subsample size varying by household). The weight is multiplied by
  n_eligible / n_selected (equivalent to prob = n_selected/n_eligible).
  Defaults to 1. Only used together with `n_eligible`.

## Examples

``` r
# simple random selection of one eligible person per household
df <- transform(sample_survey,
                n_elig = ave(person_id, household_id, FUN = length))
weighting_spec(df, base_weights = pw) |>
  step_select_within(n_eligible = n_elig)
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. within-household selection
#> Status  : not estimated
#> 

# simple random selection of two eligible persons per household
weighting_spec(df, base_weights = pw) |>
  step_select_within(n_eligible = n_elig, n_selected = 2)
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. within-household selection
#> Status  : not estimated
#> 
```
