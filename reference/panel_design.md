# Describe the rotating-panel structure of a survey

Tags stacked per-wave survey data with its rotation structure so the
panel steps and the report can read it, and so the overlap and linkage
quality can be inspected *before* any weighting. `panel_design()`
computes only; it does not create or change weights. It is the panel
analogue of
[`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md):
the descriptor lives in `attr(data, "wf_panel")` and the returned object
is still an ordinary `data.frame`.

## Usage

``` r
panel_design(
  data,
  unit,
  wave,
  rotation_group = NULL,
  cluster = NULL,
  pattern = NULL,
  waves = NULL,
  reference_wave = NULL
)
```

## Arguments

- data:

  a stacked `data.frame`, one row per unit per wave.

- unit:

  one or more column names (a character vector) that together identify
  the longitudinal unit, stable across waves. A household is often a
  single id (`"ID"`); a person needs several (`c("ID", "nper")` =
  household id plus person line number). The columns are pasted into the
  tracking key.

- wave:

  string: the column holding the wave/period.

- rotation_group:

  optional string: the column holding the rotation group / panel. Needed
  to derive `Pr(panel selection)` exactly; without it that field is left
  `NA` and only the unit-level overlap is computed.

- cluster:

  optional one or more column names identifying a within-unit cluster
  (e.g. the household `"ID"`) when the tracked unit is a person but the
  overlap is realised at the household level.

- pattern:

  optional string describing the rotation scheme, for verification only:
  CEPAL's `"4(0)1"`, the CPS `"4-8-4"`, or a plain integer like `"6"`.
  Nothing in the computation depends on parsing it.

- waves:

  optional character vector giving the wave order explicitly; defaults
  to `sort(unique(data[[wave]]))`.

- reference_wave:

  optional wave whose population the longitudinal weight represents (the
  calibration target for a longitudinal recipe); defaults to the first
  wave. Read by
  [`step_longitudinal()`](https://jpferreira33.github.io/weightflow/reference/step_cross_sectional.md).

## Value

`data`, unchanged as a data frame, with the descriptor in
`attr(data, "wf_panel")` and class `"wf_panel_design"` prepended.

## Details

`data` must be in **stacked (long) form**: one row per unit per wave,
with a `unit` column that is stable across waves and a `wave` column
identifying the period. From the `unit` x `wave` membership it derives
the observed overlap matrix (the fraction of each wave retained in every
other wave, i.e. CEPAL's *traslape*), and, when `rotation_group` is
given, the panel-selection probability `Pr(panel selection)` for each
adjacent pair and for the full combination – the reciprocal of which is
the CEPAL panel base-weight factor.

The linkage quality is measured, not assumed: if a `pattern` is supplied
the observed adjacent overlap is compared against the one it implies,
and a large gap (alert `PN-01`) is the early warning that the linkage
key is unstable (relabelled ids, a redesigned frame, duplicated panels).
Uneven rotation-group sizes, which break the scalar reciprocal of
`Pr(panel selection)`, raise `PN-02`.

## See also

[`panel_merge()`](https://jpferreira33.github.io/weightflow/reference/panel_merge.md),
[`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)

## Examples

``` r
# person-level tracking: the key is household id + person line number
pd <- panel_design(panel_ine, unit = c("id_hogar", "nper"), wave = "ola",
                   rotation_group = "grupo_rotacion", cluster = "id_hogar",
                   pattern = "6")
pd            # overlap matrix, Pr(panel selection), linkage rate, alerts
#> <weightflow panel design>
#>   waves      : 3 (1, 2, 3)
#>   unit       : id_hogar + nper  (cluster: id_hogar)
#>   rotation   : grupo_rotacion  pattern: 6
#>   units      : 2783 (linked in >=2 waves: 2063, 74%)
#>   overlap (row wave retained in column wave):
#>   1    2    3   
#> 1 1.00 0.83 0.64
#> 2 0.83 1.00 0.81
#> 3 0.65 0.82 1.00
#>   Pr(panel selection), adjacent : 0.833, 0.833  (full combination: 0.667)
#>   overlap implied by pattern    : 0.83 0.67   (lag 1 2)
#>   pattern                       : 6 group(s) in sample, cycle 6, useful lags 1, 2, 3, 4, 5
summary(pd)
#> Panel design summary
#>   waves            : 1, 2, 3
#>   n per wave       : 1=2063, 2=2069, 3=2042
#>   units (linked)   : 2783 (2063, 74.1%)
#>   overlap matrix:
#>      1     2     3
#> 1 1.00 0.832 0.644
#> 2 0.83 1.000 0.809
#> 3 0.65 0.820 1.000
```
