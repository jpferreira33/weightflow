# Transition matrix with per-cell bootstrap standard errors

Like
[`transition_matrix()`](https://jpferreira33.github.io/weightflow/reference/transition_matrix.md),
but every cell also gets a standard error and confidence interval from
the bootstrap replicate weights of a longitudinal-weight
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
object, by re-tabulating the flow within each replicate. The recipe is
re-run per replicate, so the uncertainty of the longitudinal weighting
propagates into the flow SEs.

## Usage

``` r
boot_transition(
  boot,
  from,
  to,
  states = NULL,
  format = c("row", "col", "joint", "counts")
)
```

## Arguments

- boot:

  a `weightflow_boot` from
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  on the longitudinal recipe.

- from, to, states, format:

  as in
  [`transition_matrix()`](https://jpferreira33.github.io/weightflow/reference/transition_matrix.md).

## Value

a `weightflow_transition_boot` with `estimate`, `se`, `ci_lower`,
`ci_upper` matrices.

## See also

[`transition_matrix()`](https://jpferreira33.github.io/weightflow/reference/transition_matrix.md),
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
