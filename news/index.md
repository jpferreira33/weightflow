# Changelog

## weightflow 1.0.0.9000 (development version)

### New features

- **[`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_replicate_weights.md)
  now exports jackknife replicates too.** It previously accepted only a
  bootstrap object; it now also takes a `weightflow_jack` (delete-a-PSU
  jackknife, the North-American replicate-weights standard) and attaches
  the correct replication design as attributes (`"type"`, `"scale"`,
  `"rscales"`) so the exported data feeds `survey`/`srvyr` with the
  right variance scaling for either method. Its first argument is
  renamed `boot` -\> `object` (unnamed calls are unaffected).

- **Iterative recipe refinement.** Adding a step to an already-prepped
  recipe now clears the previous results with a message and downgrades
  the recipe to unprepped, so stale weights can never be read by
  accident; the whole cascade re-runs on the next
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md).
  Typical use: prep, inspect the realized weight distribution, choose
  trimming bounds from it, add
  [`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md)
  and prep again – the recipe stays the single audit trail of the final
  decision.

- **Trimming diagnostics in the report.** The trim steps share a card:
  winsorization accounting (mass moved, redistributed vs absorbed), bias
  cost in SEs with `report_weighting(y_vars = ...)`, the Potter MSE
  curve, a threshold-sensitivity table, per-subgroup detail, and alerts
  for over-trimming, inert trims and a later calibration re-inflating a
  trimmed cap.

- **Calibration diagnostics in the report.**
  `step_calibrate(method = "linear")` gains a card: g-range, negative /
  at-bound counts, chi-square distance, condition number, per-constraint
  influence, expected efficiency gain (`y_vars`), an overlap note with
  prior nonresponse steps, and a per-domain table under `by =`;
  ill-conditioning and negative weights raise alerts.

- **Propensity-model diagnostics in the report.**
  `step_nonresponse(method = "propensity")` gains a card: calibration by
  decile (Cox slope, Brier), propensity floor / overlap, covariate
  balance, model spec and hyperparameters, weighted AUC read in context,
  top predictors, and the in-sample vs out-of-fold gap; a miscalibrated
  model raises an alert. The refit runs once at report time, never in
  the bootstrap.

- **Nonresponse-by-calibration diagnostics (unified).**
  `step_nonresponse(method = "calibration")` recovers the implicit
  propensity phi-hat = 1/g and shows its distribution, the information
  level (InfoS / InfoU) and an auxiliary-quality grade (explains
  response / explains `y`); non-positive g raises an alert. Weighting
  classes, propensities and calibration now share one diagnostic
  language.

