# weightflow 1.3.1 (in development)

## New features

* **`step_round(method = "balanced", formula = )`: balance on the calibration
  design.** Until now the balancing matrix could only be built from `by`, which crosses
  the variables into cells. That is a different problem from the one a recipe calibrates:
  it preserves every crossed cell total, which implies the margins but also imposes
  constraints the calibration never asked for, and with many sparse cells the rounding
  cannot meet them -- it gets slower and less accurate on the very totals `by` exists to
  protect. With cell indicators each unit also loads on a single column, so the problem
  separates into one independent cell at a time and the cube method has no overlap to
  exploit. `formula = ~ dam + stratum` now builds the matrix with `model.matrix()`, which
  reproduces exactly the totals a calibration on that formula reproduces. Passing neither
  `formula` nor `by` after a `step_calibrate(formula = )` inherits that formula. `by` is
  unchanged and still right after a post-stratification, where the cells are the
  calibration. Reported by A. Gutierrez.

* **`step_model_calibration(by = )` and `step_pseudoweight(by = )`: one domain at a
  time.** `by` names a domain column and partitions the sample, with the same meaning
  it already has in `step_calibrate()`. In model calibration that gives two things at
  once: every working model in `models` is fitted on the units of its own domain and
  never sees the other domains, and the `x_formula` totals are reproduced exactly **within**
  each domain rather than only nationally. In pseudo-weighting it fits one
  participation model per domain, splitting the `reference` by the same column, so a
  covariate whose effect changes sign across regions is no longer averaged away into a
  national model that fits none of them.

  Both check up front that each domain can carry its own system -- `q_A + K`
  constraints on `n_g` units, and with `crossfit` enough rows left in every fold --
  and name the domains that cannot, because the symptom of a singular per-domain system
  is wild weights rather than an error. `population` (or `reference`) must carry the
  domain column, and per-domain `x_totals` must be in the tidy form: a national named
  vector would be applied to every domain and the population counted once per domain.

  With linear working models, fitting by domain is the same mechanism as cross-fitting:
  the prediction columns leave the shared span, so the rank ceiling moves from
  `K <= q - q_A` to `K <= Gq - q_A` with `G` domains, and the two
  compose.

## Bug fixes

