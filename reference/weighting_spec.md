# Start a weighting specification

Creates an inert recipe object. Nothing is computed until prep() is
called.

## Usage

``` r
weighting_spec(data, base_weights)
```

## Arguments

- data:

  data.frame with the sample units (one row per case).

- base_weights:

  unquoted name of the design base-weight column.

## Value

an object of class "weighting_spec".

## Examples

``` r
rec <- weighting_spec(sample_survey, base_weights = pw)
rec
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 1575 cases
#> Base wts: pw
#> Steps   : (none yet)
#> Status  : not estimated
#> 
```
