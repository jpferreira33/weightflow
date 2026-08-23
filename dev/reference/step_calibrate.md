# Calibration to population totals

Adjusts the weights so that the weighted sample reproduces known
population totals of auxiliary variables, while moving the incoming
weights as little as possible. This is the calibration estimator of
Deville and Sarndal (1992), with raking, post-stratification and linear
(GREG) calibration, optional bounds on the adjustment factor, ridge
relaxation of the targets, domain partitions and one-weight-per-cluster
(integrative) calibration.

## Usage

``` r
step_calibrate(
  spec,
  margins = NULL,
  method = c("raking", "poststratify", "linear"),
  formula = NULL,
  totals = NULL,
  count = NULL,
  by = NULL,
  cluster = NULL,
  equal_within_cluster = FALSE,
  calfun = c("linear", "logit", "raking"),
  bounds = NULL,
  maxit = 50L,
  tol = 1e-06,
  penalty = NULL,
  population = NULL,
  id = NULL
)
```

## Arguments

- spec:

  a weighting_spec.

- margins:

  named list (classic format for "raking"/"poststratify"). Each element
  is a named numeric vector with the target totals per category. E.g.:
  list(sex = c(M = 5000, F = 5200), region = c(N = 3000, S = 7200)).
  Still fully supported; for a tidy alternative see `totals` and
  `count`.

- method:

  "raking" (IPF, categorical margins), "poststratify" (post-strata: one
  or more categorical variables crossed) or "linear" (GREG / regression
  estimator; handles continuous and categorical auxiliaries together).

- formula:

  (only method = "linear") auxiliary formula, e.g. ~ sex + income. Uses
  model.matrix; includes the intercept unless you write ~ 0 + ...

- totals:

  population totals, in one of two forms. Classic (all methods): for
  "linear" a named numeric vector aligned with the model.matrix columns
  (including "(Intercept)" = N); for "raking"/"poststratify" use
  `margins`. Tidy (recommended): a data frame or a named list of data
  frames/numbers giving the totals in a friendly way, paired with
  `count`. For "poststratify", a single data frame with one or more
  category columns plus a counts column. For "raking", a list of data
  frames, one per margin. For "linear", a named list whose names match
  the formula terms: a data frame with all categories for each factor,
  and a single number for each continuous auxiliary; weightflow builds
  the model.matrix totals internally (you never handle the intercept or
  dropped reference category).

- count:

  (tidy `totals` only) string naming the counts column in the totals
  data frame(s). All other columns are treated as category variables.

- by:

  (tidy `totals` only) NULL, or a string naming a domain (partition)
  column. When given, the weights are calibrated **independently within
  each domain**, each to its own totals (partitioned / domain
  calibration). The totals tables carry the domain as a column, and each
  `count` table is split by it; a continuous total becomes a data frame
  `domain, value` (one total per domain). The domain variable must NOT
  appear in `formula` / the margins: it is the partition. Composes with
  `calfun`, `bounds`, `penalty` and `equal_within_cluster`, applied
  within each domain. NULL (default) calibrates globally, as before.

- cluster:

  (only method = "linear") name of the cluster id column (e.g.
  "household"), for equal weights within the cluster.

- equal_within_cluster:

  (only method = "linear") logical. If TRUE, Lemaitre-Dufour (1987)
  integrative calibration: a single weight per cluster. Requires
  `cluster`. Final weights are equal within the cluster provided the
  incoming weight is also uniform within the cluster. Works with any
  `calfun` distance ("linear", "raking" or "logit"), with `bounds` and
  with `by`.

- calfun:

  (only method = "linear") distance function for the calibration factor
  g: "linear" (g = 1 + u, closed form), "raking" (g = exp(u), the
  exponential/multiplicative distance, which keeps the weights positive
  and still satisfies the constraints exactly) or "logit" (bounded by
  construction; requires `bounds`). "raking" and "logit" use the
  iterative Deville-Sarndal solver and work with the integrative option
  (`equal_within_cluster`) too.

- bounds:

  (only method = "linear") numeric c(L, U) with L \< 1 \< U. Bounds on
  the calibration factor g (g-weights). With "linear" it truncates; with
  "logit" it is enforced smoothly. Avoids extreme/negative weights
  without a separate trimming step.

- maxit, tol:

  convergence control for raking and bounded calibration.

- penalty:

  (only method = "linear", unbounded) NULL or positive cost(s) for ridge
  (penalized) calibration. A positive scalar applies the same cost to
  every constraint; a named vector sets a cost per constraint (matched
  to the model.matrix columns). The cost is scale-free: a large value
  keeps the constraint (near) exact, a small value relaxes it to control
  extreme weights when there are many auxiliaries. Under ridge the
  achieved totals no longer match the targets exactly; the diagnostics
  report the deviation.

