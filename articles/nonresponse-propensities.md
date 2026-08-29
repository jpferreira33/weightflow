# Nonresponse: weighting classes, propensities and calibration

Nonresponse adjustment inflates the weights of respondents so they also
represent the nonrespondents.
[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
offers two routes: weighting classes and response propensity models.
This vignette explains both, when each is preferable, and how they are
estimated.

Throughout, only active units (weight \> 0) take part, so cases already
dropped earlier in the recipe (unknown eligibility, ineligible) are
excluded automatically. We write $`w_i`$ for the weight entering the
step, $`r`$ for the set of respondents, $`\mathbf{x}_i`$ for the
auxiliaries known for unit $`i`$, and $`w_i^{\mathrm{nr}}`$ for the
weight after the adjustment.

Both routes rest on the same assumption: response is ignorable given the
auxiliaries (missing at random). That is, conditional on
$`\mathbf{x}_i`$, responding is independent of the survey outcome
$`y_i`$,

``` math
P(\text{respond} \mid \mathbf{x}_i, y_i) = P(\text{respond} \mid \mathbf{x}_i)
  = \phi_i .
```

Under this assumption the respondents, reweighted by the inverse of
their response propensity $`\phi_i`$, represent the nonrespondents
without bias. Choosing auxiliaries that are related both to responding
and to the outcomes is therefore what makes the adjustment work.

## Weighting classes

Units are partitioned into cells (the *weighting classes*) according to
one or more categorical auxiliaries, and within each cell the
respondents absorb the weight of the nonrespondents. The method rests on
a homogeneity assumption: every unit in a cell is taken to have the same
response probability, so that within the cell the respondents are a
random subsample of the active units (response is MCAR within the cell,
MAR across cells). Equivalently, it is a model in which the expected
outcome is the same for respondents and nonrespondents of the same cell;
the adjustment removes bias to the extent that this within-cell equality
holds. Cells should therefore be chosen so that response rates differ
between cells while the units inside a cell are homogeneous (i.e.,
similar in their propensity to respond and, ideally, in the survey
outcomes).

This adjustment is the natural choice when nothing is known about the
nonrespondents beyond what the sampling frame already carries (e.g.,
strata, primary sampling units, region, and other design variables
available for sampled respondents and nonrespondents alike). When the
auxiliaries are known for the whole population rather than only the
sample, the same arithmetic becomes post-stratification.

The adjustment factor in a cell $`c`$ is the total weight of the active
units over the weight of the respondents in that cell,

``` math
f_c = \frac{\sum_{i \in c} w_i}{\sum_{i \in c \cap r} w_i} .
```

Each respondent’s weight is multiplied by $`f_c`$ and nonrespondents go
to zero, so $`w_i^{\mathrm{nr}} = f_c\,w_i`$ for $`i \in c \cap r`$.
This is the special case of a propensity model in which $`\phi_i`$ is
estimated by the (weighted) response rate within the cell: a single
estimated propensity shared by every unit of the cell.

In
[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
the cells are specified through the `by` argument, which names the
categorical variables that define them (here, `region`):

``` r

wf <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = "region") |>
  prep()
summary(wf)
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)  [nonresponse_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base      467    4371  0.236     1.056   442
#>  stage_1_step_nonresponse      270    4371  0.144     1.021   265
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
#> --- Step 1: nonresponse (weighting class) ---
#>   cell n_respondents n_nonresponse   factor
#>   East            52            44 1.846154
#>  North            78            41 1.525641
#>  South            72            49 1.680556
#>   West            68            63 1.926471
#> Kish deff: 1.056 -> 1.021   |   n_eff: 442 -> 265
#> 
#> R-indicator (representativity of response): 0.892  (on region)
```

**Validation.** By construction the total weight is preserved *within
each cell* (the nonrespondents’ weight is moved to the respondents, not
lost). So the weighted total per region after the step equals the
base-weight total before it:

``` r

before <- tapply(sample_survey$pw,  sample_survey$region, sum)
after  <- tapply(wf$final_weight,   sample_survey$region, sum)
round(cbind(before, after, diff = after - before), 6)
#>          before     after diff
#> North 1487.5000 1487.5000    0
#> South 1210.0000 1210.0000    0
#> East   800.0000  800.0000    0
#> West   873.3333  873.3333    0
```

The differences are zero: weighting classes redistribute, they do not
create or destroy weight.

## Response propensities

Instead of cells, the probability of responding is modelled from
auxiliaries known for respondents and nonrespondents alike,

``` math
\phi_i = P(\text{respond} \mid \mathbf{x}_i),
```

and estimated by $`\hat\phi_i`$. The model is fitted on the active
units, weighted by the current weights, and two routes follow. With
`num_classes = NULL`, each respondent is weighted by the inverse
propensity, $`w_i^{\mathrm{nr}}
= w_i / \hat\phi_i`$. With an integer `num_classes`, units are grouped
into that many classes formed from quantiles of $`\hat\phi_i`$ and a
weighting-class adjustment is applied within each, which is more robust
to a misspecified model.

### Logistic regression

``` r

wf <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "propensity",
                   formula = ~ region + sex + age, engine = "logit",
                   num_classes = 5) |>
  prep()
summary(wf)
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
#>  stage_1_step_nonresponse      270    4371  0.155     1.024   264
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
#> --- Step 1: nonresponse (propensity: logit, 5 classes) ---
#>  propensity_class   n mean_prop   factor
#>     [0.499,0.524]  94 0.5122335 2.224138
#>     (0.524,0.547]  93 0.5341818 1.837719
#>     (0.547,0.594] 101 0.5721654 1.602273
#>     (0.594,0.643]  86 0.6162161 1.574468
#>     (0.643,0.684]  93 0.6600845 1.576271
#> Kish deff: 1.056 -> 1.024   |   n_eff: 442 -> 264
#> 
#> R-indicator (representativity of response): 0.889  (on region, sex, age)
```

Because the model is fitted with survey weights, a logistic fit may
print a “non-integer \#successes” message: that is expected for a
weighted binomial fit and does not affect the estimated propensities.

### Trees, forests and boosting

The same propensity can be estimated with a regression tree
(`engine = "tree"`, package `rpart`), a random forest
(`engine = "forest"`, package `ranger`), or gradient boosting
(`engine = "boost"`, package `xgboost`), which capture nonlinearities
and interactions without specifying them. More flexibility is not free,
though: a very flexible model can overfit the response and produce more
dispersed adjustment factors, which raises the variance of the weights
(a higher design effect). Compare the deff after each engine below, the
forest and boosting typically yield the largest, the weighting classes
the smallest.

``` r

wf <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "propensity",
                   formula = ~ region + sex + age, engine = "tree",
                   num_classes = 5) |>
  prep()
design_effect(wf$final_weight)$deff
#> [1] 1.055763
```

``` r

wf <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "propensity",
                   formula = ~ region + sex + age, engine = "forest",
                   num_classes = 5) |>
  prep()
design_effect(wf$final_weight)$deff
#> [1] 1.11675
```

### Flexibility, overfitting, and cross-fitting

The reason flexibility is not free deserves a closer look. A very
flexible model can fit the *noise* of the particular sample in addition
to the signal (overfitting). When the propensity is then predicted for
the very units the model was trained on, the estimates $`\hat\phi_i`$
are pulled toward the observed responses: some respondents receive
artificially low propensities, and since the adjustment is
$`1/\hat\phi_i`$, those units get extreme weights that inflate the
variance. The model is not bad at prediction; i.e., it predicts too well
in-sample and poorly out of it.

The remedy is **cross-fitting**: estimate each unit’s propensity with a
model trained on *other* units (held-out folds), so the prediction is
out-of-sample and free of this optimism. weightflow provides it through
the `crossfit` argument:

``` r

wf <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "propensity",
                   formula = ~ region + sex + age, engine = "forest",
                   num_classes = 5, crossfit = 5, crossfit_seed = 1) |>
  prep()
design_effect(wf$final_weight)$deff
#> [1] 1.051409
```

The *Machine learning, cross-fitting and robust calibration* article
develops the boosting engine and cross-fitting in full, with a worked
comparison of the design effect with and without cross-fitting.

### Weighting the propensity model

By default the propensity model is fitted using the weights that enter
the step, that is, the base design weights or the weights already
adjusted by earlier steps in the cascade (unknown eligibility, an
earlier nonresponse stage). Setting `weight_model = FALSE` fits it
unweighted, so those incoming weights enter only the $`1/\hat\phi_i`$
adjustment and not the model fit. Fitting unweighted can lower the
variance of the propensity estimates when the incoming weights are
unrelated to response given the covariates, at the cost of possible bias
if they are related (Little and Vartivarian 2003). Only the model fit
changes; the adjustment always uses the incoming weights.

``` r

f <- function(wm) weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "propensity",
                   formula = ~ region + sex + age, engine = "logit",
                   num_classes = NULL, weight_model = wm) |>
  prep()
c(weighted   = design_effect(f(TRUE)$final_weight)$deff,
  unweighted = design_effect(f(FALSE)$final_weight)$deff)
#>   weighted unweighted 
#>   1.021551   1.022794
```

## Person or household level

Nonresponse can occur at the person level (within a reached household)
or at the household level (the whole household is not reached). The
`cluster` argument moves the adjustment to the household: each household
counts once with its weight, and the redistribution (or the propensity
model) is done over households, then assigned to their members.

``` r

wf <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = "region", cluster = "household_id") |>
  prep()
design_effect(wf$final_weight)$deff
#> [1] 1.06383
```

The level is dictated by what is known about the nonrespondents:
household auxiliaries and a whole-household outcome call for `cluster`;
person-level auxiliaries within reached households do not. Note that the
effective sample size drops more at the household level, since
households (not persons) are the independent units being adjusted.

## Nonresponse by calibration

A third route calibrates the respondents’ weights so that, over the
auxiliaries, they reproduce the totals the active units (respondents and
nonrespondents) carried before the step. With `method = "calibration"`
and `totals = NULL` (the default) the targets are those incoming,
design-weighted totals, so the adjustment is the two-phase, sample-level
calibration estimator (Sarndal and Lundstrom 2005): the calibrated
respondent estimates reproduce the pre-nonresponse cascade estimates
exactly. Supply `totals` to calibrate to external population totals
instead.

``` r

wf <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "calibration",
                   formula = ~ region + sex) |>
  prep()
summary(wf)
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
#> --- Step 1: nonresponse (calibration: linear, sample-level) ---
#>     variable    target achieved
#>  (Intercept) 4370.8333  4370.83
#>  regionSouth 1210.0000  1210.00
#>   regionEast  800.0000   800.00
#>   regionWest  873.3333   873.33
#>         sexM 2284.1667  2284.17
#> nonresponse calibration to sample-level totals; g in [1.491, 1.950] 
#> Kish deff: 1.056 -> 1.021   |   n_eff: 442 -> 264
#> 
#> R-indicator (representativity of response): 0.890  (on region, sex)
```

Validation. The respondents, reweighted, reproduce the auxiliary totals
of all active units before the step:

``` r

X      <- model.matrix(~ region + sex, sample_survey)
resp   <- sample_survey$responded == 1
before <- colSums(sample_survey$pw * X)               # respondents + nonrespondents
after  <- colSums(wf$final_weight[resp] * X[resp, ])  # respondents, calibrated
round(rbind(before, after, diff = after - before), 4)
#>        (Intercept) regionSouth regionEast regionWest     sexM
#> before    4370.833        1210        800   873.3333 2284.167
#> after     4370.833        1210        800   873.3333 2284.167
#> diff         0.000           0          0     0.0000    0.000
```

The distance (`calfun`), `bounds` and ridge `penalty` carry over from
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md).
With `equal_within_cluster = TRUE` and a `cluster` the adjustment is
integrative: the responding members of a household share one calibration
factor, so the weights stay constant within household.

``` r

wf <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "calibration",
                   formula = ~ region, cluster = "household_id",
                   equal_within_cluster = TRUE) |>
  prep()
design_effect(wf$final_weight)$deff
#> [1] 1.020774
```

## Which to use

Weighting classes need categorical auxiliaries and enough respondents
per cell; they are simple and transparent. Propensity models handle
continuous predictors and many auxiliaries at once, and the tree/forest
engines relax functional-form assumptions. Using propensity classes
(`num_classes`) rather than the direct $`1/\hat\phi_i`$ keeps the
adjustment stable when the model is imperfect, at the cost of some
efficiency. In all cases, model the response on auxiliaries that are
both predictive of responding and related to the survey outcomes.

## See also

To recover the fitted propensities and see, unit by unit, what the
adjustment did, use
[`collect_propensities()`](https://jpferreira33.github.io/weightflow/reference/collect_propensities.md)
and
[`collect_step_detail()`](https://jpferreira33.github.io/weightflow/reference/collect_step_detail.md);
the full quality-control flow is in
[`vignette("inspecting-auditing")`](https://jpferreira33.github.io/weightflow/articles/inspecting-auditing.md).
