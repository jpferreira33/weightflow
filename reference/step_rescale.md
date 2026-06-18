# Rescale (normalize) the weights

Rescale (normalize) the weights

## Usage

``` r
step_rescale(spec, to = c("n", "total"), total = NULL, by = NULL)
```

## Arguments

- spec:

  a weighting_spec.

- to:

  "n" (weights sum to the number of active units, i.e. mean weight 1) or
  "total" (weights sum to `total`).

- total:

  numeric. Target sum when to = "total".

- by:

  character. Rescale within these groups (optional). With to = "n", each
  group sums to its own active count.
