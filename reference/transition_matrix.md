# Gross-flow transition matrix between two panel waves

Weighted cross-tabulation of a categorical state at an earlier wave
(`from`) against a later wave (`to`) – e.g. the labour-force status of
the same people across two periods – computed on the **longitudinal**
weight. This is the gross flow (CEPAL ch. XVII): who moved between which
states.
[`boot_transition()`](https://jpferreira33.github.io/weightflow/reference/boot_transition.md)
adds a per-cell standard error from the ordinary bootstrap.

## Usage

``` r
transition_matrix(
  data,
  from,
  to,
  weights = NULL,
  states = NULL,
  format = c("row", "col", "joint", "counts")
)
```

## Arguments

- data:

  a `data.frame` (wide longitudinal file) or a prepped `weighting_spec`.

- from, to:

  names of the earlier- and later-wave state columns.

- weights:

  a weight column name or a numeric vector; defaults to 1 (or the
  prepped weight when `data` is a prepped spec).

- states:

  optional character vector fixing the state levels and their order.

- format:

  `"row"` (default, P(to\|from)), `"col"` (P(from\|to)), `"joint"`
  (P(from,to)) or `"counts"` (weighted counts).

## Value

a `weightflow_transition` object holding the matrix.

## Why there is a single weight, and not two

Feinberg and Stasny (1983) describe a gross-change table built from the
**two cross-sectional weights**: when \\w\_{k,t-1} \neq w\_{k,t}\\, the
smaller weight goes to the (i, j) cell and the difference goes to an
"out of population" cell – (Outside, j) or (i, Outside) depending on the
sign – on the assumption that the weights differ only because of natural
entries to and exits from the target population. ECLAC cites it (ch.
XVI, sec. B) as the state of things *before* a longitudinal weight is
built.

This function takes **one** weight because the package builds that
longitudinal weight instead, by the sequence the same chapter
prescribes: panel base weight, adjustment for nonresponse in the first
period, an explicit definition of the longitudinal population, the
attrition adjustment and the final calibration. Once that weight exists
the discrepancy Feinberg-Stasny reconstructs no longer arises – who left
the population was decided explicitly at
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md)
rather than inferred from a difference between two weights. The
two-weight construction is the alternative to the longitudinal weight,
not a complement to it.

## See also

[`boot_transition()`](https://jpferreira33.github.io/weightflow/reference/boot_transition.md)
