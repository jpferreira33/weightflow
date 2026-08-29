# Jackknife estimate, standard error and confidence interval

Applies a statistic to the point weights and to every delete-a-PSU
replicate, and returns the estimate with its stratified jackknife (JKn)
standard error and a normal confidence interval. `jack_total()` and
`jack_mean()` are the shortcuts for a weighted total and a weighted mean
of one column.

## Usage

``` r
jackknife_estimate(
  jack,
  statistic,
  level = 0.95,
  ci_type = c("normal", "t"),
  df = NULL
)

jack_total(jack, variable)

jack_mean(jack, variable)
```

## Arguments

- jack:

  a `weightflow_jack` object.

- statistic:

  a function `function(w, data)` returning a numeric scalar (or vector)
  given a weight vector and the data.

- level:

  confidence level for the interval.

- ci_type:

  interval type: "normal" (default) or "t" (Student t with the design
  degrees of freedom). The percentile interval is not defined for the
  jackknife.

- df:

  degrees of freedom for the t interval; `NULL` (default) uses the
  design df stored on the object (total PSUs minus strata).

- variable:

  name of the variable to estimate (for `jack_total`/`jack_mean`).

## Value

A data frame with `estimate`, `se`, `ci_lower`, `ci_upper`.

## Details

The stratified (JKn) variance sums each stratum's delete-a-PSU spread,
\$\$\widehat V\_{JK} = \sum_h \frac{n_h - 1}{n_h}\sum\_{i \in
h}\big(\hat\theta\_{(hi)} - \hat\theta_h\big)^2,\$\$ with
\\\hat\theta\_{(hi)}\\ the estimate with PSU \\i\\ of stratum \\h\\
deleted and \\\hat\theta_h\\ their within-stratum mean; the unstratified
JK1 uses a single stratum. No finite population correction is applied.

## Note

`jack_total()` / `jack_mean()` center the replicate deviations on the
per-stratum mean of the deleted-PSU estimates (the standard JKn). The
`survey` design built by
[`as_svrepdesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
instead uses `mse = TRUE`, which centers on the point estimate. Both are
legitimate, so the standard errors from `jack_total()` and from
`svytotal()` on the same object can differ slightly.

## See also

Other variance estimation:
[`as_svydesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md),
[`bootstrap_estimate()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md),
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md),
[`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_replicate_weights.md),
[`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)

## Examples

``` r
spec <- weighting_spec(sample_one, base_weights = pw) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region))))
jk <- jackknife_weights(spec, strata = "region", psu = "psu", progress = FALSE)
jackknife_estimate(jk, function(w, d) sum(w * d$employed, na.rm = TRUE))
#>   estimate       se ci_lower ci_upper
#> 1 1031.456 85.28049 864.3092 1198.603
```
