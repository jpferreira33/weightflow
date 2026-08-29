# Changelog

## weightflow 1.2.0

### New features

- **Two-phase (double) sampling.**
  **[`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md)**
  records a second phase of sampling – a subsample of the first-phase
  units drawn for a costlier follow-up – expanding the subsampled units
  by the inverse phase-2 probability and dropping the rest. When the
  recipe contains it,
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  switches to the two-phase variance `V = V1 + V2`: the phase-1 sampling
  variance plus the expected conditional variance of the phase-2
  subsample, which a single-phase bootstrap would miss. The per-unit
  resampling factor has variance `(1 - f1) * pi2 + (1 - pi2)`, the sum
  of the phase-1 component (seen through the subsample) and the phase-2
  conditional component (the additive coupling `lambda1 + lambda2 - 1`);
  a naive product `lambda1 * lambda2` over-counts the interaction term
  and is too wide. The factor is drawn from a strictly positive Gamma of
  that mean and variance, so every replicate weight stays positive and a
  downstream propensity/GLM step re-runs cleanly. The whole recipe (both
  cascades) is re-run per replicate, so nonresponse and calibration
  downstream of the subsample are captured automatically. This first
  version covers a Poisson (independent) second phase nested in the
  first (the household-subsampling case), with the phase-1 fraction `f1`
  taken from `fpc` (0 by default). Calibrating the subsample to the
  first-phase sample – the two-phase regression estimator (Fuller 1998),
  where the control totals are estimated by the larger first phase –
  needs no extra machinery: compose
  [`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md)
  with a
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
  built from the first-phase sample and its replicate weights, and the
  two variance components separate on their own (Opsomer and Erciulescu
  2021). Validated against Monte Carlo (ratio ~ 1.0) including
  calibration re-run per replicate, second-phase nonresponse,
  clustering, and calibration to first-phase estimates; see the
  two-phase methodology notes.
- **Non-probability samples.**
  `weighting_spec(base_weights = NULL, nonprob = TRUE)` starts an opt-in
  panel / volunteer / river sample with a base weight of 1 and records
  that it is non-probability (the report declares it and adds the
  methodological caveat).
  **[`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/reference/step_pseudoweight.md)**
  then estimates each unit’s participation propensity against a
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
  and assigns the inverse-propensity pseudo-weight (Elliott and Valliant
  2017), stacking the two samples internally (no manual pooling).
  Passing the reference’s replicate weights through
  `reference_sample(replicates = )` propagates its sampling variance
  through the recipe-aware bootstrap. A non-probability sample can also
  be adjusted by calibrating to a
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
  with
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  /
  [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
  (model-based), or by combining both (doubly robust).
- **[`step_nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/step_nr_sensitivity.md)**
  and
  **[`nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/nr_sensitivity.md)**
  add a sensitivity analysis for nonignorable nonresponse or selection,
  following the proxy pattern-mixture model of Andridge and Little
  (2011). The step changes no weights: it reduces the auxiliaries to a
  single proxy (the respondent regression prediction of the study
  variable) and, over a grid of a single sensitivity parameter phi in
  \[0, 1\] (from ignorable-given-the-proxy at 0 to depending only on the
  outcome at 1), reports the adjusted mean, producing an *ignorance
  interval* to read next to the sampling confidence interval. The report
  gains a matching block (one per study variable when several are
  analysed). An `eligible` argument (the mirror of the one in
  [`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md))
  keeps out-of-scope units out of the nonrespondent set, `phi = 0` (MAR)
  is always anchored in the grid, and the same machinery covers a
  non-probability sample (participants as respondents, reference units
  as nonrespondents). The estimator, mu(phi) = ybar_r + (1 -
  pi)(s_yr/s_xr) m(phi) (xbar_nr - xbar_r) with m(phi) = ((1 - phi)
  rho + phi)/((1 - phi) + phi rho), is validated by a Monte Carlo test
  that recovers the true mean at the generating phi.
