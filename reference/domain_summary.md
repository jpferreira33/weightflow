# Per-domain weight summary at every stage of the cascade

For quality control by study domain (for example a department / DAM),
this summarises how the weights move within each domain at every stage
of the recipe: the base weights, then the weights after each step. It
reads the stage-by-stage weights that
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
already stores, so it adds no computation to the cascade and never
changes a weight.

## Usage

``` r
domain_summary(object, by)
```

## Arguments

- object:

  a prepped `weighting_spec` (the output of
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)).

- by:

  the name (string) of a domain column in the data (e.g. `"region"`).

## Value

A `data.frame` with one row per stage x domain and the columns `stage`
(an ordered factor: base weights, then `1. <step>`, `2. <step>`, ...),
`domain`, `n_active` (active units in the domain at that stage), `sum_w`
(sum of the active weights), `mean_w`, `deff` (the Kish design effect
within the domain) and `n_eff`. Reading down a domain shows how its
weight total and dispersion evolve step by step.

## See also

[`design_effect()`](https://jpferreira33.github.io/weightflow/reference/design_effect.md),
[`weight_factors()`](https://jpferreira33.github.io/weightflow/reference/weight_factors.md),
[`summary.prepped_weighting_spec()`](https://jpferreira33.github.io/weightflow/reference/summary.prepped_weighting_spec.md)

## Examples

``` r
fit <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  step_calibrate(method = "raking", margins = list(region = c(table(population$region)))) |>
  prep()
domain_summary(fit, by = "region")
#>             stage domain n_active     sum_w    mean_w deff n_eff
#> 1    base weights   East       96  800.0000  8.333333    1    96
#> 2    base weights  North      119 1487.5000 12.500000    1   119
#> 3    base weights  South      121 1210.0000 10.000000    1   121
#> 4    base weights   West      131  873.3333  6.666667    1   131
#> 5  1. nonresponse   East       52  800.0000 15.384615    1    52
#> 6  1. nonresponse  North       78 1487.5000 19.070513    1    78
#> 7  1. nonresponse  South       72 1210.0000 16.805556    1    72
#> 8  1. nonresponse   West       68  873.3333 12.843137    1    68
#> 9    2. calibrate   East       52  927.0000 17.826923    1    52
#> 10   2. calibrate  North       78 1570.0000 20.128205    1    78
#> 11   2. calibrate  South       72 1250.0000 17.361111    1    72
#> 12   2. calibrate   West       68  748.0000 11.000000    1    68
```
