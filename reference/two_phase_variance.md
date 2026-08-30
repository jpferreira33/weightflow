# Decompose a two-phase variance into V = V1 + V2

For a recipe containing
[`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md),
`two_phase_variance()` splits the recipe-aware bootstrap variance of an
estimate into its first-phase and second-phase components, \\V = V_1 +
V_2\\. The per-unit coupling factor has variance \\d = (1-f_1)\pi_2 +
(1-\pi_2)\\, the sum of the phase-1 term \\(1-f_1)\pi_2\\ and the
phase-2 conditional term \\1-\pi_2\\; running the same bootstrap with
each term in turn yields the two components.

## Usage

``` r
two_phase_variance(
  object,
  variable,
  estimator = c("mean", "total"),
  replicates = 500L,
  seed = NULL,
  fpc = NULL
)
```

## Arguments

- object:

  a `weighting_spec` (or prepped) whose recipe contains
  [`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md).

- variable:

  name of the study variable (a single column).

- estimator:

  `"mean"` (default) or `"total"`.

- replicates, seed, fpc:

  passed through to
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md).

## Value

An object of class `weightflow_tp_variance`: `V1`, `V2`, `V`, the
matching standard errors `se1`, `se2`, `se`, and `prop_phase2` = V2 / V.

## Details

The share `prop_phase2` = V2 / V is an operational read: a large share
means the second-phase subsampling drives the uncertainty, so
subsampling more would pay off; a small share means a denser (more
expensive) subsample would buy little, and the first phase is the
binding constraint.

## See also

[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md),
[`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md).

## Examples

``` r
# \donttest{
df <- transform(sample_survey,
                in2 = as.integer(runif(nrow(sample_survey)) < 0.3), p2 = 0.3)
spec <- weighting_spec(df, base_weights = pw) |>
  step_subsample(selected = in2, prob = p2, psu = "household_id")
two_phase_variance(spec, "income", replicates = 100)
#> Two-phase variance of the mean of 'income'  (V = V1 + V2)
#>   V1  phase-1  = 731721   (SE 855.41)
#>   V2  phase-2  = 1.34677e+06   (SE 1160.5)
#>   V   total    = 2.07849e+06   (SE 1441.7)
#>   phase-2 share  V2/V = 64.8%
# }
```
