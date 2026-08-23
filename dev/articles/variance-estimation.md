# Variance estimation

weightflow computes weights and also estimates their variances. This
vignette shows a few ways to obtain standard errors from a weightflow
recipe, and how they relate: a recipe-aware bootstrap, a survey-package
linearization, and a recipe-aware jackknife.

Throughout, $`U`$ is the population and $`s`$ the sample; $`w_i`$ is the
final weight of unit $`i`$; and a population total is written
$`Y = \sum_{i \in U} y_i`$, estimated by
$`\hat Y = \sum_{i \in s} w_i\,y_i`$. The sample is drawn in clusters:
primary sampling units (PSUs) nested in strata.

## Why the adjustments matter for variance

A weighting recipe rarely stops at the design weight. It redistributes
unknown eligibility, drops out-of-scope units, adjusts for nonresponse
and calibrates to known totals. Each of those stages is *estimated from
the sample*, so each one adds (or, for calibration, often removes)
variability.

A linearization that takes the final weights as fixed and applies the
ultimate-cluster formula ignores that the nonresponse and calibration
steps were themselves estimated. The cleanest way to account for them is
to **re-run the whole recipe on each replicate**, so the replicate
weights carry the variability of every stage.

## Method 1: a PSU bootstrap that re-applies the recipe

[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_weights.md)
resamples primary sampling units (PSUs) with replacement within strata
and re-runs the recipe on each replicate. Pass the **inert** recipe (do
not call
[`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md)
first): the bootstrap preps it once per replicate.

``` r
dat <- sample_one
dat$age_grp <- cut(dat$age, c(0, 30, 45, 60, Inf),
                   labels = c("18-30", "31-45", "46-60", "60+"))
dat$f <- 0.15                    # illustrative first-stage sampling fraction (used later)

spec <- weighting_spec(dat, base_weights = pw) |>
  step_unknown_eligibility(unknown = unknown_elig, by = "region",
                           cluster = "household_id") |>
  step_drop_ineligible(ineligible = ineligible) |>
  step_nonresponse(respondent = hh_responded, method = "weighting_class",
                   by = "region", cluster = "household_id") |>
  step_select_within(prob = p_within) |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = c("region", "sex", "age_grp")) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region)),
                                sex    = c(table(population$sex))))

boot <- bootstrap_weights(spec, replicates = 200, strata = "region",
                          psu = "psu", seed = 2024, progress = FALSE)
boot
#> <weightflow bootstrap>
#>   replicates : 200
#>   units      : 417 (active: 209)
#>   strata     : region
#>   psu        : psu
#>   df         : 44
```

The multiplier is the **Rao-Wu rescaling bootstrap**. Consider a stratum
$`h`$ with $`n_h`$ PSUs, from which $`m_h`$ are drawn with replacement
(by default $`m_h = n_h -
1`$). Let $`t_{hi}^{*}`$ be the number of times PSU $`i`$ is selected in
a replicate. Every unit in that PSU has its weight rescaled by

``` math
\lambda_{hi} = 1 - \sqrt{\tfrac{m_h}{n_h - 1}}
  + \sqrt{\tfrac{m_h}{n_h - 1}}\;\frac{n_h}{m_h}\,t_{hi}^{*},
```

so the replicate weight is $`w_i^{*} = \lambda_{hi}\,w_i`$. The factor
has expectation one over the resampling,
$`\mathbb{E}(\lambda_{hi}) = 1`$, which keeps each replicate
design-unbiased, and the construction never turns it negative, so the
recipe can be re-prepped on every replicate without invalid weights.
Whole PSUs are kept together (every unit in a drawn PSU is retained), as
the design’s clustering requires.

### Estimates with bootstrap standard errors

Writing $`\hat\theta`$ for the point estimate and $`\hat\theta_b`$ for
its value on replicate $`b`$ (each computed from the re-prepped
replicate weights), the bootstrap variance is the average squared
deviation across the $`B`$ replicates,

``` math
\widehat{\operatorname{Var}}(\hat\theta)
  = \frac{1}{B} \sum_{b=1}^{B} \big(\hat\theta_b - \hat\theta\big)^2 .
```

``` r
boot_mean(boot,  "income")     # mean income
#>   estimate       se ci_lower ci_upper
#> 1 21615.21 884.4228 19881.77 23348.65
boot_total(boot, "employed")   # total employed
#>   estimate       se ci_lower ci_upper
#> 1 1927.219 145.0993  1642.83 2211.609
boot_mean(boot,  "employed")   # employment rate
#>    estimate         se  ci_lower  ci_upper
#> 1 0.4287473 0.03228016 0.3654794 0.4920153
```

For any other statistic, pass a function of the weights and the data to
[`bootstrap_estimate()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_estimate.md):

