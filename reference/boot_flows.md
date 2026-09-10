# Gross-flow TOTALS with standard errors, plus net flows and margins

The gross change is about the **number of people** who move between
states, i.e. totals. From a longitudinal-weight
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
object this returns, all with a bootstrap standard error computed within
each replicate: the from x to count matrix (the gross flows, in
population totals), the **net** flow matrix `i->j minus j->i`, and the
margins – the origin totals (how many started in each state), the
destination totals (how many ended in each), the stayers (the diagonal)
and the movers (off-diagonal).

## Usage

``` r
boot_flows(boot, from, to, states = NULL)
```

## Arguments

- boot:

  a `weightflow_boot` from
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  on the longitudinal recipe.

- from, to, states:

  as in
  [`transition_matrix()`](https://jpferreira33.github.io/weightflow/reference/transition_matrix.md).

## Value

a `weightflow_flows` object with `counts`/`counts_se`, `net`/`net_se`,
`origin`/`origin_se`, `dest`/`dest_se`, and `stayers`/`movers` (each
with its SE).

## See also

[`boot_transition()`](https://jpferreira33.github.io/weightflow/reference/boot_transition.md),
[`transition_matrix()`](https://jpferreira33.github.io/weightflow/reference/transition_matrix.md)
