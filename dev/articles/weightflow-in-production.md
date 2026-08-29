# weightflow in production (GSBPM 5.6)

In the Generic Statistical Business Process Model (GSBPM), the
construction of analysis weights is sub-process 5.6 (“calculate
weights”) and the production of estimates and their variances is 5.7
(“calculate aggregates”). In a statistical office this step is not a
one-off script: it is a governed, auditable and repeatable part of the
production line, run every wave, reviewed, and archived. This article
shows how weightflow supports that workflow. Every piece below already
exists in the package; the point is to use them together.

## The recipe is the artifact

The core idea is that the whole weighting process is a single
declarative object. You define it once, estimate it with
[`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md),
and everything else (diagnostics, variance, the report) reads from that
one object. The recipe is what you version, review in a pull request,
and archive alongside the estimates.

``` r

rec <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = "region") |>
  step_calibrate(method = "raking", id = "calib_main",
                 margins = list(region = c(table(population$region)),
                                sex    = c(table(population$sex))))
fit <- prep(rec)
summary(fit)
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)  [nonresponse_1]
#>   2. calibration (raking)  [calib_main]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base      467    4371  0.236     1.056   442
#>  stage_1_step_nonresponse      270    4371  0.144     1.021   265
#>    stage_2_step_calibrate      270    4495  0.211     1.045   258
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
#> --- Step 1: nonresponse (weighting class) ---
#>   cell n_respondents n_nonresponse   factor
#>   East            52            44 1.846154
#>  North            78            41 1.525641
#>  South            72            49 1.680556
#>   West            68            63 1.926471
#> Kish deff: 1.056 -> 1.021   |   n_eff: 442 -> 265
#> 
#> --- Step 2: calibration (raking) ---
#>  variable category target achieved   n
#>    region    North   1570     1570  78
#>    region    South   1250     1250  72
#>    region     East    927      927  52
#>    region     West    748      748  68
#>       sex        F   2311     2311 130
#>       sex        M   2184     2184 140
#> (converged/iterated in 5 iterations)
#> Kish deff: 1.021 -> 1.045   |   n_eff: 265 -> 258
#> 
#> R-indicator (representativity of response): 0.892  (on region)
```

Because the definition is separated from the execution, the same recipe
object is the specification, the documentation and the input to the
variance machinery. Each step has a stable id (here `calib_main`,
otherwise a derived one), so a step can be referenced from a script long
after the run.

## A programmatic quality gate

Production pipelines need a machine-readable pass or fail, not a human
reading a report.
[`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md)
records every quality incident in `$alerts`, readable with
[`weighting_alerts()`](https://jpferreira33.github.io/weightflow/dev/reference/weighting_alerts.md)
and
[`has_alerts()`](https://jpferreira33.github.io/weightflow/dev/reference/weighting_alerts.md).
That is the hook for a continuous integration check: fail the build when
the recipe raises an incident.

``` r

if (has_alerts(fit)) {
  # in CI: stop() here so the pipeline fails and the run is not published
  weighting_alerts(fit)
} else {
  "no quality incidents"
}
#> [1] "no quality incidents"
```

`?weightflow-alerts` catalogues the incidents
[`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md)
can raise, with the trigger and the remedy for each. For a hard
threshold that must hold (a maximum design effect, a minimum effective
sample size), add a
[`step_assert()`](https://jpferreira33.github.io/weightflow/dev/reference/step_assert.md):
it errors at that point of the cascade if the condition fails, so a
recipe that violates it never produces weights at all.

``` r

rec |> step_assert(max_deff = 2.5, min_n_eff = 500)
```

## Reproducibility

The replication functions take a single `seed`, and draw the whole
resampling pattern from it up front, so a parallel run is bit-identical
to the serial one. Fix the seed, and record the exact package and R
versions used (for example in a lockfile), because a flexible learner
such as a random forest can change between versions of its engine. The
report’s reproducibility card records the versions at run time.

``` r

boot <- bootstrap_weights(fit, replicates = 100, strata = "region",
                          psu = "psu", seed = 20260601, progress = FALSE)
boot_mean(boot, "income")
#>   estimate       se ci_lower ci_upper
#> 1 20503.24 609.6998 19308.25 21698.23
```

## The report is the quality document

[`report_weighting()`](https://jpferreira33.github.io/weightflow/dev/reference/report_weighting.md)
writes a self-contained HTML report: the cascade in prose, the target
and achieved control totals, the design effect and effective sample
size, the fieldwork outcomes and response rates when the recipe has
eligibility and nonresponse steps, and a reference-metadata header
aligned to the ESS SIMS concepts and GSBPM 5.6. Archive that HTML next
to the released estimates; it is the artifact a reviewer reads.

``` r

report_weighting(
  fit, replicates = boot, file = "weights_2026.html", lang = "en",
  metadata = list(
    survey           = "Continuous Household Survey",
    reference_period = "2026",
    producer         = "National Statistical Office",
    frame            = "Population and housing census 2023",
    totals_source    = "Population projections 2026",
    version          = "1.0"))
```

## Variance and dissemination

The recipe-aware bootstrap and jackknife re-run the whole recipe on each
replicate, so the replicate weights carry the variability of every
adjustment. Many offices release replicate weights alongside public-use
microdata so that external users can compute design-consistent variances
without the full design.
[`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_replicate_weights.md)
returns the point weight and every replicate weight as ordinary columns,
ready to write out and to load into `survey` or `srvyr`.

``` r

pub <- collect_replicate_weights(boot)          # point + replicate weights
# survey / srvyr read them directly:
des <- as_svrepdesign(boot)
```

The point weights and replicate weights also flow into `survey` through
[`as_svydesign()`](https://jpferreira33.github.io/weightflow/dev/reference/as_svydesign.md)
/
[`as_svrepdesign()`](https://jpferreira33.github.io/weightflow/dev/reference/as_svydesign.md),
so downstream estimands and domains use the design-based machinery the
office already trusts.

## Where it sits

The cascade maps onto the total survey error framework:
unknown-eligibility redistribution and dropping out-of-scope units
address coverage error, the within-household selection restores the
design, the nonresponse step addresses nonresponse error, and
calibration reduces coverage bias and improves precision. Placing the
whole process in one auditable, re-runnable object is what the quality
frameworks ask for: the UN Fundamental Principles of Official Statistics
and the European Statistics Code of Practice both require sound
methodology, transparency and reproducibility. weightflow does not
replace the parts of 5.6 and 5.7 that belong to other tools (small-area
estimation, editing, imputation); it is the reproducible spine that
documents and computes the weights, and bridges to those tools honestly.

## See also

[`vignette("variance-estimation")`](https://jpferreira33.github.io/weightflow/dev/articles/variance-estimation.md)
for the replicate methods,
[`vignette("quality-report")`](https://jpferreira33.github.io/weightflow/dev/articles/quality-report.md)
for the report,
[`vignette("inspecting-auditing")`](https://jpferreira33.github.io/weightflow/dev/articles/inspecting-auditing.md)
for the programmatic quality-control accessors, and `?weightflow-alerts`
for the alert catalogue.
