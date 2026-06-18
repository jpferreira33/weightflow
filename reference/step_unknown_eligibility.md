# Unknown-eligibility adjustment

Redistributes the weight of unknown-eligibility cases among the
known-eligibility cases, within the cells defined by `by`.

## Usage

``` r
step_unknown_eligibility(spec, unknown, by = NULL)
```

## Arguments

- spec:

  a weighting_spec.

- unknown:

  a 0/1 dummy column (1 = eligibility unknown) or any logical condition
  (unquoted) that is TRUE for unknown-eligibility cases. Evaluated on
  the data.

- by:

  character. Variables defining the adjustment cells (optional).
