# Nonresponse adjustment

Inflates the weights of the eligible respondents so they also represent
the eligible nonrespondents, under the assumption that response is
ignorable given the information used. Three estimators are available –
weighting classes, a response-propensity model (four engines, with
optional cross-fitting), and calibration of the respondents to auxiliary
totals – at the unit level or, through `cluster`, at a coarser level
(e.g. the household).

## Usage

``` r
step_nonresponse(
  spec,
  respondent,
  method = c("weighting_class", "propensity", "calibration"),
  by = NULL,
  formula = NULL,
  engine = c("logit", "tree", "forest", "boost"),
  weight_model = TRUE,
  num_classes = 5L,
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

  a 0/1 dummy column (1 = responded) or any logical condition (unquoted)
  TRUE for respondents. Eligible cases that are not respondents are
  treated as nonresponse.

- method:

  "weighting_class" (cells), "propensity" (predictive model) or
  "calibration" (calibrate the respondents to auxiliary totals;
  two-phase / Sarndal-Lundstrom).

- by:

  character. Adjustment cells for method = "weighting_class".

- formula:

  predictor formula (right-hand side only), e.g. ~ age + region, used
  when method = "propensity".

- engine:

  engine to estimate the propensity when method = "propensity": "logit"
  (logistic regression, base R), "tree" (CART via package 'rpart'),
  "forest" (random forest via package 'ranger') or "boost" (gradient
  boosting via package 'xgboost'). 'rpart', 'ranger' and 'xgboost' are
  optional: only needed if you pick that engine. The flexible learners
  run with fixed default settings and their hyperparameters are not
  currently exposed: "tree" and "forest" use the 'rpart' and 'ranger'
  defaults, and "boost" uses xgboost with nrounds = 150, max_depth = 4
  and eta = 0.1.

- weight_model:

  logical. Only for method = "propensity": whether to fit the
  response-propensity model with the incoming weights (`TRUE`, the
  default) or unweighted (`FALSE`). Fitting unweighted can reduce the
  variance of the propensity estimates when the weights are unrelated to
  response given the model covariates, at the cost of possible bias if
  they are (Little & Vartivarian 2003). The 1/p (or class) adjustment
  always uses the design weights; only the model fit is affected.

- num_classes:

  integer or NULL. Controls how propensities are used: an integer forms
  that many propensity classes (cell adjustment within each class); NULL
  applies the direct factor 1/p to each unit. When the fitted
  propensities are (nearly) constant the requested quantile classes
  cannot be formed; rather than error, or fabricate classes by jittering
  the propensities (which is not reproducible and invents structure that
  is not there), all units are placed in a single adjustment class and a
  quality alert is raised – the statistically correct outcome, since
  equal propensities give nothing to differentiate.

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
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/dev/reference/step_calibrate.md))
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

  optional string: a stable identifier for this step, shown in the
  recipe print-out and usable to select it in
  [`collect_step_detail()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_step_detail.md);
  defaults to a derived `"<class>_<k>"`.

## Value

The input `weighting_spec` with this step appended to its recipe. The
step is recorded only; it is evaluated when
[`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md)
is called.

## Details

The three estimators are the same operation with a different inflation
factor. Weighting classes inflate the responding weight to the cell
total, \\f_c = \sum\_{i \in c} w_i / \sum\_{i \in c} r_i w_i\\ (with
\\r_i = 1\\ if \\i\\ responds), applied as \\w_i \leftarrow f_c w_i\\. A
response-propensity model instead adjusts unit by unit, \\w_i \leftarrow
w_i / \hat\phi_i\\, with \\\hat\phi_i\\ the estimated response
propensity. Calibration of the respondents solves for a factor \\v_i\\
that makes the respondents reproduce a reference total (the two-phase /
Sarndal-Lundstrom approach).

## Examples

``` r
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = "region")
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)  [nonresponse_1]
#> Status  : not estimated
#> 

# household-level nonresponse (whole household responds or not)
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = "region", cluster = "household_id") |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class, by household_id)  [nonresponse_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base      467    4371  0.236     1.056   442
#>  stage_1_step_nonresponse      111    3047  0.253     1.064   104
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
# propensity with cross-fitting (out-of-sample, avoids overfitting)
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "propensity",
                   formula = ~ region + sex, engine = "logit",
                   num_classes = 5, crossfit = 5, crossfit_seed = 1) |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (propensity: logit, 5 classes)  [nonresponse_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base      467    4371  0.236     1.056   442
#>  stage_1_step_nonresponse      270    4371  0.203     1.041   259
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 

# gradient boosting engine (requires the 'xgboost' package)
# \donttest{
if (requireNamespace("xgboost", quietly = TRUE)) {
  weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "propensity",
                     formula = ~ region + sex + age, engine = "boost",
                     num_classes = 5, crossfit = 5) |>
    prep()
}
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (propensity: boost, 5 classes)  [nonresponse_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base      467    4371  0.236     1.056   442
#>  stage_1_step_nonresponse      270    4371  0.254     1.065   254
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
# }

# nonresponse by calibration (two-phase): calibrate the respondents to the
# R+NR design-weighted totals of the auxiliaries at that stage, so their
# estimates reproduce the pre-nonresponse ones (Sarndal & Lundstrom 2005)
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "calibration",
                   formula = ~ region + sex) |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (calibration: linear, sample-level)  [nonresponse_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base      467    4371  0.236     1.056   442
#>  stage_1_step_nonresponse      270    4371  0.146     1.021   264
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
