# weightflow 1.0.0

## New features

* **Per-domain reliability card in `report_weighting()`.** A new `domains`
  argument (a one-sided formula) adds a card with the active n, sum of weights,
  CV, Kish design effect and effective sample size within each domain, so
  small-area reliability is visible at a glance. Each formula term is one table
  (`+` for separate tables, `:` for a crossing), e.g.
  `domains = ~ region + region:sex`.

* **More descriptive step names and context-aware alerts in the report.** The
  HTML report now labels calibration steps by their auxiliaries (e.g. "GREG
  calibration to region, sex and age") in the diagram, step cards and impact
  table, and the low-cell-count alert tailors its advice to the step type
  (collapsing cells for unknown-eligibility; collapsing or switching to raking
  for post-stratification / weighting classes).

* **Per-step impact table, status checklist and completion line in
  `report_weighting()`.** The per-stage section adds a per-step impact table: the
  change in Kish deff and CV versus the previous stage, each step's share of the
  total |change in deff|, and whether it increases variance or recovers
  efficiency (factual decomposition and sign, with no arbitrary magnitude
  cut-offs, since none are established in the literature). The executive summary
  gains a truthful status checklist (convergence, final design effect, extreme
  weights, replicate weights, alerts), and the report closes with a completion
  line ("successfully", or "with N points of attention").

* **Richer, still self-contained `report_weighting()` HTML.** Adds a navigation
  menu (anchor links to each section), a Kish design-effect evolution chart
  across stages (inline SVG), conditional colouring of the per-stage
  design-effect cells, a plain-language interpretation of the final design
  effect, and a collapsible per-step detail section (native `<details>`). No new
  dependencies and no JavaScript.

* **Replication-design card in `report_weighting()`.** A new `replicates`
  argument accepts a `weightflow_boot` / `weightflow_jack` object and adds a
  card documenting the variance replication design: method (bootstrap Rao-Wu /
  JKn / JK1), number of replicates, strata and mean PSUs per stratum, lonely-PSU
  handling, seed, cores and run time, with an attention note when few PSUs per
  stratum favour JKn. `bootstrap_weights()` and `jackknife_weights()` now record
  this design metadata (including elapsed time and cores) in their returned
  object.

* **Unweighted propensity models.** `step_nonresponse(method = "propensity")`
  gains `weight_model` (default `TRUE`). With `FALSE` the response-propensity
  model is fit unweighted, so the incoming weights enter only the 1/p (or class)
  adjustment and not the model fit -- useful when the weights are unrelated to
  response given the covariates (Little & Vartivarian 2003). Works at unit and
  household (cluster) level and across all engines. Thanks to Andrés Gutiérrez
  (ECLAC - Statistics Division) for the suggestion.

* **Nonresponse by calibration (two-phase).** `step_nonresponse()` gains
  `method = "calibration"`: instead of weighting classes or inverse propensities,
  it adjusts for nonresponse by calibrating the respondents' weights to auxiliary
  totals (Lundstrom & Sarndal 1999; Sarndal & Lundstrom 2005). With
  `totals = NULL` (default) the targets are the R+NR design-weighted totals at that
  stage, so the calibrated respondent estimates reproduce the pre-nonresponse
  cascade estimates exactly (the two-phase / sample-level case, Estevao & Sarndal
  2002); supply `totals` to calibrate to population totals instead. Continuous and
  categorical auxiliaries, the distance `calfun` (linear/raking/logit), `bounds`
  and `penalty` (ridge) all carry over from `step_calibrate()`. The sample-level
  target is recomputed inside each bootstrap/jackknife replicate, so the two-phase
  variance is captured by the recipe-aware machinery. With
  `equal_within_cluster = TRUE` (and a `cluster`) the adjustment is integrative
  (Lemaitre-Dufour): the responding members of a household share a single
  calibration factor, so nonresponse calibration keeps the weights constant
  within household, as in a household survey. `method = "weighting_class"`
  remains the post-stratification (joint-cell) special case; the marginal
  (IPF via `margins`) variant is planned for a later 0.3.0 increment.

* **`step_trim_calibrated()`: trimmed (range-restricted) calibration.** Trims
  already-calibrated weights into an absolute interval `[lower, upper]` while
  **preserving the calibration totals**, unlike `step_trim_weights()` which caps
  and redistributes (breaking the constraints). It is a bounded re-calibration
  (the generalized exponential method of Folsom & Singh 2000): the targets to
  preserve are the totals the incoming weights already
  achieve, and the absolute-weight bound becomes a per-unit factor bound
  `w_new / w in [lower/w, upper/w]`, solved with the range-restricted Euclidean
  distance (`calfun = "linear"`, the default) or the multiplicative one
  (`"raking"`). Weights inside the range stay put; out-of-range ones saturate at
  their bound and the rest move minimally to restore every total. If the range
  is infeasible, the unmet totals are relaxed and a warning is raised. It reuses
  the bounded-calibration solver, now able to take per-unit bounds. With
  `equal_within_cluster = TRUE` (and a `cluster`) the trimming is integrative:
  one factor per household, so weights that were constant within household stay
  constant (the household-level analogue of `survey`'s `aggregate.stage`
  calibration).

* **Lonely-PSU handling and parallelism in the replicate-variance functions.**
  `bootstrap_weights()` and `jackknife_weights()` gain a `lonely_psu` argument:
  `"certainty"` (default) keeps the previous behaviour (single-PSU strata are
  self-representing, contribute no variance, and warn), while `"collapse"` merges
  single-PSU strata into a pseudo-stratum so they are resampled and yield a
  (conservative) variance instead of zero. Both functions also gain a `cores`
  argument: with `cores > 1` the per-replicate re-preps run in parallel via
  `parallel::mclapply` (forking; serial on Windows). The resampling is drawn up
  front from the `seed`, so the parallel run is bit-identical to the serial one.

* **Automatic methodological narrative in `report_weighting()` (GSBPM / ESQRS
  style).** With `narrative = TRUE` (default) the HTML report now reads like a
  methodological quality report: an auto-generated executive summary at the top
  (the cascade in prose plus the headline design effect, effective n and
  R-indicator), and a natural-language paragraph on each step explaining what was
  done and why, built from the step's own parameters and diagnostics (method,
  engine, auxiliaries, distance, bounds, integrative/ridge options, the
  R-indicator and its leading partials, the change in Kish design effect, ...).
  A new `lang` argument produces the narrative in English (`"en"`, default) or
  Spanish (`"es"`). Set `narrative = FALSE` for the previous, tables-only report.
  A new `metadata` argument (a named list) adds a reference-metadata header card
  aligned to the ESS SIMS / ESMS concepts and GSBPM sub-process 5.6 (statistical
  operation, reference period, geographic coverage, producer, author, contact,
  sampling frame, the source and reference date of the calibration control
  totals, version, confidentiality, notes); `survey` is also woven into the
  executive summary.