* **The coordinated bootstrap's behaviour when a stratum changes its number of PSUs is
  now described correctly, and the alternative it used to recommend does not exist.** The
  warning, the code comment and the *Coordinated replication* vignette all said that the
  multiplicity transfer of `wave_step()` -- the Statistics Canada route -- avoids the loss
  of between-wave covariance that the uniform-based draw suffers when `n_h` drifts.
  Measured against a design-level Monte Carlo with a known truth, it does not: it recovers
  0.846 of the true covariance against 0.841 for the sequential multinomial. Two other
  candidates were measured and are worse -- the comonotone (`binom`) coupling attains the
  best per-PSU correlation any scheme can (about 0.96, since with `n_h` changed the two
  waves' marginals are different laws and 1 is unreachable) and still gives a negative
  covariance for a total, because it is uncentred; and resampling the design's PSU set
  rather than the wave's recovers more covariance and loses more to the level variance.
  The inflation of `V(change)` is therefore a limitation of the rescaling bootstrap for
  this contrast, not a defect of the draw, and it is now documented as one. The vignette
  also no longer claims that re-drawing from a stored uniform cannot reproduce a shared
  PSU's multiplicity: while `n_h` is preserved -- the rotating-panel case the method is
  built for -- it reproduces it exactly, correlation 1.000 at every rank.

* **`step_cre(rotation_group = )` took the number of rotation groups from whoever
  answered the wave.** The equal-representation constraints target `N / G`, and `G` was
  counted off the active sample. Lose one of six groups -- a group that has fully
  attrited, or a domain with no respondents in it -- and every remaining group is
  calibrated to `N / 5`: 20% above its share, with the missing group's population handed
  out among the others while the intercept still targets the whole `N`. It converged, the
  constraints held to 1e-6, and nothing was reported. The step now establishes `G` from
  the design -- the new `n_groups` argument, or the column's factor levels, which survive
  a level going empty -- and *refuses* a mismatch instead of solving it, because with the
  intercept pinned at `N` the two constraints cannot both hold; the message names the
  missing groups and the three ways out. A character column with no `n_groups` carries no
  record of an empty group, so there the step warns that it had to read `G` off the wave.

* **The trim steps no longer give up in silence.** Every trim loop ends for one of two
  reasons: every weight is inside the band, or `maxit` ran out. Only the first was ever
  reported. On the second, `step_trim()` and `step_trim_weights()` returned weights still
  above the cap while the diagnostics table printed the cap that had been *requested* and
  the report certified the step as applied. Giving up is itself legitimate -- each pass
  hands the trimmed mass to the units still inside the band, which can push one of them
  back out, so the iteration is not guaranteed to converge -- but it has to be said. Both
  steps now warn, with how many weights are left outside, on which side, and the worst
  one as a percentage of its own bound. A deliberate single pass (`strict = FALSE`) is
  not this case and stays quiet. The two unit tests that pinned the silent behaviour now
  assert the warning instead.

* **A value of the data could reach the HTML report as markup.** The header tiles
  interpolated their value straight into the page, and `report_panel()` feeds them the
  `wave` column, so an ordinary column value was rendered as HTML rather than as text --
  in a file that `open = TRUE` opens by itself. Tile values are now escaped by default;
  a call site that genuinely builds markup for a value has to ask for it. Tile *labels*
  are literals written in the package (some carry entities such as `&alpha;`) and are
  unchanged. Every other route data takes into the report -- tables, chips, axis labels,
  the JS string literals -- already escaped, and that was re-checked by probing the
  rendered HTML for factor levels, column names, wave and rotation-group values, gross
  flow states, step ids and metadata, in both languages.

* **`step_pseudoweight()` now says which end of the propensity scale fired, and what it
  does to the weight.** The boundary warning was wired for the nonresponse path only:
  the step never passed `raw_inverse`, so with `num_classes = NULL` -- the default --
  a unit at the floor was reported as protected by quantile binning that was not being
  applied, while its pseudo-weight was in fact about 1e6. The message now names the
  participation odds `(1 - p)/p` that this step actually applies, and counts the units
  against the non-probability sample rather than against "respondents". The wording of
  the nonresponse warning is unchanged.

* **The mirror end of the scale is no longer silent.** Only the floor was ever checked.
  For a pseudo-weight the ceiling is the dangerous end: `(1 - p)/p` at `p = 1 - 1e-6`
  is 1e-6, so a unit predicted at the boundary keeps essentially none of its weight and
  leaves every total without being reported as dropped. A pure leaf in
  `engine = "tree"` or `"forest"` gives `p == 1` exactly, so this is the common case
  there and almost never happens with a logit. It now warns, with the count of affected
  units.

* **`step_pseudoweight()` reports how its weights compare with the population the
  reference estimates -- and the package no longer claims the two are equal.** The
  step's documentation, its code comments and the HTML report all said the pseudo-weights
  "sum to the reference's estimated population size", as though the pooled fit imposed it.
  It does not. The sum is an *unbiased estimator* of that population: with a correctly
  specified model, simulation puts its standard deviation at 2.0% of N with a reference
  of 500 units and 1.0% with 3,000, so a few per cent either way is ordinary sampling
  variation. A calibration step imposes its totals exactly; this never did. Every place
  that asserted the identity now says what actually holds.

  The ratio is reported in the step's diagnostics (and so in the report), and the step
  warns when the gap is gross. That threshold cannot be calibrated -- how much the ratio
  moves depends on the reference size, the participation rate and the strength of
  selection -- so it is set where only a real level error trips it, and the message says
  that a ratio inside it is not evidence of a good fit. A level error here matters
  because a later calibration hides it completely: calibrating to known totals re-imposes
  the level and the pseudo-weights are never seen again. `num_classes` does not fix it
  either; binning changes how dispersed the weights are, not what they sum to.

  With `engine = "forest"` there is a second, specific cause, and only for that engine:
  `ranger` reads `case.weights` as bootstrap sampling probabilities rather than as counts,
  so the fitted `p` is close to an unweighted proportion (measured: 0.83 against 1.00 for
  `engine = "tree"` on the same data). `tree` and `boost` hand the weights to `rpart` and
  `xgboost` as analytic weights and are unaffected -- an earlier version of this warning
  blamed every non-logit engine.


* Calibrating by domain with `equal_within_cluster = TRUE` now errors when a cluster
  spans more than one domain, naming the clusters. Each domain is solved on its own
  units, so a household split across two domains picked up two calibration factors
  and ended up with several weights -- the very promise the step makes -- without a
  warning. Covers `step_calibrate()` and `step_model_calibration()`.

* `step_model_calibration()` now warns when a model prediction lies in the span of
  `x_formula`, naming the constraint. That system is singular, so it was solved by
  pseudo-inverse and the step quietly became a plain GREG while the diagnostics
  still showed an exact fit and `converged = TRUE`.

* Calibration totals that mix categorical margins summing to different population
  sizes with a continuous total now error instead of reconciling only the margins.
  A single number carries no population size, so the continuous total was left
  untouched while everything around it was rescaled, and the weights closed on an
  implicit mean that had not been declared. The message gives the margins, the
  reconciled N and the factor for each, so the total can be rescaled deliberately.
  Margins that disagree with no continuous total are unchanged.

* The reported condition number is now that of the system actually solved -- column
  scaled and weighted -- instead of `kappa(X'X)` on the raw matrix. The old figure
  measured the disparity of units rather than collinearity, so any calibration
  carrying an auxiliary in natural units (income, sales, area) raised the
  ill-conditioning alert and was told to drop an auxiliary that was not redundant.
  The unbounded linear solve, which is the default route, is scaled the same way;
  the weights are unchanged and `penalty` behaves exactly as before.

* Raking diagnostics carry `prev_total` and `factor`, so the `max_factor` alert now
  fires for raking as it already did for post-stratification. A cell with three
  units taken to a population count of 50,000 reports its factor of 1,667 instead of
  passing unremarked.

* Nonresponse calibration drops empty factor levels, as the other calibration paths
  do. A level defined but with no eligible unit added a column of zeros, and the
  step failed naming a target the user had never supplied.

* The non-convergence warning names the distance in use and only mentions `bounds`
  when bounds were given, and reports how large the miss is. An unbounded raking
  solve that stalled is also reported as not converged: the solver's own flag was
  being discarded unless the distance was truncated.

* The cluster checks in `step_model_calibration()` run before the working models are
  fitted, so an integrative recipe that cannot work fails immediately.

* `vignettes/model-calibration.Rmd` no longer states that `calfun` and `bounds` do
  not apply to model calibration; they have since 1.3.0.

* `jackknife_weights()` takes `groups` and `seed`: the delete-a-group jackknife
  (Kott 2001; Rust and Rao 1996) for a direct sample. With `psu = NULL` the engine
  deletes one unit at a time, which is the correct estimator for element sampling but
  needs one full re-prep and one replicate column per unit -- an `n x n` matrix, about
  80 GB at n = 100,000. `groups = G` partitions the sample at random within each
  stratum and deletes one whole group per replicate, which is the same estimator with
  the group standing in for the PSU: on 4,000 units in 4 strata, 200 replicates instead of
  4,000 and 6.4 MB instead of 128 MB, with the standard error tracking the delete-one
  one (0.310 at G = 100 against 0.311). `df` becomes `G - strata`, which is the honest
  precision. There is no default: the choice of `G` is the analyst's and the two
  variances are not the same number. The unit-level path is unchanged and now explains
  the cost, and points at `groups`, above 5,000 units.

* `prep()` checks, once the whole recipe has run, that the final weights still carry
  the population each calibration step fixed, and names the later step that threw it
  away. A step's diagnostics describe the weight at the moment that step ran and are
  never re-read, so a calibration to 1,570 followed by `step_rescale()` left the
  weights summing to 400 while its own table still printed target 1,570 / achieved
  1,570 -- in the HTML report, in green, with no alert anywhere. Steps that preserve
  the total, such as `step_round(method = "preserve_total")`, stay silent.

* `step_cre()` detects a broken linkage key instead of reading it as a rotation. With
  `birth = NULL` -- the default, and what the examples and the vignette used -- every
  unit that fails to link is classified as the incoming rotation group, the one category
  that does not take part in the change correction. The guard written to catch this
  fired on the count of unlinked non-births, which is zero by construction in that
  branch, so it was dead code: on `panel_ine` a fully broken `person_no` gave an overlap
  of 1e-6 and 100% births in a design whose nominal incoming group is one sixth, with
  `converged = TRUE` and no warning. The step now compares the measured link rate
  against the design's (below half, or below `overlap` minus ten points when `overlap`
  is given) and names the key, and refuses outright below 2%, where the carry-backward
  multiplier `1/delta - 1` passes 49. `cre_link` carries `linked_rate` and
  `birth_inferred` so the check can be asserted on.

