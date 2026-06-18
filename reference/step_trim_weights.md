# Automatic weight trimming (survey-style)

Caps weights into `[lower, upper]` and redistributes the change among
the untrimmed units to preserve the total, mirroring
survey::trimWeights(). By default no weight may fall below 1, and the
upper cap is set by an automatic empirical rule (Tukey far-out fence:
Q3 + 3\*IQR).

## Usage

``` r
step_trim_weights(spec, lower = 1, upper = NULL, strict = TRUE, maxit = 50L)
```

## Arguments

- spec:

  a weighting_spec.

- lower:

  numeric. Lower floor (default 1: no weight below 1).

- upper:

  numeric or NULL. Upper cap. If NULL, automatic rule Q3 + 3\*IQR of the
  active weights.

- strict:

  logical. If TRUE (default), iterate cap+redistribution until no weight
  is outside `[lower, upper]` (like survey's strict = TRUE). If FALSE, a
  single pass (redistribution may push some weights slightly past the
  cap).

- maxit:

  integer. Maximum iterations when strict = TRUE.