- **Differentiated (per-subgroup) trimming.**
  [`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md)
  gains a `by` argument, and `lower` / `upper` may be a named vector of
  bounds per subgroup, so each subgroup is trimmed to its own bounds
  while the preserved totals of `formula` stay global. On a suggestion
  by Andrés Gutiérrez (ECLAC - Statistics Division).

### Bug fixes

- **Two silent-corruption traps now error.** A non-finite base weight
  (`Inf` / `NaN`) used to pass through the whole cascade untouched (only
  `NA` and negative weights were rejected);
  [`weighting_spec()`](https://jpferreira33.github.io/weightflow/reference/weighting_spec.md)
  now requires finite base weights. A classic (named-vector) raking or
  post-stratification margin naming a level that matches no active unit
  (a typo like `"Zona99"`, or a category carried over from the
  population projections) used to be raked silently to an unreachable
  total;
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  now errors, naming the offending levels.

- **Missing disposition flags now error instead of being read as
  `FALSE`.** A `respondent` / `unknown` / `ineligible` flag with `NA`
  values **among the units still in scope at that step** used to be
  silently coerced to `FALSE` (treating the case as nonrespondent /
  known eligibility / eligible); it now stops with the count of missing
  values, so an uncoded disposition can no longer misclassify units
  silently. `NA` for units already out of scope (weight 0, dropped as
  ineligible or unknown) is still fine – their disposition is genuinely
  undefined. Consistent with how `NA` auxiliaries are handled in
  calibration.

- **Clearer guards on natural misuse.**
  [`weighting_spec()`](https://jpferreira33.github.io/weightflow/reference/weighting_spec.md)
  errors on a 0-row data frame (a common symptom of an upstream filter
  that emptied the data);
  [`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md)
  warns when the output column (default `.weight`) already exists in the
  data and is overwritten (use `weight_name=`); and
  [`design_effect()`](https://jpferreira33.github.io/weightflow/reference/design_effect.md)
  now accepts a prepped recipe directly, not only a weight vector.

- **`step_nonresponse(num_classes =)` no longer fails with “invalid
  number of intervals”** when the fitted propensities are nearly
  constant: the quantile cut-points collapse to a single class (with an
  alert) instead of erroring. Found by the variance-validation
  simulation.

- **Correctness on degenerate inputs.** Units in an adjustment cell with
  no respondents (or all of unknown eligibility) are now set to weight 0
  instead of passing through with their original weight;
  `step_calibrate(method = "linear")` and
  [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
  error on `NA` auxiliaries instead of silently returning corrupted
  weights (recycling); and `lonely_psu = "collapse"` nests PSU ids
  within their original stratum, so two distinct PSUs are no longer
  merged (which had under-estimated the variance).
  `step_trim(reference = "median", by = )` now uses each group’s own
  median.

- **Clearer failures and validation.**
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  errors on a `margins` variable that is not a column of the data (was a
  silent no-op);
  [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
  warns about arguments ignored by the chosen `method`;
  [`weighting_spec()`](https://jpferreira33.github.io/weightflow/reference/weighting_spec.md)
  rejects negative base weights and
  [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
  validates `num_classes`; step conditions now resolve variables from
  the caller’s environment; and `tol` is honored in bounded and
  non-linear calibration.

- **New quality alerts.** The report now flags very small response
  propensities (extreme `1/p` weights, from a poor model or a degenerate
  cross-fitting fold) and partially-responding households (treated as
  whole-household nonresponse, which discards responding members).

- **`survey` bridge.**
  [`as_svydesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
  accepts formulas (no deprecation warning), and its help clarifies that
  only the replicate-weights design propagates the adjustment
  variability;
  [`as_svrepdesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
  drops failed (`NA`) replicates and rescales to the valid ones;
  parallel replicates fall back to serial on Windows.

- **Report and performance.** User-supplied group names and the `by`
  column are HTML-escaped, the report template uses named interpolation
  (no positional mismatch), and raking / post-stratification precompute
  the cell indices, which is much faster on large samples with fine
  margins.

- **Design-effect note reads in context.** The report’s methodological
  footnote now explains that the Kish design effect measures weight
  variability against equal weighting and should be read in context:
  calibration to informative auxiliaries can raise it even as precision
  improves (the design effect overstates the loss when weights correlate
  with the outcome), whereas a nonresponse adjustment trades variance
  for reduced bias. It is best used as a post-hoc diagnostic (Kish 1992;
  Spencer 2000; Little and Vartivarian 2005; Valliant, Dever and Kreuter
  2018).

## weightflow 1.0.0

CRAN release: 2026-08-04

### New features

- **Tidy control totals that disagree on N now reconcile instead of
  failing.** When the tidy `totals` given to
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  do not all sum to the same population size (typical rounding of
  independently produced control totals), the largest margin is kept as
  the reference N and the others are rescaled proportionally, so their
  internal distribution is preserved and the calibration always closes.
  This applies to both `method = "raking"` (which previously could fail
  to converge) and `method = "linear"` / GREG (which previously used the
  first margin silently). The adjustment is reported through a message
  (informative, never fatal, so it is safe under `options(warn = 2)`)
  and is carried into
  [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md),
  where it appears in the points-of-attention panel and the calibration
  step card listing every rescaled margin and the common N, so
  control-total mismatches are surfaced for review rather than hidden.
  This keeps the tidy interface usable without the manual dropping of a
  category that a design matrix would otherwise require.

- **Unweighted propensity models.**
  `step_nonresponse(method = "propensity")` gains `weight_model`
  (default `TRUE`). With `FALSE` the response-propensity model is fit
  unweighted, so the incoming weights enter only the 1/p (or class)
  adjustment and not the model fit – useful when the weights are
  unrelated to response given the covariates (Little & Vartivarian
  2003). Works at unit and household (cluster) level and across all
  engines. On a suggestion by Andrés Gutiérrez (ECLAC - Statistics
  Division).

- **Nonresponse by calibration (two-phase).**
  [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
  gains `method = "calibration"`: instead of weighting classes or
  inverse propensities, it adjusts for nonresponse by calibrating the
  respondents’ weights to auxiliary totals (Lundstrom & Sarndal 1999;
  Sarndal & Lundstrom 2005). With `totals = NULL` (default) the targets
  are the R+NR design-weighted totals at that stage, so the calibrated
  respondent estimates reproduce the pre-nonresponse cascade estimates
  exactly (the two-phase / sample-level case, Estevao & Sarndal 2002);
  supply `totals` to calibrate to population totals instead. Continuous
  and categorical auxiliaries, the distance `calfun`
  (linear/raking/logit), `bounds` and `penalty` (ridge) all carry over
  from
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md).
  The sample-level target is recomputed inside each bootstrap/jackknife
  replicate, so the two-phase variance is captured by the recipe-aware
  machinery. With `equal_within_cluster = TRUE` (and a `cluster`) the
  adjustment is integrative (Lemaitre-Dufour): the responding members of
  a household share a single calibration factor, so nonresponse
  calibration keeps the weights constant within household, as in a
  household survey. `method = "weighting_class"` remains the
  post-stratification (joint-cell) special case; the marginal (IPF via
  `margins`) variant is planned for a later 0.3.0 increment.

- **[`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md):
  trimmed (range-restricted) calibration.** Trims already-calibrated
  weights into an absolute interval `[lower, upper]` while **preserving
  the calibration totals**, unlike
  [`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md)
  which caps and redistributes (breaking the constraints). It is a
  bounded re-calibration (the generalized exponential method of Folsom &
  Singh 2000): the targets to preserve are the totals the incoming
  weights already achieve, and the absolute-weight bound becomes a
  per-unit factor bound `w_new / w in [lower/w, upper/w]`, solved with
  the range-restricted Euclidean distance (`calfun = "linear"`, the
  default) or the multiplicative one (`"raking"`). Weights inside the
  range stay put; out-of-range ones saturate at their bound and the rest
  move minimally to restore every total. If the range is infeasible, the
  unmet totals are relaxed and a warning is raised. It reuses the
  bounded-calibration solver, now able to take per-unit bounds. With
  `equal_within_cluster = TRUE` (and a `cluster`) the trimming is
  integrative: one factor per household, so weights that were constant
  within household stay constant (the household-level analogue of
  `survey`’s `aggregate.stage` calibration).

- **Lonely-PSU handling and parallelism in the replicate-variance
  functions.**
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  and
  [`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)
  gain a `lonely_psu` argument: `"certainty"` (default) keeps the
  previous behaviour (single-PSU strata are self-representing,
  contribute no variance, and warn), while `"collapse"` merges
  single-PSU strata into a pseudo-stratum so they are resampled and
  yield a (conservative) variance instead of zero. Both functions also
  gain a `cores` argument: with `cores > 1` the per-replicate re-preps
  run in parallel via
  [`parallel::mclapply`](https://rdrr.io/r/parallel/mclapply.html)
  (forking; serial on Windows). The resampling is drawn up front from
  the `seed`, so the parallel run is bit-identical to the serial one.

- **`redistribute` argument for
  [`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md).**
  The trimmed mass can now be shared among the untrimmed units either in
  proportion to their weights (`"proportional"`, the default, keeps
  their relative sizes) or in equal amounts (`"uniform"`, the same
  amount to each untrimmed unit, with already-trimmed cases not reused).
  The `"uniform"` option reproduces
  [`survey::trimWeights()`](https://rdrr.io/pkg/survey/man/trimWeights.html)
  exactly, for bit-for-bit agreement when a weighting pipeline is
  validated against `survey`.

- **[`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
  is now a full methodological quality report (GSBPM 5.6 / ESS style).**
  With `narrative = TRUE` (default) the HTML report reads like an
  official quality report: an auto-generated executive summary (the
  cascade in prose plus the headline design effect, effective n and
  R-indicator) and a natural-language paragraph on each step built from
  its own parameters and diagnostics, in English or Spanish (new
  `lang`). A new `metadata` argument adds a reference-metadata header
  card aligned to the ESS SIMS / ESMS concepts and GSBPM sub-process 5.6
  (operation, reference period, coverage, producer, contact, sampling
  frame, the source and date of the control totals, version,
  confidentiality). When the recipe has eligibility / nonresponse steps,
  a “Fieldwork outcomes” card reconstructs every case’s disposition and
  reports the AAPOR response rate in three variants, from most to least
  conservative in how unknown-eligibility cases are treated, RR1 \<= RR3
  (CASRO, e-adjusted) \<= RR5, weighted and unweighted (Valliant, Dever
  & Kreuter 2018, ch. 6). The executive summary also aggregates a
  “Points of attention” panel (steps that did not converge or raised an
  alert, each with a short recommendation), a truthful status checklist
  (convergence, final design effect, extreme and replicate weights,
  alerts) and a completion line; calibration steps get descriptive names
  by their auxiliaries and a relative-deviation column on their
  target/achieved tables. Set `narrative = FALSE` for the previous
  tables-only report.

- **New analytical cards, charts and navigation in
  [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md).**
  A per-domain reliability card (new `domains` one-sided formula: active
  n, sum of weights, CV, Kish design effect and effective n within each
  domain, one table per term, `+` separate and `:` crossed). A per-step
  impact table (the change in Kish deff and CV versus the previous
  stage, each step’s share of the total \|deff change\|, and whether it
  adds variance or recovers efficiency). A Kish design-effect evolution
  chart across stages. A replication-design card (new `replicates`, a
  `weightflow_boot` / `weightflow_jack` object: method, replicates,
  strata, mean PSUs per stratum, lonely-PSU handling, seed, cores and
  run time);
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  and
  [`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)
  now record this metadata. Plus a navigation menu, conditional
  colouring of the design-effect cells, a plain-language interpretation
  of the final design effect, collapsible per-step details, and a
  restyle to the package identity. Still pure inline SVG, no JavaScript
  and no new dependencies.

### Bug fixes

- **Cross-fitting no longer errors in a fresh session.** With a
  `crossfit_seed`,
  [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
  and
  [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
  saved and restored the global RNG state but assumed `.Random.seed`
  already existed, which fails in a session that has not yet drawn a
  random number (e.g. a vignette build). The state is now saved only
  when present and unset again otherwise.

- **[`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md)
  now trims negative weights.** It previously acted only on positive
  weights (`w > 0`), so negative weights produced by unbounded linear
  calibration were left untouched by a lower floor. It now trims every
  non-zero weight, flooring negatives to `lower`, while still leaving
  dropped units (weight exactly 0) alone. Recipes without negative
  weights are unaffected.

- **Reproducible report scatter plots.** The weight before/after scatter
  in
  [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
  subsampled points at random (without a seed) when a step had more than
  800 units, so the plotted cloud changed between renders even though
  the weights were identical. It now uses a deterministic thinning
  (`.thin_scatter()`): all points are drawn up to `cap = 3000`, and
  above that the plot always keeps both tails on each axis
  (smallest/largest weights before and after) and the largest departures
  from the y = x line, then systematically thins the dense core. The
  scatter is now identical across runs and never drops the outliers.

## weightflow 0.2.0

CRAN release: 2026-07-22

### New features

- **Tidy population totals for
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md).**
  In addition to the classic `margins`/`totals` inputs (which keep
  working unchanged), calibration targets can now be given as tidy data
  frames, paired with the new `count` argument that names the counts
  column:
  - *Post-stratification*: a data frame with one or more category
    columns plus a counts column. Several category columns are crossed
    automatically, so there is no need to build a collapsed cell
    variable by hand.
  - *Raking*: a list of data frames, one per margin.
  - *Linear/GREG*: a named list matching the formula terms, with a data
    frame (all categories) for each factor and a single number for each
    continuous total; weightflow builds the model.matrix totals
    internally, so the user never drops a reference category or handles
    the intercept. Calibration also reports clearer diagnostics and
    warnings: post-stratification flags cells in the sample but missing
    from the totals (error) or in the totals but absent from the sample
    (warning); raking warns on mutually inconsistent margins or
    non-convergence; linear calibration warns when the constraints are
    not fully satisfied; and calibration variables with missing values
    raise an informative error.
- **Subsampling of more than one person per household in
  [`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md).**
  A new `n_selected` argument (a single number or an unquoted column)
  works alongside `n_eligible` for simple random selection of a
  subsample: the weight is multiplied by `n_eligible / n_selected`
  (equivalent to `prob = n_selected/n_eligible`). It defaults to 1, so
  selecting a single person keeps working unchanged.
- **External consistency totals for
  [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md).**
  The totals of the `x_formula` auxiliaries can now be supplied through
  the new `x_totals` argument, in the same two shapes as
  `step_calibrate(method = "linear")`: the tidy format (a named list
  with a data frame per factor, paired with `count`, and a single number
  per continuous total) or the classic model-matrix vector. This covers
  the common case where the X control totals come from an external
  source rather than from the frame; the auxiliaries then need to be
  present only in the sample, not in `population`. When `x_totals` is
  `NULL` (default) the X totals are still taken from `population`, so
  existing code is unchanged. `population` remains required, because the
  model-assisted block predicts each outcome over every population unit.
  Model calibration now also warns, like linear calibration, when the
  achieved totals do not fully satisfy the constraints (collinear or
  ill-conditioned auxiliaries).
- **Delete-a-PSU jackknife variance (recipe-aware).**
  [`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)
  builds jackknife replicate weights by deleting one PSU at a time and
  re-running the whole recipe on each replicate, so the replicate
  weights carry the variability of every adjustment. It is the
  stratified jackknife (JKn) with `strata`/`psu`, the unstratified
  jackknife (JK1) with `strata = NULL`, and the delete-one-unit
  jackknife with `psu = NULL`.
  [`jackknife_estimate()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)
  (plus
  [`jack_total()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)
  /
  [`jack_mean()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md))
  summarise a statistic with the JKn variance and match `survey`’s
  replicate jackknife for totals.
  [`as_svrepdesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
  now also accepts a jackknife object, so the recipe-aware replicate
  weights flow into `survey`/`srvyr` for any estimand and any domain.
- **Domain (partitioned) calibration in
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md).**
  A new `by` argument names a domain (partition) column; the weights are
  then calibrated **independently within each domain**, each to its own
  totals (partitioned / domain calibration). The tidy totals carry the
  domain as a column, and a continuous total becomes a data frame
  `domain, value` (one total per domain); the domain variable does not
  go in the formula/margins. It composes with `calfun`, `bounds`,
  `penalty` and `equal_within_cluster`, applied within each domain, and
  reproduces every domain’s benchmarks. `by = NULL` (default) calibrates
  globally, unchanged.
- **Exponential (raking) distance for
  `step_calibrate(method = "linear")`.** `calfun` now also accepts
  `"raking"` (the multiplicative distance g = exp(u)), next to
  `"linear"` and `"logit"`. It keeps the calibration weights positive
  without needing explicit `bounds` and still satisfies the constraints
  exactly, and works on mixed categorical and continuous auxiliaries as
  well as with the integrative option (`equal_within_cluster`, one
  weight per cluster). Matches `survey::calibrate(calfun = "raking")`.
- **R-indicator of response representativity (automatic diagnostic).**
  When the recipe includes a nonresponse adjustment,
  [`summary()`](https://rdrr.io/r/base/summary.html) and
  [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
  now report the R-indicator (Schouten, Cobben & Bethlehem), R = 1 -
  2\*S, with S the design-weighted standard deviation of the estimated
  response propensities over the eligible sample: closer to 1 means a
  more representative response and less nonresponse-bias risk. The
  report also shows the unconditional partial R-indicators by auxiliary,
  pointing to which variable drives the lack of representativity. It is
  computed on the auxiliaries of the nonresponse step and needs no new
  function or user action; recipes without a nonresponse step are
  unaffected.
- **Machine-learning response propensities** (CART, random forest and
  gradient boosting via `xgboost`) for
  [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
  and
  [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md).
- **k-fold cross-fitting** (`crossfit`) to estimate each unit
  out-of-sample, with folds formed by cluster to avoid leakage.
- **Ridge (penalized) calibration** (`penalty`) to keep weights stable
  with many auxiliaries.
- **Potter MSE-optimal trimming** (`method = "potter"`), a data-driven
  cutoff.
- **Quality alerts in
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md).**
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
  now computes non-fatal quality alerts and stores them on the prepped
  object (`$alerts`) and per step: negative or sub-1 weights and
  g-factors outside the Deville-Särndal bounds `[0.1, 10]` after
  calibration, small adjustment cells (new `min_cell_n`, default 30,
  following Kalton and Flores-Cervantes 2003) and excessive adjustment
  factors (new `max_factor`, default 2.5). Alerts always appear in the
  HTML report; set `prep(warn = TRUE)` to also raise them as R warnings.
- **Weight distribution and alerts in
  [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md).**
  The report gains a “Weight distribution (final)” summary (min, p1,
  median, p99, max, max/min ratio, and counts of negative, sub-1 and
  extreme weights) and a per-step “Quality alerts” block.
- **New `disposition` column in the `sample_one` example data.** A
  single factor with the full field disposition (eligible respondent,
  eligible nonrespondent, household nonresponse, ineligible, unknown
  eligibility), recoded from the existing indicator columns (which are
  kept). It gives a tidy single-column view of the dispositions and can
  be used directly via logical conditions in the steps.
- **New vignette “Preparing the sample: eligibility and response before
  weighting”**, on how the input sample should be classified (the
  disposition tree), how it is sized (eligibility and response
  inflation) and how the dispositions map to the adjustment steps.

### Bug fixes

- The optional machine-learning engines (`engine = "forest"` via ranger,
  `engine = "boost"` via xgboost) now run single-threaded by default,
  for reproducibility and to respect the core limits applied in CRAN
  checks. Set `options(weightflow.num_threads = n)` to use `n` threads.

- [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
  now flags calibration steps that did not converge. When a raking,
  linear or bounded calibration stops without satisfying the requested
  totals (the same condition that already prints a console warning), the
  HTML report shows a “Did not converge” alert on that step and no
  longer states that the step converged. Previously the report always
  reported convergence, regardless of the actual result.

- `step_calibrate(equal_within_cluster = TRUE)` now implements the
  genuine Lemaitre-Dufour (1987) integrative method: each unit’s
  auxiliaries are replaced by their household mean before a person-level
  calibration, so the per-household penalty scales with household size.
  This matches `survey`’s `calibrate(aggregate.stage = )`
  (Vanderhoeft 2001) to machine precision. The previous implementation
  used a household-level distance (summed auxiliaries, uniform
  per-household penalty), a different (non-standard) method.
  Integrative-calibration weights will change; totals are still met
  exactly and weights remain constant within household.

## weightflow 0.1.0

CRAN release: 2026-06-30

First release.

A dependency-free, pipeable API to compute survey weights from design
base weights through a chain of hierarchical adjustment stages. Build a
recipe lazily, estimate it with
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md),
and extract the weights with
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md).
Separating *define* from *apply* makes the whole process reproducible
and auditable, and lets the bootstrap re-run the entire cascade on each
replicate.

### Adjustment steps

- [`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md):
  redistribute the weight of unknown-eligibility cases to the known ones
  (person- or household-level via `cluster`).
- [`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md):
  zero out out-of-scope units.
- [`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md):
  within-household selection (unequal `prob` or equal `n_eligible`).
- [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md):
  weighting-class or propensity adjustment, at the person or household
  level (`cluster`).
- [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md):
  raking, post-stratification and linear/GREG calibration, with bounded
  (Deville-Särndal) and integrative (one weight per household) cluster
  options.
- [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md):
  Wu-Sitter model calibration.
- [`step_trim()`](https://jpferreira33.github.io/weightflow/reference/step_trim.md),
  [`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md),
  [`step_round()`](https://jpferreira33.github.io/weightflow/reference/step_round.md),
  [`step_rescale()`](https://jpferreira33.github.io/weightflow/reference/step_rescale.md):
  trimming, rounding and rescaling.
- [`step_assert()`](https://jpferreira33.github.io/weightflow/reference/step_assert.md):
  quality checkpoint (deff, weight ratio, effective n).

### Inspection and reporting

- [`summary()`](https://rdrr.io/r/base/summary.html),
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html) and
  [`weight_factors()`](https://jpferreira33.github.io/weightflow/reference/weight_factors.md)
  for per-stage diagnostics.
- [`design_effect()`](https://jpferreira33.github.io/weightflow/reference/design_effect.md)
  for the Kish design effect and effective sample size.
- [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
  builds a self-contained HTML report with a pipeline diagram, the
  variables used, per-stage summaries and per-step visuals.

### Variance estimation

- [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  resamples PSUs within strata (Rao-Wu rescaling) and re-applies the
  whole recipe on each replicate, so the replicate weights carry the
  variability of every adjustment.
- [`boot_mean()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  and
  [`boot_total()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  return the estimate, standard error and CI.
- [`as_svydesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md),
  [`as_svrepdesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
  and
  [`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_replicate_weights.md)
  bridge to the `survey` and `srvyr` packages for design-based
  inference.

### Data

- Bundled example datasets `population`, `sample_survey` (take-all
  roster) and `sample_one` (multistage select-one design), all with
  stratum, PSU and design weight.