* `step_cre()` warns when the population estimated from `previous` differs from the
  one `totals` fixes for this wave, and takes `rescale_previous` to put the composite
  block on the current wave's scale. `Zhat` is a total carried on the previous wave's
  population while the demographic block fixes this wave's, and the identity that keeps
  the composite block a smoother assumes the two agree. When they do not, the whole gap
  lands on the labour-status estimate: measured on `panel_ine` with the totals of the
  function's own examples -- which drift 12.9% between waves -- the employment rate moved
  7 points, with every constraint met to 1e-6 and `converged = TRUE`. The examples, the
  vignette and the test fixtures now use one population vector across waves, as a series
  of projections would be.

* `wave_bootstrap()` warns when a stratum changes its number of PSUs between waves,
  naming the strata and the counts. The coordination reads per-PSU uniforms through a
  sequential multinomial that spends each wave's own budget, so it is exact only while
  `n_h` is preserved: measured on the draw itself, the two multiplicities of a shared PSU
  correlate 0.96 at the first rank and 0.28 at the last when `n_h` goes from 10 to 6,
  against 1.00 throughout when it does not change. The lost covariance makes the
  variance of a net change too large -- conservative, but large enough to hide a real
  movement. The warning points at `wave_jackknife()`, which is deterministic and
  barely affected, and at `wave_step()`, which carries multiplicities across periods.

