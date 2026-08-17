# Trim extreme weights against a ratio

Caps the current weights at a multiple of a reference (each unit's base
weight, the group median, or an absolute value) and, by default,
redistributes the removed mass among the untrimmed units so the weighted
total survives the trim. With `by`, the reference and the cap are
computed separately within each subgroup. An optional step that can
appear anywhere in the recipe, more than once.

## Usage

``` r
step_trim(
  spec,
  max_ratio,
  min_ratio = NULL,
  reference = c("base", "median", "value"),
  redistribute = TRUE,
  by = NULL,
  maxit = 50L
)
```

## Arguments

- spec:

  a weighting_spec.

- max_ratio:

  number. Upper cap. Its meaning depends on `reference`. E.g. with
  reference = "base" and max_ratio = 4, no weight may exceed 4 times its
  design weight.

- min_ratio:

  number or NULL. Lower floor (same units as max_ratio).

- reference:

  "base" (multiple of each unit's base weight), "median" (multiple of
  the median of current weights) or "value" (absolute weight value).

- redistribute:

  logical. If TRUE, redistributes the trimmed excess among the uncapped
  weights to preserve the total (iterating). If you calibrate afterwards
  you can use FALSE: calibration restores the totals.

- by:

  character. Groups within which to redistribute (optional).

- maxit:

  integer. Maximum cap+redistribution iterations.

## Value

The input `weighting_spec` with this step appended to its recipe. The
step is recorded only; it is evaluated when
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
is called.

## Details

There is no standard threshold: `max_ratio` is an analyst decision, a
bias-variance trade-off. Use Kish's design effect (see summary) to judge
whether trimming is worth it.

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_trim(max_ratio = 3, reference = "base")
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. trimming (base, cap 3)
#> Status  : not estimated
#> 
```
