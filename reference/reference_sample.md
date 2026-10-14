# Use a weighted survey as the calibration reference instead of a frame

Wraps a reference-survey microdata `data.frame` together with its design
weights so it can be passed as the `population` argument of
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
(and any step that takes a `population` frame). The calibration totals
are then the *weighted* sums over the reference survey – an estimate of
the population totals – instead of unweighted sums over a full frame.
This is the model-assisted / two-survey setup: fit the model on your
sample, project it onto a larger reference survey, and calibrate to the
weighted totals of the projection (Wu and Sitter 2001; Kim and Rao
2012).

## Usage

``` r
reference_sample(data, weights, replicates = NULL)
```

## Arguments

- data:

  a `data.frame` of reference-survey microdata, with the columns used in
  `x_formula` and the model predictors.

- weights:

  either the name (string) of a positive weight column in `data`, or a
  numeric vector with one weight per row.

- replicates:

  optional numeric matrix (or data.frame) of replicate weights for the
  reference survey – one row per reference unit, one column per
  replicate – used to propagate the reference sampling variance through
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md).
  `NULL` (default) treats the totals as fixed. Note that only
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  pairs the reference replicates and propagates this variance;
  [`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)
  treats the estimated totals as fixed even when `replicates` is
  supplied, so use the bootstrap when this component matters.

## Value

`data` tagged so that
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
weights its totals by `weights`. It is still an ordinary `data.frame`.

## Details

A reference survey with all weights equal to 1 reproduces the
plain-frame behaviour exactly. To propagate the reference survey's own
sampling variance into the recipe-aware bootstrap, pass its replicate
weights through `replicates`: each bootstrap replicate then re-estimates
the totals from the paired reference replicate (Opsomer and Erciulescu
2021), so the extra variance from estimating the totals is captured.
Without `replicates` the totals are treated as fixed – the same
assumption made when calibrating to another survey's published totals.

How much that assumption costs depends on what the reference is used
for, and the two uses are not equivalent. In
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
the reference supplies *totals*, a smooth functional of it. In
[`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/reference/step_pseudoweight.md)
every reference unit is a row of the pooled participation fit, so the
fitted propensities – and therefore every pseudo-weight – depend on the
reference unit by unit. Treating it as fixed there understates the
variance even when the reference is several times the size of the
sample, and the recipe cannot repair this on its own: building the
reference's replicates needs its strata, PSUs and finite-population
correction (and its control totals, if it was calibrated), which only
the reference's own producer has. So pass them, from the survey's
published replicate file or built with
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
on the reference's design; without them
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
and
[`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)
say which assumption they fell back on.

## See also

[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)

## Examples

``` r
ref <- reference_sample(population, weights = rep(1, nrow(population)))
```
