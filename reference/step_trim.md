# Trim extreme weights

Caps weights above a limit and, optionally, redistributes the excess
among the others to preserve the weighted total (Potter 1988, 1990; Liu
et al. 2004). Optional step that can be inserted anywhere in the recipe,
even several times. Operates on the CURRENT weights at that point of the
cascade.

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

## Details

There is no standard threshold: `max_ratio` is an analyst decision, a
bias-variance trade-off. Use Kish's design effect (see summary) to judge
whether trimming is worth it.
