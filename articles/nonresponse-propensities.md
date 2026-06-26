# Nonresponse: weighting classes and propensities

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
estimated by the (weighted) response rate within the cell — a single
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
#>   1. nonresponse (weighting class)
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
#>   1. nonresponse (propensity: logit, 5 classes)
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
#> [1] 1.12651
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
#> [1] 1.050402
```

The *Machine learning, cross-fitting and robust calibration* article
develops the boosting engine and cross-fitting in full, with a worked
comparison of the design effect with and without cross-fitting.

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

## Which to use

Weighting classes need categorical auxiliaries and enough respondents
per cell; they are simple and transparent. Propensity models handle
continuous predictors and many auxiliaries at once, and the tree/forest
engines relax functional-form assumptions. Using propensity classes
(`num_classes`) rather than the direct $`1/\hat\phi_i`$ keeps the
adjustment stable when the model is imperfect, at the cost of some
efficiency. In all cases, model the response on auxiliaries that are
both predictive of responding and related to the survey outcomes.
