# Evaluate an estimation pipeline

Runs every estimand of a `weightflow_estimation` across the cross of its
[`step_domain()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md)
columns, using the coordinated replicates for the variance, and returns
a tidy table.

## Usage

``` r
collect_estimates(est)
```

## Arguments

- est:

  a `weightflow_estimation` from
  [`step_estimate()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md).

## Value

a `weightflow_estimation_result`: one row per (estimand x domain cell)
with `estimate`, `se`, `ci_lower`, `ci_upper` and (for changes) `rho`.
The object also carries a row-aligned `detail` frame (confidence level,
effective replicates, the two wave levels behind a change and the
overlap design effect) and the pipeline's `filters`, so
[`report_panel()`](https://jpferreira33.github.io/weightflow/reference/report_panel.md)
can document the estimates without re-running them.

## See also

[`step_estimate()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md),
[`report_panel()`](https://jpferreira33.github.io/weightflow/reference/report_panel.md)
