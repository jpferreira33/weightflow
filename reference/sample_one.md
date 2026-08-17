# Synthetic address sample with one selected person per household

A multistage sample of 417 addresses (stratum, then PSU, then household,
then one person inside the reached household) carrying every
complication a household survey meets: unresolved eligibility,
out-of-scope addresses, household nonresponse, unequal within-household
selection and person nonresponse. It is the dataset that exercises the
complete weighting cascade.

## Usage

``` r
sample_one
```

## Format

A data frame with one row per sampled household (the selected person, or
a single placeholder row for non-roster cases):

- person_id, household_id, psu:

  identifiers

- region:

  stratum

- sex, age:

  selected person's attributes (NA on non-roster rows)

- pw:

  design base weight (product of the stage selection probabilities)

- status:

  "eligible", "ineligible" or "unknown"

- disposition:

  full field disposition as a single factor (a recode of the indicator
  columns): "eligible respondent", "eligible nonrespondent", "household
  nonresponse", "ineligible" or "unknown eligibility"

- unknown_elig:

  1 if eligibility is unknown (no roster)

- ineligible:

  1 if the address is out of scope (no roster)

- hh_responded:

  1 reached, 0 household nonresponse, NA for non-eligible

- responded:

  1 if the selected person responded (NA on non-roster rows)

- n_elig:

  number of eligible persons in the household (NA on non-roster rows)

- p_within:

  within-household selection probability of the selected person

- income, employed:

  survey outcomes; NA unless the person responded
