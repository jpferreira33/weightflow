# Panel / longitudinal HTML report

Builds an HTML report by ADDING the panel cards to the standard report.
When a longitudinal weight is given, it renders the full
[`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
page for that weight (cascade, weight distribution, deff, ...) and
injects a "Panel / longitudinal" section with the rotation structure
([`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)),
the coordinated net-change variance
([`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md)),
the attrition/retention summary, and the gross flows
([`transition_matrix()`](https://jpferreira33.github.io/weightflow/reference/transition_matrix.md)
/
[`boot_transition()`](https://jpferreira33.github.io/weightflow/reference/boot_transition.md)).
Without a longitudinal weight it writes a small standalone page with
those cards. Any argument may be `NULL`; its card is skipped.

## Usage

``` r
report_panel(
  design = NULL,
  change = NULL,
  longitudinal = NULL,
  transition = NULL,
  coordinated = NULL,
  estimates = NULL,
  variance = NULL,
  file = NULL,
  open = TRUE,
  lang = c("en", "es")
)
```

## Arguments

- design:

  a `wf_panel_design` from
  [`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md).

- change:

  a `weightflow_change` from
  [`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md)
  /
  [`change_mean()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md).

- longitudinal:

  a prepped longitudinal `weighting_spec`; when given, the report is the
  full weighting report of that weight with the panel section added.

- transition:

  a `weightflow_transition` / `_boot` from the flow functions.

- coordinated:

  the coordinated
  [`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md)
  /
  [`wave_jackknife()`](https://jpferreira33.github.io/weightflow/reference/wave_jackknife.md)
  object behind `change`, so the report shows a "Replication-based
  variance estimation" card stating the coordinated method, replicates,
  strata, PSUs, recipe-aware setting and seed.

- estimates:

  results of the estimation grammar: a `weightflow_estimation_result`
  from
  [`collect_estimates()`](https://jpferreira33.github.io/weightflow/reference/collect_estimates.md),
  an uncollected
  [`step_estimate()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md)
  pipeline (collected here), or a named list of either – the names
  become the card titles. Each becomes a results block with the levels
  behind a change, its coordinated standard error and confidence
  interval, a dot-and-whisker chart across the
  [`step_domain()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md)
  cells, and the subpopulation any
  [`step_filter()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md)
  restricted it to.

- variance:

  the longitudinal-weight
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  / jackknife object, so the base report shows the variance/replication
  card (deff, method, replicates) for the longitudinal weight instead of
  "replicate weights not created". The coordinated CHANGE variance is
  shown by the `change` card.

- file:

  output path; a temporary `.html` if `NULL`.

- open:

  open the file in a browser.

- lang:

  `"en"` (default) or `"es"`.

## Value

the path to the written HTML file, invisibly.

## See also

[`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md),
[`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md),
[`change_estimate()`](https://jpferreira33.github.io/weightflow/reference/change_estimate.md),
[`boot_transition()`](https://jpferreira33.github.io/weightflow/reference/boot_transition.md)
