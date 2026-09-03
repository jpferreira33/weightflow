# Round the final weights

Rounds the weights to a given number of decimals, either unit by unit
(`"nearest"`), with the largest-remainder method (`"preserve_total"`),
which keeps the weighted total exactly, or with the cube method
(`"balanced"`), which keeps the calibrated totals – by domain, not only
the grand total – as close as the integer grid allows. Typically the
last step of a recipe, after calibration, when the weights have to be
delivered as integers or with a fixed number of decimals.

## Usage

``` r
step_round(
  spec,
  digits = 0L,
  method = c("nearest", "preserve_total", "balanced"),
  by = NULL,
  id = NULL
)
```

## Arguments

- spec:

  a weighting_spec.

- digits:

  integer. Decimals to keep (0 = integers).

- method:

  one of `"nearest"` (simple rounding), `"preserve_total"` (largest
  remainder; keeps the grand total exactly) or `"balanced"` (cube
  method; keeps the totals of the domains named in `by` as close as the
  grid allows). Note: `"preserve_total"` and `"balanced"` can break
  equality of weights within a cluster; if you need integer and equal
  weights per household, use `"nearest"`.

- by:

  for `method = "balanced"` only: a character vector of variables whose
  (crossed) cell totals must be preserved, e.g.
  `by = c("dam", "estrato")` – the same domains you calibrated to. Every
  weight is sent to its floor or ceiling by balanced sampling on the
  cell indicators (cube method), so each cell total (and hence each
  margin, and the grand total) is reproduced up to at most one unit's
  worth. Required when `method = "balanced"`.

- id:

  optional string: a stable identifier for this step, shown in the
  recipe print-out and usable to select it in
  [`collect_step_detail()`](https://jpferreira33.github.io/weightflow/reference/collect_step_detail.md);
  defaults to a derived `"<class>_<k>"`.

## Value

The input `weighting_spec` with this step appended to its recipe. The
step is recorded only; it is evaluated when
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
is called.

## Details

The `"balanced"` method implements balanced rounding by the cube method
(Deville and Tille 2004; ECLAC/CEPAL household-survey methodology,
chapter 9, section F.2) natively, with no external sampling dependency.
It is randomized: call
[`set.seed()`](https://rdrr.io/r/base/Random.html) before
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
for a reproducible result.

## References

Deville J-C, Tille Y (2004). Efficient balanced sampling: the cube
method. *Biometrika* 91(4):893-912.

## See also

Other weighting steps:
[`step_assert()`](https://jpferreira33.github.io/weightflow/reference/step_assert.md),
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md),
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md),
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md),
[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md),
[`step_nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/step_nr_sensitivity.md),
[`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/reference/step_pseudoweight.md),
[`step_rescale()`](https://jpferreira33.github.io/weightflow/reference/step_rescale.md),
[`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md),
[`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md),
[`step_trim()`](https://jpferreira33.github.io/weightflow/reference/step_trim.md),
[`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md),
[`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md),
[`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md)

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_round(digits = 0) |> prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. rounding (nearest, 0 decimals)  [round_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>               stage n_active sum_wts cv_wts deff_kish n_eff
#>                base      467    4371  0.236     1.056   442
#>  stage_1_step_round      467    4323  0.211     1.045   447
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