* `panel_estimate()` no longer aborts when a delete-one replicate failed. The
  jackknife branch behind it did not drop the non-finite replicate, so the whole
  covariance went missing and the call ended in an internal message naming neither
  the cause nor the wave -- on an object `change_estimate()` handled without
  trouble. A replicate that fails because deleting a PSU emptied a calibration cell
  is the ordinary case, not an exotic one.

* Every panel and single-stage jackknife rescales a stratum by `(n_h - 1)/m_h` over
  its surviving replicates, as the single-stage estimator already did. With a failed
  delete-one replicate the panel paths divided by `n_h` and biased the variance low.

* `boot_total()`, `boot_mean()`, `jack_total()`, `jack_mean()`, `level_mean()`,
  `level_total()`, `change_mean()`, `change_total()`, `panel_mean()` and
  `panel_total()` take `level`, `ci_type` and `df`, and default `df` to the design
  degrees of freedom. The underlying estimators had always accepted them; the
  shortcuts most people use did not, so a t interval was unreachable from the
  production path even though the design df were computed and printed. The default
  interval is unchanged (normal): with 20 PSUs in 4 strata a t interval is about
  8% wider.

* `print()` on a bootstrap object reports the Monte Carlo error of any standard
  error drawn from it, and the estimate carries it as the `"mcse"` attribute. At the
  default 200 replicates that error is 5% of the SE, so two runs of the same
  analysis with different seeds differ by about 9%. The jackknife reports zero.

* Dropped replicates say what dropping them does to the variance, in both the
  bootstrap and the jackknife, instead of only counting them.

* `ci_type = "percentile"` on a coordinated jackknife errors instead of silently
  returning a normal interval; the delete-one jackknife yields a variance, not a
  distribution to take quantiles of.

* The two-phase vignette no longer states that the phase-1 multiplier makes the
  variance of a mean or ratio exact. It self-centres only to first order and the SE
  is mildly conservative (+5-8% in simulation), which `boot_mean()` now reports.
  The DESCRIPTION qualifies the two-phase decomposition as applying to an
  unclustered first phase, which is what the code supports.

# weightflow 1.3.0

## New features

