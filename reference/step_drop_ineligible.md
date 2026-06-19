# Drop ineligible (out-of-scope) units

Sets the weight of known-ineligible units to zero so they leave the
cascade (excluded from every later step and from collect_weights). No
redistribution is done.

## Usage

``` r
step_drop_ineligible(spec, ineligible)
```

## Arguments

- spec:

  a weighting_spec.

- ineligible:

  a 0/1 dummy column (1 = ineligible) or any logical condition
  (unquoted) that is TRUE for out-of-scope units.

## Details

Apply it AFTER step_unknown_eligibility: ineligibles must be present and
NOT flagged as unknown during that step, so they take part in the
known-eligibility group and receive their share of the redistributed
unknown weight. Their weight is then correctly discarded here (it
represents the ineligible share of the unknown units, which are out of
scope).

## Examples

``` r
df <- transform(sample_survey,
                ineligible = as.integer(region == "West" & age > 90))
weighting_spec(df, base_weights = pw) |>
  step_drop_ineligible(ineligible = ineligible) |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 1575 cases
#> Base wts: pw
#> Steps   :
#>   1. drop ineligible
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                         stage n_active sum_wts cv_wts deff_kish n_eff
#>                          base     1575   15182  0.229     1.053  1496
#>  stage_1_step_drop_ineligible     1572   15162  0.229     1.052  1494
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
