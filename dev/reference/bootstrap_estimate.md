# Bootstrap estimate, standard error and confidence interval

Applies a statistic to the point weights and to every bootstrap
replicate, and returns the estimate with its bootstrap standard error
and a normal confidence interval. `boot_total()` and `boot_mean()` are
the two shortcuts you will use most: a weighted total and a weighted
mean of one column.

## Usage

``` r
bootstrap_estimate(
  boot,
  statistic,
  level = 0.95,
  ci_type = c("normal", "t", "percentile"),
  df = NULL
)

boot_total(boot, variable)

boot_mean(boot, variable)
```

## Arguments

- boot:

  a `weightflow_boot` object.

- statistic:

  a function `function(w, data)` returning a numeric scalar (or vector)
  given a weight vector and the data.

- level:

  confidence level for the interval.

- ci_type:

  interval type: "normal" (default, z-based), "t" (Student t with the
  design degrees of freedom, wider and less anticonservative with few
  PSUs), or "percentile" (empirical quantiles of the valid replicates).

- df:

  degrees of freedom for the t interval; `NULL` (default) uses the
  design df stored on the object (total PSUs minus strata).

- variable:

  name of the variable to estimate.

## Value

A data frame with `estimate`, `se`, `ci_lower`, `ci_upper`.

## Details

The bootstrap variance takes the replicate estimates
\\\hat\theta^{\*}\_b\\ around the point estimate \\\hat\theta\\ (the
`mse = TRUE` convention of `survey`), over the \\R\\ valid replicates (a
failed replicate is dropped, not counted), \$\$\widehat
V\_{\mathrm{boot}}(\hat\theta) =
\frac{1}{R}\sum\_{b=1}^{R}\big(\hat\theta^{\*}\_b -
\hat\theta\big)^2.\$\$
