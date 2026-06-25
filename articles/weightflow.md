# Staged survey weighting: the adjustment logic

Survey weights are the fundamental input used to produce population
estimates from sample data. Let $`U={1,\ldots,N}`$ denote the target
population and let $`y_i`$ be the value of a study variable for unit
($`i`$). A common objective is to estimate finite population quantities
such as the total

``` math
Y=\sum_{i \in U} y_i, 
```

or functions derived from it (e.g., means, proportions, and ratios).
Survey weighting provides the mechanism for translating information
observed in the sample into estimates for these population quantities.

The process starts from the sample design and then sequentially adjusts
for the mechanisms that cause the realized sample to differ from the
target population. Some adjustments aim to reduce potential selection
biases in the effective sample (i.e., eligible responding units) by
modeling mechanisms such as response propensities. Other adjustments
incorporate auxiliary information to improve precision and ensure
consistency with known population counts or totals through techniques
such as calibration. Together, these steps transform the initial design
weights into analysis weights suitable for population inference.

`weightflow` expresses the weighting process as a reproducible pipeline
of explicit steps. Each step corresponds to a well defined adjustment,
records how weights are modified, and passes its output to the next
stage in the workflow. This vignette explains the purpose of each
adjustment, the statistical reasoning behind it, and why the order of
the steps matters.

## The starting point: design weights

Under a probability design, unit $`i`$ enters the sample ($`s`$) with a
known inclusion probability $`\pi_i`$. The design (base) weight is its
inverse,
``` math
w_i^{0} =\frac{1}{\pi_i}
```

Under ideal conditions, the Horvitz-Thompson estimator,

``` math
\hat{Y}_{HT}=\sum_{i\in s}w_i^{0} \times y_i,
```

is unbiased for the population total. These conditions include a
sampling frame that perfectly covers the target population $`U`$,
correct inclusion probabilities, and complete response from all selected
units. In practice, however, surveys rarely satisfy these assumptions.
Frames may contain coverage errors, some sampled units may be found
ineligible, and nonresponse typically reduces the effective sample. As a
result, additional weighting adjustments are often required to mitigate
potential biases and improve the quality of the resulting estimates.

Every subsequent stage modifies the base weight through a multiplicative
adjustment factor. The final analysis weight is therefore obtained as
the product of all adjustment factors applied in sequence. We use the
bundled multistage sample:

``` r
dat <- sample_one
dat$age_grp <- cut(dat$age, c(0, 30, 45, 60, Inf),
                   labels = c("18-30", "31-45", "46-60", "60+"))
```

## The cascade

Starting from the design weights, each stage addresses a specific
departure from the ideal conditions under which design based estimators
are unbiased. Some adjustments aim to reduce potential selection biases
arising because the effective sample differs from the original
probability sample. These adjustments often increase weight variability
and, consequently, the standard errors of survey estimates. Other
adjustments incorporate auxiliary information $`x`$ to improve
efficiency and align estimates with known population totals. The
weighting process therefore involves balancing bias reduction against
variance inflation.

### Unknown eligibility

Some sampled units are never resolved, making it impossible to determine
whether they belong to the target population. Ignoring them would
implicitly assume they represent no population units, while treating
them all as eligible would overestimate the target population size. The
standard solution redistributes their weight among resolved cases
(eligible and ineligible, i.e., out-of-scope units) within adjustment
cells, allowing resolved units to represent the unresolved share. This
adjustment seeks to reduce potential bias arising from unresolved cases,
although the resulting increase in weight variability may inflate
standard errors. When the unknowns arrive without a roster, this is done
at the household level (`cluster`).

### Ineligible units

Resolved out of scope units (e.g., vacant dwellings or non residential
addresses) do not belong to the target population and therefore receive
zero weight. They must remain in the data during the unknown eligibility
adjustment so they absorb their share of unresolved cases before being
removed. This step primarily ensures that estimation targets the correct
population.

### Within-household selection

When only one person is selected within a sampled household, that person
must represent all eligible persons in the household. The weight is
therefore multiplied by the inverse of the within household selection
probability (`prob`) or, under equal probability selection, by the
number of eligible persons (`n_eligible`). This adjustment restores the
original selection probabilities implied by the sampling design.

### Nonresponse

Not all sampled units provide data. If respondents and nonrespondents
differ systematically, estimates based only on respondents may be
biased. Under the assumption that response is ignorable conditional on
observed auxiliary variables, respondents are inflated to represent
nonrespondents using weighting classes or response propensity models.
These adjustments can substantially reduce nonresponse bias but
typically increase weight variability and may lead to larger standard
errors. They can be applied at either the household or person level. The
*Nonresponse* article covers this stage in detail.

