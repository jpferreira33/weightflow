# Attrition adjustment for panel waves

The panel-facing nonresponse step: it adjusts for **attrition**
(nonresponse between waves) when building a longitudinal weight,
reweighting the units that stayed in to also represent those that
dropped out, among the units that remain **eligible**. It is a thin
wrapper over
[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
– so the theory stays visible in the recipe – that uses the same
estimators but under a name that reads correctly in a panel cascade and
with the panel conventions: the covariates should come from a wave where
the unit was observed (e.g. the first period), and it does NOT absorb
eligibility (out-of-scope and unknown-eligibility go in
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md)
/
[`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md)).

## Usage

``` r
step_attrition(
  spec,
  respondent,
  method = c("propensity", "rhg", "weighting_class", "calibration"),
  formula = NULL,
  by = NULL,
  engine = c("logit", "tree", "forest", "boost"),
  num_classes = 5L,
  id = NULL
)
```

## Arguments

- spec:

  a weighting_spec.

- respondent:

  an unquoted 0/1 column or logical condition, TRUE for the units that
  responded in the wave being adjusted (e.g. `disp_T2 == "R"`).

- method:

  attrition estimator: `"propensity"` (individual `1/phi`, the
  SLID/ECLAC response-propensity weighting; default), `"rhg"` (response
  homogeneity groups: propensity stratified into `num_classes` classes),
  `"weighting_class"` (design-variable cells), or `"calibration"`
  (Sarndal-Lundstrom).

- formula:

  model formula for `"propensity"`/`"rhg"`, in covariates observed for
  responders and nonrespondents (from a wave where the unit was seen).

- by:

  adjustment cells for `"weighting_class"`.

- engine:

  propensity engine (`"logit"`/`"tree"`/`"forest"`/`"boost"`).

- num_classes:

  number of propensity classes for `"rhg"`.

- id:

  optional stable step id.

## Value

the `weighting_spec` with the attrition step appended.

## Details

The attrition adjustment prescribed by ECLAC's household-survey manual
(ch. XVI) and used by Statistics Canada's SLID (Naud 2002; LaRoche 2003)
is **response-propensity weighting** (`method = "propensity"`, i.e.
inverse of the estimated response probability; Little 1986; Rosenbaum
1987) – not an ECLAC invention. `method = "rhg"` is the
response-homogeneity-group variant (propensity stratified into
`num_classes` groups, then the class-mean rate), which stabilises the
weights.

Two ECLAC prescriptions are **not** implemented, and the difference
matters when they apply. The manual (ch. XVI, sec. B.1.b) allows two
fallback imputations for units with no auxiliary information at all: a
nonrespondent whose rotation panel does not overlap (impute the overall
effective response rate as its `phi`), and a newly incorporated
nonrespondent (impute the adjusted expansion factor of its household).
Here a covariate that is `NA` for an eligible unit is an **error**, not
an imputation – an `NA` propensity would let that nonrespondent survive
the adjustment silently, which is the failure the error exists to
prevent, and the package will not silently substitute a value of its own
for a missing input.

So when the error fires, the fix belongs in the data, and either ECLAC
route is available to you there: impute the missing covariates before
the step (the manual's own fallback is the overall effective response
rate, i.e. a constant, which is what a model with no covariates for
those units amounts to), give a newly incorporated nonrespondent its
household's adjusted factor, or restrict `formula` to a covariate set
observed for every eligible unit. What the package will not do is choose
one of those for you and leave no trace in the recipe. Multi-wave
retention chaining (decomposing Pr(in at T3) into Pr(reach T2) x Pr(T2
to T3)) is likewise absent: this step adjusts one transition at a time,
which is what ch. XVI specifies for two consecutive periods.

## See also

[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md),
[`step_panel_overlap()`](https://jpferreira33.github.io/weightflow/reference/step_panel_overlap.md),
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md)

## Examples

``` r
wide <- panel_merge(
  list(T1 = subset(panel_ine, ola == 1), T2 = subset(panel_ine, ola == 2)),
  by = c("id_hogar", "nper"), require = "all")
weighting_spec(wide, base_weights = w_base_T1) |>
  step_panel_overlap(prob = 5 / 6) |>
  step_drop_ineligible(disp_T2 == "OS", reason = "left the target population") |>
  step_attrition(respondent = disp_T2 == "R", method = "propensity",
                 formula = ~ edad_T1 + sexo_T1 + region_T1) |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 1717 cases
#> Base wts: w_base_T1
#> Steps   :
#>   1. panel overlap  [panel_overlap_1]
#>   2. drop ineligible (left the target population)  [drop_ineligible_1]
#>   3. attrition (propensity)  [nonresponse_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                         stage n_active sum_wts cv_wts deff_kish n_eff
#>                          base     1717  245498  0.300     1.090  1575
#>    stage_1_step_panel_overlap     1717  294597  0.300     1.090  1575
#>  stage_2_step_drop_ineligible     1633  279699  0.302     1.091  1496
#>        stage_3_step_attrition     1464  279688  0.303     1.092  1341
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
