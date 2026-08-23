# Synthetic person sample with a take-all household roster

A stratified two-stage sample of 467 persons drawn from
[population](https://jpferreira33.github.io/weightflow/dev/reference/population.md):
PSUs within region, then households within PSU, then **every** adult of
the selected household (take-all roster). It carries unequal design base
weights, an unknown-eligibility flag and a person-level response
indicator, and it is the dataset the short examples in this package use.

## Usage

``` r
sample_survey
```

## Format

A data frame with one row per sampled person:

- person_id, household_id, psu:

  identifiers

- region, sex, age:

  frame auxiliaries, known for all units

- pw:

  design base weight (inverse sampling fraction)

- unknown_elig:

  1 if eligibility is unknown

- responded:

  1 if the person responded

- income, employed:

  survey outcomes; NA for nonrespondents
