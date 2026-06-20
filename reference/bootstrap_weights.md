# Bootstrap replicate weights that re-apply the recipe

Builds bootstrap replicate weights by resampling primary sampling units
(PSUs) with replacement within strata and re-running the whole recipe on
each replicate. Because every adjustment (nonresponse, calibration, ...)
is recomputed per replicate, the resulting replicate weights propagate
the variability introduced by each weighting stage.

## Usage

``` r
bootstrap_weights(
  object,
  replicates = 200L,
  strata = NULL,
  psu = NULL,
  m = NULL,
  seed = NULL,
  progress = TRUE
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

- seed:

  optional RNG seed.

- progress:

  print progress every 25 replicates.

## Value

An object of class `weightflow_boot` with the `replicates` matrix (units
x replicates), the point `weights`, and the design metadata.

## Details

The multiplier is the Rao-Wu rescaling bootstrap: within a stratum with
\\n\\ PSUs, \\m\\ PSUs are drawn with replacement (default \\m = n -
1\\) and unit \\i\\ in PSU \\k\\ gets \\\lambda = 1 - \sqrt{m/(n-1)} +
\sqrt{m/(n-1)}\\(n/m)\\t_k\\, with \\t_k\\ the number of times its PSU
was drawn.

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
#> 1 2663.277 99.4537 2468.351 2858.203
```
