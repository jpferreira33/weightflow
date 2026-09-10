# Linear combination of panel waves, with honest between-wave variance

Estimates any linear combination `psi = sum(contrast * theta_wave)` of a
statistic across panel waves – an annual average
(`contrast = rep(1/W, W)`), a net change (`contrast = c(-1, 1)`, i.e.
what
[`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md)
does), a semester contrast, etc. – and its variance `a' Sigma a`, where
`Sigma` is the between-wave covariance matrix that the overlap of a
rotating panel induces. That covariance is taken straight from the
coordinated replicates of
[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md)
or
[`wave_jackknife()`](https://jpferreira33.github.io/weightflow/reference/wave_jackknife.md),
so it is correct without any analytic covariance formula. Treating the
waves as independent (the diagonal of `Sigma` only) understates the
variance of an average and overstates that of a change.

## Usage

``` r
panel_estimate(
  wb,
  statistic,
  contrast = NULL,
  waves = NULL,
  level = 0.95,
  ci_type = c("normal", "t"),
  df = NULL
)

panel_mean(wb, variable, contrast = NULL, waves = NULL, level = 0.95)

panel_total(wb, variable, contrast = NULL, waves = NULL, level = 0.95)
```

## Arguments

- wb:

  a `weightflow_wave_boot` from
  [`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md)
  or a `weightflow_wave_jack` from
  [`wave_jackknife()`](https://jpferreira33.github.io/weightflow/reference/wave_jackknife.md).

- statistic:

  a function `function(w, data)` returning one number, evaluated per
  wave.

- contrast:

  numeric weights, one per wave, defining the combination; defaults to
  the equal-weight average `rep(1/W, W)`. May be named by wave label
  (matched to `waves`).

- waves:

  optional character vector of the waves to combine (defaults to all, in
  order).

- level:

  confidence level for the normal-approximation interval.

- ci_type:

  `"normal"` (default, z) or `"t"` (Student t with `df` df).

- df:

  degrees of freedom for the `"t"` interval; `NULL` uses the object's
  design df.

- variable:

  name of a numeric variable present in every wave.

## Value

an object of class `weightflow_panel_estimate` with `estimate`, `se`,
`V`, `Vind` (the independence-assuming variance), `deff = V / Vind`, the
covariance matrix `Sigma`, the per-wave `point` estimates, the
`contrast`, and the confidence interval.

## See also

[`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md),
[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md),
[`wave_jackknife()`](https://jpferreira33.github.io/weightflow/reference/wave_jackknife.md)

## Examples

``` r
waves <- lapply(1:3, function(t)
  weighting_spec(subset(panel_ine, ola == t & disp == "R"), base_weights = w_base))
names(waves) <- c("T1", "T2", "T3")
wb <- wave_bootstrap(waves, replicates = 100, strata = "estrato", psu = "psu",
                     seed = 1, progress = FALSE)
rate <- function(w, d) weighted.mean(d$desocupado, w, na.rm = TRUE)
panel_estimate(wb, rate)                       # average unemployment level over the waves
#> <weightflow panel estimate>
#>   contrast   : T1=0.333333, T2=0.333333, T3=0.333333
#>   estimate   : 0.275714   SE 0.00797932
#>   95% CI    : [0.260075, 0.291353]
#>   V = 6.367e-05  vs  V(independent) = 3.59e-05  (ratio 1.773)
#>   between-wave covariance RAISES the variance (an average-type contrast).
panel_estimate(wb, rate, contrast = c(-1, 0, 1))  # T3 - T1 change
#> <weightflow panel estimate>
#>   contrast   : T1=-1, T2=0, T3=1
#>   estimate   : 0.00100547   SE 0.0127257
#>   95% CI    : [-0.0239364, 0.0259473]
#>   V = 0.0001619  vs  V(independent) = 0.0002196  (ratio 0.737)
#>   between-wave covariance LOWERS the variance (a change-type contrast).
```
