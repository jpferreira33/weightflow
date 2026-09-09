# weightflow 1.3.0

## New features

* **`step_filter()` restricts a coordinated estimation to a subpopulation.** Add it
  to a `step_domain()` / `step_estimate()` pipeline to estimate a change or level over
  a domain -- e.g. `step_filter(edad >= 25 & edad <= 54)`. The condition is evaluated
  per wave and the rows are **masked, not dropped**, so the PSU-coordinated replicate
  alignment between waves (and hence the overlap covariance of a change) is preserved.
  Filters stack (their conditions are ANDed) and compose with `step_domain()`.

* **`wave_bootstrap()` now resamples PSUs with an exact multinomial by default
  (`resample = "multinom"`).** The previous independent-binomial Rao-Wu draw
  (`resample = "binom"`, still available) does not force the per-stratum resample
  counts to sum to `m_h`; that extra between-PSU variance is amplified by the
  composite-regression block (`step_cre()`) and inflated its replicate SE by
  ~8-10% in simulation against a known truth. The exact multinomial removes the
  inflation (bias of the composite change SE drops from ~+10% to ~+2%) while
  preserving the overlap covariance. Coordination across rotating waves is exact
  when the PSU sets match and approximate otherwise.

* **Panel / longitudinal support (in progress): `panel_design()` and
  `panel_merge()`.** `panel_design()` tags stacked per-wave data with its
  rotating-panel structure the way `reference_sample()` tags a reference survey:
  it derives the observed wave-to-wave overlap matrix, the panel-selection
  probability `Pr(panel selection)` from rotation-group cohort continuity (the
  reciprocal of the CEPAL panel base-weight factor), and the linkage quality,
  raising alerts (`PN-01` overlap vs. pattern, `PN-02` uneven rotation groups,
  `PN-06` no unit links across waves) *before* any weighting. `panel_merge()`
  reshapes a named list of per-wave surveys into the wide, one-row-per-unit
  longitudinal file with `.wf_in_<wave>` / `.wf_resp_<wave>` indicators. Neither
  changes `weighting_spec()`; the descriptor travels in `attr(data, "wf_panel")`.
  This is the structure/linkage layer of the panel roadmap (CEPAL ch. XVI-XVII);
  the longitudinal-weight steps and the coordinated-replicate variance follow.
* **`step_panel_overlap()` and `panel_pr()`** add the CEPAL panel base-weight
  adjustment: `step_panel_overlap(prob = ...)` divides the incoming weight by the
  panel-selection probability (`d_base = d1 / Pr`), the first step of the
  Verma-Betti-Ghellini longitudinal-weight sequence. `prob` is a per-unit column
  or a constant; `panel_pr(pd, waves)` derives that constant from a `panel_design()`
  with a rotation group (the fraction of rotation-group cohorts present in all the
  combined waves). Surveys with no public rotation group pass a probability derived
  otherwise. Validated on real ECH (Uruguay) and ENE (Chile) microdata.
* **Coordinated bootstrap for panel change: `wave_bootstrap()` + `change_estimate()`
  (`change_mean()` / `change_total()`).** Builds recipe-aware bootstrap replicate weights
  for several waves that are **coordinated by PSU** -- a PSU present in more than one wave
  gets the same resampling in all of them -- so the sampling covariance the overlap of a
  rotating panel induces is captured, and the honest variance of a net change follows:
  `V = V1 + V2 - 2*Cov`, with `rho` and `deff_change` reported. It is fully **self-contained**
  in `R/variance-panel.R` and does **not** touch the CRAN bootstrap in `R/variance.R`
  (frozen and guarded by a firewall snapshot test), at the cost of a small copy of the
  Rao-Wu draw. The method was validated by Monte Carlo before implementation (the naive
  independent bootstrap over-estimates the change variance up to ~11x under high overlap
  and correlation, which this fixes).
* **`wave_jackknife()`: coordinated delete-one jackknife.** A deterministic counterpart to
  `wave_bootstrap()` that removes the same PSU from every wave at once, so the change
  covariance is captured with no randomness. It feeds the same `change_estimate()` /
  `change_mean()` / `change_total()` and reports the same `V = V1 + V2 - 2*Cov`. It serves
  as the cheap exact oracle for the coordinated bootstrap -- in the full-overlap regime it
  reproduces the textbook stratified delete-one jackknife of the per-PSU difference, and it
  is exact in the disjoint limit (`Cov = 0`) -- and is a valid variance estimator on its own.
  Also self-contained in `R/variance-panel.R`; `R/variance.R` untouched.