- **[`data_defect()`](https://jpferreira33.github.io/weightflow/reference/data_defect.md)**
  and a prominent report block bring the data-defect view of Meng (2018)
  to non-probability samples: the effective sample size is governed by
  the correlation between the outcome and participation, not by the raw
  size, so a large opt-in sample can carry a small effective one.
  Because that correlation on the target variable is not observable from
  the sample, the report shows the effective size across a grid of
  plausible residual values (an ignorance range, not a single number),
  alongside the measurable selection strength on the covariates that
  pseudo-weighting corrects.
- **[`write_recipe()`](https://jpferreira33.github.io/weightflow/reference/write_recipe.md)
  /
  [`read_recipe()`](https://jpferreira33.github.io/weightflow/reference/read_recipe.md)**
  serialize the recipe (the weighting method, not the data) to a
  human-readable YAML file and read it back. The file is a versionable
  metadata artifact you can review in a pull request or archive next to
  the report;
  [`read_recipe()`](https://jpferreira33.github.io/weightflow/reference/read_recipe.md)
  returns an inspectable manifest, or, given `data`, rebuilds an
  executable `weighting_spec` ready for
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md).
  A
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
  is stored as a descriptor only (its microdata is not metadata) and is
  passed back in at read time; small control-totals tables (tidy
  `totals`) are serialized in full, while a data frame larger than
  10,000 rows is treated as microdata and rejected.
  `write_recipe(timestamp = FALSE)` gives byte-identical output for
  clean version-control diffs. Needs the `yaml` package.
- **`domain_summary(min_n_eff = )`** turns the implicit per-domain
  reliability read into an explicit publication gate: it adds a
  `publishable` column (whether the domain reaches the threshold at the
  final stage) and warns which domains fall below it, pointing to
  small-area estimation
  ([`as_sae_input()`](https://jpferreira33.github.io/weightflow/reference/as_sae_input.md))
  for those.
- **Confidentiality tools for public-use files.**
  `collect_replicate_weights(scramble = TRUE)` permutes the replicate
  columns (moving their scale factors in lockstep, so the variance is
  identical) and drops the design identifier columns, so the exported
  replicate weights do not reveal the sampling design.
  [`disclosure_risk()`](https://jpferreira33.github.io/weightflow/reference/disclosure_risk.md)
  flags units whose final weight is an outlier within a publication cell
  (a re-identification risk), reporting each unit’s share of the cell
  weight; trimming is the usual remedy.
- **[`as_sae_input()`](https://jpferreira33.github.io/weightflow/reference/as_sae_input.md)**
  exports, for each study domain, the direct estimate, its recipe-aware
  design-based standard error (from the replicate weights), the
  effective sample size and a CV-based publishability rating, in the
  shape a Fay-Herriot area-level model consumes. It bridges weightflow
  to the small-area-estimation packages (`emdi`, `sae`, `hbsae`) without
  fitting any SAE model itself.
- **[`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)**
  lets
  [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
  calibrate to a weighted reference survey instead of a full population
  frame: the model is fit on the sample, projected onto the reference
  survey, and the calibration targets are the design-weighted totals of
  the projection (an estimate of the population totals). A reference
  with all weights equal to 1 reproduces the plain-frame behaviour
  exactly. Passing the reference survey’s replicate weights through
  `replicates=` propagates its sampling variance through the
  recipe-aware bootstrap (each replicate re-estimates the totals from
  the paired reference replicate; Opsomer and Erciulescu 2021); without
  them the totals are treated as fixed.
- **[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  accepts a
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
  too** (all three methods: raking, poststratify, linear/GREG). Pass
  `population = reference_sample(...)` with a `formula` naming the
  calibration variables; the targets are the design-weighted sums over
  the reference, and their sampling variance propagates through the
  bootstrap when replicate weights are supplied.
- **The HTML report reflects estimated control totals.** When
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  or
  [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
  calibrate to a
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md),
  the step narrative states the totals are estimated (not census
  figures) and whether their sampling variance is propagated (replicate
  weights supplied; Opsomer and Erciulescu 2021) or treated as fixed;
  the replication card carries the matching note.
- **[`weighting_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md)
  and
  [`has_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md)**
  read the quality incidents recorded by
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md).
  Every incident now lands in `$alerts`, including warnings a step
  raises internally (such as a calibration that could not meet its
  constraints), so `$alerts` is the single reliable channel for
  programmatic quality control even when the surrounding warnings were
  suppressed.
- **[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  gains a finite-population correction (`fpc=`).** Give the first-stage
  sampling fraction as a column name, a single number, or a vector named
  by stratum; the `(1 - f_h)` factor is folded into the Rao-Wu rescaling
  (Rao, Wu and Yue 1992; Beaumont and Patak 2012). `fpc = 0` / `NULL`
  reproduces the with-replacement bootstrap exactly. Matters for the
  high sampling fractions common in LatAm household surveys.
- **`t` and percentile confidence intervals.**
  [`bootstrap_estimate()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  gains `ci_type = c("normal", "t", "percentile")` and
  [`jackknife_estimate()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)
  gains `ci_type = c("normal", "t")`; both carry the design degrees of
  freedom (`$df` = total PSUs minus strata) so the `t` interval is not
  anticonservative with few PSUs. Default stays `"normal"`.
- **Stable step ids.** Every `step_*()` gains an `id` argument and, by
  default, a unique derived id (`"<class>_<k>"`, e.g. `calibrate_1`).
  The id is shown in the recipe print-out and can be used to select a
  step in `collect_step_detail(step = "calibrate_1")`. Two steps of the
  same class are no longer indistinguishable, and a custom
  `id = "trim_final"` must be unique within the recipe.

### Bug fixes

- Two-phase variance now accepts a first-phase fraction `fpc` that
  varies across phase-2 units (the per-region `fpc` column the
  documentation advertises). The single-phase stratum-constancy check
  was running even in two-phase mode – where it is unused – and rejected
  a legitimately varying `fpc`; it is now skipped when a
  [`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md)
  is present (the per-PSU `f1` is validated inside the two-phase setup
  instead).
- Re-preparing or bootstrapping an already-prepped **non-probability**
  spec no longer collapses every weight to 0.
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
  drops the synthetic all-ones base column (`.wf_base1`) from its output
  so it does not leak; re-using the prepped spec then found the column
  gone and read `NULL` base weights. The column is now re-materialised
  wherever a prepped spec is re-run.
- The AAPOR response-rate card no longer counts out-of-scope cases with
  a missing (`NA`) disposition as nonrespondents. The disposition
  reconstruction now passes `active` when evaluating the disposition
  flags, so an `NA` on already-dropped units (ineligible / not contacted
  – the normal multistage case) no longer aborts the evaluation and
  falls back to all-`FALSE`; ineligible and unknown-eligibility cases
  are also excluded from the nonrespondent bucket. Previously such a
  recipe could report 0 respondents / RR = 0% / 100% nonresponse.
- The two-phase bootstrap degrees of freedom now count only phase-2
  sampling units that carry a positive final weight, so units dropped
  before the subsample step (ineligible, whole-household nonresponse) no
  longer inflate the df and the resulting t / percentile confidence
  intervals.
- Household-level nonresponse modelling now records its smallest
  responding-household propensity and its calibration slope, so the
  tiny-propensity alert and the propensity-calibration diagnostic fire
  for extreme household adjustments exactly as they already did for
  person-level ones (both were previously stored only on the
  person-level path).
- The bootstrap’s internal two-phase setup, the sample-level nonresponse
  calibration, and the two weight-trimming steps now pass `active` when
  they evaluate a selection/`by`/disposition expression, so an `NA` on
  units already dropped earlier in the cascade no longer aborts the run
  or raises a spurious `(missing)`-cell warning (the same `active=`
  family as the fixes above).
- Sample-level nonresponse calibration
  (`step_nonresponse(method = "calibration")`) now rejects a `totals`
  vector with duplicated names, matching
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md);
  previously `c(a = 120, a = 80)` silently calibrated to the first value
  and discarded the rest.
- A model-based step (propensity, model calibration) that receives
  negative case weights (from an earlier unbounded GREG calibration) now
  fails with a message naming the cause and the fix, instead of the bare
  [`glm()`](https://rdrr.io/r/stats/glm.html) error “negative weights
  not allowed”.
- The Spanish report now humanises the model engine in a step’s short
  description (e.g. “random forest”) instead of printing the raw engine
  id (“forest”), matching the English text.
- [`as_sae_input()`](https://jpferreira33.github.io/weightflow/reference/as_sae_input.md)
  now rates a domain with fewer than two active units as “not
  publishable” instead of deriving a “publishable” rating from an
  untrustworthy single-unit replicate CV.
- [`write_recipe()`](https://jpferreira33.github.io/weightflow/reference/write_recipe.md)
  /
  [`read_recipe()`](https://jpferreira33.github.io/weightflow/reference/read_recipe.md)
  now preserve an ordered factor – and `Date` / `POSIXct` columns – in a
  control-totals table through the YAML round-trip; they were being read
  back as plain character columns (the decoder had no case for those
  classes).
- Nonresponse and unknown-eligibility steps with a `by` grouping now
  warn about missing values in the cell variables only for the units the
  step actually adjusts (still active), not for units already dropped
  earlier in the cascade (ineligible, unknown-eligibility,
  whole-household nonresponse) that commonly lack later-collected
  variables like sex or age. This removes a spurious “grouped into a
  ‘(missing)’ cell” warning – repeated once per bootstrap replicate – on
  otherwise correct recipes.
- **Behaviour change:**
  [`boot_mean()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md),
  [`jack_mean()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)
  and
  [`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_replicate_weights.md)
  now keep active negative weights (a valid unbounded GREG output)
  rather than dropping them, matching the totals estimators and the
  [`as_svydesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
  /
  [`as_svrepdesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
  export. Estimates and standard errors may shift where a linear (GREG)
  calibration produced negative weights; the new results are the
  consistent ones.
- Constructor argument validation is stricter: several `step_*()`
  functions now reject out-of-range or non-numeric values (trimming
  ratios, bounds, tolerances and iteration caps, assertion thresholds)
  at build time instead of failing later or passing silently.
- Various robustness fixes for uncommon or malformed inputs, including
  missing values in calibration auxiliaries and post-stratification
  cells, negative calibration weights, empty or absent cells, degenerate
  bounds, integrative trimming with non-uniform incoming weights, and
  domain calibration with a scalar continuous total. Each fix is covered
  by a regression test.
- Further report honesty fixes: the status checklist no longer makes
  vacuous claims (a “no extreme weights” or “all calibration steps
  converged” line only when there are weights, or calibration steps, to
  speak of); a post-stratification-only recipe now gets the “constraints
  preserved” credit; and a step that does not track convergence reports
  its iteration count without claiming it converged.
- Report honesty fixes for domain calibration and estimated control
  totals: the calibration-drift table is now computed within each
  domain, and the reference-survey variance is only described as
  propagated for a bootstrap (the jackknife treats the totals as fixed).
- [`bootstrap_estimate()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md)
  and
  [`jackknife_estimate()`](https://jpferreira33.github.io/weightflow/reference/jackknife_estimate.md)
  no longer pass a failed (all-NA) replicate to a user statistic, and
  enforce a constant statistic length, so a non-NA-safe or vector-valued
  statistic no longer aborts the whole estimate.
- [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
  records the resolved design (`$design`: the per-stratum sampling
  fraction, PSU count, effective resample size, and whether lonely
  strata were collapsed), so the effective design is auditable from the
  object rather than only from the arguments passed.
- Broader, more consistent argument validation across the step
  constructors (flags given as strings, non-integer or infinite counts,
  non-numeric trimming bounds, malformed
  [`y_model()`](https://jpferreira33.github.io/weightflow/reference/y_model.md)
  and `id` values, and `penalty` with a non-Euclidean distance) now
  fails at build time with a clear message instead of a later cryptic
  error. Blank primary sampling unit or stratum ids are also rejected
  before resampling.
- The HTML report and its CSV export received accuracy and formatting
  fixes, and the report no longer errors on legal edge cases such as an
  open trimming bound.
- Documentation updates, including a correspondence table for arguments
  that name the same concept across functions (`?weightflow-concepts`),
  a new `?weightflow-alerts` catalogue of the quality alerts
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
  can raise, and `@family` cross-links across the step, variance and
  cascade-audit functions for easier navigation.
- [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  now warns when both `margins` and `totals` are supplied (`totals` wins
  and `margins` was being dropped silently).
- [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
  also guards missing values in the `y_model` predictor variables on the
  population frame (not only the `x_formula` variables), so an `NA`
  there no longer reaches the model engine.
- [`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/reference/step_pseudoweight.md)
  hardening: participation propensities are clamped away from both 0 and
  1 (a propensity of exactly 1, which a pure tree or forest leaf can
  return, no longer sends the pseudo-weight to 0 and silently drops the
  unit), and a near-1 propensity is now flagged. The step also exposes
  its pooled propensity so the report renders the common-support,
  calibration, Brier and AUC diagnostics and a methodological paragraph;
  warns when the factor levels of a covariate differ between the sample
  and the reference, and when `num_classes` collapses under
  near-constant propensities; drops the internal all-ones base column
  from
  [`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md);
  and `bootstrap_weights(fpc = )` is ignored (with a warning) for a
  non-probability sample.

## weightflow 1.1.0

CRAN release: 2026-08-19

### New features

- **Diagnostics report suite.**
  [`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
  gains a per-step card reading the bias-variance trade-off of each
  adjustment, with quality alerts for trimming, calibration,
  machine-learning propensity models and nonresponse-by-calibration.
- **Honest variance for machine-learning adjustments.** A flexible
  learner (tree / forest / boost) run without `crossfit` now raises an
  alert, since same-sample predictions can understate the variance even
  under recipe-aware replication; the `ranger` seed is fixed so the
  forest’s noise no longer enters the replicates.
- **[`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_replicate_weights.md)
  also exports delete-a-PSU jackknife objects**, with the `type` /
  `scale` / `rscales` needed by `survey` / `srvyr` (first argument
  renamed `boot` -\> `object`).
- **Iterative recipe refinement.** Adding a step to a prepped recipe
  clears the results with a message and re-runs the cascade on the next
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md),
  so stale weights cannot be read by accident.
- **Per-subgroup trimming.**
  [`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md)
  gains a `by` argument and per-group `lower` / `upper` bounds
  (requested by ECLAC).
- **[`collect_propensities()`](https://jpferreira33.github.io/weightflow/reference/collect_propensities.md)**
  recovers the per-unit response propensities fitted by a
  `step_nonresponse(method = "propensity")` step from a prepped recipe,
  so their distribution can be inspected before the adjusted weights are
  trusted; it returns the same information whether the adjustment was
  made at the unit level or, through `cluster`, at the household level
  (the household propensity is broadcast to its members). It also
  returns `.factor` (the multiplier actually applied to each unit) and,
  with propensity classes, `.class`; note that `1/.propensity`
  reconstructs the applied factor only when `num_classes = NULL`.
  Requested by ECLAC.
- **[`collect_step_detail()`](https://jpferreira33.github.io/weightflow/reference/collect_step_detail.md)**
  is a generic companion to
  [`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md):
  for any step it returns the weight each unit received (`.weight_in`)
  and the multiplier the step applied (`.factor`, read from the stored
  stage weights so `.weight_in * .factor` equals the outgoing weight by
  construction), plus that step’s native per-unit quantities when it
  exposes them (for a propensity step, `.propensity` and `.class`).
- **[`domain_summary()`](https://jpferreira33.github.io/weightflow/reference/domain_summary.md)**
  reports, for a study domain (e.g. a department / DAM), how the weights
  move within each domain at every stage of the cascade – active units,
  sum of weights, mean weight and Kish design effect – so weight
  movement can be reviewed step by step per domain for quality control
  (requested by ECLAC). Domains follow their factor / numeric order, a
  missing domain value is shown as an explicit `(missing)` domain, and
  `by` accepts several columns (crossed).

### Bug fixes and documentation

- Robustness and correctness fixes for uncommon edge cases – malformed
  or degenerate inputs, replicate-variance accounting, and the HTML
  report – each covered by a regression test.
- Documentation overhaul: help pages reviewed and rewritten, estimator
  formulas added to the details, and a new `?weightflow-concepts` page.

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
