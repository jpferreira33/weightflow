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
weighting_spec(data, base_weights = NULL, nonprob = FALSE)
```

## Arguments

- data:

  data.frame with the sample units (one row per case).

- base_weights:

  unquoted name of the design base-weight column. For a non-probability
  sample with no design weights, leave it `NULL` and set
  `nonprob = TRUE`: every unit then starts with a base weight of 1.

- nonprob:

  logical. Declare the sample as non-probability (an opt-in panel, a
  volunteer or river sample). Required when `base_weights = NULL`. The
  flag is recorded so the report states the sample is non-probability
  and adds the methodological caveat; a non-probability sample is
  usually adjusted with
  [`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/dev/reference/step_pseudoweight.md)
  (inverse participation propensity against a reference) and/or
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/dev/reference/step_calibrate.md)
  /
  [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/dev/reference/step_model_calibration.md)
  to a
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/dev/reference/reference_sample.md).
  A non-probability panel that already carries recruitment/base weights
  can pass them as `base_weights` together with `nonprob = TRUE`.

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
# a non-probability sample: no design weights, base weight 1
np <- weighting_spec(sample_survey, base_weights = NULL, nonprob = TRUE)
```
