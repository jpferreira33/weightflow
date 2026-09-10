# Coordinated bootstrap across panel waves

Builds recipe-aware bootstrap replicate weights for two or more waves
that are **coordinated** by PSU: a PSU present in several waves gets the
same resampling in all of them, so the sampling covariance between waves
– which the overlap of a rotating panel induces – is captured. Feed the
result to
[`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md)
for the honest variance of a net change. Ignoring the coordination (a
separate per-wave bootstrap) over-estimates the variance of change
whenever the waves overlap and are correlated.

## Usage

``` r
wave_bootstrap(
  specs,
  replicates = 500L,
  strata = NULL,
  psu = NULL,
  m = NULL,
  seed = NULL,
  refit_steps = "all",
  resample = c("multinom", "binom"),
  progress = TRUE
)
```

## Arguments

- specs:

  a **named** list of `weighting_spec` objects, one per wave; the names
  are the wave labels used by
  [`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md).

- replicates:

  number of bootstrap replicates.

- strata, psu:

  column names of the design strata and PSU, present in every wave's
  data. The PSU id must be **consistent across waves** (the same value =
  the same PSU): that consistency is what makes the coordination
  possible. `strata = NULL` treats the whole sample as one stratum;
  `psu = NULL` treats each row as its own PSU.

- m:

  optional PSU resample size per stratum (default `n_h - 1`, the Rao-Wu
  choice).

- seed:

  optional integer seed for the permanent uniforms (reproducibility).

- refit_steps:

  which recipe steps to re-run per replicate. `"all"` (default, the
  honest recipe-aware bootstrap) re-preps the whole recipe, propagating
  the variance of every step. `"calibration"` freezes everything up to
  the first calibration step and re-runs only calibration per replicate
  – the Statistics Canada LFS convention (the Rao-Wu factor is applied
  to the frozen pre-calibration subweight). A character vector of step
  classes (e.g. `c("step_nonresponse", "step_calibrate")`) splits at the
  first one matched: the prefix is frozen, the suffix re-prepped. The
  point estimate always uses the full recipe; only the replicate
  variance is affected.

- resample:

  the Rao-Wu resample scheme. `"multinom"` (default) draws an exact
  multinomial per stratum (counts sum to `m_h`), the centred Rao-Wu
  draw, which gives an unbiased replicate variance for
  composite/calibration estimators and for totals; `"binom"` (legacy)
  draws an independent binomial per PSU (counts need not sum to `m_h`),
  which loses the multinomial's negative between-PSU covariance and
  estimates an uncentred variance – only mildly high for a ratio or mean
  (~+8-10%) but a large overestimate for a **total** (up to an order of
  magnitude), so use `"multinom"` when estimating totals. Both share the
  per-PSU uniforms; the multinomial coordinates across rotating waves
  exactly when the PSU sets match (identical or disjoint waves) and
  approximately otherwise.

- progress:

  show a progress message per wave.

## Value

an object of class `weightflow_wave_boot`: per-wave point weights,
replicate matrices (aligned by replicate index across waves), the
per-wave data, and the design.

## Details

Self-contained: it does not modify
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md);
each wave's recipe is re-run through
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
on perturbed base weights, exactly as the single-sample bootstrap does,
but with a PSU-coordinated Rao-Wu draw shared across waves.

Composite (CRE) recursion is handled automatically: when a wave's recipe
holds a
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
whose `previous` is the preceding wave, that wave's estimated control
totals `Zhat*` are re-estimated per replicate from the previous wave's
replicate-b weights (not the frozen point weights), so the reported
variance includes the sampling variance of `Zhat` itself. Waves are
processed in order and each wave's replicate matrix is carried into the
next, giving the full coordinated variance of the recursive estimator.
(Assumes each `step_cre`'s `previous` is the immediately preceding wave
in `specs`; otherwise that step keeps its fixed point `previous`.)

## See also

[`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md),
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md),
[`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)

## Examples

``` r
t1 <- subset(panel_ine, ola == 1 & disp == "R")
t2 <- subset(panel_ine, ola == 2 & disp == "R")
wb <- wave_bootstrap(
  list(T1 = weighting_spec(t1, base_weights = w_base),
       T2 = weighting_spec(t2, base_weights = w_base)),
  replicates = 200, strata = "estrato", psu = "psu", seed = 1, progress = FALSE)
change_estimate(wb, function(w, d) weighted.mean(d$desocupado, w, na.rm = TRUE))
#> <weightflow net change>
#>   T1 -> T2
#>   change     : -0.0149512   SE 0.00944777
#>   95% CI    : [-0.0334685, 0.00356605]
#>   V1 0.0001239 | V2 0.0001211 | Cov 7.791e-05 | rho 0.636   (levels)
#>   V = 8.926e-05  vs  V1+V2 = 0.0002451  (deff_change 0.364: overlap saved 64%)
```
