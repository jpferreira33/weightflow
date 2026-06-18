# Round the final weights

Optional step, typically the last one (after calibration). Simple
rounding ("nearest") slightly breaks the calibrated totals;
"preserve_total" uses the largest-remainder method to keep the exact
total.

## Usage

``` r
step_round(spec, digits = 0L, method = c("nearest", "preserve_total"))
```

## Arguments

- spec:

  a weighting_spec.

- digits:

  integer. Decimals to keep (0 = integers).

- method:

  "nearest" (simple rounding) or "preserve_total" (keeps the sum of
  weights). Note: "preserve_total" can break equality of weights within
  a cluster; if you need integer and equal weights per household, use
  "nearest".