* **Rotating and pure panels.** `panel_design()` reads the unit x wave structure and
  the rotation calendar -- and, given a `cluster`, the overlap at the cluster level
  too, which is the one the rotation calendar describes (the unit-level figure is
  that overlap net of within-household churn); `panel_merge()` builds the
  longitudinal file; `panel_pr()` and `step_panel_overlap()` apply the
  panel-selection probability; `step_attrition()` is the panel-facing nonresponse
  adjustment and takes the full argument list of `step_nonresponse()`, `crossfit`
  included; and `step_longitudinal()` / `step_cross_sectional()` declare which weight
  a recipe is building.

* **Net change with a coordinated variance.** `wave_bootstrap()` and
  `wave_jackknife()` resample PSUs *coordinately* across waves, so the sample
  overlap shows up as covariance instead of being ignored. `change_estimate()`
  (with `change_mean()` / `change_total()`, absolute or relative, optionally by
  domain), `level_estimate()` and `panel_estimate(contrast = )` read the estimates
  off those replicates. Both engines take `lonely_psu` as `bootstrap_weights()` does,
  because a stratum with a single PSU contributes no variance to a change either;
  the collapse map is built over all the waves at once so the replicate pairing
  survives it.

* **Chained production: `wave_step()`, `wave_carry()`, `wave_contrast()`.** One
  period at a time, as an office actually publishes: each run leaves a compact
  *carry* that the next one needs, and `wave_contrast()` estimates any linear
  combination over a chain (a rolling quarter, an annual average) from the saved
  carries alone.

* **Composite (regression composite) estimation: `step_cre()`.** The MR1/MR2
  estimator of the Canadian LFS and Uruguay's ECH, including the equal-representation
  constraints across rotation groups, with `Zhat` re-estimated inside every
  replicate. The step reports the quality of the wave-to-wave link it depends on --
  the overlap rate, the births, and how many non-birth units failed to link -- and
  warns when that failure rate gets high, because a broken linkage key attenuates the
  estimated change rather than announcing itself.

* **Gross flows.** `transition_matrix()`, `boot_transition()` and `boot_flows()`
  give the weighted flow between states across waves, as conditional or joint
  distributions and as population totals with standard errors and net flows.

* **A declarative estimation grammar.** `step_domain()`, `step_filter()`,
  `step_estimate()` and `collect_estimates()` run over a saved replicate object, so
  the expensive replicate build happens once and many estimates are read off it.
  Units whose domain value is missing are reported rather than quietly dropped, so
  it is visible when the cells will not add up to the overall figure. Every verb of
  the statistic DSL validates its arguments against the wave data, because a
  replicate object will put a standard error and a confidence interval on whatever
  number it is handed: an estimand must give one numeric or logical value per unit
  (so `prop()` takes a condition, `prop(status == "unemployed")`, and refuses a
  factor rather than averaging its integer codes), `p` in `quantile(var, p)` must be
  a probability in `[0, 1]` (`0.5`, not `50`), `level` must be a proportion, and
  `ratio(num, den)` is taken over the domain where both are observed -- matching
  `survey::svyratio(na.rm = TRUE)` exactly -- rather than dropping the missing rows
  of each sum independently. A domain column may not be named after one of the
  result table's own columns.

* **`report_panel()`**, a self-contained HTML quality report for a panel run, and
  new panel alerts (`PN-01`, `PN-02`, `PN-06`, `PN-07`, `PN-08`) plus an alert when a
  nonresponse adjustment stops preserving the eligible total.

* **Exact multinomial PSU resampling** is the default in the panel engines
  (`resample = "multinom"`): the per-stratum resample counts sum to `m_h`, which
  removes an ~8-10% inflation of the composite change SE seen in simulation. Within a
  stratum the PSUs are ordered by how many waves they appear in, so the units that
  carry the overlap get the exactly-coordinated draws and the answer does not depend
  on which PSU ids happen to rotate out.

* Smaller additions: `bounds` and `calfun` for `step_model_calibration()`,
  `step_trim_calibrated()` after a model-calibration step, and `refit_steps` to
  choose which steps are re-run per replicate.

* Four new vignettes: *Rotating panels*, *Pure panels*, *Coordinated replication*
  and *Composite estimation*. The change variance is now also validated against an
  analytic estimator from a different family (Berger and Priam 2016, via
  `ReGenesees::svyDelta()`), with the reference values frozen in the test suite.

