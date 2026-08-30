# Recipe-aware bootstrap replicate weights

Builds bootstrap replicate weights by resampling primary sampling units
(PSUs) with replacement within strata and re-running the **entire**
weighting recipe on each replicate – every estimated stage (nonresponse,
calibration, model calibration, trimming), not just one. Reach for this
when those stages are estimated from the sample and you want their
uncertainty inside the standard error, instead of conditioning on them
as if they were known.

## Usage

``` r
bootstrap_weights(
  object,
  replicates = 200L,
  strata = NULL,
  psu = NULL,
  m = NULL,
  fpc = NULL,
  lonely_psu = c("certainty", "collapse"),
  seed = NULL,
  cores = 1L,
  progress = TRUE,
  .tp_component = c("full", "phase1", "phase2")
)
```

## Arguments

- object:

  a `weighting_spec` (or a prepped one) holding the recipe.

- replicates:

  number of bootstrap replicates.

- strata, psu:

  column names of the stratum and the PSU. If `psu` is NULL each unit is
  its own PSU; if `strata` is NULL a single stratum is assumed.

- m:

  PSUs drawn per stratum (default `n - 1`).

- fpc:

  optional first-stage finite-population correction: the name of a
  column holding the first-stage sampling fraction f_h (constant within
  stratum, in `[0, 1]`), a single number applied to every stratum, or a
  numeric vector named by stratum level. `NULL` (default) is the
  with-replacement bootstrap (no correction). The correction folds
  `(1 - f_h)` into the Rao-Wu rescaling (Rao, Wu and Yue 1992; Beaumont
  and Patak 2012); `f_h = 0` reproduces the uncorrected result. Only
  available for the bootstrap.

- lonely_psu:

  how to treat strata with a single PSU (which a with-replacement
  bootstrap cannot resample): "certainty" (default) treats them as
  self-representing, so they contribute no bootstrap variance, and
  warns; "collapse" merges the single-PSU strata into a pseudo-stratum
  (with the smallest other stratum if there is only one), so they are
  resampled and do contribute a (conservative) variance. For full
  control, build your own collapsed stratum column and pass it as
  `strata`.

- seed:

  optional RNG seed.

- cores:

  number of parallel workers for the replicates (default 1 = serial).
  With `cores > 1` the replicate re-preps run in parallel via
  [`parallel::mclapply`](https://rdrr.io/r/parallel/mclapply.html)
  (forking; on Windows it falls back to serial). Results are identical
  to the serial run: the resampling is drawn up front with the seed and
  only the deterministic re-prep is parallelised.

- progress:

  print progress every 25 replicates (serial only).

- .tp_component:

  internal. For a two-phase recipe, `"full"` (default) draws the coupled
  factor; `"phase1"` / `"phase2"` draw only the phase-1 or phase-2
  component of the coupling. Used by
  [`two_phase_variance()`](https://jpferreira33.github.io/weightflow/reference/two_phase_variance.md)
  to split \\V = V_1 + V_2\\; not for direct use.

## Value

An object of class `weightflow_boot` with the `replicates` matrix (units
x replicates), the point `weights`, and the design metadata.

## Details

The multiplier is the Rao-Wu rescaling bootstrap: within a stratum with
\\n\\ PSUs, \\m\\ PSUs are drawn with replacement (default \\m = n -
1\\) and unit \\i\\ in PSU \\k\\ gets \\\lambda = 1 - \sqrt{m/(n-1)} +
\sqrt{m/(n-1)}\\(n/m)\\t_k\\, with \\t_k\\ the number of times its PSU
was drawn.

## See also

Other variance estimation:
[`as_svydesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md),
[`bootstrap_estimate()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md),
[`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_replicate_weights.md),
[`jackknife_estimate()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md),
[`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)

## Examples

``` r
spec <- weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region))))
boot <- bootstrap_weights(spec, replicates = 50, strata = "region",
                          psu = "psu", seed = 1)
#>   bootstrap replicate 25/50
#>   bootstrap replicate 50/50
boot_total(boot, "responded")
#>   estimate      se ci_lower ci_upper
#> 1 2663.277 90.4319 2486.034  2840.52
# with a first-stage finite-population correction (per-stratum sampling fraction)
d <- sample_survey; d$f <- 0.1
spec_f <- weighting_spec(d, base_weights = pw)
bootstrap_weights(spec_f, replicates = 50, strata = "region", psu = "psu",
                  fpc = "f", seed = 1)
#>   bootstrap replicate 25/50
#>   bootstrap replicate 50/50
#> <weightflow bootstrap>
#>   replicates : 50
#>   units      : 467 (active: 467)
#>   strata     : region
#>   psu        : psu
#>   df         : 96  (fpc applied)
```
