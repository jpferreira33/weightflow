# Bootstrap estimate, standard error and confidence interval

Applies a statistic to the point weights and to every replicate, and
summarises it with the bootstrap variance \\(1/B)\sum(\theta^\*\_b -
\hat\theta)^2\\.

## Usage

``` r
bootstrap_estimate(boot, statistic, level = 0.95)

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

  confidence level for the (normal) interval.

- variable:

  name of the variable to estimate.

## Value

A data frame with `estimate`, `se`, `ci_lower`, `ci_upper`.
