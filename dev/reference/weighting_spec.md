# Start a weighting specification

Opens a weighting recipe on a sample and its design base weights. The
object it returns is inert: it holds the data, the name of the
base-weight column and an empty list of steps, and computes nothing.
Every `step_*()` function takes such an object and returns it with one
more step appended;
[`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md)
estimates the result.

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
#> Data    : 467 cases
#> Base wts: pw
#> Steps   : (none yet)
#> Status  : not estimated
#> 
```
