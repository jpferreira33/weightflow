# Composite regression estimator (CRE / regression composite estimation)

Final-weight step for rotating panels that exploits the sample overlap
**in the estimation**, not only in the variance. It is the composite
calibration of the Canadian LFS (Gambino, Kennedy and Singh 2001; Fuller
and Rao 2001) and the composite calibration of the Uruguayan ECH (INE,
methodology sec. 8.4): the same estimator. On top of the ordinary
calibration to known population totals `X`, it adds a second set of
constraints to control totals `Zhat` estimated from the **previous
wave** (the composite auxiliaries: previous-month labour status,
optionally crossed by domains). Because `Zhat` uses the previous wave's
composite weights, the estimator is recursive.

## Usage

``` r
step_cre(
  spec,
  previous = NULL,
  status,
  composite = list(NULL),
  id_unit,
  formula,
  totals = NULL,
  count = NULL,
  birth = NULL,
  alpha = 2/3,
  overlap = "auto",
  on_missing_prev = c("carry_backward", "zero"),
  cluster = NULL,
  equal_within_cluster = FALSE,
  calfun = c("linear", "logit", "raking"),
  bounds = NULL,
  rotation_group = NULL,
  status_ref = NULL,
  id = NULL
)
```

## Arguments

- spec:

  a weighting_spec (its recipe up to here yields the
  nonresponse-adjusted weights `w_nr` that this step starts from).

