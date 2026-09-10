# Declare the recipe's scope: cross-sectional or longitudinal weights

Two argument-free declarative steps that say what the recipe is
building. They do not touch the weights (like
[`step_assert()`](https://jpferreira33.github.io/weightflow/reference/step_assert.md));
they record the intent so the rest of the recipe, the report and the
estimators behave accordingly, and so a wrong-purpose estimate can be
flagged. All the panel detail – waves, rotation group, reference wave –
already lives in
[`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md),
so these steps need no arguments.

## Usage

``` r
step_cross_sectional(spec, id = NULL)

step_longitudinal(spec, id = NULL)
```

## Arguments

- spec:

  a weighting_spec.

- id:

  optional string identifier for the step.

## Value

The input `weighting_spec` with the scope declared.

## Details

Put the scope step first. `step_cross_sectional()` is the default (a
plain recipe with no scope step behaves as cross-sectional).
`step_longitudinal()` requires the data to be tagged by
[`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)
and marks the recipe as building the panel (longitudinal) weight, so
steps like
[`step_panel_overlap()`](https://jpferreira33.github.io/weightflow/reference/step_panel_overlap.md)
apply and the calibration targets the reference wave.

## ECLAC conventions for the longitudinal weight

The three points below are conventions of ECLAC's household-survey
manual (ch. XVI). The package cannot enforce them – a vector of control
totals carries no label saying which period it belongs to – so they are
the reader's to apply.

**Who is in the longitudinal population.** It is made up of the units
that were in the target population at the *first* period **and remained
in it** through the last. Units that left (death, migration,
institutionalization) are out, and so are units that *entered* after the
first period: a panel adds no elements over time. Drop the first group
with
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md)
before the attrition step – leaving the target population is not
nonresponse and must not be compensated by redistributing weight.

**Calibrate to the FIRST period's totals.** ECLAC is explicit that the
auxiliary totals used in the calibration must represent the population
of the *first* period of interest, because a panel that adds no elements
over the measurement periods is representative only of the period in
which it was selected (ch. XVI, sec. B.2.c). In the original:


    "los totales auxiliares utilizados en la calibracion deben representar la
     poblacion del primer periodo de interes, puesto que, al conformar un panel
     que no suma elementos a lo largo de los periodos de medicion, la muestra
     sera representativa unicamente del periodo en el que fue seleccionada"

Passing the *later* period's projections is a silent error: the recipe
converges, the totals close, and the weights represent a population the
sample never had a chance to cover.

**Cross-sectional estimates from a longitudinal file are reference
only.** They will not match the published cross-sectional figures **and
should not**: the target population of the panel combination is not the
target population of the cross-section (ch. XVI, sec. C). Use the
longitudinal weight for gross flows, transitions and durations – what it
exists for – and the cross-sectional weight for levels.

## See also

[`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md),
[`step_panel_overlap()`](https://jpferreira33.github.io/weightflow/reference/step_panel_overlap.md)

## Examples

``` r
wide <- panel_merge(
  list(T1 = subset(panel_ine, ola == 1), T2 = subset(panel_ine, ola == 2)),
  by = c("id_hogar", "nper"), require = "all")
weighting_spec(wide, base_weights = w_base_T1) |>
  step_longitudinal() |>
  step_panel_overlap(prob = 5 / 6) |> prep()
#> Warning: step_longitudinal() without a panel_design() on the data: the reference wave and rotation structure are unknown. Tag the recipe data with panel_design() for the reference wave, Pr(panel selection) and the panel report.
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 1717 cases
#> Base wts: w_base_T1
#> Steps   :
#>   1. scope: longitudinal  [longitudinal_1]
#>   2. panel overlap  [panel_overlap_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                       stage n_active sum_wts cv_wts deff_kish n_eff
#>                        base     1717  245498    0.3      1.09  1575
#>   stage_1_step_longitudinal     1717  245498    0.3      1.09  1575
#>  stage_2_step_panel_overlap     1717  294597    0.3      1.09  1575
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
