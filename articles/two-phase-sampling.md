# Two-phase (double) sampling

## When there is a second phase of sampling

In a two-phase (or *double*) sample, a large first-phase sample is drawn
and some cheap information is collected on all of it; then a
**subsample** of the first-phase units is drawn for a costlier follow-up
– a longer questionnaire, a lab measurement, an income module. The
follow-up variable is observed only on the subsample, and the subsampled
units must stand in for the whole first-phase sample.

[`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md)
records that second phase. It expands each subsampled unit by the
inverse of its phase-2 selection probability and drops the units that
were not subsampled, and – crucially – it tells
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
that the variance now has two components.

## A worked example

We build a first-phase sample of households and take a Poisson subsample
of them (the follow-up rate varies by region). The follow-up variable is
`income`.

``` r

set.seed(1)
NH  <- 4000L; m <- 3L                       # first-phase households, members each
reg <- sample(c("A", "B", "C"), NH, replace = TRUE, prob = c(0.5, 0.3, 0.2))
u   <- rnorm(NH, c(A = 10, B = 16, C = 24)[reg], 4)

frame <- data.frame(
  hh      = rep(seq_len(NH), each = m),
  region  = rep(reg, each = m),
  income  = rep(u, each = m) + rnorm(NH * m, 0, 5),
  w1      = 10                              # first-phase design weight
)

## phase 2: Poisson subsample of households, rate by region
p2_by  <- c(A = 0.25, B = 0.45, C = 0.70)
sel_hh <- runif(NH) < p2_by[reg]
frame$selected <- as.integer(frame$hh %in% which(sel_hh))
frame$p2       <- p2_by[frame$region]
```

The recipe expands the subsample; the phase-2 sampling unit is the
household:

``` r

spec <- weighting_spec(frame, base_weights = w1) |>
  step_subsample(selected = selected, prob = p2, psu = "hh")

fit <- prep(spec)
summary(fit)
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 12000 cases
#> Base wts: w1
#> Steps   :
#>   1. phase-2 subsample  [subsample_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                   stage n_active sum_wts cv_wts deff_kish n_eff
#>                    base    12000  120000  0.000     1.000 12000
#>  stage_1_step_subsample     4845  121838  0.432     1.187  4082
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
#> --- Step 1: phase-2 subsample ---
#>  n_selected n_dropped psu n_psu2  design min_prob max_prob
#>        4845      7155  hh   1615 poisson     0.25      0.7
#> Kish deff: 1.000 -> 1.187   |   n_eff: 12000 -> 4082
```

## The two-phase variance

The sampling variance of a two-phase estimator is the sum of two
components,

``` math
V = V_1 + V_2,
```

the first-phase sampling variance plus the expected conditional variance
of the phase-2 subsample. A single-phase bootstrap of the achieved
sample captures only $`V_1`$ and **undercovers**.

When the recipe contains a
[`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md),
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
switches to the two-phase coupling automatically – no extra arguments:

``` r

boot <- bootstrap_weights(spec, replicates = 200, seed = 1, progress = FALSE)
boot_mean(boot, "income")
#>   estimate        se ci_lower ci_upper
#> 1 14.49937 0.2037054 14.10012 14.89863
```

The per-unit resampling factor has variance
$`(1 - f_1)\,\pi_2 + (1 - \pi_2)`$: the phase-1 component (seen through
the subsample) plus the phase-2 conditional component. The two add – a
naive *product* of two factors would add a spurious interaction term and
overstate the variance. In practice the factor is drawn from a strictly
positive Gamma of that mean and variance, so every replicate weight
stays positive and any downstream step (including a response-propensity
GLM) re-runs cleanly.

`f1` is the first-phase sampling fraction; it defaults to 0 (negligible,
as in most household surveys) and can be supplied through the `fpc`
argument of
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
when it is not.

## The cascade is re-run on every replicate

The whole recipe is re-executed for each bootstrap replicate, so any
nonresponse adjustment or calibration placed **after** the subsample has
its variance captured as well. A fuller two-phase recipe:

``` r

weighting_spec(frame, base_weights = w1) |>
  step_subsample(selected = selected, prob = p2, psu = "hh") |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  step_calibrate(margins = list(region = region_totals), method = "poststratify")
```

Each replicate re-estimates the nonresponse factors and re-solves the
calibration on the perturbed weights, so the reported standard error
reflects the sampling of both phases and the recipe together.

## Calibrating the subsample to the first-phase sample

National statistical offices often calibrate the second-phase sample not
to known population totals but to the totals *estimated by the
first-phase sample* – the larger phase is used as a reference for the
smaller one. This is the **two-phase regression estimator** (Fuller
1998): it gains efficiency by borrowing the first-phase information, and
its target totals are themselves random, so their sampling variance must
be propagated.

No special engine is needed: this falls out of composing
[`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md)
with a
[`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
built from the first-phase sample. Supply the first-phase sample as the
reference, together with its own replicate weights, and calibrate to it:

``` r

# `phase1` is the full first-phase sample (with the auxiliary `x` and its weight
# `w1`); `phase1_reps` are replicate weights for the first-phase design.
ref <- reference_sample(phase1, weights = "w1", replicates = phase1_reps)

weighting_spec(sample, base_weights = w1) |>
  step_subsample(selected = selected, prob = p2, psu = "hh") |>
  step_calibrate(method = "linear", formula = ~ x, population = ref)
```

Each bootstrap replicate re-estimates the first-phase totals from the
paired first-phase replicate (the sample-based calibration of Opsomer
and Erciulescu 2021) and re-solves the calibration. The two variance
components separate on their own: after calibration the
[`step_subsample()`](https://jpferreira33.github.io/weightflow/reference/step_subsample.md)
factor carries the residual variance, and the reference replicates carry
the variance of the predicted part, reproducing
`V = V1(y) + V2(residuals)` with no double counting. Monte Carlo
confirms this composition returns the two-phase regression variance
(ratio ~ 1.0), including with second-phase nonresponse and clustered
households.

## Scope

This version covers a **Poisson (independent) second phase** whose
sampling unit is nested in the first phase (the household-subsampling
case). It does not yet cover a without-replacement second phase
(`design = "srswor"`) or a coarser first-phase clustering (areas then
households);
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
raises a clear error rather than silently undercovering when
`strata`/`psu` are supplied with a two-phase recipe, and
[`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)
refuses a two-phase recipe (use the bootstrap).

## References

Sarndal, Swensson and Wretman (1992), *Model Assisted Survey Sampling*,
ch. 9; Fuller (1998), *Statistica Sinica* 8(4); Kim, Navarro and Fuller
(2006); Beaumont and Patak (2012); Opsomer and Erciulescu (2021),
*Survey Methodology*.
