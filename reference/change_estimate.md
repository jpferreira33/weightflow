# Net change between two panel waves, with honest variance

Estimates a net change (a statistic in wave 2 minus the same statistic
in wave 1) from a
[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md),
decomposing its variance into `V1`, `V2` and the sampling covariance the
overlap induces: `V = V1 + V2 - 2*Cov`. Because the bootstrap replicates
are coordinated by PSU, `Cov` emerges from them – no analytic covariance
formula. Reports the correlation `rho` and
`deff_change = V / (V1 + V2)`, i.e. how much the overlap lowered the
variance of the change relative to treating the waves as independent.

## Usage

``` r
change_estimate(
  wb,
  statistic,
  waves = NULL,
  level = 0.95,
  type = c("absolute", "relative"),
  by = NULL,
  ci_type = c("normal", "t", "percentile"),
  df = NULL
)

change_mean(
  wb,
  variable,
  waves = NULL,
  level = 0.95,
  type = c("absolute", "relative"),
  by = NULL
)

change_total(
  wb,
  variable,
  waves = NULL,
  level = 0.95,
  type = c("absolute", "relative"),
  by = NULL
)
```

## Arguments

- wb:

  a `weightflow_wave_boot` from
  [`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md).

- statistic:

  a function `function(w, data)` returning a single number, evaluated on
  each wave's weights and data (e.g.
  `function(w, d) weighted.mean(d$y, w)`).

- waves:

  optional length-2 character vector naming the two waves (defaults to
  the first two).

- level:

  confidence level for the interval.

- type:

  `"absolute"` (default) for the net change `theta2 - theta1`, or
  `"relative"` for the relative change `theta2 / theta1 - 1` (e.g. the
  percent change of a rate). The relative change's variance comes from
  the coordinated replicate distribution of the ratio (bootstrap) or the
  delta method on the level pieces (jackknife), so the overlap
  covariance is captured either way. `V1`, `V2`, `cov`, `rho` always
  describe the levels.

- by:

  optional name of a grouping column present in both waves: returns one
  change per domain (a `weightflow_change_by` table) instead of a single
  change.

- ci_type:

  interval type: `"normal"` (default, z-based), `"t"` (Student t with
  `df` degrees of freedom, wider and safer with few PSUs) or
  `"percentile"` (bootstrap only).

- df:

  degrees of freedom for the `"t"` interval; `NULL` (default) uses the
  design df stored on the object (total PSUs minus strata).

- variable:

  name of a numeric variable present in both waves.

## Value

an object of class `weightflow_change` with the estimate, `se`, `V`,
`V1`, `V2`, `Vind = V1 + V2`, `cov`, `rho`, `deff_change` and the
confidence interval; or, with `by=`, a `weightflow_change_by` holding
one row per domain.

## See also

[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md),
`change_mean()`, `change_total()`,
[`level_estimate()`](https://jpferreira33.github.io/weightflow/reference/level_estimate.md)