* **Fieldwork outcome rates (AAPOR) in `report_weighting()`.** When the recipe
  includes eligibility / nonresponse steps, the report now shows a "Fieldwork
  outcomes" card near the top that reconstructs the disposition of every case
  (ineligible / out of scope, unknown eligibility, eligible respondent, eligible
  nonrespondent) and reports the eligibility rate `e`, the e-adjusted response
  rate (AAPOR Standard Definitions RR3 = R / (R + NR + e&middot;U)) and the
  nonresponse rate, both unweighted and weighted by the base (design) weights. The card now
  reports the response rate in three AAPOR variants, from most to least
  conservative in how unknown-eligibility cases (U) are treated: RR1 (all U
  eligible, R/(R+NR+U)), RR3 (CASRO, e-adjusted, R/(R+NR+e&middot;U)) and RR5
  (U excluded, R/(R+NR)), so RR1 <= RR3 <= RR5 bracket the rate (Valliant,
  Dever & Kreuter 2018, ch. 6).
  `e` uses the proportional (CASRO) allocation of the unknown-eligibility cases.
  The card is bilingual and is omitted when the recipe has no nonresponse step.

* **Calibration diagnostics show relative deviations.** Any per-step
  diagnostics table with target/achieved totals (calibration, nonresponse
  calibration, trimmed calibration) now includes a relative-difference column,
  100 &times; (achieved &minus; target) / target, so a residual gap is read as a
  percentage rather than only in absolute units.

