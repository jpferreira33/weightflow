# Data-defect diagnostics for a non-probability sample

For a non-probability sample, Meng (2018) decomposes the error of the
sample mean into the data-defect correlation (`rho`, the population
correlation between the target variable and the participation
indicator), the sampling fraction and the problem difficulty. The
effective sample size a probability sample would need to match the same
mean-squared error is \$\$n\_{\mathrm{eff}} = \frac{f/(1-f)}{\rho^2},
\qquad f = n/N,\$\$ which does not depend on the outcome except through
`rho`. Because `rho` on the target variable is not observable from the
sample alone, `data_defect()` returns the effective size across a grid
of plausible residual `rho` (read it as an ignorance range, not a single
number), plus the measurable selection strength on the covariates used
for pseudo-weighting (the largest correlation between an auxiliary and
participation, which pseudo-weighting neutralises).

## Usage

``` r
data_defect(object, ddc_grid = c(0.001, 0.005, 0.01, 0.05, 0.1))
```

## Arguments

- object:

  a prepped non-probability `weighting_spec` (from
  [`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md),
  built with `weighting_spec(..., nonprob = TRUE)`).

- ddc_grid:

  the residual data-defect correlations to tabulate. Positive values;
  only their magnitude matters.

## Value

a list (class `weightflow_data_defect`) with the sample size `n`, the
estimated population size `N` (the sum of the final weights), the
fraction `f`, the sensitivity `grid` (`ddc`, `n_eff`), and `aux`, a data
frame of the covariate-participation correlations (or `NULL` when the
recipe has no pseudo-weighting step).

## References

Meng, X.-L. (2018). Statistical paradises and paradoxes in big data (I).
Annals of Applied Statistics 12(2), 685-726.

## See also

[`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/dev/reference/step_pseudoweight.md),
[`report_weighting()`](https://jpferreira33.github.io/weightflow/dev/reference/report_weighting.md)