* **Panel HTML report: `report_panel()`.** Assembles a standalone HTML page from whichever panel
  objects it is given -- the rotation structure ([panel_design()]: overlap heat-map, Pr(panel
  selection), linkage, PN alerts), the coordinated net-change variance ([change_estimate()]:
  V1/V2/Cov/rho/deff and the explicit contrast against the independent bootstrap), the
  longitudinal attrition/retention (a prepped longitudinal recipe), and the gross flows
  ([transition_matrix()] / [boot_transition()]: a **Sankey** of the flows plus a heat-mapped matrix
  with per-cell SE). The cards carry hand-built inline-SVG visualisations (no dependency): a flow
  Sankey, a retention bar, an overlap heat-map, and a coordinated-vs-independent SE bar. Any
  argument may be `NULL`; its card is skipped. Reuses the existing report CSS/i18n (English/Spanish).
* **Gross flows: `transition_matrix()` and `boot_transition()`.** The weighted flow between a
  categorical state at an earlier wave and a later one (CEPAL ch. XVII) -- who moved between which
  states -- on the **longitudinal** weight of the wide file. `transition_matrix()` is the point
  estimate (`"row"` = P(to|from), `"col"`, `"joint"`, `"counts"`); `boot_transition()` adds a
  per-cell standard error from the ordinary bootstrap replicate weights (re-running the recipe per
  replicate). Self-contained base R, no new dependency; the per-cell SE reuses
  `bootstrap_estimate()`'s vector-valued-statistic path.
* **`boot_flows()`: gross-flow TOTALS with standard errors.** The gross change is about the *number
  of people* who move between states, so this returns the from x to count matrix (population
  totals), the **net** flow matrix (`i->j` minus `j->i`), and the margins -- origin totals (started
  in each state), destination totals (ended in each), stayers (diagonal) and movers (off-diagonal)
  -- **each with a bootstrap SE** computed within each replicate, in one pass. The totals
  counterpart of the mean/proportion estimands.
* **`step_attrition()`: the panel-facing attrition adjustment.** A thin wrapper over
  [step_nonresponse()] that reads correctly in a longitudinal cascade and carries the panel
  conventions (covariates from an observed wave; it does not absorb eligibility). The estimator
  ECLAC's manual (ch. XVI) and Statistics Canada's SLID (Naud 2002; LaRoche 2003) prescribe is
  **response-propensity weighting** -- individual `1/phi` (Little 1986; Rosenbaum 1987), i.e.
  `method = "propensity"`, not an ECLAC invention; `method = "rhg"` is the response-homogeneity-
  group variant (propensity stratified into `num_classes` classes). `"weighting_class"` and
  `"calibration"` also available. The **discrete-time attrition hazard** (the retention product
  `1/prod(phi_t)` used by PSID/EU-SILC/SOEP) needs no special method: because a nonresponse step
  fits only on the units still alive (`.wf_active`), **chaining `step_attrition()` per wave
  reproduces the multiplicative hazard**, monotone (no resurrection), with the theory visible in
  the recipe. (The SLID/ECLAC fallback imputations and a doubly-robust `model_calibration` method
  follow.)
* **Longitudinal panel weights (case c), built by reusing the cascade.** The longitudinal
  weight -- for the population followed across waves -- is assembled on the wide file
  (`panel_merge(..., require = "all")`, which keeps only the units in sample in every wave, i.e.
  the overlapping rotation groups) with the ordinary cascade on top of `step_panel_overlap()`:
  `step_unknown_eligibility()` (UNK), `step_drop_ineligible()` (OS, out of scope -> weight 0, no
  reweight), `step_nonresponse()` (NR attrition). The same recipe serves a pure panel (Pr = 1)
  and a rotating one (Pr < 1). Its variance is the existing ordinary `bootstrap_weights()` --
  no new engine; `R/variance.R` untouched. `step_drop_ineligible()` gains a `reason=` argument
  that records why units are out of scope (e.g. "left the target population between waves"), so
  the report narrative distinguishes a between-wave universe exit from ordinary ineligibility.
* **Declarative estimation grammar: `step_domain()`, `step_estimate()`, `collect_estimates()`.**
  A sibling of the weighting recipe that runs over a saved [wave_bootstrap()] /
  [wave_jackknife()] object and emits estimates, not weights. `wb |> step_domain(region, sexo)
  |> step_estimate(mean(desocupado), over = "change", type = "relative")` disaggregates and
  estimates with the honest overlap covariance. Needed because survey/srvyr cannot express the
  change covariance of overlapping waves (they would treat them as independent). It is a thin
  front end over the engine (`change_estimate` / `panel_estimate` / `level_estimate`), typed as
  `weightflow_estimation` so it never collides with the weighting steps; heavy replicate build
  once, cheap estimation many times. A `statistic` DSL covers `mean/total/prop/ratio/quantile`
  or a raw function. (`step_transition()` for gross flows is stubbed pending the longitudinal
  bootstrap object.)
