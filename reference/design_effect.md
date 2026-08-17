# Kish design effect from unequal weighting

Computes Kish's design effect due to unequal weighting, \\deff = 1 +
CV^2(w) = m \sum w^2 / (\sum w)^2\\, and the effective sample size
\\n\_\mathrm{eff} = m / deff\\ it implies. It is the standard one-number
summary of what a weighting cascade cost in precision, and it is what
the [`summary()`](https://rdrr.io/r/base/summary.html) and
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) methods of a
prepped recipe report step by step.

## Usage

``` r
design_effect(w)
```

## Arguments

- w:

  vector of weights (zeros are dropped; negative weights are kept
  active, but see the note above on the design effect).

## Value

list with deff, n_eff, cv and n.

## Details

Zero weights are dropped (they are the "dropped-unit" marker); negative
weights – a valid but unusual output of unbounded linear/GREG
calibration – are kept active, so the count `n` matches
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md).
Be aware, however, that the Kish formula assumes non-negative weights: a
negative weight shrinks \\\sum w\\ and enlarges \\\sum w^2\\ at once, so
with negatives present `deff` is inflated and no longer interpretable as
an effective-sample summary.
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
raises an alert when a calibration produces negative weights; prefer
`bounds` to keep the factor positive if you need the design effect to be
meaningful.

## Examples

``` r
design_effect(sample_survey$pw)
#> $deff
#> [1] 1.055596
#> 
#> $n_eff
#> [1] 442.4043
#> 
#> $cv
#> [1] 0.2357872
#> 
#> $n
#> [1] 467
#> 
```