- population:

  (all methods) a
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/dev/reference/reference_sample.md)
  (or a plain frame) from which the calibration targets are computed,
  instead of passing `margins` / `totals`. Give `formula` naming the
  calibration variables; the targets are the design-weighted sums over
  the reference (raking margins, poststratify cells, or linear
  model-matrix totals). If the reference carries replicate weights,
  [`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_weights.md)
  propagates its sampling variance. Not combined with `margins` /
  `totals` or `by`.

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

The calibrated weight is \\w_i = d_i g_i\\, close to the incoming
weights \\d_i\\ and reproducing the totals \\\sum\_{i \in s} w_i
\mathbf{x}\_i = \mathbf{X}\\, with the factor \\g_i\\ minimizing a
distance to \\d_i\\: linear \\g_i = 1 +
\mathbf{x}\_i'\boldsymbol\lambda\\ or exponential ("raking") \\g_i =
\exp(\mathbf{x}\_i'\boldsymbol\lambda)\\. The `penalty` (ridge) relaxes
the exact constraint to steady extreme weights when the auxiliaries are
many or collinear, minimizing \$\$\sum_i \frac{(w_i - d_i)^2}{d_i q_i} +
\frac{1}{s}\sum_j c_j (\hat X_j - X_j)^2,\$\$ where \\c_j\\ is the cost
of missing constraint \\j\\: as \\c_j \to \infty\\ the constraint is met
exactly, as \\c_j \to 0\\ the weights return to \\d_i\\.

## Examples

``` r
# Raking to population margins
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  step_calibrate(method = "raking",
                 margins = list(sex    = c(table(population$sex)),
                                region = c(table(population$region)))) |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)  [nonresponse_1]
#>   2. calibration (raking)  [calibrate_1]
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

# ridge (penalized) calibration: relaxes the targets to control extreme
# weights; a smaller penalty relaxes more. Uses only base R.
pop_tot <- c("(Intercept)" = nrow(population),
             regionSouth = sum(population$region == "South"),
             regionEast  = sum(population$region == "East"),
             regionWest  = sum(population$region == "West"),
             sexM        = sum(population$sex == "M"))
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  step_calibrate(method = "linear", formula = ~ region + sex,
                 totals = pop_tot, penalty = 1) |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)  [nonresponse_1]
#>   2. calibration (linear, ridge)  [calibrate_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base      467    4371  0.236     1.056   442
#>  stage_1_step_nonresponse      270    4371  0.144     1.021   265
#>    stage_2_step_calibrate      270    4438  0.159     1.025   263
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 

# --- Tidy `totals` format (recommended) ---------------------------------
# Post-stratification: give the population counts as a data frame with one or
# more category columns plus a counts column named by `count`.
ps_totals <- as.data.frame(table(region = population$region, sex = population$sex))
weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "poststratify", totals = ps_totals, count = "Freq") |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. calibration (poststratify)  [calibrate_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                   stage n_active sum_wts cv_wts deff_kish n_eff
#>                    base      467    4371  0.236     1.056   442
#>  stage_1_step_calibrate      467    4495  0.306     1.093   427
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 

# Raking: a list of data frames, one per margin.
m_region <- as.data.frame(table(region = population$region))
m_sex    <- as.data.frame(table(sex = population$sex))
weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "raking",
                 totals = list(m_region, m_sex), count = "Freq") |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. calibration (raking)  [calibrate_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                   stage n_active sum_wts cv_wts deff_kish n_eff
#>                    base      467    4371  0.236     1.056   442
#>  stage_1_step_calibrate      467    4495  0.295     1.087   430
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 

# Linear/GREG with mixed auxiliaries: data frames for categoricals (all
# categories) and a single number for a continuous total. weightflow builds
# the model.matrix totals internally, so you never drop a reference category.
resp <- subset(sample_survey, responded == 1)
weighting_spec(resp, base_weights = pw) |>
  step_calibrate(method = "linear", formula = ~ region + sex + income,
                 totals = list(region = m_region, sex = m_sex,
                               income = sum(population$income)),
                 count = "Freq") |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 270 cases
#> Base wts: pw
#> Steps   :
#>   1. calibration (linear)  [calibrate_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                   stage n_active sum_wts cv_wts deff_kish n_eff
#>                    base      270    2582  0.233     1.054   256
#>  stage_1_step_calibrate      270    4495  0.242     1.058   255
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 

# Domain (partitioned) calibration: `by` calibrates independently within each
# domain, each to its own totals. The domain is an extra column in the tidy
# totals, not a term in the formula/margins. Here we rake two margins (sex and
# age group) within each region, which a single global cross could not express.
pop  <- transform(population,
  age_grp = cut(age, c(0, 30, 45, 60, Inf), labels = c("18-30","31-45","46-60","60+")))
samp <- transform(sample_survey,
  age_grp = cut(age, c(0, 30, 45, 60, Inf), labels = c("18-30","31-45","46-60","60+")))
sex_by_region <- as.data.frame(table(region = pop$region, sex     = pop$sex))
age_by_region <- as.data.frame(table(region = pop$region, age_grp = pop$age_grp))
weighting_spec(samp, base_weights = pw) |>
  step_calibrate(method = "raking",
                 totals = list(sex_by_region, age_by_region),
                 count = "Freq", by = "region") |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. calibration (raking)  [calibrate_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                   stage n_active sum_wts cv_wts deff_kish n_eff
#>                    base      467    4371  0.236     1.056   442
#>  stage_1_step_calibrate      467    4495  0.331     1.109   421
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
