# Recipe-aware delete-a-PSU jackknife replicate weights

Builds jackknife replicate weights by deleting one primary sampling unit
(PSU) at a time and re-running the **entire** weighting recipe on each
replicate. This is the deterministic sibling of
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_weights.md):
same recipe-aware variance, no random number generation, and a replicate
count fixed by the design rather than chosen by the analyst.

## Usage

``` r
jackknife_weights(
  object,
  strata = NULL,
  psu = NULL,
  lonely_psu = c("certainty", "collapse"),
  cores = 1L,
  progress = TRUE
)
```

## Arguments

- object:

  a weighting_spec (inert recipe) or a prepped weighting_spec. Pass the
  recipe *before*
  [`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md):
  the jackknife preps it once per replicate.

- strata:

  name of the stratum column, or NULL for a single stratum.

- psu:

  name of the PSU column, or NULL to delete one unit at a time.

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
[`jackknife_estimate()`](https://jpferreira33.github.io/weightflow/dev/reference/jackknife_estimate.md)),
and the design metadata.

## Details

For a stratum \\h\\ with \\n_h\\ PSUs, the replicate that deletes PSU
\\i\\ zeros the base weight of that PSU and inflates the remaining PSUs
of the stratum by \\n_h/(n_h-1)\\; other strata are unchanged. There is
one replicate per PSU. Strata with a single PSU contribute no variance
and are skipped. This is the stratified jackknife (JKn); with
`strata = NULL` it is the unstratified jackknife (JK1), and with
`psu = NULL` each unit is its own PSU (delete-one-unit jackknife).

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