* **`change_estimate()` rounded out: relative change, by-domain, and `level_estimate()`.**
  `type = "relative"` gives `theta2/theta1 - 1` (e.g. the percent change of a rate) with the
  overlap covariance from the coordinated replicates (exact for the bootstrap, delta method for
  the jackknife). `by =` returns one change per domain. `level_estimate()` /`level_mean()` /
  `level_total()` estimate a single wave's level with its replicate variance, so a level and a
  change come from the same object. `change_mean()` / `change_total()` gain `type=` / `by=`.
* **`refit_steps` in `wave_bootstrap()` / `wave_jackknife()`: choose which recipe steps are
  re-run per replicate.** `"all"` (default) is the honest recipe-aware bootstrap that re-preps
  the whole cascade, propagating every step's variance -- the choice the coordinated-bootstrap
  literature endorses (Roberts, Kovacevic, Mantel & Phillips 2001). `"calibration"` freezes the
  subweights and re-runs only calibration per replicate, reproducing the **Statistics Canada
  LFS** convention (the Rao-Wu factor enters at the frozen pre-calibration weight). A character
  vector of step classes splits the recipe at the first match: prefix frozen, suffix re-prepped.
  This is the "what is refit" axis that lets one engine both replicate other NSOs and offer the
  more honest full-recipe variance; it uses only the public `prep()` and leaves `R/variance.R`
  untouched. The point estimate never depends on `refit_steps`; only the replicate variance does.
* **`panel_estimate(contrast = )` (with `panel_mean()` / `panel_total()`): any linear
  combination of waves.** Generalises `change_estimate()` to an arbitrary contrast
  `psi = sum(contrast * theta_wave)` -- an annual average (`rep(1/W, W)`, the default), a
  net change (`c(-1, 1)`), a semester-vs-semester contrast, etc. -- with the honest
  variance `a' Sigma a`, where `Sigma` is the between-wave covariance matrix taken directly
  from the coordinated replicates (works with either `wave_bootstrap()` or
  `wave_jackknife()`). Reports the covariance matrix and `deff = V / V(independent)`, making
  explicit that ignoring the overlap covariance **understates** the variance of an average
  and **overstates** that of a change. `contrast = c(-1, 1)` reproduces `change_estimate()`
  exactly.
* **`step_longitudinal()` and `step_cross_sectional()`** declare, without arguments,
  whether a recipe builds the panel (longitudinal) weight or the ordinary
  cross-sectional weight -- the panel detail (waves, rotation group, reference
  wave) already lives in `panel_design()`. They leave the weights unchanged (like
  `step_assert()`); the declaration governs how the rest of the recipe and the
  report behave, and flags a wrong-purpose set-up (`step_panel_overlap()` warns
  on panel data when `step_longitudinal()` was not declared). `panel_design()`
  gains `reference_wave` (defaults to the first wave), the population the
  longitudinal weight represents.

* **`step_model_calibration()` gains `bounds`** (and `calfun`), matching
  `step_calibrate(method = "linear")`: an optional `c(L, U)` with `L < 1 < U`
  bounds the calibration g-factor so the final weights stay in `[L, U]` times the
  incoming weight, found by the bounded Deville-Sarndal iteration. This keeps
  model-calibration weights from turning negative or exploding when the projected
  totals pull hard; the default (no bounds) is unchanged.
* **`step_trim_calibrated()` now supports a preceding `step_model_calibration()`.**
  The model-calibration step saves its prediction columns, which the trim step
  appends to `formula`'s design, so range-restricted trimming preserves the
  model-prediction totals as well as the known margins (previously it kept only the
  `X` margins). Pass the same `x_formula` as `formula`.

## Bug fixes

* **Robustness of `step_cre()`, the panel jackknife, `wave_bootstrap()` and labelled base
  weights.** `step_cre()` now captures the calling environment, so a `birth =` expression can
  reference a variable from the caller instead of failing with "object not found" (CRE-03),
  and composite cells are joined with `|` rather than `.`, so two distinct cells of a
  multi-column crossing can no longer collide on the same column name and overwrite each
  other's constraint (CRE-04). The coordinated jackknife drops a failed (non-finite)
  delete-one replicate from its stratum and warns, instead of turning the whole variance into
  `NA` or aborting (VAR-08). `wave_bootstrap()` restores the caller's RNG state on exit, so
  its internal `set.seed()` no longer advances the global stream (VAR-10). And a
  `haven_labelled` base-weight column is coerced to a plain numeric, so the final weight is
  not tagged with the base weight's value labels when exported with `haven::write_sav()`
  (SPEC-01).

