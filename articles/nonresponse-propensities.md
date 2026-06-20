# Nonresponse: weighting classes and propensities

Nonresponse adjustment inflates the weights of respondents so they also
represent the nonrespondents.
[`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)
offers two routes: weighting classes and response propensity models.
This vignette explains both, when each is preferable, and how they are
estimated.

Throughout, only **active** units (weight \> 0) take part, so cases
already dropped earlier in the recipe (unknown eligibility, ineligible)
are excluded automatically.

## Weighting classes

Units are grouped into cells defined by `by`, and within each cell the
respondents absorb the weight of the nonrespondents. The adjustment
factor in a cell `c` is

    f_c = ( sum of weights of all active units in c ) /
          ( sum of weights of the respondents in c )

Each respondent’s weight is multiplied by `f_c`; nonrespondents go to
zero.

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
auxiliaries known for respondents and nonrespondents alike:

    p_i = P(respond | x_i)

The model is fitted **on the active units, weighted by the current
weights**, and two routes follow. With `num_classes = NULL`, each
respondent is weighted by the inverse propensity, `w_i* = w_i / p_i`.
With an integer `num_classes`, units are grouped into that many
propensity classes and a weighting-class adjustment is applied within
each, which is more robust to a misspecified model.

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

### Trees and forests

The same propensity can be estimated with a regression tree
(`engine = "tree"`, package **rpart**) or a random forest
(`engine = "forest"`, package **ranger**), which capture nonlinearities
and interactions without specifying them. More flexibility is not free,
though: a very flexible model can overfit the response and produce more
dispersed adjustment factors, which *raises* the variance of the weights
(a higher design effect). Compare the `deff` after each engine below —
the forest typically yields the largest, the weighting classes the
smallest.

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
households — not persons — are the independent units being adjusted.

## Which to use

Weighting classes need categorical auxiliaries and enough respondents
per cell; they are simple and transparent. Propensity models handle
continuous predictors and many auxiliaries at once, and the tree/forest
engines relax functional-form assumptions. Using propensity **classes**
(`num_classes`) rather than the direct `1 / p` keeps the adjustment
stable when the model is imperfect, at the cost of some efficiency. In
all cases, model the response on auxiliaries that are both predictive of
responding and related to the survey outcomes.
