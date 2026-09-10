# Panel-selection probability for a set of combined waves

Returns `Pr(panel selection)` for combining `waves` in a
[`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)
that carries a `rotation_group`: the fraction of rotation-group cohorts
present in *all* the combined waves. Its reciprocal is the CEPAL panel
base-weight factor used by
[`step_panel_overlap()`](https://jpferreira33.github.io/weightflow/reference/step_panel_overlap.md)
(`prob = panel_pr(pd, c("T1","T2"))`). Surveys without a public
rotation-group variable (e.g. the Chilean ENE) cannot use this – derive
the probability another way and pass it to
[`step_panel_overlap()`](https://jpferreira33.github.io/weightflow/reference/step_panel_overlap.md).

## Usage

``` r
panel_pr(object, waves = NULL)
```

## Arguments

- object:

  a `wf_panel_design` (from
  [`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)).

- waves:

  optional character vector of the combined waves; defaults to all.

## Value

a single probability in `(0, 1]`.

## See also

[`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md),
[`step_panel_overlap()`](https://jpferreira33.github.io/weightflow/reference/step_panel_overlap.md)

## Examples

``` r
pd <- panel_design(panel_ine, unit = c("id_hogar", "nper"), wave = "ola",
                   rotation_group = "grupo_rotacion")
panel_pr(pd)                    # over all waves
#> [1] 0.6666667
panel_pr(pd, c("1", "2"))       # combining waves 1 and 2
#> [1] 0.8333333
```
