# Flag re-identification risk from outlier weights within a publication cell

A unit whose final weight is far larger than the rest of its publication
cell is a disclosure risk in a public-use file: an extreme weight makes
a rare unit stand out. `disclosure_risk()` flags, within each cell
defined by `by`, the units whose final weight exceeds `ratio` times the
cell's median weight, and reports the unit's share of the cell's total
weight. Trimming
([`step_trim_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim_weights.md)
or the totals-preserving
[`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim_calibrated.md))
is the usual remedy.

## Usage

``` r
disclosure_risk(object, by, ratio = 10)
```

## Arguments

- object:

  a prepped `weighting_spec` (the output of
  [`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md)).

- by:

  the name(s) of the publication cell column(s) (e.g. `"region"`, or
  `c("region", "sex")`). The risk is judged within each cell.

- ratio:

  the multiple of the cell median weight above which a unit is flagged.
  Default 10.

## Value

A `data.frame`, one row per flagged unit, with the row index (`.row`),
the `cell`, the unit `weight`, the `cell_median`, the `cell_n` (active
units in the cell) and `cell_share` (the unit's fraction of the cell's
total weight), ordered from the largest weight down. Zero rows when
nothing is flagged.

## See also

[`step_trim_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim_weights.md),
[`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim_calibrated.md),
[`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_replicate_weights.md)

## Examples

``` r
fit <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  prep()
disclosure_risk(fit, by = "region")
#> [1] .row        cell        weight      cell_median cell_n      cell_share 
#> <0 rows> (or 0-length row.names)
```