## Bug fixes

These are fixes against **1.2.0 as published**. The panel layer is new in this
release, so nothing about it appears here: what it does and what it checks is
described under New features.

* Response-propensity models could diverge under production design weights: a
  binomial GLM reads the prior weights as the number of trials, so large design
  weights started the fit at the separation boundary and the fitted propensities
  collapsed. Model weights are now normalized to mean 1 wherever a weighted binomial
  model is fitted, which leaves the estimates invariant.

* **Recipe files are safe to exchange.** `read_recipe()` accepts only a whitelist of
  data-manipulation calls in the conditions and formulas a recipe stores, unless
  `allow_code = TRUE`; before, a hand-edited condition still ran on the first
  `prep()`. And `write_recipe()` no longer serializes a `population =` data frame
  value by value: it is stored as a descriptor and asked back through `references =`,
  as `reference_sample()` already was.

* Adjustment cells are keyed unambiguously. A `by` value containing the `" | "`
  separator, or equal to the `"(missing)"` sentinel, used to collapse two different
  cells into one -- with the wrong adjustment factor for both, and the "cell with no
  respondents" alert suppressed because the empty half was absorbed by the full one.

* Two publication gates that failed open are closed: `disclosure_risk()` silently
  skipped cells with a missing value or a non-positive median weight, leaving those
  units out of the screen for weight dominance, and `as_sae_input()` rated both a
  missing-domain area and a zero-variance domain as publishable.

* `step_round("preserve_total")` breaks ties in the fractional part at random rather
  than by row order, which was moving mass systematically towards whatever the file
  was sorted by while reporting the grand total as preserved. Call `set.seed()`
  before `prep()` for a reproducible result, as `method = "balanced"` already
  required.

* The model-assisted and propensity steps are steadier under cross-fitting: whether a
  `y_model()` is a regression or a classification is decided once over the whole
  sample instead of inside each fold (and an explicit `family` is respected),
  propensities at the 0/1 boundary warn instead of being clamped in silence, and a
  fold whose training set has only respondents says so rather than failing inside the
  model engine.

* The HTML reports describe the active weights, negatives included, in the
  weight-distribution card and the matching Status check; a column name containing a
  space no longer aborts the whole report; and the trimming note names the direction
  the weight total moved when the bounds could not be met.

* `boot_total()` warns that the two-phase total variance is conservative, which it
  was silently before, and the wave engines reject `NA` or blank in `strata` / `psu`,
  as `bootstrap_weights()` has since 1.2.0 -- those rows paste into one design key
  and were resampled as a single pseudo-PSU, understating the variance.

* Stricter validation and robustness fixes for degenerate and edge-case inputs across
  the cascade, trimming and the auxiliary outputs, each with a regression test.

# weightflow 1.2.0

## New features

* **Two-phase (double) sampling.** `step_subsample()` records a second phase and the
  bootstrap returns the variance split into its two components (`V = V1 + V2`).
* **Non-probability samples.** `step_pseudoweight()` (pseudo-weighting, mass
  imputation and doubly robust estimators), `step_nr_sensitivity()` for
  nonignorable nonresponse, and `data_defect()` for the Meng (2018) view.
* **Calibrate to a reference survey** with `reference_sample()`, propagating the
  reference's own sampling error.
* **Recipes as files.** `write_recipe()` / `read_recipe()` serialize the method (not
  the data) to a versionable YAML manifest.
* **Confidentiality and hand-off.** `collect_replicate_weights(scramble = TRUE)`,
  `disclosure_risk()`, and `as_sae_input()` for small-area models.
* **Quality control.** `weighting_alerts()` / `has_alerts()` as a single programmatic
  channel, `domain_summary(min_n_eff = )` as an explicit publication gate, and
  stable `id`s on every step.
* **Finite-population correction** (`fpc`) and `t` / percentile confidence intervals
  in the replicate estimators.

## Bug fixes

* Cells for `by`-based steps are now built over the units still active, so units
  dropped earlier no longer raise spurious `(missing)` cells.
* **Behaviour change:** the mean estimators and replicate-weight exports keep active
  negative weights (a valid GREG output), matching the totals estimators and
  `survey`.
