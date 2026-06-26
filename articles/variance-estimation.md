# Variance estimation

weightflow computes weights and also estimates their variances. This
vignette shows two ways to obtain standard errors from a weightflow
recipe, and how they relate.

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

[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
resamples primary sampling units (PSUs) with replacement within strata
and re-runs the recipe on each replicate. Pass the **inert** recipe (do
not call
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
first): the bootstrap preps it once per replicate.

``` r

dat <- sample_one
dat$age_grp <- cut(dat$age, c(0, 30, 45, 60, Inf),
                   labels = c("18-30", "31-45", "46-60", "60+"))

spec <- weighting_spec(dat, base_weights = pw) |>
  step_unknown_eligibility(unknown = unknown_elig, by = "region") |>
  step_drop_ineligible(ineligible = ineligible) |>
  step_nonresponse(respondent = hh_responded, method = "weighting_class",
                   by = "region") |>
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
#> 1 21615.21 872.7788 19904.59 23325.82
boot_total(boot, "employed")   # total employed
#>   estimate       se ci_lower ci_upper
#> 1 1927.219 140.9421 1650.978 2203.461
boot_mean(boot,  "employed")   # employment rate
#>    estimate         se  ci_lower  ci_upper
#> 1 0.4287473 0.03102821 0.3679331 0.4895615
```

For any other statistic, pass a function of the weights and the data to
[`bootstrap_estimate()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_estimate.md):

``` r

bootstrap_estimate(boot, function(w, d) {
  ok <- !is.na(d$income) & w > 0
  stats::median(rep(d$income[ok], times = round(w[ok])))   # weighted median (approx.)
})
#>   estimate     se ci_lower ci_upper
#> 1    18136 930.15 16312.94 19959.06
```

## Method 2: hand the weights to the survey package

[`as_svydesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
builds an ultimate-cluster linearization design from a prepped recipe.
It is fast, but treats the calibration as fixed.

``` r

fitted <- prep(spec)
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
#> income 21615 872.78
```

This matches `boot_mean(boot, "income")` exactly, because
[`as_svrepdesign()`](https://jpferreira33.github.io/weightflow/reference/as_svydesign.md)
sets `scale = 1 / B`, `rscales = 1` and `mse = TRUE`.

## Replicate weights for a tidyverse workflow

[`collect_replicate_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_replicate_weights.md)
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
#> 1      21615.           873.
```

## Which one to use

Use the **recipe-aware bootstrap** (method 1, in any of its three forms)
when the nonresponse and calibration steps are a meaningful part of the
design and you want their uncertainty reflected; it is the more honest
variance. Use the **linearization** (method 2) for a quick,
well-understood standard error when the adjustments are minor or you
only need the design-and-clustering part.

A few practical notes. More replicates give a more stable bootstrap SE;
200 is fine for exploration, 500-1000 for final figures. Each stratum
needs at least two PSUs to be resampled (single-PSU strata are left
untouched, with a warning). If a replicate leaves a calibration or
weighting-class cell empty it is dropped with a warning; coarser `by`
cells make the bootstrap more robust.
