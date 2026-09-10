# One period of a coordinated panel bootstrap, chained from the previous ones

Runs the whole weighting recipe of a single period, coordinates its
bootstrap with the periods that share sample with it, and returns the
cross-sectional weights, the level and net-change estimates, and a
compact **carry** artifact for the next run. It is the production
counterpart of
[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md):
that one needs every wave in memory at once, this one needs only what
the earlier runs left behind.

## Usage

``` r
wave_step(
  spec,
  previous = NULL,
  estimands = NULL,
  by = NULL,
  replicates = 500L,
  strata = NULL,
  psu = NULL,
  period = NULL,
  rotation_map = NULL,
  m = NULL,
  seed = NULL,
  refit_steps = "all",
  resample = c("multinom", "binom"),
  carry = c("auto", "thin", "fat"),
  progress = TRUE
)
```

## Arguments

- spec:

  a
  [`weighting_spec()`](https://jpferreira33.github.io/weightflow/reference/weighting_spec.md)
  for this period, with its full recipe.

- previous:

  a `wf_wave_carry` from a previous run, or a list of them; `NULL` for
  the first period of a chain.

- estimands:

  a named list of functions `function(w, data)` each returning one
  number (e.g.
  `list(unemp = function(w, d) weighted.mean(d$unemployed, w, na.rm = TRUE))`).
  Their replicate values are what the carry stores, and what the next
  period needs to compute a net change. Required to estimate change.

- by:

  optional character vector of domain columns: every estimand is also
  evaluated within each level, and the change is reported per domain.

- replicates:

  number of bootstrap replicates. Must be constant along the chain.

- strata, psu:

  column names identifying the stratum and the primary sampling unit.
  The PSU identity is nested within the stratum, so ids restarting at 1
  in each stratum are handled.

- period:

  a label for this period (defaults to `"t<seq>"`). Used in the carry
  and in the change table.

- rotation_map:

  optional named character vector mapping a new PSU id to the id of the
  PSU it replaces, in the same nested `stratum` + `psu` form. Improves
  the pairing; without it partners are matched in sorted order.

- m:

  PSUs drawn per stratum (default `n_h - 1`).

- seed:

  integer seed. The caller's RNG state is restored on exit.

- refit_steps:

  which steps to re-run per replicate; `"all"` (default) re-runs the
  entire cascade, which is what makes the variance recipe-aware.

- resample:

  `"multinom"` (default, exact Rao-Wu) or `"binom"` (legacy).

- carry:

  `"auto"` (default) stores the replicate weights only when the recipe
  needs them, i.e. when it contains a
  [`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md);
  `"thin"` forces the compact form (only the replicate values of the
  estimands); `"fat"` always stores the replicate weight matrix, which
  lets a later run estimate an estimand that was not declared here.

- progress:

  print progress messages.

## Value

an object of class `wf_wave_step` with `$weights` (the publishable
cross-sectional weights), `$level`, `$change`, `$strata` (the
per-stratum coordination report), and `$carry` – the artifact to save
for the next period.

## Details

Coordination transfers the **multiplicity** of each primary sampling
unit, following the Statistics Canada LFS (cat. 71-526-X, section 7.2.2,
after Roberts, Kovacevic, Mantel and Phillips 2001): current-period PSUs
are paired with earlier ones, common PSUs with themselves, and each
inherits its partner's multiplicity. When a stratum's PSU count is
unchanged this is a permutation, so the stratum total is preserved
exactly and every shared PSU keeps exactly its resampling; the
coordination is then exact. When the count changes, multiplicity is
added or dropped at random until the stratum total closes, and the
coordination is approximate – `$strata` reports, per stratum, the share
of replicates that needed no adjustment.

`previous` is a **list** of carries, not a single one, because which
earlier periods share sample is a property of the rotation design: a
6-consecutive design overlaps at lags 1 to 5 and nowhere else, a 4-(8)-4
design overlaps at lags 1-3 and again at 9-15, and a 1-(3)-1-(3)-1-(3)-1
design has no overlap at lag 1 at all. Each PSU inherits from the most
recent carry that holds it, so gaps and returning cohorts need no window
parameter. Supply every carry whose period shares sample with this one.

The cross-sectional weights are **not** touched by any of this:
`$weights` is exactly `prep(spec)$final_weight`.

## See also

[`wave_carry()`](https://jpferreira33.github.io/weightflow/reference/wave_carry.md),
[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md),
[`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md)