### Calibration

Finally, auxiliary information available for the entire population is
used to align the weighted sample with known population totals. In this
example, calibration forces agreement with known counts by region and
sex. Besides improving consistency with external benchmarks, calibration
can reduce coverage bias and increase precision when the calibration
variables are associated with the survey outcomes. Unlike many
nonresponse adjustments, calibration often reduces variance while
simultaneously improving accuracy. From a design based perspective,
calibration is closely related to the generalized regression (GREG)
estimator. The Validation article shows that weightflow reproduces the
calibration results obtained with the survey package.The *Validation*
article shows weightflow’s calibration reproduces the `survey` package.

``` r
fitted <- weighting_spec(dat, base_weights = pw) |>
  step_unknown_eligibility(unknown = unknown_elig, by = "region") |>
  step_drop_ineligible(ineligible = ineligible) |>
  step_nonresponse(respondent = hh_responded, method = "weighting_class",
                   by = "region") |>
  step_select_within(prob = p_within) |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = c("region", "sex", "age_grp")) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region)),
                                sex    = c(table(population$sex)))) |>
  prep()
```

### Trimming, rounding, rescaling

Weighting adjustments can sometimes produce a small number of extremely
large weights. While these weights may help reduce bias, they can
substantially increase the variance of survey estimates and inflate
design effects.

Trimming limits extreme weights, typically by capping them and
redistributing the excess weight among other units. This introduces a
controlled amount of bias in exchange for potentially meaningful
reductions in variance, a classic bias-variance trade-off in survey
weighting (e.g., Potter, 1990).

Rounding and rescaling serve different purposes. They do not alter the
underlying adjustment logic but make weights easier to interpret,
report, or use operationally. Common examples include integer weights,
weights that sum to the sample size, or weights scaled to a known
population total.

A final consideration is the order of operations. Trimming performed
after calibration generally preserves the overall weight total but may
disturb the calibrated margins. For this reason, a rigorous workflow
typically re-calibrates the weights after trimming to restore
consistency with the auxiliary population totals.

``` r
trimmed <- weighting_spec(dat, base_weights = pw) |>
  step_unknown_eligibility(unknown = unknown_elig, by = "region") |>
  step_drop_ineligible(ineligible = ineligible) |>
  step_nonresponse(respondent = hh_responded, method = "weighting_class",
                   by = "region") |>
  step_select_within(prob = p_within) |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = c("region", "sex", "age_grp")) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region)),
                                sex    = c(table(population$sex)))) |>
  step_trim_weights() |>
  prep()
```

## Reading the cascade: the design effect

The Kish design effect,

``` math
deff = 1 + CV^2,
```

where $`CV`$ is the coefficient of variation of the weights, quantifies
the variance inflation attributable to unequal weighting. An approximate
effective sample size can be obtained as

``` math
n_{eff} = \frac{n_{active}}{deff}.
```

Many weighting adjustments, particularly those addressing eligibility,
within household selection, and nonresponse, increase weight variability
and therefore tend to increase the design effect. Calibration may either
increase or decrease weight dispersion depending on the auxiliary
information used and the calibration constraints. Trimming typically
reduces the design effect by limiting extreme weights, trading a small
amount of bias for a potentially substantial reduction in variance.

The per stage summary provides a useful diagnostic of this process,
showing how each adjustment modifies the weight distribution and how the
cumulative weighting strategy affects both effective sample size and
variance inflation:

