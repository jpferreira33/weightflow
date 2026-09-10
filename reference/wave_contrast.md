# Linear combination of an estimand across a chain of periods

[`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
reports the level of its own period and the net change against each
carry it was given – that is, **pairwise** contrasts. Many published
series are not pairwise: a rolling quarter is the average of three
consecutive months, a semester-on-semester contrast is
`c(-1/2, -1/2, 1/2, 1/2)`, an annual average is `rep(1/W, W)`.
`wave_contrast()` estimates any such combination \\\psi = a'\theta\\
directly from the carries the chain already wrote to disk, with
\\V(\psi) = a' \Sigma a\\.

## Usage

``` r
wave_contrast(carries, estimand, contrast = NULL, level = 0.95)
```

## Arguments

- carries:

  a list of `wf_wave_carry` objects, one per period entering the
  combination. Order defines the order of `contrast`; they are used as
  given (not sorted).

- estimand:

  name of the estimand to combine, as it appears in `carry$point` (a
  domain estimand is named e.g. `"rate|sex=F"`).

- contrast:

  numeric weights, one per carry. Defaults to the average `rep(1/W, W)`.

- level:

  confidence level for the interval.

## Value

a one-row `data.frame` with `estimate`, `se`, `V`, `lo`, `hi`, `R_used`,
the periods and the contrast used, plus the covariance matrix `Sigma` as
an attribute.

## Details

The carries make this possible without keeping the waves in memory: each
one stores the `R` replicate values of every declared estimand, and
those replicates are **paired across periods** because the coordination
transferred the PSU multiplicities. Stacking them into an `R x W` matrix
and taking its (uncentred-at-`R`) covariance recovers the full
between-period covariance matrix, from which any linear combination
follows. With `contrast = c(-1, 1)` the result reproduces the `$change`
row of
[`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
exactly.

## See also

[`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md),
[`wave_carry()`](https://jpferreira33.github.io/weightflow/reference/wave_carry.md);
[`panel_estimate()`](https://jpferreira33.github.io/weightflow/reference/panel_estimate.md)
does the same on a
[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md)
object, when all waves are held together.
