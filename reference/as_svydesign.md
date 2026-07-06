# Export weightflow weights to a survey design

`as_svydesign()` builds a linearization (ultimate-cluster) design from a
prepped recipe; `as_svrepdesign()` builds a replicate-weights design
from a bootstrap (`weightflow_boot`) or jackknife (`weightflow_jack`)
object, so survey/srvyr standard errors include the recipe's
adjustments. Both require the 'survey' package. With replicate weights
you can then estimate any statistic for any domain (`svytotal`,
`svymean`, `svyratio`, `svyby`, ...) with variances that reflect the
whole recipe.

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