* **Panel variance: PSU ids are nested within strata, `step_domain()` requires the column in
  every wave, and the panel intervals offer a t option.** `wave_bootstrap()` /
  `wave_jackknife()` collapsed PSUs that share an id across strata (published microdata often
  restart PSU ids at 1 per stratum), understating the variance; the PSU identity is now
  `(stratum, id)`, a no-op when ids are already unique (VAR-09). `step_domain()` validated the
  grouping column against the union of the waves, so a column present in only some waves
  silently produced NA cells; it now requires the column in every wave (EST-03). And the
  panel estimators (`change_estimate()`, `level_estimate()`, `panel_estimate()`) gain
  `ci_type = "t"` with a design `df` (total PSUs minus strata) for a wider, safer interval
  when the number of PSUs is small; the default `"normal"` is unchanged (VAR-14).

* **The `"boost"` (xgboost) learner now encodes factors with the training levels.**
  `model.matrix()` chooses a factor's reference level from the levels present in each data
  frame, so under cross-fitting (or when predicting on the population) a fold missing a level
  got a different reference and silently encoded that category as the training reference.
  Categorical predictors are now coerced to the training levels before the design matrix is
  built, so the encoding is identical everywhere (ML-01).

* **The report no longer certifies "calibration constraints preserved" without checking,
  and the trim narrative respects the sign of the change.** The checklist only measures the
  post-calibration drift for post-stratification/raking; for linear/GREG, model calibration
  and trimmed calibration it could not, yet it printed "constraints preserved"
  unconditionally -- even when a later `step_round()` broke the totals. It now says the
  totals were "not re-checked for this method" in that case (REP-01). The trim card said the
  weight total "fell" even when a floor raised it (printing a negative "fell by -X%"); it now
  says "rose" or "fell" by the sign (REP-02). And the AAPOR disposition table adds a note when
  its rows do not sum to the issued sample because units left through another step (a cluster
  drop, `step_select_within()` or `step_assert()`), instead of silently failing to close
  (REP-03).

* **More symmetric validation and honest diagnostics across the cascade.** `step_trim()`
  now records the mass it could not redistribute (previously `NA`, so the report could never
  flag it), reports `sum_before` / `sum_after` like the other trim steps, and warns when the
  weighted total changed (TRIM-02); its constructor rejects `min_ratio >= 1` for a relative
  reference, mirroring the `max_ratio > 1` rule, instead of silently inflating the total
  (TRIM-03). `prep()` now validates the base-weight column is numeric -- a character column
  from a recipe rebuilt outside `weighting_spec()` (e.g. `read_recipe()`) used to flow
  through and yield an empty `collect_weights()` (PREP-02) -- and raises an alert naming the
  step that leaves 0 active units, rather than running the rest of the recipe silently on an
  empty sample (PREP-01). `step_cre()`'s `status_ref` documentation now matches the code
  (`NULL` drops the last level; one level is always dropped for identifiability) (CRE-01).

* **`write_recipe()` no longer serializes the previous wave's microdata for a
  `step_cre()` recipe.** A composite step holds the entire prepped previous wave (its data,
  weights and history) in `previous`; the serializer used to write that whole object into the
  YAML -- leaking the previous wave's microdata for a small wave, and aborting outright for a
  realistic one. It is now replaced with a `previous_wave` marker, and the executable
  `read_recipe(file, data =)` raises a clear error that a CRE recipe cannot be rebuilt from
  YAML alone (the previous wave is a fitted object, not metadata) instead of silently
  degrading to a seed calibration (IO-02).

* **`read_recipe()` no longer executes code from the recipe file by default.** A step
  that stored an R function was serialized as its source and evaluated on read, so
  opening an untrusted recipe ran arbitrary code. `read_recipe()` gains
  `allow_code = FALSE` (default): a function node now raises an error instead of being
  evaluated; pass `allow_code = TRUE` only for a file you trust, as you would `source()`.

* **`step_trim_weights()` with the automatic Tukey fence no longer loses weight mass
  when the IQR is 0.** With a dominant modal weight (or a near self-weighting design) the
  far-out fence degenerated to the third quartile, capping every unit above the mode and
  leaving no units to receive the trimmed mass, so the weighted total silently dropped.
  The fence now falls back to a high quantile in that case, and the step emits a
  `warning()` whenever any mass cannot be redistributed (previously only a deferred alert
  that `prep(warn = FALSE)` hid).

* **The composite-regression card now renders in reports.** The report guards keyed on a
  `step$cre` field that never existed, so the `step_cre()` card (alpha, composite
  constraints, block/cell/status table) never appeared and, under `lang = "es"`, the step
  showed in English in the diagram and per-stage table. The guards now test the step class.

