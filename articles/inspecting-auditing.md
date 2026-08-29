# Inspecting and auditing the cascade

A weightflow recipe is meant to be *audited*, not just run. Every step
records what it did, and there are two complementary ways to read it
back:

- the self-contained **HTML report**
  ([`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)),
  for a visual, shareable walk-through; and
- the **programmatic quality-control (QC) surface** shown here, for
  scripted checks you can wire into a production pipeline.

This vignette is the programmatic path: run a recipe, gate it on the
quality alerts, then drill down unit by unit and domain by domain.

``` r

library(weightflow)

fit <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "propensity",
                   engine = "logit", formula = ~ region + sex + age) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region)),
                                sex    = c(table(population$sex)))) |>
  prep()
```

## Every step has a stable id

Printing the recipe shows each step with a unique id (`<class>_<k>`).
The id is the handle you use everywhere below; you can also set it
yourself with `step_*(..., id = "my_name")`.

``` r

fit
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (propensity: logit, 5 classes)  [nonresponse_1]
#>   2. calibration (raking)  [calibrate_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base      467    4371  0.236     1.056   442
#>  stage_1_step_nonresponse      270    4371  0.155     1.024   264
#>    stage_2_step_calibrate      270    4495  0.217     1.047   258
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
```

## The quality-alert gate

[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
records every quality incident in one place, regardless of whether the
surrounding warnings were shown or suppressed.
[`has_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md)
is the gate;
[`weighting_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md)
returns the messages, each tagged with the step that raised it. This is
the hook to stop a publication when something is off:

``` r

has_alerts(fit)
#> [1] FALSE
weighting_alerts(fit)
#> character(0)

if (has_alerts(fit)) {
  message("Review needed before dissemination:")
  for (a in weighting_alerts(fit)) message("  - ", a)
}
```

## Unit by unit: what did a step do?

[`collect_step_detail()`](https://jpferreira33.github.io/weightflow/reference/collect_step_detail.md)
returns, for a chosen step, the weight each unit brought in
(`.weight_in`), the multiplier the step applied (`.factor`, so
`.weight_in * .factor` is the outgoing weight), plus that step’s native
per-unit quantities. Select the step by its id:

``` r

det <- collect_step_detail(fit, step = "nonresponse_1")
head(det)
#>   person_id household_id psu region sex age   pw unknown_elig responded income
#> 1         8            3   1  North   F  28 12.5            0         1  52146
#> 2         9            3   1  North   F  71 12.5            0         0     NA
#> 3       178           85   5  North   M  51 12.5            0         0     NA
#> 4       179           85   5  North   M  61 12.5            0         0     NA
#> 5       195           92   5  North   M  18 12.5            0         1  28263
#> 6       198           94   6  North   M  40 12.5            0         1  33898
#>   employed .weight_in  .factor .propensity .responded        .class
#> 1        0       12.5 1.576271   0.6597763       TRUE (0.643,0.684]
#> 2       NA       12.5 0.000000   0.6781653      FALSE (0.643,0.684]
#> 3       NA       12.5 0.000000   0.6501147      FALSE (0.643,0.684]
#> 4       NA       12.5 0.000000   0.6544954      FALSE (0.643,0.684]
#> 5        0       12.5 1.574468   0.6354809       TRUE (0.594,0.643]
#> 6        0       12.5 1.576271   0.6452665       TRUE (0.643,0.684]
```

For a nonresponse propensity step,
[`collect_propensities()`](https://jpferreira33.github.io/weightflow/reference/collect_propensities.md)
recovers the fitted response propensities directly, so you can inspect
their distribution before trusting the adjusted weights:

``` r

props <- collect_propensities(fit)
summary(props$.propensity)
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>  0.4989  0.5289  0.5748  0.5782  0.6355  0.6836
```

## Domain by domain: is each domain reliable?

[`domain_summary()`](https://jpferreira33.github.io/weightflow/reference/domain_summary.md)
reports, for each study domain, how the weights move at every stage of
the cascade (active units, sum of weights, mean weight and the Kish
design effect), so weight movement can be reviewed per domain, not only
overall:

``` r

domain_summary(fit, by = "region")
#>             stage domain n_active     sum_w    mean_w     deff     n_eff
#> 1    base weights  North      119 1487.5000 12.500000 1.000000 119.00000
#> 2    base weights  South      121 1210.0000 10.000000 1.000000 121.00000
#> 3    base weights   East       96  800.0000  8.333333 1.000000  96.00000
#> 4    base weights   West      131  873.3333  6.666667 1.000000 131.00000
#> 5  1. nonresponse  North       78 1536.4362 19.697900 1.000000  77.99998
#> 6  1. nonresponse  South       72 1143.9047 15.887566 1.000077  71.99449
#> 7  1. nonresponse   East       52  751.7719 14.457152 1.007602  51.60767
#> 8  1. nonresponse   West       68  938.7205 13.804713 1.008337  67.43777
#> 9    2. calibrate  North       78 1570.0000 20.128205 1.004104  77.68119
#> 10   2. calibrate  South       72 1250.0000 17.361111 1.003403  71.75581
#> 11   2. calibrate   East       52  927.0000 17.826923 1.003610  51.81293
#> 12   2. calibrate   West       68  748.0000 11.000000 1.004786  67.67608
```

A domain whose design effect jumps or whose active count collapses is
where to look first.

## HTML report vs programmatic QC

Use the two together:

- `report_weighting(fit)` for the human-facing document, for reviewers,
  a methods annex, or a training session.
- [`weighting_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md),
  [`collect_step_detail()`](https://jpferreira33.github.io/weightflow/reference/collect_step_detail.md),
  [`collect_propensities()`](https://jpferreira33.github.io/weightflow/reference/collect_propensities.md)
  and
  [`domain_summary()`](https://jpferreira33.github.io/weightflow/reference/domain_summary.md)
  for automated acceptance rules in a script: fail the run if
  [`has_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md)
  flags a critical incident, if a domain’s design effect exceeds a
  threshold, or if a propensity model produced extreme factors.

The recipe object, its ids and its alerts are stable across runs, so the
same QC script keeps working as the recipe evolves.
