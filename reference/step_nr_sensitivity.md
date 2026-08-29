# Sensitivity of a mean to nonignorable nonresponse or selection

A diagnostic step (it does not change any weight) that gauges how much
the weighted mean of a study variable could move if response, or
participation in a non-probability sample, depended on the outcome
itself beyond the observed auxiliaries. It implements the proxy
pattern-mixture model of Andridge and Little (2011): the auxiliaries are
reduced to a single proxy (the respondent regression prediction of `y`),
and a single sensitivity parameter `phi` in `[0, 1]` moves the mechanism
from ignorable given the proxy (`phi = 0`, MAR) to depending only on the
outcome (`phi = 1`). Evaluated over a grid of `phi`, the adjusted means
form an *ignorance interval* to read alongside the sampling confidence
interval; see
[`nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/nr_sensitivity.md)
and the report block.

## Usage

``` r
step_nr_sensitivity(
  spec,
  y,
  formula,
  respondent = NULL,
  eligible = NULL,
  phi = c(0, 0.25, 0.5, 0.75, 1),
  id = NULL
)
```

## Arguments

- spec:

  a `weighting_spec`.

- y:

  the study variable (bare column name), observed for respondents and
  `NA` for nonrespondents.

- formula:

  one-sided formula of the auxiliaries for the proxy, observed for all
  units, e.g. `~ region + sex + age`.

- respondent:

  optional response/participation indicator (bare column or condition).
  Defaults to `!is.na(y)`.

- eligible:

  optional in-scope indicator (bare column or condition), the mirror of
  the argument in
  [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md).
  Out-of-scope (ineligible) units are neither respondents nor
  nonrespondents and must be excluded, or they would be counted as
  nonrespondents and pull the estimate toward their proxy mean. Give it
  in any household survey that has ineligible units. Default `NULL`
  treats every active unit as in scope.

- phi:

  the sensitivity grid, values in `[0, 1]`; `0` (MAR) is always added.
  Little et al. (2020) suggest `0.5` as a central value; above `0.5` the
  implied mechanism is often unrealistically strong.

- id:

  optional stable step id.

## Value

the input `weighting_spec` with this diagnostic step appended.

## Details

The proxy correlation `rho` (the multiple correlation of `y` on the
auxiliaries among respondents) sets how informative the auxiliaries are:
a weak proxy widens the ignorance interval (at `phi = 1` the slope is
`1/rho`). The step reads the base design weights, so place it anywhere
in the recipe; it needs the nonrespondents still present (a study
variable that is `NA` for them, or an explicit `respondent` indicator).

## References

Andridge, R. R. and Little, R. J. A. (2011). Proxy pattern-mixture
analysis for survey nonresponse. Journal of Official Statistics 27(2),
153-180.

## See also

[`nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/nr_sensitivity.md),
[`step_assert()`](https://jpferreira33.github.io/weightflow/reference/step_assert.md)

Other weighting steps:
[`step_assert()`](https://jpferreira33.github.io/weightflow/reference/step_assert.md),
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md),
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md),
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md),
[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md),
[`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/reference/step_pseudoweight.md),
[`step_rescale()`](https://jpferreira33.github.io/weightflow/reference/step_rescale.md),
[`step_round()`](https://jpferreira33.github.io/weightflow/reference/step_round.md),
[`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md),
[`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md),
[`step_trim()`](https://jpferreira33.github.io/weightflow/reference/step_trim.md),
[`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md),
[`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md),
[`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md)
