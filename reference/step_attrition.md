# Attrition adjustment for panel waves

The panel-facing nonresponse step: it adjusts for **attrition**
(nonresponse between waves) when building a longitudinal weight,
reweighting the units that stayed in to also represent those that
dropped out, among the units that remain **eligible**. It is a thin
wrapper over
[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
– so the theory stays visible in the recipe – that uses the same
estimators but under a name that reads correctly in a panel cascade and
with the panel conventions: the covariates should come from a wave where
the unit was observed (e.g. the first period), and it does NOT absorb
eligibility (out-of-scope and unknown-eligibility go in
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md)
/
[`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md)).

## Usage

``` r
step_attrition(
  spec,
  respondent,
  method = c("propensity", "rhg", "weighting_class", "calibration"),
  formula = NULL,
  by = NULL,
  engine = c("logit", "tree", "forest", "boost"),
  num_classes = 5L,
  weight_model = TRUE,
  cluster = NULL,
  crossfit = NULL,
  crossfit_seed = NULL,
  totals = NULL,
  count = NULL,
  calfun = c("linear", "logit", "raking"),
  bounds = NULL,
  penalty = NULL,
  equal_within_cluster = FALSE,
  maxit = 50L,
  tol = 1e-06,
  id = NULL
)
```

## Arguments

- spec:

  a weighting_spec.

- respondent:

  an unquoted 0/1 column or logical condition, TRUE for the units that
  responded in the wave being adjusted (e.g. `disposition_T2 == "R"`).

- method:

  attrition estimator: `"propensity"` (individual `1/phi`, the
  SLID/ECLAC response-propensity weighting; default), `"rhg"` (response
  homogeneity groups: propensity stratified into `num_classes` classes),
  `"weighting_class"` (design-variable cells), or `"calibration"`
  (Sarndal-Lundstrom).

- formula:

  model formula for `"propensity"`/`"rhg"`, in covariates observed for
  responders and nonrespondents (from a wave where the unit was seen).

- by:

  adjustment cells for `"weighting_class"`.

- engine:

  propensity engine (`"logit"`/`"tree"`/`"forest"`/`"boost"`).

- num_classes:

  number of propensity classes for `"rhg"`.

- weight_model:

  logical. Only for method = "propensity": whether to fit the
  response-propensity model with the incoming weights (`TRUE`, the
  default) or unweighted (`FALSE`). Fitting unweighted can reduce the
  variance of the propensity estimates when the weights are unrelated to
  response given the model covariates, at the cost of possible bias if
  they are (Little & Vartivarian 2003). The 1/p (or class) adjustment
  always uses the design weights; only the model fit is affected.

- cluster:

  character or NULL. If given, the adjustment is done at the cluster
  level for whole-cluster nonresponse: each cluster counts once with its
  (uniform) weight; in "weighting_class" the redistribution is between
  responding and nonresponding clusters within the cells, and in
  "propensity" the model is fitted with one row per cluster (cluster
  auxiliaries), predicting the cluster's response. The resulting factor
  is assigned to every member; nonresponding clusters go to zero. As
  always, only active units (weight \> 0) take part, so units already
  dropped (unknown eligibility, ineligible) are excluded automatically.
  For `method = "calibration"`, `cluster` is used together with
  `equal_within_cluster = TRUE` for integrative (one weight per cluster)
  calibration.

  The cluster need not be a household: it is any grouping whose members
  share a fate and a weight – a dwelling, an area segment, or a whole
  primary sampling unit (an entire PSU inaccessible, then redistributed
  within its stratum). A methodological consequence to keep in mind: a
  cluster-level adjustment preserves the *mass of clusters* in each cell
  (the cluster weight is the mean of its members, in the sense of
  Valliant et al. 2018), and the factor is uniform within the cell; it
  does **not**, by construction, preserve the mass of the underlying
  units (persons). That is the job of the later calibration, whose
  margins bring the person totals back exactly.

- crossfit:

  integer or NULL. If given (number of folds K \>= 2), the propensity is
  estimated by K-fold cross-fitting: for each fold the model is trained
  on the other folds and used to predict the held-out fold, so each
  unit's propensity comes from a model that did not see it. This avoids
  the overfitting that flexible engines (forest, boost) can produce,
  which would otherwise inflate the weights. Folds are formed by
  `cluster` when given (so correlated units stay together). NULL
  (default) fits and predicts in-sample. For flexible learners it also
  keeps the design-based variance honest: same-sample predictions can
  understate the variance even under recipe-aware replication (Dagdoug,
  Goga and Haziza 2023), so cross-fitting is recommended whenever
  `engine` is not "logit".

- crossfit_seed:

  integer or NULL. Seed for reproducible fold assignment when `crossfit`
  is used.

- totals:

  (method = "calibration") calibration targets. NULL (default)
  calibrates the respondents to the R+NR design-weighted totals of
  `formula` at that stage (the two-phase / sample-level case; Sarndal &
  Lundstrom 2005); a named vector or a tidy `totals`/`count` input (as
  in
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md))
  calibrates to population totals instead.

- count:

  (method = "calibration", tidy `totals`) string naming the counts
  column of the totals data frame(s).

- calfun:

  (method = "calibration") distance function for the calibration factor:
  "linear", "raking" or "logit", as in
  `step_calibrate(method = "linear")`.

- bounds:

  (method = "calibration") numeric c(L, U) with L \< 1 \< U. Bounds on
  the calibration factor, to keep the nonresponse factors positive.

- penalty:

  (method = "calibration", unbounded) NULL or positive cost(s) for ridge
  (penalized) calibration.

- equal_within_cluster:

  (method = "calibration") logical. If TRUE, integrative
  (Lemaitre-Dufour) nonresponse calibration: the responding members of a
  household (`cluster`) share a single calibration factor, so the
  adjustment keeps the weights constant within household. Requires
  `cluster`. FALSE (default) calibrates each responding unit on its own.

- maxit, tol:

  (method = "calibration") convergence control for the bounded or
  exponential-distance calibration solver.

- id:

  optional stable step id.

## Value

the `weighting_spec` with the attrition step appended.

## Details

The attrition adjustment prescribed by ECLAC's household-survey manual
(ch. XVI) and used by Statistics Canada's SLID (Naud 2002; LaRoche 2003)
is **response-propensity weighting** (`method = "propensity"`, i.e.
inverse of the estimated response probability; Little 1986; Rosenbaum
1987) – not an ECLAC invention. `method = "rhg"` is the
response-homogeneity-group variant (propensity stratified into
`num_classes` groups, then the class-mean rate), which stabilises the
weights.

Two ECLAC prescriptions are **not** implemented, and the difference
matters when they apply. The manual (ch. XVI, sec. B.1.b) allows two
fallback imputations for units with no auxiliary information at all: a
nonrespondent whose rotation panel does not overlap (impute the overall
effective response rate as its `phi`), and a newly incorporated
nonrespondent (impute the adjusted expansion factor of its household).
Here a covariate that is `NA` for an eligible unit is an **error**, not
an imputation – an `NA` propensity would let that nonrespondent survive
the adjustment silently, which is the failure the error exists to
prevent, and the package will not silently substitute a value of its own
for a missing input.

So when the error fires, the fix belongs in the data, and either ECLAC
route is available to you there: impute the missing covariates before
the step (the manual's own fallback is the overall effective response
rate, i.e. a constant, which is what a model with no covariates for
those units amounts to), give a newly incorporated nonrespondent its
household's adjusted factor, or restrict `formula` to a covariate set
observed for every eligible unit. What the package will not do is choose
one of those for you and leave no trace in the recipe. Multi-wave
retention chaining (decomposing Pr(in at T3) into Pr(reach T2) x Pr(T2
to T3)) is likewise absent: this step adjusts one transition at a time,
which is what ch. XVI specifies for two consecutive periods.

## The arguments of step_nonresponse()

Attrition *is* nonresponse over waves, so this step delegates to
[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
and takes its arguments too. That was not true before: the twelve
remaining ones were missing, including `crossfit` – which the step's own
quality alert recommends when a flexible engine overfits the propensity,
a remedy that could not be applied – and `totals` / `calfun` / `bounds`,
i.e. the whole Sarndal-Lundstrom calibration route with nothing to
configure.

## See also

[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md),
[`step_panel_overlap()`](https://jpferreira33.github.io/weightflow/reference/step_panel_overlap.md),
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md)

## Examples

``` r
wide <- panel_merge(
  list(T1 = subset(panel_ine, wave == 1), T2 = subset(panel_ine, wave == 2)),
  by = c("household_id", "person_no"), require = "all")
weighting_spec(wide, base_weights = pw_T1) |>
  step_panel_overlap(prob = 5 / 6) |>
  step_drop_ineligible(disposition_T2 == "OS", reason = "left the target population") |>
  step_attrition(respondent = disposition_T2 == "R", method = "propensity",
                 formula = ~ age_T1 + sex_T1 + region_T1) |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 1717 cases
#> Base wts: pw_T1
#> Steps   :
#>   1. panel overlap  [panel_overlap_1]
#>   2. drop ineligible (left the target population)  [drop_ineligible_1]
#>   3. attrition (propensity)  [nonresponse_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                         stage n_active sum_wts cv_wts deff_kish n_eff
#>                          base     1717  245498  0.300     1.090  1575
#>    stage_1_step_panel_overlap     1717  294597  0.300     1.090  1575
#>  stage_2_step_drop_ineligible     1633  279699  0.302     1.091  1496
#>        stage_3_step_attrition     1464  279688  0.303     1.092  1341
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
