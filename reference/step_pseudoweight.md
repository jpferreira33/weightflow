# Pseudo-weights for a non-probability sample against a reference

For a non-probability sample (opt-in panel, volunteer or river sample)
with no design weights, `step_pseudoweight()` estimates each unit's
*participation propensity* `p` against a probability
[`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
and assigns the pseudo-weight `(1 - p)/p` (the participation odds;
Elliott and Valliant 2017), which inflates each unit to the population
so the weights sum to the reference's estimated population size. It
stacks the non-probability sample and the reference internally (the
participation indicator and the two samples' weights are built for you),
fits the propensity, and returns the pseudo-weight on the
non-probability units only; the reference is used to train the model and
then dropped.

## Usage

``` r
step_pseudoweight(
  spec,
  reference,
  formula,
  engine = c("logit", "tree", "forest", "boost"),
  num_classes = NULL,
  crossfit = NULL,
  crossfit_seed = NULL,
  id = NULL
)
```

## Arguments

- spec:

  a non-probability `weighting_spec`.

- reference:

  a
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
  (the probability reference with its design weights). Pass the
  reference's replicate weights through
  `reference_sample(replicates = )` to propagate its sampling variance
  through the recipe-aware bootstrap: each replicate refits the
  propensity from the paired reference replicate. Without them the
  reference is treated as fixed, so the bootstrap reflects only the
  variability of the non-probability sample (which it resamples as a
  with-replacement sample of units, a slightly conservative
  approximation when that sample is a large fraction of the population).

- formula:

  one-sided formula of the covariates shared by both samples, e.g.
  `~ sex + age + region`.

- engine:

  propensity learner: `"logit"` (default), `"tree"`, `"forest"` or
  `"boost"`.

- num_classes:

  NULL (default, direct `1/pi`) or an integer: group the fitted
  propensities into that many quantile classes and use the class-average
  pseudo-weight, which is more robust to a misspecified model.

- crossfit, crossfit_seed:

  optional K-fold cross-fitting of the propensity (recommended for the
  flexible learners), and its seed.

- id:

  optional stable step id.

## Value

the input `weighting_spec` with this step appended.

## Details

The recipe must be a non-probability spec:
`weighting_spec(..., nonprob = TRUE)`. This step is the
inverse-propensity (IPW) route; you can instead, or additionally,
calibrate to a
[`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
with
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
/
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
(mass imputation / model-based), and combining both gives the doubly
robust estimator.

## References

Elliott, M. R. and Valliant, R. (2017). Inference for non-probability
samples. Statistical Science 32(2), 249-264.

## See also

[`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md),
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md),
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)

Other weighting steps:
[`step_assert()`](https://jpferreira33.github.io/weightflow/reference/step_assert.md),
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md),
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md),
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md),
[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md),
[`step_nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/step_nr_sensitivity.md),
[`step_rescale()`](https://jpferreira33.github.io/weightflow/reference/step_rescale.md),
[`step_round()`](https://jpferreira33.github.io/weightflow/reference/step_round.md),
[`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md),
[`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md),
[`step_trim()`](https://jpferreira33.github.io/weightflow/reference/step_trim.md),
[`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md),
[`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md),
[`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md)
