# Extract the carry artifact of a period

The object
[`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
leaves for the next run: the PSU multiplicities that coordinate the next
period's bootstrap, the replicate values of the declared estimands, and
– only when the recipe needs them – the replicate weights.

## Usage

``` r
wave_carry(x)
```

## Arguments

- x:

  a `wf_wave_step` from
  [`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md).

## Value

a `wf_wave_carry`, to be saved
([`saveRDS()`](https://rdrr.io/r/base/readRDS.html)) and passed as
`previous` next period.

## See also

[`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
