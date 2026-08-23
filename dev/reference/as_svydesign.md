# Export weightflow weights to a survey design

`as_svydesign()` builds a linearization (ultimate-cluster)
`survey.design` from a prepped recipe, treating the final weights as
fixed constants. `as_svrepdesign()` builds a replicate-weights
`svyrep.design` from a
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_weights.md)
or
[`jackknife_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/jackknife_weights.md)
object. Both are the bridge to the `survey` package, and therefore to
[`svytotal()`](https://rdrr.io/pkg/survey/man/surveysummary.html),
[`svymean()`](https://rdrr.io/pkg/survey/man/surveysummary.html),
[`svyratio()`](https://rdrr.io/pkg/survey/man/svyratio.html),
[`svyby()`](https://rdrr.io/pkg/survey/man/svyby.html),
[`svyglm()`](https://rdrr.io/pkg/survey/man/svyglm.html) and domain
estimation generally.

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
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_weights.md)
/
[`jackknife_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/jackknife_weights.md))
when the adjustment variability should be included.
