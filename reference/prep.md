# Estimate the weighting cascade

Walks the steps in the order they were added, starting from the base
weights. Each step multiplies the current weight by its adjustment
factor.

## Usage

``` r
prep(spec)
```

## Arguments

- spec:

  a weighting_spec.

## Value

a "prepped_weighting_spec" object.
