# Kish design effect from unequal weighting

deff = 1 + CV^2(w) = m \* sum(w^2) / (sum(w))^2, over the active
weights. The effective sample size is n_eff = m / deff.

## Usage

``` r
design_effect(w)
```

## Arguments

- w:

  vector of weights (zeros are dropped).

## Value

list with deff, n_eff, cv and n.

## Examples

``` r
design_effect(sample_survey$pw)
#> $deff
#> [1] 1.052567
#> 
#> $n_eff
#> [1] 1496.342
#> 
#> $cv
#> [1] 0.2292753
#> 
#> $n
#> [1] 1575
#> 
```