* **Calibration no longer deadlocks on an empty factor level, and post-stratification
  reports non-convergence when a cell cannot be adjusted.** A factor level that is defined
  but has no active unit (imported with extra levels, or a cell emptied upstream) added a
  zero column to the linear/GREG design whose target could neither be supplied nor omitted
  without an error; the empty levels are now dropped before building the model matrix
  (CAL-4). And a post-stratification cell whose weights sum to a non-positive value (after
  negative weights from an earlier step) cannot be scaled to its target: the step now
  warns and reports `converged = FALSE` instead of silently leaving the cell off-target
  with a success flag (CAL-5).

* **`step_calibrate(method = "linear")` now requires the tidy `totals` to cover every
  sample level of a factor.** A level present in the sample but missing from `totals` --
  in particular the factor's reference level, which has no model-matrix column and so was
  never checked -- built the intercept N from only the supplied counts and calibrated the
  missing level to an implicit population of 0, reporting `converged = TRUE`. The linear
  path now errors on incomplete coverage, matching raking's margin-level check.

* **`step_calibrate(method = "linear")` now rejects a non-numeric counts column
  in tidy `totals`.** A factor or character counts column (e.g. from
  `read.csv(stringsAsFactors = TRUE)` or a thousands-separated value) previously
  passed through `as.numeric()` as its integer level codes, so the calibration
  targeted an absurd population size (the sum of the codes) yet reported
  `converged = TRUE` with `target == achieved` on the wrong scale -- weights could
  come out hundreds of times too small with no error. The linear/GREG path now
  validates the counts column up front, matching the post-stratification and
  raking paths.

* **`boot_total()` and `two_phase_variance(estimator = "total")` now warn that the
  two-phase total variance is conservative.** The two-phase replicate factor is a
  Hansen-Hurwitz (uncentred) per-PSU multiplier: it self-centres for a mean/ratio but not
  for a total, where it can overestimate the variance substantially. The total estimators
  warn (read the SE as an upper bound) and the two-phase vignette documents the caveat
  (VAR-05). `boot_mean()` / ratio estimates are unaffected.

* **`bootstrap_weights()` / `jackknife_weights()` now warn on a `step_cre()` recipe.** The
  single-sample engines re-estimate the composite control totals `Zhat` from the previous
  wave's frozen point weights, holding them fixed and understating the change variance; they
  now warn and point to `wave_bootstrap()` / `wave_jackknife()`, which coordinate `Zhat` per
  replicate (VAR-04).

* **`wave_bootstrap(resample = "binom")` documentation corrected.** The legacy binomial
  draw loses the multinomial's negative between-PSU covariance and estimates an uncentred
  variance: only mildly high for a ratio or mean (~+8-10%) but a large overestimate for a
  total. The help now says so and recommends the default `"multinom"` for totals (VAR-02).

* **Replicate variance now propagates the reference-sample replicates and disables
  `step_assert()` in the jackknife and both panel engines.** `jackknife_weights()` set
  `wf_replicate` but not `wf_replicate_idx`, and `wave_bootstrap()` / `wave_jackknife()`
  set neither, so a recipe calibrating against a `reference_sample()` with replicates fell
  back to the frozen point totals (understating the variance), and a `step_assert()`
  evaluated against the Rao-Wu-perturbed replicate weights failed every replicate. Both
  attributes are now set in all four engines: the reference replicate is paired per
  replicate, and `step_assert()` is a no-op inside replicates as it already is in the
  single-sample bootstrap.

* **The coordinated panel variance now fails loudly instead of silently
  under-reporting.** Four silent failure modes flagged by an external audit of the
  panel module were closed, all in the coordinated engines and none touching
  `variance.R`: (1) when a `step_cre()`'s `previous` wave does not align with the
  preceding wave in `specs` (row-count mismatch), the coordinated `Zhat*` is held
  fixed and the change variance is anticonservative -- `wave_bootstrap()` /
  `wave_jackknife()` now emit a `warning()` and expose `$n_cre_injected` /
  `$n_cre_skipped` counts (shown by `print()`); (2) `change_estimate()` warns when
  more than 5% of coordinated replicates were non-finite and dropped (the dropped
  replicates are not missing at random, so a high drop rate biases the SE down) and
  reports the effective replicate count in `$R`; (3) the coordinated jackknife warns
  when `V = V1 + V2 - 2*cov` goes negative and is truncated to a zero SE (high
  overlap, few PSUs), instead of silently reporting perfect precision; (4)
  `wave_bootstrap()` / `wave_jackknife()` warn that `psu = NULL` coordinates the
  waves **by row position**, which is only valid for row-aligned samples.

