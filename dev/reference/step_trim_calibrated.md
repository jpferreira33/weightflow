# Trimmed calibration (range-restricted, totals-preserving)

Pulls already-calibrated weights into an absolute interval
`[lower, upper]` without breaking the calibration: instead of capping
and redistributing, it re-solves a bounded calibration whose targets are
the totals the incoming weights already reproduce, optionally with its
own band per subgroup through `by`. It is the only one of the three
trimming steps that leaves the calibration totals intact.

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
  tol = 1e-07,
  id = NULL
)
```

## Arguments

- spec:

  a weighting_spec.

- formula:

  the auxiliaries whose calibration totals must be preserved (right-hand
  side only), e.g. `~ region + age_group`. Usually the same formula used
  in the preceding
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/dev/reference/step_calibrate.md).

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

- id:

  optional string: a stable identifier for this step, shown in the
  recipe print-out and usable to select it in
  [`collect_step_detail()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_step_detail.md);
  defaults to a derived `"<class>_<k>"`.

## Value

The input `weighting_spec` with this step appended to its recipe. The
step is recorded only; it is evaluated when
[`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md)
is called.

## Details

The absolute-weight bound is imposed as a per-unit factor bound
`w_new / w in [lower/w, upper/w]` on top of the incoming weights, using
a bounded (range-restricted) calibration with the truncated
Deville-Sarndal distances: the range-restricted Euclidean distance
(`calfun = "linear"`, the default) or the multiplicative one
(`calfun = "raking"`). Weights inside the range that are not needed to
restore the totals stay put; the out-of-range ones saturate at their
bound and the rest move as little as possible. If the range is too tight
to preserve every total, the totals that cannot be met are relaxed and a
warning is raised.

This step is meant to run **after** a
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/dev/reference/step_calibrate.md):
it acts on the active incoming weights (including any negative weights
an unbounded linear calibration produced, which it can bring back into
`[lower, upper]`) and leaves dropped units (weight 0) alone.

## References

Deville, J.-C. and Sarndal, C.-E. (1992). Calibration estimators in
survey sampling. Journal of the American Statistical Association, 87,
376-382. [doi:10.2307/2290268](https://doi.org/10.2307/2290268) . The
totals-preserving trimming solves a bounded (range-restricted)
calibration with the truncated distances introduced there.

## Examples

``` r
# calibrate, then trim the calibrated weights into [5.5, 13.5] without breaking
# the region/sex totals (the calibrated weights of sample_survey live in ~[5.4, 14])
weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region)),
                                sex    = c(table(population$sex)))) |>
  step_trim_calibrated(~ region + sex, lower = 5.5, upper = 13.5) |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. calibration (raking)  [calibrate_1]
#>   2. trimmed calibration [5.5, 13.5]  [trim_calibrated_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                         stage n_active sum_wts cv_wts deff_kish n_eff
#>                          base      467    4371  0.236     1.056   442
#>        stage_1_step_calibrate      467    4495  0.295     1.087   430
#>  stage_2_step_trim_calibrated      467    4495  0.297     1.088   429
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
