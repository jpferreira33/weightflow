# Synthetic rotating- and pure-panel datasets

Four small, reproducible household-panel datasets that ship with
weightflow to test and illustrate the panel tools. They share one
structure and differ only in the **rotation system**, so the same code
runs on a pure panel and on each rotating design. All are in **long
format**: one row per person and per wave the person is in sample.
Continuing units keep the same `id_hogar` / `id_persona` across waves,
so they link the panel; the household is the natural cluster and
`c(id_hogar, nper)` the person-level key.

## Usage

``` r
panel_puro

panel_cl

panel_ine

panel_us
```

## Format

A `data.frame` with one row per person-wave and the columns:

- id_hogar:

  household id, persistent across waves (the panel link / cluster).

- id_persona, nper:

  person id and person-number within household; `c(id_hogar, nper)` is
  the person key.

- estrato, psu:

  design stratum and primary sampling unit (PSU nested in stratum, at
  least two PSUs per stratum), for the coordinated bootstrap /
  jackknife.

- region, sexo, edad:

  covariates usable as estimation domains.

- ola:

  wave (month) index.

- grupo_rotacion, mes_en_muestra:

  rotation group and order-in-sample.

- w_base:

  design (base) weight.

- disp:

  between-wave disposition: `"R"`, `"NR"`, `"OS"`, `"UNK"`.

- condicion:

  labour status within the working-age population, a factor with levels
  `"emp"` / `"unemp"` / `"inact"`; `NA` for non-respondents. This is the
  `status` argument of
  [`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
  (the previous-wave composite auxiliary).

- ocupado, desocupado:

  employed / unemployed indicators (labour force; `NA` if not `"R"` or
  not in the labour force).

- ingreso:

  labour income (`NA` if not `"R"`).

## Details

The between-wave disposition `disp` follows the four-state taxonomy the
longitudinal cascade needs: `"R"` responded, `"NR"` eligible nonresponse
(reweight), `"OS"` out of scope – left the target population between
waves, so the household exits permanently and is not reweighted – and
`"UNK"` unknown eligibility. The variables of interest (`ocupado`,
`desocupado`, `ingreso`) are observed only when `disp == "R"` (and, for
the labour-force items, when the person is in the labour force),
otherwise `NA`; they repeat across waves for continuing persons, with
within-person persistence, so net change and gross flows are meaningful.

The datasets differ only in the rotation calendar (which waves each
rotation group is in sample), giving different overlap structures:

- `panel_puro`:

  **Pure panel**, no rotation: every unit is followed across all 4
  waves; the sample shrinks only through attrition. Style of EU-SILC /
  SLID pure panels.

- `panel_cl`:

  **Chile ENE, 2-2-2** (in-out-in): 3 waves, consecutive overlap ~1/2,
  and units that **return** (in sample in waves 1 and 3 but not 2). The
  real ENE has no public rotation group; `grupo_rotacion` is included
  for teaching, but the panel also links through the persistent ids
  alone.

- `panel_ine`:

  **INE Uruguay ECH / StatCan LFS, 6-month rotation**: 6 groups in
  sample each wave, one sixth rotating out per wave, so consecutive
  overlap ~5/6.

- `panel_us`:

  **US CPS, 4-8-4**: 3 waves, consecutive overlap ~3/4, with a cohort
  that leaves and **returns** after the 8-month gap.

## Examples

``` r
# rotation structure of the 6-month panel
panel_design(panel_ine, unit = c("id_hogar", "nper"), wave = "ola",
             rotation_group = "grupo_rotacion", pattern = "6")
#> <weightflow panel design>
#>   waves      : 3 (1, 2, 3)
#>   unit       : id_hogar + nper
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
# coordinated change of the unemployment rate between two waves
t1 <- subset(panel_ine, ola == 1 & disp == "R")
t2 <- subset(panel_ine, ola == 2 & disp == "R")
wb <- wave_bootstrap(
  list(T1 = weighting_spec(t1, base_weights = w_base),
       T2 = weighting_spec(t2, base_weights = w_base)),
  replicates = 100, strata = "estrato", psu = "psu", seed = 1, progress = FALSE)
change_mean(wb, "desocupado")
#> <weightflow net change>
#>   T1 -> T2
#>   change     : -0.0149512   SE 0.010056
#>   95% CI    : [-0.0346606, 0.00475807]
#>   V1 0.0001126 | V2 0.0001035 | Cov 5.75e-05 | rho 0.533   (levels)
#>   V = 0.0001011  vs  V1+V2 = 0.0002161  (deff_change 0.468: overlap saved 53%)
```
