# Build the wide longitudinal file from per-wave surveys

Joins a named list of per-wave `data.frame`s on a stable unit key into
the wide, one-row-per-unit file that the longitudinal recipe consumes.
Each wave's non-key columns are suffixed with the wave name, and
per-wave presence indicators `.wf_in_<wave>` (and, if `responded` is
given, response indicators `.wf_resp_<wave>`) are added so a later
[`step_attrition()`](https://jpferreira33.github.io/weightflow/reference/step_attrition.md)
can model the response pattern.

## Usage

``` r
panel_merge(
  waves,
  by,
  responded = NULL,
  require = c("any", "all"),
  suffix = "_"
)
```

## Arguments

- waves:

  a **named** list of per-wave `data.frame`s; the names become the wave
  labels and column suffixes.

- by:

  one or more column names (a character vector) forming the unit key,
  present in every wave – e.g. `"ID"` for a household or
  `c("ID", "person_no")` for a person.

- responded:

  optional string: the name of a response indicator present in every
  wave, used to build `.wf_resp_<wave>`.

- require:

  one of `"any"` (union of units, default) or `"all"` (intersection).

- suffix:

  string inserted before the wave label when renaming columns (default
  `"_"`), e.g. `age` in wave `T1` becomes `age_T1`.

## Value

a wide `data.frame`, one row per unit, ready for
[`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)
/
[`weighting_spec()`](https://jpferreira33.github.io/weightflow/reference/weighting_spec.md).

## Details

`require = "any"` (the default) keeps every unit seen in at least one
wave – which the attrition model needs, because it has to be fitted over
responders *and* non-responders. `require = "all"` keeps only the
intersection (CEPAL's `s(2) = s1 cap s2 cap ...`); prefer to reach it
with
[`step_attrition()`](https://jpferreira33.github.io/weightflow/reference/step_attrition.md)
after estimating, not by dropping units before the model can see them.

## See also

[`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)

## Examples

``` r
# reshape two waves of the long panel into one wide, one-row-per-unit file
wide <- panel_merge(
  list(T1 = subset(panel_ine, wave == 1), T2 = subset(panel_ine, wave == 2)),
  by = c("household_id", "person_no"), require = "any")
names(wide)                       # per-wave columns are suffixed _T1 / _T2
#>  [1] "household_id"       "person_no"          "person_id_T1"      
#>  [4] "stratum_T1"         "psu_T1"             "region_T1"         
#>  [7] "sex_T1"             "age_T1"             "wave_T1"           
#> [10] "rotation_group_T1"  "month_in_sample_T1" "pw_T1"             
#> [13] "disposition_T1"     "lf_status_T1"       "employed_T1"       
#> [16] "unemployed_T1"      "income_T1"          ".wf_in_T1"         
#> [19] "person_id_T2"       "stratum_T2"         "psu_T2"            
#> [22] "region_T2"          "sex_T2"             "age_T2"            
#> [25] "wave_T2"            "rotation_group_T2"  "month_in_sample_T2"
#> [28] "pw_T2"              "disposition_T2"     "lf_status_T2"      
#> [31] "employed_T2"        "unemployed_T2"      "income_T2"         
#> [34] ".wf_in_T2"         
```
