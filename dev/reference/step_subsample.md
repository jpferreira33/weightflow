# Second-phase subsampling (two-phase sampling)

Undoes a second phase of sampling: when a subsample of the first-phase
units was drawn for a more expensive follow-up (measuring an outcome, a
longer questionnaire), the subsampled units must represent the whole
first-phase sample. Their weight is multiplied by the inverse of the
phase-2 selection probability, and the not-subsampled units leave the
cascade (weight 0).

## Usage

``` r
step_subsample(
  spec,
  selected,
  prob,
  psu,
  strata = NULL,
  design = c("poisson", "srswor"),
  id = NULL
)
```

## Arguments

- spec:

  a weighting_spec.

- selected:

  a 0/1 dummy column (1 = selected in phase 2) or any logical condition
  (unquoted) TRUE for the subsampled units. Units that are not selected
  leave the cascade (weight 0).

- prob:

  unquoted column with the phase-2 selection probability \\\pi_2\\ of
  the selected units. The weight is multiplied by 1/prob. Must be in (0,
  1\] for every selected unit and constant within each phase-2 sampling
  unit.

- psu:

  character. The phase-2 sampling unit column (e.g. the household id at
  which the subsample was drawn). The two-phase resampling factor is
  generated at this level and shared by the members of the unit.

- strata:

  character. Phase-2 design strata (where `prob` is constant), optional.

- design:

  the phase-2 selection scheme: "poisson" (independent / Bernoulli
  selection, the default) or "srswor" (simple random sampling without
  replacement within a stratum). Only "poisson" is fully implemented in
  this version.

- id:

  optional string: a stable identifier for this step, shown in the
  recipe print-out and usable to select it in
  [`collect_step_detail()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_step_detail.md);
  defaults to a derived `"<class>_<k>"`.

## Value

The input `weighting_spec` with this step appended to its recipe. The
step is recorded only; it is evaluated when
[`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md)
is called.

## Details

The step also *records the phase-2 design* (the selection probability,
the phase-2 sampling unit, its stratification, and the selection scheme)
so that
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_weights.md)
can reproduce the two-phase variance \\V = V_1 + V_2\\: the phase-1
sampling variance plus the expected conditional variance of the phase-2
subsample. A single-phase bootstrap would only capture \\V_1\\ and
undercover.

The coupling is additive, not multiplicative: the per-unit resampling
factor has variance \\(1-f_1)\pi_2 + (1-\pi_2)\\, the sum of the phase-1
component \\(1-f_1)\pi_2\\ (seen through the subsample) and the phase-2
conditional component \\1-\pi_2\\. A naive product of two factors adds a
spurious interaction term and is too wide. In practice the factor is
drawn once per phase-2 sampling unit from a strictly positive Gamma of
that mean and variance, so every replicate weight stays positive (a
downstream propensity/GLM step re-runs cleanly). See the package's
two-phase methodology notes.

This first version covers a Poisson (independent) second phase whose
sampling unit is nested in the first phase (e.g. households subsampled
from a first-phase household sample). The phase-1 sampling fraction
\\f_1\\ is taken from the `fpc` argument of
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_weights.md)
and defaults to 0 (negligible, the usual case in household surveys),
which reduces the coupling to a single independent per-unit factor of
variance 1.

## See also

[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_weights.md)
for the two-phase variance;
[`step_select_within()`](https://jpferreira33.github.io/weightflow/dev/reference/step_select_within.md)
for within-cluster subsampling that is not a separate sampling phase.

Other weighting steps:
[`step_assert()`](https://jpferreira33.github.io/weightflow/dev/reference/step_assert.md),
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/dev/reference/step_calibrate.md),
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/dev/reference/step_drop_ineligible.md),
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/dev/reference/step_model_calibration.md),
[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/dev/reference/step_nonresponse.md),
[`step_nr_sensitivity()`](https://jpferreira33.github.io/weightflow/dev/reference/step_nr_sensitivity.md),
[`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/dev/reference/step_pseudoweight.md),
[`step_rescale()`](https://jpferreira33.github.io/weightflow/dev/reference/step_rescale.md),
[`step_round()`](https://jpferreira33.github.io/weightflow/dev/reference/step_round.md),
[`step_select_within()`](https://jpferreira33.github.io/weightflow/dev/reference/step_select_within.md),
[`step_trim()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim.md),
[`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim_calibrated.md),
[`step_trim_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim_weights.md),
[`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/dev/reference/step_unknown_eligibility.md)

## Examples

``` r
# households subsampled for a follow-up module, selected with prob p2
df <- transform(sample_survey,
                in_phase2 = as.integer(runif(nrow(sample_survey)) < 0.3),
                p2 = 0.3)
weighting_spec(df, base_weights = pw) |>
  step_subsample(selected = in_phase2, prob = p2, psu = "household_id")
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. phase-2 subsample  [subsample_1]
#> Status  : not estimated
#> 
```
