# Export weightflow weights to a survey design

`as_svydesign()` builds a linearization (ultimate-cluster) design from a
prepped recipe; `as_svrepdesign()` builds a replicate-weights design
from a bootstrap object, so survey/srvyr standard errors include the
recipe's adjustments. Both require the 'survey' package.

## Usage

``` r
as_svydesign(object, ids, strata = NULL, weight_name = ".weight", ...)

as_svrepdesign(boot, ...)
```

## Arguments

- object:

  a prepped recipe (for `as_svydesign`) or a data frame with the weight
  and design columns.

- ids, strata:

  column names of the PSU and the stratum.

- weight_name:

  name of the weight column.

- ...:

  passed to the survey constructor.

- boot:

  a `weightflow_boot` object.

## Value

A `survey.design` / `svyrep.design` object.
