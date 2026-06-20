# Staged survey weighting: the adjustment logic

Survey weighting turns a sample into estimates for a population. It
starts from the design and then corrects, one stage at a time, for
everything that pulls the realized sample away from the target
population: addresses that could not be resolved, units out of scope,
subsampling inside households, nonresponse, and coverage. weightflow
expresses that chain as a pipeline of explicit steps. This vignette
walks the logic of each stage, why it exists, and why the order matters.

## The starting point: design weights

Under a probability design, unit `i` enters the sample with a known
inclusion probability `pi_i`. The design (base) weight is its inverse,

    d_i = 1 / pi_i,

so the Horvitz-Thompson estimator of a total, `sum(d_i * y_i)` over the
sample, is unbiased for the population total. Every later stage
multiplies this weight by a correction factor; the recipe is just the
product of those factors, applied in order. We use the bundled
multistage sample:

``` r
dat <- sample_one
dat$age_grp <- cut(dat$age, c(0, 30, 45, 60, Inf),
                   labels = c("18-30", "31-45", "46-60", "60+"))
```

## The cascade

### Unknown eligibility

Some sampled addresses are never resolved — you cannot tell whether they
were in scope. Discarding them would lose their share of the population;
keeping them as if eligible would overstate it. The standard fix
redistributes their weight over the resolved cases (eligible **and**
ineligible) within cells, so the resolved units carry the unresolved
share. When the unknowns arrive without a roster, this is done at the
household level (`cluster`).

### Ineligible units

Resolved out-of-scope units (vacant addresses, non-residential) are
simply removed — their weight goes to zero with no redistribution. They
must be present during the unknown-eligibility step (so they absorb
their share) and only then dropped.

### Within-household selection

When one person is selected per household, that person represents all
the eligible persons there. The weight is multiplied by the inverse of
the within-household selection probability (`prob`), or by the number of
eligibles (`n_eligible`) under equal selection.

### Nonresponse

Not everyone responds. Under the assumption that response is ignorable
given the auxiliaries used (missing at random within cells or given the
model), the respondents are inflated to represent the nonrespondents —
either with weighting classes or a response-propensity model, at the
person or household level. The *Nonresponse* article covers this stage
in detail.

### Calibration

Finally, auxiliary totals known for the whole population (here, region
and sex counts) are used to force the weighted sample to match them.
Calibration reduces coverage bias and, when the auxiliaries are related
to the outcomes, lowers variance; it is the weighting counterpart of the
generalized regression (GREG) estimator. The *Validation* article shows
weightflow’s calibration reproduces the `survey` package.

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

Adjustments can create a few very large weights, which inflate the
variance. Trimming caps them (and redistributes the excess) to trade a
little bias for a worthwhile variance reduction; the bias-variance
trade-off of trimming is a classic topic (Potter). Rounding and
rescaling are presentational: integer weights, or weights that sum to
the sample size (mean one) or to a chosen total.

A caveat on order: trimming after calibration preserves the overall
total but can perturb the calibrated margins slightly, so a rigorous
workflow re-calibrates after trimming.

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

The Kish design effect, `deff = 1 + CV^2` (with `CV` the coefficient of
variation of the weights), measures how much unequal weighting inflates
the variance; the effective sample size is `n_eff = n_active / deff`.
Each adjustment tends to *raise* the design effect (it makes the weights
more unequal) and trimming brings it back down. The per-stage summary
shows the whole trajectory:

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

The sequence is not arbitrary. Unknown eligibility comes first, so
ineligibles are still present to absorb their share before being
dropped. Household nonresponse precedes within-household selection (the
household must be reached before a person is selected), and person
nonresponse follows it. Calibration comes last, so it operates on
weights that already reflect eligibility, selection and response.
Trimming and presentational steps close the pipeline. weightflow makes
this order explicit — it is simply the order in which you pipe the steps
— and records what each one did, which you can inspect with
[`summary()`](https://rdrr.io/r/base/summary.html),
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) and
[`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md).
For standard errors that respect the whole cascade, see the *Variance
estimation* article.
