# Assert conditions on the weights at this point of the cascade

A checkpoint that does NOT change the weights; it verifies conditions
and fails (error) or warns if they are not met. Useful to guard a
production pipeline (tidymodels-style tests inside the recipe).

## Usage

``` r
step_assert(
  spec,
  max_deff = NULL,
  max_weight_ratio = NULL,
  min_n_eff = NULL,
  on_fail = c("error", "warning")
)
```

## Arguments

- spec:

  a weighting_spec.

- max_deff:

  numeric or NULL. Maximum acceptable Kish design effect.

- max_weight_ratio:

  numeric or NULL. Maximum allowed final/base weight ratio (per active
  unit).

- min_n_eff:

  numeric or NULL. Minimum acceptable effective sample size.

- on_fail:

  "error" (stop the cascade) or "warning".