* **"Points of attention" panel in `report_weighting()`.** The executive summary
  now aggregates, at the top, any step that did not converge or raised a quality
  alert, each with a short conservative recommendation (e.g. relax the bounds or
  increase `maxit`). Nothing is shown when the cascade is clean.

* **`report_weighting()` restyled to the package identity.** The HTML report now
  uses the weightflow palette (violet accent, lavender plot points, brand amber
  for quality alerts) and neutral grey for the "no change" reference lines in the
  per-step scatter and histogram (previously red, which read as an alert). The
  per-step plots are also polished: faint gridlines, thinner axes with short
  ticks, and a `y = x` / `factor = 1` label on the reference line. Still pure
  inline SVG (no graphics device, no new dependencies).

* **`redistribute` argument for `step_trim_weights()`.** The trimmed mass can now
  be shared among the untrimmed units either in proportion to their weights
  (`"proportional"`, the default, keeps their relative sizes) or in equal amounts
  (`"uniform"`, the same amount to each untrimmed unit, with already-trimmed cases
  not reused). The `"uniform"` option reproduces `survey::trimWeights()` exactly,
  for bit-for-bit agreement when a weighting pipeline is validated against
  `survey`.

## Bug fixes

* **Cross-fitting no longer errors in a fresh session.** With a `crossfit_seed`,
  `step_nonresponse()` and `step_model_calibration()` saved and restored the
  global RNG state but assumed `.Random.seed` already existed, which fails in a
  session that has not yet drawn a random number (e.g. a vignette build). The
  state is now saved only when present and unset again otherwise.

* **`step_trim_weights()` now trims negative weights.** It previously acted only
  on positive weights (`w > 0`), so negative weights produced by unbounded linear
  calibration were left untouched by a lower floor. It now trims every non-zero
  weight, flooring negatives to `lower`, while still leaving dropped units (weight
  exactly 0) alone. Recipes without negative weights are unaffected.


* **Reproducible report scatter plots.** The weight before/after scatter in
  `report_weighting()` subsampled points at random (without a seed) when a step
  had more than 800 units, so the plotted cloud changed between renders even
  though the weights were identical. It now uses a deterministic thinning
  (`.thin_scatter()`): all points are drawn up to `cap = 3000`, and above that
  the plot always keeps both tails on each axis (smallest/largest weights before
  and after) and the largest departures from the y = x line, then systematically
  thins the dense core. The scatter is now identical across runs and never drops
  the outliers.

# weightflow 0.2.0

## New features

* **Tidy population totals for `step_calibrate()`.** In addition to the classic
  `margins`/`totals` inputs (which keep working unchanged), calibration targets
  can now be given as tidy data frames, paired with the new `count` argument
  that names the counts column:
    - *Post-stratification*: a data frame with one or more category columns plus
      a counts column. Several category columns are crossed automatically, so
      there is no need to build a collapsed cell variable by hand.
    - *Raking*: a list of data frames, one per margin.
    - *Linear/GREG*: a named list matching the formula terms, with a data frame
      (all categories) for each factor and a single number for each continuous
      total; weightflow builds the model.matrix totals internally, so the user
      never drops a reference category or handles the intercept.
  Calibration also reports clearer diagnostics and warnings: post-stratification
  flags cells in the sample but missing from the totals (error) or in the totals
  but absent from the sample (warning); raking warns on mutually inconsistent
  margins or non-convergence; linear calibration warns when the constraints are
  not fully satisfied; and calibration variables with missing values raise an
  informative error.
* **Subsampling of more than one person per household in `step_select_within()`.**
  A new `n_selected` argument (a single number or an unquoted column) works
  alongside `n_eligible` for simple random selection of a subsample: the weight is
  multiplied by `n_eligible / n_selected` (equivalent to
  `prob = n_selected/n_eligible`). It defaults to 1, so selecting a single person
  keeps working unchanged.
