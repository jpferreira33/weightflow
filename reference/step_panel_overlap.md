# Adjust base weights by the panel-selection probability (CEPAL ch. XVI)

Divides each incoming weight by `Pr(panel selection)` – the probability
that a rotation panel belongs to the combined-wave sample – turning the
design weight of the reference wave into the panel base weight of the
longitudinal sample (`d_base = d1 / Pr`). This is the first step of the
Verma-Betti-Ghellini longitudinal-weight sequence: combining `k` waves
in a design that keeps `g` of its `G` rotation groups in all of them
gives `Pr = g / G`, so the factor is its reciprocal (e.g. 4/3 when 3 of
4 groups persist, 4 when only 1 does).

## Usage

``` r
step_panel_overlap(spec, prob, id = NULL)
```

## Arguments

- spec:

  a weighting_spec.

- prob:

  a panel-selection probability in `(0, 1]`: an unquoted per-unit
  column/expression, or a single constant (e.g.
  `panel_pr(pd, c("T1","T2"))`).

- id:

  optional string identifier for the step, shown in the recipe print-out
  and usable in
  [`collect_step_detail()`](https://jpferreira33.github.io/weightflow/reference/collect_step_detail.md).

## Value

The input `weighting_spec` with this step appended to its recipe.

## Details

`prob` is a probability in `(0, 1]`: either a per-unit column (or
expression) or a single constant applied to every active unit. When the
data has a `rotation_group`, get the constant from
[`panel_pr()`](https://jpferreira33.github.io/weightflow/reference/panel_pr.md):
`prob = panel_pr(pd, c("T1", "T2"))`. When it does not (e.g. the Chilean
ENE), derive the probability yourself (from the design fraction or the
cluster) and pass it here. Run this on the longitudinal sample (the
intersection of the combined waves), before the attrition and
calibration steps.

## See also

[`panel_pr()`](https://jpferreira33.github.io/weightflow/reference/panel_pr.md),
[`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md),
[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md),
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)

## Examples

``` r
# wide longitudinal file of the units in sample in both waves
wide <- panel_merge(
  list(T1 = subset(panel_ine, ola == 1), T2 = subset(panel_ine, ola == 2)),
  by = c("id_hogar", "nper"), require = "all")

# rotation group known -> derive Pr(panel selection) from the panel design
pd <- panel_design(panel_ine, unit = c("id_hogar", "nper"), wave = "ola",
                   rotation_group = "grupo_rotacion")
weighting_spec(wide, base_weights = w_base_T1) |>
  step_panel_overlap(prob = panel_pr(pd, c("1", "2"))) |> prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 1717 cases
#> Base wts: w_base_T1
#> Steps   :
#>   1. panel overlap  [panel_overlap_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                       stage n_active sum_wts cv_wts deff_kish n_eff
#>                        base     1717  245498    0.3      1.09  1575
#>  stage_1_step_panel_overlap     1717  294597    0.3      1.09  1575
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 

# no rotation group (e.g. Chile ENE) -> pass the probability directly
weighting_spec(wide, base_weights = w_base_T1) |>
  step_panel_overlap(prob = 5 / 6) |> prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 1717 cases
#> Base wts: w_base_T1
#> Steps   :
#>   1. panel overlap  [panel_overlap_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                       stage n_active sum_wts cv_wts deff_kish n_eff
#>                        base     1717  245498    0.3      1.09  1575
#>  stage_1_step_panel_overlap     1717  294597    0.3      1.09  1575
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
