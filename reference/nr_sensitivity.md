# Read the nonresponse-sensitivity analysis from a prepped recipe

Returns the proxy pattern-mixture ignorance analysis stored by
[`step_nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/step_nr_sensitivity.md):
the adjusted mean of the study variable at each `phi`, with the
ignorance interval and the proxy strength.

## Usage

``` r
nr_sensitivity(object, step = NULL)
```

## Arguments

- object:

  a prepped `weighting_spec` containing a
  [`step_nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/step_nr_sensitivity.md).

- step:

  optional step id to select among several sensitivity steps (for
  example one per study variable). With one step it can be left `NULL`.

## Value

a list (class `weightflow_nr_sensitivity`) with `table` (`phi`, `mu`),
`rho`, `ybar_r`, `ignorance` (the min-max interval over `phi`), `mu_mar`
(the `phi = 0` estimate) and the respondent/nonrespondent counts.

## See also

[`step_nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/step_nr_sensitivity.md)
