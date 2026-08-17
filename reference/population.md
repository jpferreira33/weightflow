# Synthetic target population (sampling frame)

The simulated frame every weightflow example draws from: 4,495 persons
nested in 1,882 households, in 120 primary sampling units, in 4 regions
used as strata. Because the whole population is observed, it supplies
the known population totals a calibration step needs, and the true
values against which a weighted estimate can be checked.

## Usage

``` r
population
```

## Format

A data frame with one row per person:

- person_id:

  individual identifier

- household_id:

  household identifier (cluster)

- psu:

  primary sampling unit (segment) within the stratum

- region:

  stratum: North, South, East or West

- sex:

  F or M

- age:

  age in years (18-95)

- income:

  annual income

- employed:

  employment indicator (0/1)