* **`report_panel()` now validates the class of every argument instead of writing
  an empty report.** Passing an object of the wrong class (e.g. a fitted
  `prepped_weighting_spec` as `design`) previously passed the "at least one
  argument" guard, rendered as an empty card, and produced a valid-but-empty HTML
  file that read as success. Each of `design`, `change`, `longitudinal`,
  `transition`, `coordinated` and `variance` is now checked up front and a
  wrong-class object raises an informative error.

* **The estimation grammar no longer hides mistakes.** `step_domain()` now errors on
  a column absent from every wave (it previously warned and silently fell back to the
  national total under the requested breakdown); `collect_estimates()` accumulates
  per-cell estimation failures and reports them in a single `warning()` (rather than
  dropping failed domain cells without a trace), erroring only if every estimate
  failed; and `print()` of an estimation pipeline lists the declared estimands
  instead of silently running the full (possibly minutes-long) coordinated estimation.

* **`.wf_pattern_overlap()` now parses the CPS "in-out-in" rotation form.** A pattern
  like `"4-8-4"` is read as 4 months in, 8 out, 4 in -- `n_groups = 8`, adjacent
  overlap 0.75 -- instead of taking only the first integer (`n_groups = 4`). CEPAL
  `"4(0)1"` and plain-integer `"6"` forms are unchanged.

* **`report_weighting(lang = "es")` now renders the quality alerts and the
  calibration/trim notes in Spanish.** The "Quality alerts" box header, the
  `target`/`achieved` diagnostic-table headers, and every compute-time quality
  alert (propensity miscalibration and g-factor bounds, but also very small /
  near-certain propensities, collapsed propensity classes, non-positive or
  negative calibration weights, an ill-conditioned system, weights below 1,
  large or empty adjustment cells, cells with too few cases, the two-phase
  phase-2 alerts, partial-household nonresponse, and the flexible-learner /
  cross-fitting notes) were left in English under `lang = "es"`, because they are
  generated without a language at compute time (English stays canonical for the
  R warnings). The report now translates all of them at render time; English
  output is unchanged.

# weightflow 1.2.0

## New features

* **Two-phase (double) sampling.** `step_subsample()` records a second phase of sampling (a subsample drawn for a costlier follow-up), and `bootstrap_weights()` then returns the two-phase variance `V = V1 + V2` -- the phase-1 sampling variance plus the phase-2 conditional variance a single-phase bootstrap would miss. Covers a Poisson second phase nested in the first; calibrating the subsample to first-phase totals (the two-phase regression estimator, Fuller 1998) is done by composing with a `reference_sample()`. **`two_phase_variance()`** splits the estimate's variance into its phase-1 and phase-2 components (`V1`, `V2`, and the share `V2/V`), turning the coupling into an operational read of whether a denser subsample would pay off. The HTML report now explains the subsample step (in English and Spanish) and its `V = V1 + V2` logic. Validated against Monte Carlo; see `vignette("two-phase-sampling")`.
* **Non-probability samples.** `weighting_spec(base_weights = NULL, nonprob = TRUE)` starts an opt-in / volunteer / river sample, and `step_pseudoweight()` estimates each unit's participation propensity against a `reference_sample()` and assigns the inverse-propensity pseudo-weight (Elliott and Valliant 2017). Can be combined with calibration to the reference for a doubly robust estimate.
* **`step_nr_sensitivity()` / `nr_sensitivity()`** add a sensitivity analysis for nonignorable nonresponse or selection (proxy pattern-mixture model, Andridge and Little 2011), reporting an *ignorance interval* over a single sensitivity parameter; the report gains a matching block.
* **`data_defect()`** brings the data-defect view of Meng (2018) to non-probability samples: the effective sample size across a grid of plausible outcome-participation correlations (an ignorance range, not a single number).
* **`write_recipe()` / `read_recipe()`** serialize the recipe (the method, not the data) to a human-readable, versionable YAML file and read it back into an inspectable manifest or an executable `weighting_spec`. Needs the `yaml` package.
* **`domain_summary(min_n_eff = )`** turns the per-domain reliability read into an explicit publication gate (a `publishable` column and a warning for domains below the threshold, pointing to `as_sae_input()`).
* **Confidentiality tools for public-use files.** `collect_replicate_weights(scramble = TRUE)` hides the sampling design behind the exported replicate weights (variance unchanged), and `disclosure_risk()` flags weight outliers within a publication cell.
* **`as_sae_input()`** exports, per domain, the direct estimate, its recipe-aware design SE, the effective sample size and a CV rating, in the shape a Fay-Herriot model consumes -- a bridge to the SAE packages (`emdi`, `sae`, `hbsae`) without fitting any model.
* **Calibrate to a reference survey.** `reference_sample()` lets `step_calibrate()` and `step_model_calibration()` calibrate to a weighted reference survey instead of a full population frame; passing its replicate weights propagates the reference's sampling variance through the bootstrap (Opsomer and Erciulescu 2021), and the report states when control totals are estimated rather than census figures.
* **`weighting_alerts()` / `has_alerts()`** read the quality incidents recorded by `prep()`; every incident now lands in `$alerts`, a single reliable channel for programmatic quality control even under suppressed warnings.
* **`bootstrap_weights(fpc = )`** adds a finite-population correction (column, scalar, or per-stratum vector) folded into the Rao-Wu rescaling (Rao, Wu and Yue 1992; Beaumont and Patak 2012); matters for the high sampling fractions common in LatAm household surveys. `fpc = 0` / `NULL` is the with-replacement bootstrap.
* **`t` and percentile confidence intervals** for `bootstrap_estimate()` (and `t` for `jackknife_estimate()`), carrying the design degrees of freedom so the interval is not anticonservative with few PSUs. Default stays `"normal"`.
* **Stable step ids.** Every `step_*()` gains an `id` (with a unique derived default), shown in the recipe print-out and usable to select a step in `collect_step_detail()`.

