# Self-contained HTML quality report for a weighting recipe

Writes a single, self-contained HTML file documenting how a prepped
recipe turned the design base weights into the final weights: the
cascade, the parameters requested at each step, the per-stage weight
summary, the step-specific diagnostics (calibration, nonresponse,
trimming), the fieldwork outcome rates and an audit trail. It is the
deliverable to attach to a methodological report or a weighting annex:
everything is inline, so the file opens offline and can be archived or
emailed as one artifact.

## Usage

``` r
report_weighting(
  object,
  file = NULL,
  open = TRUE,
  plots = TRUE,
  narrative = TRUE,
  lang = c("en", "es"),
  metadata = NULL,
  replicates = NULL,
  domains = NULL,
  y_vars = NULL
)
```

## Arguments

- object:

  a prepped object (output of prep()).

- file:

  output path; if NULL, a temporary .html file.

- open:

  logical; open the file in the browser.

- plots:

  logical; add per-step plots (weight before-vs-after scatter and
  adjustment-factor histogram), drawn as self-contained inline SVG (no
  graphics device or extra package required).

- narrative:

  logical; add an auto-generated methodological narrative – an executive
  summary at the top and a natural-language paragraph on each step
  explaining what was done and why (built from the step's own parameters
  and diagnostics), in the spirit of a GSBPM / ESQRS methodological
  report.

- lang:

  language of the narrative: "en" (default) or "es".

- metadata:

  optional named list of reference metadata (SIMS / ESMS concepts) shown
  as a header card, e.g. `survey`, `reference_period`, `geography`,
  `producer`, `author`, `contact`, `frame`, `totals_source`,
  `totals_date`, `version`, `confidentiality`, `notes`. Recognised keys
  get a proper label; any other key is shown as given. `survey` is also
  woven into the executive summary. `totals_source`/`totals_date`
  document where the calibration control totals come from and their
  reference date.

- replicates:

  optional `weightflow_boot` or `weightflow_jack` object (from
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_weights.md)
  /
  [`jackknife_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/jackknife_weights.md)).
  If given, a "Replication design for variance" card documents the
  method, number of replicates, strata / PSU structure, lonely-PSU
  handling, seed, cores and run time, and warns when few PSUs per
  stratum favour JKn.

- domains:

  optional one-sided formula of grouping variables for a per-domain
  reliability card. Each term becomes one table (`+` = separate tables,
  `:` = crossed), showing the active n, sum of weights, CV, Kish design
  effect and effective sample size within each domain. E.g.
  `domains = ~ region + region:sex`.

- y_vars:

  optional character vector of survey outcome variables. When a
  nonresponse-by-calibration step is present, the auxiliary-quality
  table adds, for each auxiliary, its weighted correlation with each `y`
  among respondents (Sarndal-Lundstrom criterion (ii): a good auxiliary
  also explains the `y`).

## Value

(invisibly) the path to the HTML file.

## Examples

``` r
fitted <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  prep()
# \donttest{
# writes a self-contained HTML report to a temporary file (open = FALSE so
# nothing is launched); use open = TRUE to view it in the browser.
path <- report_weighting(fitted, open = FALSE)
# }
```
