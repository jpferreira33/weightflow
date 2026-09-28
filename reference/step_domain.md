# Declarative estimation over a coordinated panel object

`step_domain()` and `step_estimate()` build an estimation pipeline
(`weightflow_estimation`) on top of a saved
[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md)
/
[`wave_jackknife()`](https://jpferreira33.github.io/weightflow/reference/wave_jackknife.md)
object, so that changes, levels and linear contrasts – with the honest
overlap covariance – can be requested declaratively and disaggregated,
the way the weighting recipe is built with `step_*`. It is a thin front
end over
[`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md),
[`panel_estimate()`](https://jpferreira33.github.io/weightflow/reference/panel_estimate.md)
and
[`level_estimate()`](https://jpferreira33.github.io/weightflow/reference/level_estimate.md);
the coordinated replicates do the variance. Evaluate with
[`collect_estimates()`](https://jpferreira33.github.io/weightflow/reference/collect_estimates.md)
(printing does it too).

## Usage

``` r
step_domain(x, ...)

step_filter(x, condition)

step_estimate(
  x,
  statistic,
  over = NULL,
  type = c("absolute", "relative"),
  waves = NULL,
  contrast = NULL,
  level = 0.95,
  label = NULL
)

step_transition(x, from, to, format = c("row", "col", "joint", "counts"))
```

## Arguments

- x:

  a `weightflow_wave_boot` / `weightflow_wave_jack`, or a
  `weightflow_estimation` to extend.

- ...:

  for `step_domain()`, one or more grouping columns (unquoted or as
  strings); they stack, so the disaggregation is their cross (e.g.
  region x sex). A column may not be named after one of the result
  table's own columns (`estimand`, `over`, `type`, `estimate`, `se`,
  `ci_lower`, `ci_upper`, `rho`); rename it in the wave data first.

- condition:

  for `step_filter()`, a logical expression (unquoted) that selects the
  subpopulation to estimate over – e.g. `age >= 25 & age <= 54`. It is
  evaluated in each wave's data; rows are **masked** (not dropped), so
  the coordinated replicate structure and the overlap covariance are
  preserved. Multiple `step_filter()` calls stack (their conditions are
  ANDed).

- statistic:

  the estimand, as a DSL call – `mean(var)`, `total(var)`, `prop(cond)`,
  `ratio(num, den)`, `quantile(var, p)` – or a `function(w, data)`.
  Every argument is evaluated in the wave data and must give one numeric
  or logical value per unit: `prop()` takes a **condition**
  (`prop(status == "unemployed")`), not a category, and `p` in
  [`quantile()`](https://rdrr.io/r/stats/quantile.html) is a probability
  in `[0, 1]` (`0.5`, not `50`). `ratio()` is taken over the domain
  where numerator **and** denominator are both observed, as
  `survey::svyratio(na.rm = TRUE)` is. The weighted quantile is R's type
  5.

- over:

  what to estimate: `"change"` (between two waves), `"level"` (one wave)
  or `"contrast"` (a linear combination, with `contrast=`). Default:
  `"change"` if the object has \>= 2 waves, else `"level"`; `"contrast"`
  is implied when `contrast=` is given.

- type:

  for `over = "change"`, `"absolute"` (default) or `"relative"`
  (`theta2/theta1 - 1`).

- waves:

  optional wave label(s): one for `"level"`, two for `"change"`.

- contrast:

  numeric weights (one per wave) for `over = "contrast"`.

- level:

  confidence level.

- label:

  optional name for the estimand (defaults to the statistic's
  expression).

- from, to:

  for `step_transition()`, the from-/to-state columns.

- format:

  transition table format (`"row"`, `"col"`, `"joint"`, `"counts"`).

## Value

a `weightflow_estimation`.

## See also

[`collect_estimates()`](https://jpferreira33.github.io/weightflow/reference/collect_estimates.md),
[`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md),
[`panel_estimate()`](https://jpferreira33.github.io/weightflow/reference/panel_estimate.md),
[`level_estimate()`](https://jpferreira33.github.io/weightflow/reference/level_estimate.md)

## Examples

``` r
t1 <- subset(panel_ine, wave == 1 & disposition == "R")
t2 <- subset(panel_ine, wave == 2 & disposition == "R")
wb <- wave_bootstrap(
  list(T1 = weighting_spec(t1, base_weights = pw),
       T2 = weighting_spec(t2, base_weights = pw)),
  replicates = 100, strata = "stratum", psu = "psu", seed = 1, progress = FALSE)

# net change of the unemployment rate, by region
collect_estimates(wb |> step_domain(region) |>
  step_estimate(mean(unemployed), over = "change"))
#> <weightflow estimates [bootstrap]  T1, T2>
#>          estimand   over     type     region estimate      se ci_lower ci_upper
#>  mean(unemployed) change absolute   Interior -0.04337 0.01267 -0.06821 -0.01853
#>  mean(unemployed) change absolute Montevideo  0.01580 0.01713 -0.01777  0.04937
#>     rho
#>  0.6845
#>  0.5741

# subpopulation: same change among the working-age population (rows masked, not dropped)
collect_estimates(wb |> step_filter(age >= 25 & age <= 54) |>
  step_estimate(mean(unemployed), over = "change"))
#> <weightflow estimates [bootstrap]  T1, T2>
#>          estimand   over     type estimate      se ci_lower ci_upper    rho
#>  mean(unemployed) change absolute -0.01542 0.01937 -0.05339  0.02254 0.4246
```
