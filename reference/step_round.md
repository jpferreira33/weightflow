# Round the final weights

Rounds the weights to a given number of decimals, either unit by unit
(`"nearest"`), with the largest-remainder method (`"preserve_total"`),
which keeps the weighted total exactly, or with the cube method
(`"balanced"`), which keeps the calibrated totals – by domain, not only
the grand total – as close as the integer grid allows. For `"balanced"`,
`formula` balances on the calibration design and `by` on crossed cells;
they are different problems, and the difference is spelled out under
those arguments. Typically the last step of a recipe, after calibration,
when the weights have to be delivered as integers or with a fixed number
of decimals.

## Usage

``` r
step_round(
  spec,
  digits = 0L,
  method = c("nearest", "preserve_total", "balanced"),
  by = NULL,
  formula = NULL,
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

  for `method = "balanced"` only, and an alternative to `formula`: a
  character vector of variables whose **crossed** cell totals must be
  preserved, e.g. `by = c("dam", "stratum")`. The balancing matrix is
  then one indicator per non-empty cell, so every cell total – and hence
  every margin, and the grand total – is reproduced up to about one
  unit's worth. This is the right choice after a post-stratification,
  where the cells *are* the calibration. It is **stricter** than
  `formula`, not equivalent: preserving every cell implies preserving
  the margins, but it also imposes constraints the calibration never
  asked for, and with many sparse cells the rounding cannot meet them
  all. Note too that with cell indicators each unit loads on a single
  column, so the problem separates into one independent cell total at a
  time and the cube method has no overlap to exploit; the overlap of
  [`model.matrix()`](https://rdrr.io/r/stats/model.matrix.html) columns
  is what the method is for.

- formula:

  for `method = "balanced"` only: a one-sided formula, e.g.
  `~ dam + stratum`. The balancing matrix is
  `model.matrix(formula, data)` over the active units, so the rounding
  reproduces **exactly the totals a calibration on that same formula
  reproduces**, and nothing else. This is the argument to use after
  `step_calibrate(formula = )`: pass the same formula, or pass neither
  `formula` nor `by` and the step takes it from the last calibration
  step in the recipe.

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

`"preserve_total"` is randomized too, but only where it has to be. Ties
in the fractional part are the rule rather than the exception – a
self-weighting design, weights that land on `.5`, calibrated weights on
a grid – and they are broken at random, so the extra unit is allocated
without regard to the order of the file. Deciding ties by row order
instead moves mass systematically towards whatever the file is sorted
by, usually region, while the grand total (the one thing the method
promises) stays exactly right and hides it. Weights whose fractional
parts are distinct are rounded exactly as before.

## References

Deville J-C, Tille Y (2004). Efficient balanced sampling: the cube
method. *Biometrika* 91(4):893-912.

## See also

Other weighting steps:
[`step_assert()`](https://jpferreira33.github.io/weightflow/reference/step_assert.md),
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md),
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md),
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
