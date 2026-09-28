# Recipe-aware delete-a-PSU jackknife replicate weights

Builds jackknife replicate weights by deleting one primary sampling unit
(PSU) at a time and re-running the **entire** weighting recipe on each
replicate. This is the deterministic sibling of
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md):
same recipe-aware variance, no random number generation, and a replicate
count fixed by the design rather than chosen by the analyst.

## Usage

``` r
jackknife_weights(
  object,
  strata = NULL,
  psu = NULL,
  groups = NULL,
  seed = NULL,
  lonely_psu = c("certainty", "collapse"),
  cores = 1L,
  progress = TRUE
)
```

## Arguments

- object:

  a weighting_spec (inert recipe) or a prepped weighting_spec. Pass the
  recipe *before*
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md):
  the jackknife preps it once per replicate.

- strata:

  name of the stratum column, or NULL for a single stratum.

- psu:

  name of the PSU column, or NULL to delete one unit at a time.

- groups:

  NULL (default) or the number of random groups `G` for a delete-a-group
  jackknife on a direct sample. Units are assigned to groups at random
  within each stratum and one group is deleted per replicate, giving `G`
  replicates instead of one per unit. Requires `psu = NULL`: the group
  replaces the PSU, it does not nest inside one.

- seed:

  optional integer seed for the random group assignment, so the
  replicates are reproducible. The caller's RNG state is restored on
  exit.

- lonely_psu:

  how to treat strata with a single PSU: "certainty" (default) skips
  them (no variance) and warns; "collapse" merges them into a
  pseudo-stratum so they yield delete-a-PSU replicates.

- cores:

  number of parallel workers for the replicates (default 1 = serial).
  With `cores > 1` the replicate re-preps run in parallel via
  [`parallel::mclapply`](https://rdrr.io/r/parallel/mclapply.html)
  (forking; serial on Windows). For a deterministic recipe the result is
  identical to the serial run.

- progress:

  print progress every 25 replicates (serial only).

## Value

An object of class `weightflow_jack` with the `replicates` matrix (units
x replicates), the point `weights`, the per-replicate stratum and
stratum size (used by
[`jackknife_estimate()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)),
and the design metadata.

## Details

For a stratum \\h\\ with \\n_h\\ PSUs, the replicate that deletes PSU
\\i\\ zeros the base weight of that PSU and inflates the remaining PSUs
of the stratum by \\n_h/(n_h-1)\\; other strata are unchanged. There is
one replicate per PSU. Strata with a single PSU contribute no variance
and are skipped. This is the stratified jackknife (JKn); with
`strata = NULL` it is the unstratified jackknife (JK1), and with
`psu = NULL` each unit is its own PSU (delete-one-unit jackknife).

With a direct (element) sample the delete-one-unit jackknife is the
right estimator, but it needs one replicate per unit: the whole recipe
is re-prepped `n` times and the replicate matrix is `n x n`, which is 80
GB at n = 100,000. `groups` gives the standard device for that case, the
**delete-a-group** jackknife (Kott 2001; Rust and Rao 1996): the sample
is partitioned at random into `G` groups within each stratum and one
whole group is deleted at a time, so there are `G` replicates instead of
`n`. It is the same estimator the engine already computes – the group
simply plays the part of the PSU – with \\(G-1)/G\\ in place of
\\(n_h-1)/n_h\\, and `df = G - strata`, which is the honest precision of
the variance. `G` between 30 and 100 is the usual range; it is not
defaulted, because the choice is the analyst's and the delete-one and
delete-a-group variances are not the same number (the second is
noisier).

## See also

Other variance estimation:
[`as_svydesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md),
[`bootstrap_estimate()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md),
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md),
[`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_replicate_weights.md),
[`jackknife_estimate()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)

## Examples

``` r
spec <- weighting_spec(sample_one, base_weights = pw) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region))))
jk <- jackknife_weights(spec, strata = "region", psu = "psu", progress = FALSE)
jack_total(jk, "employed")
#>   estimate       se ci_lower ci_upper
#> 1 1031.456 85.28049 864.3092 1198.603
```