## Bug fixes

* Nonresponse, eligibility and weight-trimming steps now build their `by`-cells over the units still active, so cases dropped earlier in the cascade no longer raise spurious `(missing)`-cell warnings; the response-rate card likewise ignores out-of-scope cases with a missing disposition rather than counting them as nonresponse.
* Household-level nonresponse modelling now reports the same tiny-propensity and calibration diagnostics as the person-level path.
* **Behaviour change:** the mean estimators and replicate-weight exports keep active negative weights (a valid GREG output) rather than dropping them, matching the totals estimators and the survey exports; estimates and standard errors may shift accordingly.
* Stricter, earlier argument validation across the step constructors and estimators, with clearer messages (out-of-range or non-numeric arguments, duplicated calibration-total names, negative model weights, blank stratum/PSU ids) instead of later cryptic errors.
* Assorted robustness fixes for malformed or edge-case inputs (missing calibration auxiliaries, empty or degenerate cells, open trimming bounds), each covered by a regression test.
* Report accuracy and honesty fixes: no vacuous checklist claims, clearer per-step descriptions, and formatting/translation fixes.
* Documentation: an argument-correspondence table (`?weightflow-concepts`), a quality-alerts catalogue (`?weightflow-alerts`), and `@family` cross-links.

# weightflow 1.1.0

## New features

* **Diagnostics report suite.** `report_weighting()` gains a per-step card reading the bias-variance trade-off of each adjustment, with quality alerts for trimming, calibration, machine-learning propensity models and nonresponse-by-calibration.
* **Honest variance for machine-learning adjustments.** A flexible learner (tree / forest / boost) run without `crossfit` now raises an alert, since same-sample predictions can understate the variance even under recipe-aware replication; the `ranger` seed is fixed so the forest's noise no longer enters the replicates.
* **`collect_replicate_weights()` also exports delete-a-PSU jackknife objects**, with the `type` / `scale` / `rscales` needed by `survey` / `srvyr` (first argument renamed `boot` -> `object`).
* **Iterative recipe refinement.** Adding a step to a prepped recipe clears the results with a message and re-runs the cascade on the next `prep()`, so stale weights cannot be read by accident.
* **Per-subgroup trimming.** `step_trim_calibrated()` gains a `by` argument and per-group `lower` / `upper` bounds (requested by ECLAC).
* **`collect_propensities()`** recovers the per-unit response propensities fitted by a `step_nonresponse(method = "propensity")` step from a prepped recipe, so their distribution can be inspected before the adjusted weights are trusted; it returns the same information whether the adjustment was made at the unit level or, through `cluster`, at the household level (the household propensity is broadcast to its members). It also returns `.factor` (the multiplier actually applied to each unit) and, with propensity classes, `.class`; note that `1/.propensity` reconstructs the applied factor only when `num_classes = NULL`. Requested by ECLAC.
* **`collect_step_detail()`** is a generic companion to `collect_weights()`: for any step it returns the weight each unit received (`.weight_in`) and the multiplier the step applied (`.factor`, read from the stored stage weights so `.weight_in * .factor` equals the outgoing weight by construction), plus that step's native per-unit quantities when it exposes them (for a propensity step, `.propensity` and `.class`).
* **`domain_summary()`** reports, for a study domain (e.g. a department / DAM), how the weights move within each domain at every stage of the cascade -- active units, sum of weights, mean weight and Kish design effect -- so weight movement can be reviewed step by step per domain for quality control (requested by ECLAC). Domains follow their factor / numeric order, a missing domain value is shown as an explicit `(missing)` domain, and `by` accepts several columns (crossed).