``` r
bootstrap_estimate(boot, function(w, d) {
  ok <- !is.na(d$income) & w > 0
  stats::median(rep(d$income[ok], times = round(w[ok])))   # weighted median (approx.)
})
#>   estimate       se ci_lower ci_upper
#> 1    18136 991.6204 16192.46 20079.54
```

## Method 2: hand the weights to the survey package

[`as_svydesign()`](https://jpferreira33.github.io/weightflow/dev/reference/as_svydesign.md)
builds an ultimate-cluster linearization design from a prepped recipe.
It is fast, but treats the calibration as fixed.

``` r
fitted <- prep(spec)
#> Warning: Missing values in the cell variable(s) `by` were grouped into a
#> '(missing)' cell. Those units are adjusted within their own cell; recode the
#> NAs if that is not intended.
des <- as_svydesign(fitted, ids = "psu", strata = "region")
survey::svymean(~income, des, na.rm = TRUE)
#>         mean     SE
#> income 21615 989.34
```

To keep the recipe’s adjustments in the variance while still using
survey, feed it the bootstrap replicate weights from method 1:

``` r
rep_des <- as_svrepdesign(boot)
survey::svymean(~income, rep_des, na.rm = TRUE)
#>         mean     SE
#> income 21615 884.42
```

This matches `boot_mean(boot, "income")` exactly, because
[`as_svrepdesign()`](https://jpferreira33.github.io/weightflow/dev/reference/as_svydesign.md)
sets `scale = 1 / B`, `rscales = 1` and `mse = TRUE`.

## Replicate weights for a tidyverse workflow

[`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_replicate_weights.md)
attaches the point weight (`.weight`) and the replicate weights (`rep_1`
… `rep_B`) to the active respondents, ready for srvyr.

``` r
df <- collect_replicate_weights(boot)
d_rep <- srvyr::as_survey_rep(df, weights = .weight,
                              repweights = dplyr::starts_with("rep_"),
                              type = "bootstrap", combined.weights = TRUE,
                              scale = 1 / attr(df, "R"), rscales = 1, mse = TRUE)
srvyr::summarise(d_rep, mean_income = srvyr::survey_mean(income, na.rm = TRUE))
#> # A tibble: 1 × 2
#>   mean_income mean_income_se
#>         <dbl>          <dbl>
#> 1      21615.           884.
```

## Method 3: a delete-a-PSU jackknife that re-applies the recipe

The jackknife is the natural sibling of the bootstrap: instead of
resampling PSUs, it **deletes one PSU at a time** and re-runs the whole
recipe, so the replicate weights again carry the variability of every
stage.
[`jackknife_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/jackknife_weights.md)
builds the stratified delete-a-PSU jackknife (JKn) with `strata`/`psu`;
the unstratified JK1 follows from `strata = NULL`.

``` r
jk <- jackknife_weights(spec, strata = "region", psu = "psu", progress = FALSE)
jk
#> <weightflow jackknife>
#>   replicates : 48 (delete-a-PSU)
#>   units      : 417 (active: 209)
#>   strata     : region
#>   psu        : psu
#>   df         : 44

jack_mean(jk,  "income")     # mean income, with the JKn variance
#>   estimate       se ci_lower ci_upper
#> 1 21615.21 944.5971 19763.83 23466.59
jack_total(jk, "employed")   # total employed
#>   estimate       se ci_lower ci_upper
#> 1 1927.219 153.9697 1625.444 2228.994
```

For a total it matches `survey`’s replicate jackknife exactly. As with
the bootstrap, the replicate weights bridge to survey/srvyr through
`as_svrepdesign(jk)`, so any estimand or domain can be estimated
downstream with the recipe’s uncertainty built in.

### Lonely PSUs and parallel replicates

Strata with a single PSU carry no within-stratum resampling information.
By default (`lonely_psu = "certainty"`) they are treated as
self-representing and contribute no variance (a warning is issued).
Setting `lonely_psu = "collapse"` merges the single-PSU strata into a
pseudo-stratum so they are resampled and yield a conservative variance
instead of zero.

Both
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_weights.md)
and
[`jackknife_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/jackknife_weights.md)
also take `cores`: with `cores > 1` the per-replicate re-preps run in
parallel (forking, so serial on Windows). The resampling is drawn up
front from `seed`, so the parallel run is identical to the serial one.

## When the finite-population correction matters

The with-replacement bootstrap above ignores the finite-population
correction (FPC), which is conservative when the first-stage sampling
fraction $`f_h`$ is a material share of the stratum. That is common in
stratified LatAm designs, where some strata are sampled at 10 or 20
percent. Pass the fraction to `bootstrap_weights(fpc = )` as a column
name, a single number, or a vector named by stratum. The correction
folds $`(1 - f_h)`$ into the Rao-Wu rescaling, so `fpc = NULL`
reproduces the uncorrected result exactly.

``` r
boot0 <- bootstrap_weights(spec, replicates = 200, strata = "region",
                           psu = "psu", seed = 2024, progress = FALSE)
bootf <- bootstrap_weights(spec, replicates = 200, strata = "region",
                           psu = "psu", fpc = "f", seed = 2024, progress = FALSE)
c(no_fpc = boot_total(boot0, "employed")$se,
  fpc    = boot_total(bootf, "employed")$se)   # the correction lowers the SE
#>   no_fpc      fpc 
#> 145.0993 127.5785
```

In a validation against the closed-form stratified SRS variance, the
corrected bootstrap SE tracks the analytic SE with FPC (about 940 in
that example) while the uncorrected one tracks the analytic SE without
it (about 970). The gap grows with $`f_h`$. The FPC is a bootstrap
feature; the delete-a-PSU jackknife does not take it.

## Confidence intervals: normal, t and percentile

The estimate functions return a normal interval by default. With few
PSUs the normal interval is anticonservative, so
[`bootstrap_estimate()`](https://jpferreira33.github.io/weightflow/dev/reference/bootstrap_estimate.md)
and
[`jackknife_estimate()`](https://jpferreira33.github.io/weightflow/dev/reference/jackknife_estimate.md)
also offer `ci_type = "t"`, which uses the design degrees of freedom
(`df` = total PSUs minus strata, stored on the object and shown by
[`print()`](https://rdrr.io/r/base/print.html)). The bootstrap
additionally offers `ci_type = "percentile"`, the empirical quantiles of
the valid replicates.

``` r
emp <- function(w, d) sum(w * d$employed, na.rm = TRUE)
bootstrap_estimate(boot, emp)                          # normal (default)
#>   estimate       se ci_lower ci_upper
#> 1 1927.219 145.0993  1642.83 2211.609
bootstrap_estimate(boot, emp, ci_type = "t")           # t: wider, uses df
#>   estimate       se ci_lower ci_upper
#> 1 1927.219 145.0993 1634.791 2219.648
bootstrap_estimate(boot, emp, ci_type = "percentile")  # empirical quantiles
#>   estimate       se ci_lower ci_upper
#> 1 1927.219 145.0993 1691.042 2227.439
```

Rough guide:

- **normal**: the default; fine with many PSUs.
- **t**: few PSUs (the usual jackknife regime); wider and less
  anticonservative.
- **percentile**: skewed statistics; bootstrap only, and it needs enough
  valid replicates (a warning fires below about 50).

## Estimated control totals

When a step calibrates to a
[`reference_sample()`](https://jpferreira33.github.io/weightflow/dev/reference/reference_sample.md)
instead of a census frame, the control totals are themselves estimated,
and that adds a variance component. The bootstrap propagates it if you
pass the reference survey’s replicate weights; see
[`vignette("reference-survey")`](https://jpferreira33.github.io/weightflow/dev/articles/reference-survey.md)
for the full setup and why only the bootstrap carries this component.

## Which one to use

Use the **recipe-aware bootstrap** (method 1, in any of its three forms)
when the nonresponse and calibration steps are a meaningful part of the
design and you want their uncertainty reflected; it is the more honest
variance. Use the **linearization** (method 2) for a quick,
well-understood standard error when the adjustments are minor or you
only need the design-and-clustering part. The **jackknife** (method 3)
is the recipe-aware alternative to the bootstrap when a deterministic,
replicate-based variance is preferred; it matches `survey`’s replicate
jackknife for totals.

A few practical notes. More replicates give a more stable bootstrap SE;
200 is fine for exploration, 500-1000 for final figures. Each stratum
needs at least two PSUs to be resampled (single-PSU strata are left
untouched, with a warning). If a replicate leaves a calibration or
weighting-class cell empty it is dropped with a warning; coarser `by`
cells make the bootstrap more robust.
