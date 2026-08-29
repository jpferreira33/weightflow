# Direct estimates and design SEs per domain, ready for small-area estimation

Small-area estimation (SAE) area-level models (Fay-Herriot) need, for
each domain, the *direct* estimate, its *design-based* variance and the
effective sample size. This function computes exactly those from a
recipe-aware replicate object, so the design-based ingredients flow into
`emdi`, `sae` or `hbsae` without leaving the weightflow variance
machinery. It does not fit any SAE model itself.

## Usage

``` r
as_sae_input(
  object,
  variable,
  by,
  type = c("mean", "total"),
  level = 0.95,
  cv_breaks = c(0.165, 0.33)
)
```

## Arguments

- object:

  a `weightflow_boot` or `weightflow_jack` object (from
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_weights.md)
  /
  [`jackknife_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/jackknife_weights.md)).

- variable:

  name of the study variable.

- by:

  name(s) of the domain column(s); several are crossed.

- type:

  `"mean"` (default) or `"total"`.

- level:

  confidence level for the interval.

- cv_breaks:

  two increasing CV cut-points for the publishability rating (default
  `c(0.165, 0.33)`, common in official statistics): a CV below the first
  is `"publishable"`, between the two `"review"`, above the second
  `"not publishable"`.

## Value

A data frame with one row per domain: `domain`, `n` (active units),
`n_eff` (Kish effective sample size), `estimate`, `se`, `cv`,
`ci_lower`, `ci_upper` and `rating`. Pass `estimate` and `se^2` (the
sampling variance) to a Fay-Herriot model.

Note for very small domains: the domain estimates share one bootstrap,
and a replicate in which any domain has no active unit is dropped for
all domains (a conservative choice). With many tiny domains this wastes
replicates; use more `replicates` in the bootstrap, or estimate sparse
domains in a separate call.

## Details

The domain standard error is the recipe-aware replicate SE (it re-runs
the whole recipe per replicate), so it already reflects nonresponse and
calibration, not just the final weights.

## See also

[`domain_summary()`](https://jpferreira33.github.io/weightflow/dev/reference/domain_summary.md),
[`bootstrap_estimate()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_estimate.md),
[`design_effect()`](https://jpferreira33.github.io/weightflow/dev/reference/design_effect.md)

Other cascade audit:
[`collect_propensities()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_propensities.md),
[`collect_step_detail()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_step_detail.md),
[`collect_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_weights.md),
[`domain_summary()`](https://jpferreira33.github.io/weightflow/dev/reference/domain_summary.md),
[`weight_factors()`](https://jpferreira33.github.io/weightflow/dev/reference/weight_factors.md),
[`weighting_alerts()`](https://jpferreira33.github.io/weightflow/dev/reference/weighting_alerts.md)

## Examples

``` r
spec <- weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region))))
boot <- bootstrap_weights(spec, replicates = 50, strata = "region",
                          psu = "psu", seed = 1)
#>   bootstrap replicate 25/50
#>   bootstrap replicate 50/50
as_sae_input(boot, "responded", by = "region")
#>   domain   n n_eff  estimate         se         cv  ci_lower  ci_upper
#> 1   East  96    96 0.5416667 0.04422887 0.08165331 0.4549797 0.6283537
#> 2  North 119   119 0.6554622 0.02944014 0.04491508 0.5977606 0.7131638
#> 3  South 121   121 0.5950413 0.05318722 0.08938407 0.4907963 0.6992864
#> 4   West 131   131 0.5190840 0.04245369 0.08178579 0.4358763 0.6022917
#>        rating
#> 1 publishable
#> 2 publishable
#> 3 publishable
#> 4 publishable
```
