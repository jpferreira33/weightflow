# Export weightflow weights to a survey design

`as_svydesign()` builds a linearization (ultimate-cluster) design from a
prepped recipe, treating the final weights as fixed; `as_svrepdesign()`
builds a replicate-weights design from a bootstrap (`weightflow_boot`)
or jackknife (`weightflow_jack`) object. Both require the 'survey'
package. With the replicate-weights design you can estimate any
statistic for any domain (`svytotal`, `svymean`, `svyratio`, `svyby`,
...).

## Usage

``` r
as_svydesign(object, ids, strata = NULL, weight_name = ".weight", ...)

as_svrepdesign(object, ...)
```

## Arguments

- object:

  for `as_svydesign`, a prepped recipe or a data frame with the weight
  and design columns; for `as_svrepdesign`, a `weightflow_boot` or
  `weightflow_jack` object.

- ids, strata:

  column names of the PSU and the stratum.

- weight_name:

  name of the weight column.

- ...:

  passed to the survey constructor.

## Value

A `survey.design` / `svyrep.design` object.

## Details

Only `as_svrepdesign()` propagates the variability of the weighting
adjustments (nonresponse, calibration, ...), because each replicate
re-runs the whole recipe. `as_svydesign()` is design-based linearization
on the *fixed* final weights: its standard errors reflect the sampling
design but treat the adjustments as known without error, so they are
usually smaller. Use `as_svrepdesign()` (with
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
/
[`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md))
when the adjustment variability should be included.
