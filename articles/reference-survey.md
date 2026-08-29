# Calibrating to a reference survey

Calibration usually targets **known** population totals from a census or
frame. Often you do not have those, but you do have a larger,
well-established survey you trust: the official continuous household
survey (in Uruguay, the ECH), a labour force survey, a census long form.
[`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
lets you calibrate your sample to the **design-weighted totals of that
reference survey** instead of a frame. The targets are then *estimates*,
not census figures, and that has one consequence you must handle: their
sampling variability.

``` r

library(weightflow)
```

## A reference survey is a weighted data frame

Wrap the reference microdata together with its design weights and pass
it as the `population` argument of
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
(or
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)),
with a `formula` naming the calibration variables. Here we build a
stand-in reference by drawing a weighted subsample of the known
`population`:

``` r

set.seed(1)
N   <- nrow(population)
ref <- population[sample(N, 2000), ]
ref$w <- N / nrow(ref)          # the reference survey's own design weight

fit <- weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "raking", formula = ~ region + sex,
                 population = reference_sample(ref, "w")) |>
  prep()

# the calibration hit the reference's *weighted* region totals:
tapply(collect_weights(fit)$.weight, sample_survey$region, sum)
#>    North    South     East     West 
#> 1591.230 1254.105  899.000  750.665
tapply(ref$w, ref$region, sum)
#>    North    South     East     West 
#> 1591.230 1254.105  899.000  750.665
```

A reference whose weights are all `1` reproduces the plain-frame
behaviour exactly, because it is just an unweighted count of the frame:

``` r

frame_ref <- population
frame_ref$w <- 1
w_ref   <- (weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "raking", formula = ~ region,
                 population = reference_sample(frame_ref, "w")) |> prep())$final_weight
w_plain <- (weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region)))) |> prep())$final_weight
all.equal(w_ref, w_plain)
#> [1] TRUE
```

## Estimated totals carry variance, so propagate it

Because the targets are estimated from the reference survey, treating
them as fixed understates the variance of your estimates. To carry that
component through, pass the reference survey’s **replicate weights** to
`reference_sample(..., replicates =)`. Each bootstrap replicate of your
sample is then paired with a reference replicate and re-estimates the
totals from it (Opsomer and Erciulescu 2021):

``` r

# replicate weights for the reference survey (its own design)
rep_ref <- bootstrap_weights(weighting_spec(ref, base_weights = w),
                             replicates = 100, strata = "region", psu = "psu",
                             seed = 1, progress = FALSE)$replicates

boot <- weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "raking", formula = ~ region + sex,
                 population = reference_sample(ref, "w", replicates = rep_ref)) |>
  bootstrap_weights(replicates = 100, strata = "region", psu = "psu",
                    seed = 2, progress = FALSE)

boot_total(boot, "income")
#>   estimate      se ci_lower ci_upper
#> 1 55483786 3678026 48274986 62692585
```

Without `replicates`, the totals are treated as **fixed**, a reasonable
approximation when the reference is much larger than your sample (the
same assumption you make when calibrating to another survey’s
*published* totals), but it omits the extra variance from estimating
them.

## Only the bootstrap propagates this component

The pairing that carries the reference variance is a bootstrap
mechanism:
[`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)
treats the estimated totals as fixed **even when** `replicates` is
supplied. So when the estimated-totals component matters, use the
bootstrap. This is stated in
[`?reference_sample`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md);
the practical rule is: reference survey with replicate weights -\>
[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md).

## When to use which

- **Census / frame totals available:** plain
  `step_calibrate(margins = ...)`, with no
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
  needed.
- **Only a trusted larger survey:**
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md);
  pass its replicate weights and use the bootstrap if the totals’
  sampling error is non-negligible.
- **Reference much larger than your sample:** you may treat the totals
  as fixed (omit `replicates`); the price is small.