* **External consistency totals for `step_model_calibration()`.** The totals of
  the `x_formula` auxiliaries can now be supplied through the new `x_totals`
  argument, in the same two shapes as `step_calibrate(method = "linear")`: the
  tidy format (a named list with a data frame per factor, paired with `count`,
  and a single number per continuous total) or the classic model-matrix vector.
  This covers the common case where the X control totals come from an external
  source rather than from the frame; the auxiliaries then need to be present only
  in the sample, not in `population`. When `x_totals` is `NULL` (default) the X
  totals are still taken from `population`, so existing code is unchanged.
  `population` remains required, because the model-assisted block predicts each
  outcome over every population unit. Model calibration now also warns, like
  linear calibration, when the achieved totals do not fully satisfy the
  constraints (collinear or ill-conditioned auxiliaries).
* **Delete-a-PSU jackknife variance (recipe-aware).** `jackknife_weights()`
  builds jackknife replicate weights by deleting one PSU at a time and re-running
  the whole recipe on each replicate, so the replicate weights carry the
  variability of every adjustment. It is the stratified jackknife (JKn) with
  `strata`/`psu`, the unstratified jackknife (JK1) with `strata = NULL`, and the
  delete-one-unit jackknife with `psu = NULL`. `jackknife_estimate()` (plus
  `jack_total()` / `jack_mean()`) summarise a statistic with the JKn variance and
  match `survey`'s replicate jackknife for totals. `as_svrepdesign()` now also
  accepts a jackknife object, so the recipe-aware replicate weights flow into
  `survey`/`srvyr` for any estimand and any domain.
* **Domain (partitioned) calibration in `step_calibrate()`.** A new `by`
  argument names a domain (partition) column; the weights are then calibrated
  **independently within each domain**, each to its own totals (partitioned /
  domain calibration). The tidy totals carry the domain as a
  column, and a continuous total becomes a data frame `domain, value` (one total
  per domain); the domain variable does not go in the formula/margins. It
  composes with `calfun`, `bounds`, `penalty` and `equal_within_cluster`, applied
  within each domain, and reproduces every domain's benchmarks. `by = NULL`
  (default) calibrates globally, unchanged.
* **Exponential (raking) distance for `step_calibrate(method = "linear")`.**
  `calfun` now also accepts `"raking"` (the multiplicative distance g = exp(u)),
  next to `"linear"` and `"logit"`. It keeps the calibration weights positive
  without needing explicit `bounds` and still satisfies the constraints exactly,
  and works on mixed categorical and continuous auxiliaries as well as with the
  integrative option (`equal_within_cluster`, one weight per cluster). Matches
  `survey::calibrate(calfun = "raking")`.
* **R-indicator of response representativity (automatic diagnostic).** When the
  recipe includes a nonresponse adjustment, `summary()` and `report_weighting()`
  now report the R-indicator (Schouten, Cobben & Bethlehem), R = 1 - 2*S, with S
  the design-weighted standard deviation of the estimated response propensities
  over the eligible sample: closer to 1 means a more representative response and
  less nonresponse-bias risk. The report also shows the unconditional partial
  R-indicators by auxiliary, pointing to which variable drives the lack of
  representativity. It is computed on the auxiliaries of the nonresponse step and
  needs no new function or user action; recipes without a nonresponse step are
  unaffected.
* **Machine-learning response propensities** (CART, random forest and gradient
  boosting via `xgboost`) for `step_nonresponse()` and `step_model_calibration()`.
* **k-fold cross-fitting** (`crossfit`) to estimate each unit out-of-sample,
  with folds formed by cluster to avoid leakage.
* **Ridge (penalized) calibration** (`penalty`) to keep weights stable with many
  auxiliaries.
* **Potter MSE-optimal trimming** (`method = "potter"`), a data-driven cutoff.
* **Quality alerts in `prep()`.** `prep()` now computes non-fatal quality alerts
  and stores them on the prepped object (`$alerts`) and per step: negative or
  sub-1 weights and g-factors outside the Deville-Särndal bounds `[0.1, 10]`
  after calibration, small adjustment cells (new `min_cell_n`, default 30,
  following Kalton and Flores-Cervantes 2003) and excessive adjustment factors
  (new `max_factor`, default 2.5). Alerts always appear in the HTML report; set
  `prep(warn = TRUE)` to also raise them as R warnings.