## Bug fixes and documentation

* Robustness and correctness fixes for uncommon edge cases -- malformed or degenerate inputs, replicate-variance accounting, and the HTML report -- each covered by a regression test.
* Documentation overhaul: help pages reviewed and rewritten, estimator formulas added to the details, and a new `?weightflow-concepts` page.

# weightflow 1.0.0

## New features

* **Tidy control totals that disagree on N now reconcile instead of failing.**
  When the tidy `totals` given to `step_calibrate()` do not all sum to the same
  population size (typical rounding of independently produced control totals),
  the largest margin is kept as the reference N and the others are rescaled
  proportionally, so their internal distribution is preserved and the
  calibration always closes. This applies to both `method = "raking"` (which
  previously could fail to converge) and `method = "linear"` / GREG (which
  previously used the first margin silently). The adjustment is reported through
  a message (informative, never fatal, so it is safe under
  `options(warn = 2)`) and is carried into `report_weighting()`, where it appears
  in the points-of-attention panel and the calibration step card listing every
  rescaled margin and the common N, so control-total mismatches are surfaced for
  review rather than hidden. This keeps the tidy interface usable without the
  manual dropping of a category that a design matrix would otherwise require.

* **Unweighted propensity models.** `step_nonresponse(method = "propensity")`
  gains `weight_model` (default `TRUE`). With `FALSE` the response-propensity
  model is fit unweighted, so the incoming weights enter only the 1/p (or class)
  adjustment and not the model fit -- useful when the weights are unrelated to
  response given the covariates (Little & Vartivarian 2003). Works at unit and
  household (cluster) level and across all engines. On a suggestion by Andrés Gutiérrez (ECLAC - Statistics Division).

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

* **`redistribute` argument for `step_trim_weights()`.** The trimmed mass can now
  be shared among the untrimmed units either in proportion to their weights
  (`"proportional"`, the default, keeps their relative sizes) or in equal amounts
  (`"uniform"`, the same amount to each untrimmed unit, with already-trimmed cases
  not reused). The `"uniform"` option reproduces `survey::trimWeights()` exactly,
  for bit-for-bit agreement when a weighting pipeline is validated against
  `survey`.

* **`report_weighting()` is now a full methodological quality report (GSBPM 5.6
  / ESS style).** With `narrative = TRUE` (default) the HTML report reads like an
  official quality report: an auto-generated executive summary (the cascade in
  prose plus the headline design effect, effective n and R-indicator) and a
  natural-language paragraph on each step built from its own parameters and
  diagnostics, in English or Spanish (new `lang`). A new `metadata` argument adds
  a reference-metadata header card aligned to the ESS SIMS / ESMS concepts and
  GSBPM sub-process 5.6 (operation, reference period, coverage, producer,
  contact, sampling frame, the source and date of the control totals, version,
  confidentiality). When the recipe has eligibility / nonresponse steps, a
  "Fieldwork outcomes" card reconstructs every case's disposition and reports the
  AAPOR response rate in three variants, from most to least conservative in how
  unknown-eligibility cases are treated, RR1 <= RR3 (CASRO, e-adjusted) <= RR5,
  weighted and unweighted (Valliant, Dever & Kreuter 2018, ch. 6). The executive
  summary also aggregates a "Points of attention" panel (steps that did not
  converge or raised an alert, each with a short recommendation), a truthful
  status checklist (convergence, final design effect, extreme and replicate
  weights, alerts) and a completion line; calibration steps get descriptive names
  by their auxiliaries and a relative-deviation column on their target/achieved
  tables. Set `narrative = FALSE` for the previous tables-only report.

* **New analytical cards, charts and navigation in `report_weighting()`.** A
  per-domain reliability card (new `domains` one-sided formula: active n, sum of
  weights, CV, Kish design effect and effective n within each domain, one table
  per term, `+` separate and `:` crossed). A per-step impact table (the change in
  Kish deff and CV versus the previous stage, each step's share of the total
  |deff change|, and whether it adds variance or recovers efficiency). A Kish
  design-effect evolution chart across stages. A replication-design card (new
  `replicates`, a `weightflow_boot` / `weightflow_jack` object: method,
  replicates, strata, mean PSUs per stratum, lonely-PSU handling, seed, cores and
  run time); `bootstrap_weights()` and `jackknife_weights()` now record this
  metadata. Plus a navigation menu, conditional colouring of the design-effect
  cells, a plain-language interpretation of the final design effect, collapsible
  per-step details, and a restyle to the package identity. Still pure inline SVG,
  no JavaScript and no new dependencies.

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
