# Jackknife estimate, standard error and confidence interval

Applies a statistic to the point weights and to every delete-a-PSU
replicate, and summarises it with the stratified jackknife (JKn)
variance \$\$\sum_h \frac{n_h - 1}{n_h} \sum\_{i \in h}
(\theta\_{(hi)} - \bar\theta_h)^2,\$\$ where \\\theta\_{(hi)}\\ is the
estimate with PSU \\i\\ of stratum \\h\\ deleted and \\\bar\theta_h\\
the mean of those over the stratum. No finite population correction is
applied.

## Usage

``` r
jackknife_estimate(jack, statistic, level = 0.95)

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

  confidence level for the (normal) interval.

- variable:

  name of the variable to estimate (for `jack_total`/`jack_mean`).

## Value

A data frame with `estimate`, `se`, `ci_lower`, `ci_upper`.

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