* **Weight distribution and alerts in `report_weighting()`.** The report gains a
  "Weight distribution (final)" summary (min, p1, median, p99, max, max/min ratio,
  and counts of negative, sub-1 and extreme weights) and a per-step "Quality
  alerts" block.
* **New `disposition` column in the `sample_one` example data.** A single factor
  with the full field disposition (eligible respondent, eligible nonrespondent,
  household nonresponse, ineligible, unknown eligibility), recoded from the
  existing indicator columns (which are kept). It gives a tidy single-column view
  of the dispositions and can be used directly via logical conditions in the
  steps.
* **New vignette "Preparing the sample: eligibility and response before
  weighting"**, on how the input sample should be classified (the disposition
  tree), how it is sized (eligibility and response inflation) and how the
  dispositions map to the adjustment steps.

## Bug fixes

* The optional machine-learning engines (`engine = "forest"` via ranger,
  `engine = "boost"` via xgboost) now run single-threaded by default, for
  reproducibility and to respect the core limits applied in CRAN checks. Set
  `options(weightflow.num_threads = n)` to use `n` threads.

* `report_weighting()` now flags calibration steps that did not converge. When a
  raking, linear or bounded calibration stops without satisfying the requested
  totals (the same condition that already prints a console warning), the HTML
  report shows a "Did not converge" alert on that step and no longer states that
  the step converged. Previously the report always reported convergence,
  regardless of the actual result.

* `step_calibrate(equal_within_cluster = TRUE)` now implements the genuine
  Lemaitre-Dufour (1987) integrative method: each unit's auxiliaries are
  replaced by their household mean before a person-level calibration, so the
  per-household penalty scales with household size. This matches `survey`'s
  `calibrate(aggregate.stage = )` (Vanderhoeft 2001) to machine precision.
  The previous implementation used a household-level distance
  (summed auxiliaries, uniform per-household penalty), a different (non-standard)
  method. Integrative-calibration weights will change; totals are still met
  exactly and weights remain constant within household.

# weightflow 0.1.0

First release.

A dependency-free, pipeable API to compute survey weights from design base
weights through a chain of hierarchical adjustment stages. Build a recipe
lazily, estimate it with `prep()`, and extract the weights with
`collect_weights()`. Separating *define* from *apply* makes the whole process
reproducible and auditable, and lets the bootstrap re-run the entire cascade on
each replicate.

## Adjustment steps

* `step_unknown_eligibility()`: redistribute the weight of unknown-eligibility
  cases to the known ones (person- or household-level via `cluster`).
* `step_drop_ineligible()`: zero out out-of-scope units.
* `step_select_within()`: within-household selection (unequal `prob` or equal
  `n_eligible`).
* `step_nonresponse()`: weighting-class or propensity adjustment, at the person
  or household level (`cluster`).
* `step_calibrate()`: raking, post-stratification and linear/GREG calibration,
  with bounded (Deville-Särndal) and integrative (one weight per household)
  cluster options.
* `step_model_calibration()`: Wu-Sitter model calibration.
* `step_trim()`, `step_trim_weights()`, `step_round()`, `step_rescale()`:
  trimming, rounding and rescaling.
* `step_assert()`: quality checkpoint (deff, weight ratio, effective n).

## Inspection and reporting

* `summary()`, `plot()` and `weight_factors()` for per-stage diagnostics.
* `design_effect()` for the Kish design effect and effective sample size.
* `report_weighting()` builds a self-contained HTML report with a pipeline
  diagram, the variables used, per-stage summaries and per-step visuals.

## Variance estimation

* `bootstrap_weights()` resamples PSUs within strata (Rao-Wu rescaling) and
  re-applies the whole recipe on each replicate, so the replicate weights carry
  the variability of every adjustment.
* `boot_mean()` and `boot_total()` return the estimate, standard error and CI.
* `as_svydesign()`, `as_svrepdesign()` and `collect_replicate_weights()` bridge
  to the `survey` and `srvyr` packages for design-based inference.

## Data

* Bundled example datasets `population`, `sample_survey` (take-all roster) and
  `sample_one` (multistage select-one design), all with stratum, PSU and design
  weight.
