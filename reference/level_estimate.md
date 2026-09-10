# Level estimate for a single panel wave, with its replicate variance

Estimates a statistic in ONE wave of a
[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md)
or
[`wave_jackknife()`](https://jpferreira33.github.io/weightflow/reference/wave_jackknife.md)
object, with the variance from that wave's replicates. Lets you report a
level and a change from the same coordinated object.

## Usage

``` r
level_estimate(
  wb,
  statistic,
  wave = NULL,
  level = 0.95,
  ci_type = c("normal", "t"),
  df = NULL
)

level_mean(wb, variable, wave = NULL, level = 0.95)

level_total(wb, variable, wave = NULL, level = 0.95)
```

## Arguments

- wb:

  a `weightflow_wave_boot` or `weightflow_wave_jack`.

- statistic:

  a function `function(w, data)` returning one number.

- wave:

  optional wave label (defaults to the first).

- level:

  confidence level for the normal interval.

- ci_type:

  `"normal"` (default, z) or `"t"` (Student t with `df` df).

- df:

  degrees of freedom for the `"t"` interval; `NULL` uses the object's
  design df.

- variable:

  name of a numeric variable in the wave's data.

## Value

an object of class `weightflow_level` with `estimate`, `se`, `V` and the
interval.

## See also

[`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md),
`level_mean()`, `level_total()`