* Stricter, earlier argument validation across the step constructors and
  estimators, plus robustness fixes for malformed and edge-case inputs, each with a
  regression test.
* Documentation: `?weightflow-concepts` (argument correspondence with `survey`) and
  `?weightflow-alerts` (the alert catalogue).

# weightflow 1.1.0

## New features

* **Diagnostics report suite.** `report_weighting()` gains a per-step card reading
  the bias-variance trade-off of each adjustment, with quality alerts.
* **Honest variance for machine-learning adjustments**: a flexible learner run
  without `crossfit` now raises an alert.
* **Inspection accessors**: `collect_propensities()`, `collect_step_detail()` and
  `domain_summary()`.
* **Per-subgroup trimming** (`by` in `step_trim_calibrated()`), and jackknife export
  through `collect_replicate_weights()`.
* Adding a step to a prepped recipe now clears the results, so stale weights cannot
  be read by accident.

## Bug fixes and documentation

* Robustness and correctness fixes for edge cases in the cascade, the replicate
  variance and the HTML report, each covered by a regression test.
* Help pages reviewed and rewritten, with estimator formulas in the details.

# weightflow 1.0.0

## New features

* **Nonresponse by calibration** (`step_nonresponse(method = "calibration")`) and
  unweighted propensity models (`weight_model = FALSE`).
* **Trimmed calibration** (`step_trim_calibrated()`): trim calibrated weights into an
  absolute interval while preserving the calibration totals.
* **Tidy control totals that disagree on N now reconcile** instead of failing, with
  a message naming the rescaling.
* **Lonely-PSU handling and parallelism** in `bootstrap_weights()` and
  `jackknife_weights()`, and a `redistribute` argument for `step_trim_weights()`.
* **`report_weighting()` becomes a full methodological quality report** (GSBPM 5.6 /
  ESS style), with a narrative mode, a per-domain reliability card and new charts.

## Bug fixes

* Cross-fitting no longer errors in a fresh session, `step_trim_weights()` now trims
  negative weights, and the report's before/after scatter is reproducible.

# weightflow 0.2.0

## New features

* **Tidy population totals** for `step_calibrate()`, alongside the classic
  `margins`/`totals` inputs.
* **Domain (partitioned) calibration** (`by`) and the **exponential (raking)
  distance** (`calfun = "raking"`) for linear calibration.
* **Delete-a-PSU jackknife** variance, recipe-aware like the bootstrap.
* **Machine-learning response propensities** (CART, random forest, xgboost) with
  **k-fold cross-fitting**, **ridge (penalized) calibration**, and **Potter
  MSE-optimal trimming**.
* **Quality alerts in `prep()`**, an **R-indicator** of response representativity,
  and a weight-distribution summary in the report.
* Subsampling more than one person per household (`n_selected`), external
  consistency totals for model calibration (`x_totals`), and a new vignette on
  preparing the sample.

## Bug fixes

* The optional machine-learning engines now run single-threaded by default, for
  reproducibility and to respect CRAN core limits.
* `report_weighting()` flags calibration steps that did not converge.
* `step_calibrate(equal_within_cluster = TRUE)` now implements the genuine
  Lemaitre-Dufour (1987) integrative method.

# weightflow 0.1.0

First release. The weighting cascade as a declarative recipe:

* **Adjustment steps**: `step_unknown_eligibility()`, `step_drop_ineligible()`,
  `step_select_within()`, `step_nonresponse()`, `step_calibrate()` (raking,
  post-stratification, linear/GREG, bounded and integrative),
  `step_model_calibration()`, `step_trim()`, `step_trim_weights()`, `step_round()`,
  `step_rescale()` and `step_assert()`.
* **Inspection and reporting**: `summary()`, `plot()`, `weight_factors()`,
  `design_effect()` and a self-contained HTML report from `report_weighting()`.
* **Variance estimation**: `bootstrap_weights()` (Rao-Wu rescaling, re-applying the
  whole recipe on each replicate), `boot_mean()` / `boot_total()`, and bridges to
  `survey` / `srvyr` through `as_svydesign()`, `as_svrepdesign()` and
  `collect_replicate_weights()`.
* **Example data**: `population`, `sample_survey` and `sample_one`.