``` r
summary(fitted)
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 417 cases
#> Base wts: pw
#> Steps   :
#>   1. unknown eligibility
#>   2. drop ineligible
#>   3. nonresponse (weighting class)
#>   4. within-household selection
#>   5. nonresponse (weighting class)
#>   6. calibration (raking)
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                             stage n_active sum_wts cv_wts deff_kish n_eff
#>                              base      417    2182  0.238     1.057   395
#>  stage_1_step_unknown_eligibility      394    2182  0.234     1.055   374
#>      stage_2_step_drop_ineligible      365    2023  0.232     1.054   346
#>          stage_3_step_nonresponse      315    2023  0.197     1.039   303
#>        stage_4_step_select_within      315    4611  0.678     1.460   216
#>          stage_5_step_nonresponse      209    4611  0.714     1.510   138
#>            stage_6_step_calibrate      209    4495  0.740     1.548   135
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
#> --- Step 1: unknown eligibility ---
#>   cell  level n_known n_unknown   factor
#>   East person      56         7 1.125000
#>  North person     127         8 1.062992
#>  South person      97         2 1.020619
#>   West person     114         6 1.052632
#> Kish deff: 1.057 -> 1.055   |   n_eff: 395 -> 374
#> 
#> --- Step 2: drop ineligible ---
#>  n_dropped weight_dropped n_remaining
#>         29         159.22         365
#> Kish deff: 1.055 -> 1.054   |   n_eff: 374 -> 346
#> 
#> --- Step 3: nonresponse (weighting class) ---
#>   cell n_respondents n_nonresponse   factor
#>   East            46             8 1.173913
#>  North           105            11 1.104762
#>  South            79            13 1.164557
#>   West            85            18 1.211765
#> Kish deff: 1.054 -> 1.039   |   n_eff: 346 -> 303
#> 
#> --- Step 4: within-household selection ---
#>   using mean_factor min_factor max_factor
#>  1/prob        2.26          1      9.052
#> Kish deff: 1.039 -> 1.460   |   n_eff: 303 -> 216
#> 
#> --- Step 5: nonresponse (weighting class) ---
#>               cell n_respondents n_nonresponse   factor
#>   East | F | 18-30             2             6 4.824394
#>   East | F | 31-45             5             0 1.000000
#>   East | F | 46-60             9             0 1.000000
#>     East | F | 60+             2             1 2.006549
#>   East | M | 18-30             2             2 3.308144
#>   East | M | 31-45             2             3 2.279092
#>   East | M | 46-60             6             1 1.167901
#>     East | M | 60+             4             1 1.114621
#>  North | F | 18-30             7             2 1.219400
#>  North | F | 31-45            12             7 1.436311
#>  North | F | 46-60            12             6 1.524781
#>    North | F | 60+             5             1 1.076659
#>  North | M | 18-30            12             4 1.253068
#>  North | M | 31-45             8             6 1.900951
#>  North | M | 46-60            10             4 1.230544
#>    North | M | 60+             9             0 1.000000
#>  South | F | 18-30             4             3 1.447426
#>  South | F | 31-45             4             4 2.076124
#>  South | F | 46-60             7             6 1.823142
#>    South | F | 60+             4             9 2.808928
#>  South | M | 18-30             4             4 1.848702
#>  South | M | 31-45             9             4 1.444650
#>  South | M | 46-60            12             3 1.360523
#>    South | M | 60+             2             0 1.000000
#>   West | F | 18-30             5             3 2.847808
#>   West | F | 31-45            14             7 1.547330
#>   West | F | 46-60             4             3 1.965820
#>     West | F | 60+             9             4 1.245591
#>   West | M | 18-30             5             5 2.197804
#>   West | M | 31-45            12             2 1.192805
#>   West | M | 46-60             3             3 2.005306
#>     West | M | 60+             4             2 1.499946
#> Kish deff: 1.460 -> 1.510   |   n_eff: 216 -> 138
#> 
#> --- Step 6: calibration (raking) ---
#>  variable category target achieved
#>    region    North   1570     1570
#>    region    South   1250     1250
#>    region     East    927      927
#>    region     West    748      748
#>       sex        F   2311     2311
#>       sex        M   2184     2184
#> (converged/iterated in 4 iterations)
#> Kish deff: 1.510 -> 1.548   |   n_eff: 138 -> 135
```

And the effect of trimming on the final design effect:

``` r
c(no_trim = design_effect(fitted$final_weight)$deff,
  trimmed = design_effect(trimmed$final_weight)$deff)
#>  no_trim  trimmed 
#> 1.547642 1.499494
```

## Why the order matters

The sequence of weighting adjustments is not arbitrary. Each step
defines the population, weights, and assumptions that underpin the next
one.

Unknown eligibility must be addressed before ineligible units are
removed, so that resolved cases (including out of scope units) absorb
their appropriate share of unresolved cases. Household nonresponse
adjustments precede within household selection because a household must
first be contacted before an individual can be selected and interviewed.
Person level nonresponse adjustments naturally follow the within
household selection step, since they operate on the set of sampled
persons.

Calibration is typically performed near the end of the process because
it uses auxiliary information to align weights that already reflect
eligibility, selection, and response mechanisms. If trimming is applied
after calibration, a subsequent calibration step may be required to
restore agreement with the population totals.

In **weightflow**, this logic is made explicit through the weighting
pipeline itself. The order of operations is the order in which the steps
are applied, making the weighting process transparent, reproducible, and
easy to audit. The contribution of each stage can be examined through
[`summary()`](https://rdrr.io/r/base/summary.html),
[`plot()`](https://rdrr.io/r/graphics/plot.default.html), and
[`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md),
which document how weights evolve across the cascade. For variance
estimation methods that account for the full weighting process, see the
*Variance estimation* article.
