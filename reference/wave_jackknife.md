# Coordinated delete-one jackknife across panel waves

Deterministic counterpart of
[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md):
builds delete-one-PSU replicate weights that are **coordinated** across
waves (the same PSU is removed from every wave simultaneously), so the
sampling covariance the overlap induces is captured without any
randomness. Feed the result to
[`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md)
for an honest, reproducible variance of a net change. Meant as the cheap
exact oracle to validate
[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md);
it is also a valid variance estimator in its own right.

## Usage

``` r
wave_jackknife(
  specs,
  strata = NULL,
  psu = NULL,
  refit_steps = "all",
  progress = TRUE
)
```

## Arguments

- specs:

  a **named** list of `weighting_spec` objects, one per wave; the names
  are the wave labels used by
  [`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md).

- strata, psu:

  column names of the design strata and PSU, present in every wave's
  data. The PSU id must be **consistent across waves** (the same value =
  the same PSU): that consistency is what makes the coordination
  possible. `strata = NULL` treats the whole sample as one stratum;
  `psu = NULL` treats each row as its own PSU.

- refit_steps:

  which recipe steps to re-run per replicate; see
  [`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md).
  `"all"` (default) re-preps the whole recipe; `"calibration"` freezes
  the prefix and re-runs only calibration (StatCan LFS convention).

- progress:

  show a progress message per wave.

## Value

an object of class `weightflow_wave_jack` accepted by
[`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md);
replicate columns are aligned across waves by the union of PSU ids (a
PSU absent from a wave, or alone in its stratum, yields that wave's
point weights, i.e. a zero jackknife contribution).

## Details

Self-contained: each wave's recipe is re-run through
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
on base weights with the deleted PSU zeroed and its stratum mates
reweighted by \\n_h/(n_h-1)\\; it does not modify
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
or touch `R/variance.R`.

## See also

[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md),
[`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md)

## Examples

``` r
t1 <- subset(panel_ine, ola == 1 & disp == "R")
t2 <- subset(panel_ine, ola == 2 & disp == "R")
wj <- wave_jackknife(
  list(T1 = weighting_spec(t1, base_weights = w_base),
       T2 = weighting_spec(t2, base_weights = w_base)),
  strata = "estrato", psu = "psu", progress = FALSE)
change_mean(wj, "desocupado")
#> <weightflow net change [coordinated jackknife]>
#>   T1 -> T2
#>   change     : -0.0149512   SE 0.00869933
#>   95% CI    : [-0.0320016, 0.00209913]
#>   V1 0.0001365 | V2 0.0001351 | Cov 9.795e-05 | rho 0.721   (levels)
#>   V = 7.568e-05  vs  V1+V2 = 0.0002716  (deff_change 0.279: overlap saved 72%)
```
