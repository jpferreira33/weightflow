# Non-probability samples

Opt-in panels, volunteer surveys and river samples have no design
weights: the inclusion probabilities are unknown and, worse, related to
what we measure. A weightflow recipe treats such a sample the same way
it treats a probability sample – an explicit, auditable sequence of
adjustments with recipe-aware variances – but the first steps change:
instead of expanding design weights, we *estimate* participation and
adjust for it against a probability **reference**.

## A biased volunteer sample

We take a volunteer sample from the bundled `population` in which men
over- participate, so the sample mean of `income` is biased. A small
probability survey serves as the reference, carrying the design weights
of a real reference survey.

``` r

set.seed(1)
N   <- nrow(population)
p   <- plogis(-2 + 0.9 * (population$sex == "M") - 0.02 * (population$age - 45))
vol <- population[runif(N) < p, c("region", "sex", "age", "income")]  # volunteers
ref <- population[sample(N, 1000), c("region", "sex", "age")]         # reference
ref$d <- N / 1000                                                     # its design weights

truth <- mean(population$income)
c(truth = truth, naive_volunteer_mean = mean(vol$income))
#>                truth naive_volunteer_mean 
#>             19298.11             19827.23
```

## Declaring a non-probability sample

Start the recipe with `base_weights = NULL` and `nonprob = TRUE`: every
unit begins with a base weight of 1, and the object records that the
sample is non-probability (the report declares it and adds the
methodological caveat).

``` r

ref_sample <- reference_sample(ref, weights = "d")
```

## Pseudo-weighting

[`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/reference/step_pseudoweight.md)
fits a participation model that separates the volunteers from the
reference and assigns each volunteer the inverse-propensity
pseudo-weight `(1 - p) / p` (Elliott and Valliant 2017), so the weighted
volunteers reproduce the population. The two samples are stacked
internally – no manual pooling.

``` r

spec <- weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
  step_pseudoweight(reference = ref_sample, formula = ~ region + sex + age,
                    engine = "logit")
fit <- prep(spec)

w <- fit$final_weight
c(pseudoweighted_mean = weighted.mean(vol$income, w),
  sum_of_weights = sum(w), N = N)     # the (1-p)/p pseudo-weights sum to N
#> pseudoweighted_mean      sum_of_weights                   N 
#>           19752.506            4480.998            4495.000
```

The pseudo-weighted mean is closer to the truth than the naive volunteer
mean, and the weights sum to the population size (a `1/p` mistake would
overshoot). Flexible learners (`engine = "tree" / "forest" / "boost"`,
optionally cross-fitted) are available for the participation model,
exactly as for response-propensity models.

## Doubly robust: add calibration

Pseudo-weighting is consistent if the participation model is right;
calibration is consistent if a linear outcome model is right. Doing
**both** is doubly robust – correct if either holds. Calibrate the
pseudo-weighted sample to the reference:

``` r

weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
  step_pseudoweight(reference = ref_sample, formula = ~ region + sex + age,
                    engine = "logit") |>
  step_calibrate(method = "raking", formula = ~ region + sex,
                 population = ref_sample)
```

## How large is the sample, really?

A big opt-in sample can carry a small *effective* one.
[`data_defect()`](https://jpferreira33.github.io/weightflow/reference/data_defect.md)
brings the data-defect view of Meng (2018): the effective size is
governed by the correlation between the outcome and participation, not
by the raw count. Because that correlation is not observable from the
sample alone, the effective size is reported across a grid of plausible
values – an **ignorance range**, not a single number.

``` r

dd <- data_defect(fit)
dd
#> Data-defect diagnostics (non-probability sample)
#>   n = 916   N = 4,481   f = 0.2044
#>   strongest covariate-participation correlation: |r| = 0.177 (sexM)
#>   effective size by residual data-defect correlation (Meng 2018):
#>     |rho| = 0.001  ->  n_eff = 256,943
#>     |rho| = 0.005  ->  n_eff = 10,278
#>     |rho| = 0.010  ->  n_eff = 2,569
#>     |rho| = 0.050  ->  n_eff = 103
#>     |rho| = 0.100  ->  n_eff = 26
#>   (rho on the target variable is not observable; read as an ignorance range)
```

## Variance

The recipe-aware bootstrap re-runs the whole non-probability recipe –
the participation model included – on each replicate, so the standard
error carries the variability of the pseudo-weighting, not just the
spread of the final weights.

``` r

boot <- bootstrap_weights(spec, replicates = 200, seed = 1, progress = FALSE)
boot_mean(boot, "income")
#>   estimate       se ci_lower ci_upper
#> 1 19752.51 327.3892 19110.84 20394.18
```

## Nonignorable selection

Everything above assumes participation is ignorable given the
covariates. When it may depend on the outcome itself,
[`step_nr_sensitivity()`](https://jpferreira33.github.io/weightflow/reference/step_nr_sensitivity.md)
reports how the estimate moves across a single sensitivity parameter
(the proxy pattern-mixture model of Andridge and Little 2011), producing
an *ignorance interval* to read next to the sampling confidence
interval. See
[`?step_nr_sensitivity`](https://jpferreira33.github.io/weightflow/reference/step_nr_sensitivity.md).

## References

Elliott and Valliant (2017), *Statistical Science*; Meng (2018), *Annals
of Applied Statistics*; Andridge and Little (2011), *JSSAM*.