- previous:

  the prepped previous-wave recipe
  ([`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
  output), which supplies the previous composite weights and the
  previous labour status for `Zhat` and the overlap imputation. `NULL`
  (default) is the **seed** wave: with no `t-1` there is no composite
  block and the step reduces to an ordinary linear calibration to `X` –
  the start of the recursion.

- status:

  bare or quoted name of the categorical labour-status column (e.g.
  employed / unemployed / inactive) in the current wave; must exist with
  the same name in `previous`. Its indicators are the composite
  auxiliaries.

- composite:

  a **list of domain crossings**, each defining one block of composite
  control totals. `NULL` = country total; a string = status crossed by
  that domain (e.g. "sex"); a character vector = status crossed by the
  interaction (e.g. c("sex","age")). This mirrors the methodologies'
  composite-variable lists: the ECH's are
  `list(NULL, "sex", "department")`. Default `list(NULL)`.

- id_unit:

  character vector naming the unit key that links waves (e.g.
  c("household","person")). Used to look up each current unit's `t-1`
  status.

- formula:

  the demographic auxiliary formula for `x` (as in
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  method = "linear"), e.g. `~ age_sex + region`.

- totals, count:

  the population totals `X` for `x`, in the same forms accepted by
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  (a named vector aligned to the model.matrix, or the tidy named list
  with `count`).

- birth:

  expression (evaluated in the current data) that is TRUE for the birth
  rotation group (the units with no `t-1` value to carry). If `NULL`,
  birth units are those not found in `previous` by `id_unit`.

- alpha:

  MR1/MR2 mixing constant between 0 and 1. `alpha = 0` targets the level
  only (MR1), `alpha = 1` the change only (MR2). Default 2/3 (Chen and
  Liu 2002).

- overlap:

  the overlap rate used by the MR2 carry-backward correction: "auto"
  (default) estimates it as the `w_nr`-weighted overlap fraction, or a
  number (e.g. 5/6, the nominal LFS/ECH rate).

- on_missing_prev:

  how to treat non-birth units without a valid `t-1` status (new
  household members, newly of working age): "carry_backward" (default;
  set `z_{t-1} = z_t`) or "zero" (`z_{t-1} = 0`).

- cluster, equal_within_cluster:

  integrated method of weighting: with `equal_within_cluster = TRUE`
  (needs `cluster`) the auxiliaries `x` and `z` are averaged to the
  cluster so members share one weight (Lemaitre-Dufour 1987).

- calfun, bounds:

  distance and g-bounds for the calibration, as in
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md).
  Use `bounds = c(L, U)` with a logit `calfun` to avoid final weights
  below 1.

- rotation_group:

  optional name of the rotation-group column. When given, the step adds
  the **equal-representation** constraints both surveys impose: each
  rotation group must weight to the same working-age total, `N / G` (ECH
  sec. 8.4.1, `sum_{i in s_g} w_i = N_PET / 6`; LFS sec. 6.3.1). `N` is
  read from the intercept target in `totals` and `G` is the number of
  groups; the last group is left implied (its total follows from the
  others and `N`), so `G - 1` constraints are added to the demographic
  block. `NULL` (default) omits them.

- status_ref:

  the status level held as reference (dropped from each cell block to
  avoid the mechanical collinearity between the full status indicators
  and the demographic block, which pins the same cell totals). The
  dropped total is implied by the others plus `X`, so the estimator is
  unchanged; naming the level only sets which one is implicit (e.g.
  `"inact"` to keep employed/unemployed explicit). `NULL` (default)
  drops the last level in sorted order. One level is always dropped:
  keeping every level would make the block collinear with the intercept
  in `X`.

- id:

  optional stable identifier for this step.

## Value

the input `weighting_spec` with the CRE step appended (evaluated at
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)).
Chain waves by passing each prepped wave as the `previous` of the next.

## Details

The composite auxiliary `z` is known for the overlap sample (units
present in `t-1`) and imputed for the birth rotation group (units
entering at `t`, with no `t-1` value) by combining two imputations: MR1
(mean imputation, aimed at the level) and MR2 (carry-backward, aimed at
the change), mixed as `z = (1 - alpha) z1 + alpha z2` with
`alpha = 2/3`.

The composite weights are `w_cre = w_nr * g`, with `g` the GREG factor
of the augmented calibration `[x | z]` to `[X | Zhat]`; the same solver
as
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md).
With `equal_within_cluster = TRUE` the auxiliaries are averaged to the
household (integrated method of weighting, Lemaitre-Dufour 1987) so
every household member shares one final weight.

## References

Gambino J, Kennedy B, Singh MP (2001). Regression composite estimation
for the Canadian Labour Force Survey. *Survey Methodology* 27(1):65-74.
Fuller WA, Rao JNK (2001). A regression composite estimator with
application to the Canadian Labour Force Survey. *Survey Methodology*
27(1):45-51. Instituto Nacional de Estadistica (Uruguay). Metodologia de
la Encuesta Continua de Hogares, seccion 8.4 (calibracion compuesta).

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
[`step_round()`](https://jpferreira33.github.io/weightflow/reference/step_round.md),
[`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md),
[`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md),
[`step_trim()`](https://jpferreira33.github.io/weightflow/reference/step_trim.md),
[`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md),
[`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md),
[`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md)

## Examples

``` r
# Composite (CRE) estimation on the 6-month rotating panel `panel_ine`.
# `condicion` is the previous-wave labour status (emp / unemp / inact).
t1 <- subset(panel_ine, ola == 1 & disp == "R")
t2 <- subset(panel_ine, ola == 2 & disp == "R")
t1$sexo <- factor(t1$sexo); t2$sexo <- factor(t2$sexo)
Xtot <- function(d) colSums(d$w_base * stats::model.matrix(~ sexo, data = d))

# seed wave: no previous month, so step_cre() reduces to a linear calibration to X
seed <- weighting_spec(t1, base_weights = w_base) |>
  step_cre(previous = NULL, status = condicion, formula = ~ sexo,
           totals = Xtot(t1), status_ref = "inact") |>
  prep()

# composite wave: augment X with the previous-wave status, country-level and by sex
fit2 <- weighting_spec(t2, base_weights = w_base) |>
  step_cre(previous = seed, status = condicion, composite = list(NULL, "sexo"),
           id_unit = c("id_hogar", "nper"), formula = ~ sexo, totals = Xtot(t2),
           alpha = 2/3, status_ref = "inact") |>
  prep()
fit2
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 1774 cases
#> Base wts: w_base
#> Steps   :
#>   1. composite regression estimator (composite, alpha = 0.67)  [cre_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>             stage n_active sum_wts cv_wts deff_kish n_eff
#>              base     1774  254211  0.304     1.092  1624
#>  stage_1_step_cre     1774  254211  0.373     1.139  1557
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
