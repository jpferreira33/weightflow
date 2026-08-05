# Trimmed calibration (range-restricted, totals-preserving)

Trims already-calibrated weights into an absolute interval
`[lower, upper]` **while preserving the calibration totals** of
`formula`. Unlike
[`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md)
(which caps and then redistributes the trimmed mass, so the calibration
constraints are broken), this is a bounded re-calibration: it finds the
weights closest to the incoming ones that both lie in `[lower, upper]`
and still reproduce the totals the incoming weights achieve (the
generalized exponential method of Folsom & Singh 2000). The
absolute-weight bound is imposed as a per-unit factor bound
`w_new / w in [lower/w, upper/w]` on top of the incoming weights, using
the range-restricted Euclidean distance (`calfun = "linear"`, the
default) or the multiplicative one (`calfun = "raking"`). Weights inside
the range that are not needed to restore the totals stay put; the
out-of-range ones saturate at their bound and the rest move as little as
possible. If the range is too tight to preserve every total, the totals
that cannot be met are relaxed and a warning is raised.

## Usage

``` r
step_trim_calibrated(
  spec,
  formula,
  lower = NULL,
  upper = NULL,
  calfun = c("linear", "raking"),
  by = NULL,
  cluster = NULL,
  equal_within_cluster = FALSE,
  maxit = 100L,
  tol = 1e-07
)
```

## Arguments

- spec:

  a weighting_spec.

- formula:

  the auxiliaries whose calibration totals must be preserved (right-hand
  side only), e.g. `~ region + age_group`. Usually the same formula used
  in the preceding
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md).

- lower, upper:

  numeric. Absolute bounds on the trimmed weight. At least one must be
  supplied; the other defaults to no bound. For positive variance, use a
  positive `lower`. Each may be a single number (the same bound for
  every unit) or, together with `by`, a named vector of bounds per
  subgroup (names = the `by` group levels), for differentiated trimming.

- calfun:

  distance function: "linear" (default; the range-restricted Euclidean
  distance) or "raking" (the multiplicative distance, which keeps the
  adjustment factors positive).

- by:

  character or NULL. Subgroup column for differentiated bounds: with a
  named-vector `lower`/`upper`, each subgroup is trimmed to its own
  bounds while the preserved totals of `formula` stay global. NULL
  (default) uses the same bounds for all units.

- cluster:

  character or NULL. Cluster (e.g. household) id column, for integrative
  trimming (with `equal_within_cluster = TRUE`).

- equal_within_cluster:

  logical. If TRUE, integrative trimming: one trimming factor per
  `cluster`, so weights stay constant within household. The incoming
  weights must already be constant within cluster (e.g. from
  `step_calibrate(equal_within_cluster = TRUE)`); the absolute bound
  then applies to that common household weight. Requires `cluster`.
  FALSE (default) trims each unit on its own.

- maxit:

  integer. Maximum iterations for the bounded solver.

- tol:

  numeric. Convergence tolerance for the bounded solver.

## Value

The input `weighting_spec` with this step appended to its recipe. The
step is recorded only; it is evaluated when
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
is called.

## Details

This step is meant to run **after** a
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md):
it acts on the positive incoming weights and leaves dropped units
(weight 0) alone.

## References

Folsom, R. E. and Singh, A. C. (2000). The generalized exponential model
for sampling weight calibration for extreme values, nonresponse, and
poststratification. *ASA Proceedings of the Section on Survey Research
Methods*, 598-603.

## Examples

``` r
# calibrate, then trim the calibrated weights into [50, 400] without breaking
# the region/sex totals
weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region)),
                                sex    = c(table(population$sex)))) |>
  step_trim_calibrated(~ region + sex, lower = 50, upper = 400) |>
  prep()
#> Warning: Bounded calibration did not fully converge (bounds may be infeasible).
#> Warning: Trimmed calibration could not both stay within [50, 400] and preserve every total (max relative deviation = 7.75e+00). The range may be infeasible; widen the bounds or relax the constraints.
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. calibration (raking)
#>   2. trimmed calibration [50, 400]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                         stage n_active sum_wts cv_wts deff_kish n_eff
#>                          base      467    4371  0.236     1.056   442
#>        stage_1_step_calibrate      467    4495  0.295     1.087   430
#>  stage_2_step_trim_calibrated      467   23350  0.000     1.000   467
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
