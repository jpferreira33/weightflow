# Trimming survey weights

A few extreme weights inflate the variance of every estimate: the Kish
design effect $`\text{deff} = 1 + \text{CV}^2(w)`$ grows with the
coefficient of variation of the weights, so a long right tail costs
precision. Trimming caps that tail. The question is *how* to cap it, and
what it does to the totals you calibrated to.

weightflow offers three tools, from the most automatic to the most
constrained:

- [`step_trim_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim_weights.md):
  cap at a data-driven threshold and redistribute the excess.
- [`step_trim()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim.md):
  cap at a ratio you choose (relative to the base weights or the
  median), optionally per subgroup.
- [`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim_calibrated.md):
  pull the weights into a fixed range **while preserving the calibration
  totals**.

The rest of this article shows each on the bundled `sample_survey` data,
starting from a common calibrated recipe.

``` r
base <- weighting_spec(sample_survey, base_weights = pw) |>
  step_unknown_eligibility(unknown = unknown_elig, by = "region") |>
  step_nonresponse(respondent = responded, method = "propensity",
                   engine = "logit", formula = ~ region + sex + age,
                   num_classes = NULL) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region)),
                                sex    = c(table(population$sex))))

fit0 <- prep(base)
design_effect(fit0$final_weight)[c("deff", "n_eff")]
#> $deff
#> [1] 1.044762
#> 
#> $n_eff
#> [1] 258.4321
```

## Automatic caps: `step_trim_weights()`

[`step_trim_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim_weights.md)
caps extreme weights at an upper threshold and shares the removed mass
among the untrimmed units so the total is preserved. Called with no
arguments it applies a floor of `lower = 1` and picks the upper cap
automatically. Two rules are available through `method`:

- `"tukey"` (default): the Tukey far-out fence, $`Q_3 + 3\,\text{IQR}`$
  of the weights, a fixed, conservative rule.
- `"potter"`: Potter’s cutoff, the $`\tau`$ that minimizes an estimate
  of $`\text{bias}(\tau)^2 + \text{var}(\tau)`$ of the weighted total,
  often more aggressive.

``` r
tukey  <- base |> step_trim_weights(method = "tukey")  |> prep()
potter <- base |> step_trim_weights(method = "potter") |> prep()

k <- length(tukey$steps)               # the trim is the last step
rbind(tukey  = tukey$steps[[k]]$diagnostics[, c("method", "upper", "n_capped")],
      potter = potter$steps[[k]]$diagnostics[, c("method", "upper", "n_capped")])
#>        method  upper n_capped
#> tukey   tukey 38.405        0
#> potter potter 20.446       38
```

You can also set the bounds by hand (`lower`, `upper`), which turns off
the automatic rule. And the removed mass is shared either in proportion
to the untrimmed weights (`redistribute = "proportional"`, the default,
keeping their relative sizes) or equally (`redistribute = "uniform"`,
which reproduces
[`survey::trimWeights()`](https://rdrr.io/pkg/survey/man/trimWeights.html)
exactly).

``` r
uniform <- base |>
  step_trim_weights(upper = 2500, redistribute = "uniform") |>
  prep()
design_effect(uniform$final_weight)[["deff"]]
#> [1] 1.044762
```

## Ratio caps: `step_trim()`

[`step_trim()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim.md)
caps at a ratio you choose rather than a data-driven threshold. The
reference for the ratio is set by `reference`: `"base"` (a multiple of
each unit’s base weight), `"median"` (a multiple of the median weight)
or `"value"` (an absolute number). Here every weight is capped at four
times the median:

``` r
by_median <- base |>
  step_trim(max_ratio = 4, reference = "median", redistribute = FALSE) |>
  prep()
range(by_median$final_weight[by_median$final_weight > 0])
#> [1] 10.42822 21.20207
```

With `by`, the reference is computed **within each group**: the cap is
four times *that group’s* median, so strata with different weight levels
are trimmed on their own scale instead of against a single global
median.

``` r
by_region <- base |>
  step_trim(max_ratio = 4, reference = "median", by = "region",
            redistribute = FALSE) |>
  prep()
range(by_region$final_weight[by_region$final_weight > 0])
#> [1] 10.42822 21.20207
```

## Calibration-preserving caps: `step_trim_calibrated()`

Both tools above cap and redistribute, which quietly breaks the
calibration the recipe had achieved: the region and sex totals no longer
hold after the trim.
[`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim_calibrated.md)
instead pulls the already-calibrated weights into an absolute interval
`[lower, upper]` **as a bounded re-calibration** (the generalized
exponential method of Folsom and Singh 2000), so every calibration total
is still met. Weights inside the interval stay put; out-of-range ones
saturate at their bound and the rest move minimally to restore the
totals.

Formally, it solves for new weights $`w_i^\star`$ that stay as close as
possible to the incoming weights $`w_i`$, subject to reproducing the
totals and respecting the bounds:

``` math
\min_{w^\star}\ \sum_i w_i\, G\!\left(\frac{w_i^\star}{w_i}\right)
\quad\text{subject to}\quad
\sum_i w_i^\star\, x_i = \sum_i w_i\, x_i, \qquad L \le w_i^\star \le U,
```

where $`x_i`$ are the auxiliaries in `formula`, $`[L, U]`$ are `lower` /
`upper`, and $`G`$ is the calibration distance (the range-restricted
linear one by default, or the multiplicative “raking” distance). The
absolute-weight bound turns into a per-unit bound on the adjustment
factor $`g_i = w_i^\star / w_i \in
[L/w_i,\ U/w_i]`$, which is what the solver enforces.

``` r
w   <- collect_weights(fit0, drop_zero = FALSE)$.weight
pos <- w[w > 0]
lo  <- as.numeric(quantile(pos, 0.05)); up <- as.numeric(quantile(pos, 0.95))

trimmed <- base |>
  step_trim_calibrated(~ region + sex, lower = lo, upper = up) |>
  prep()
```

The totals are still reproduced after the trim (the differences are
zero), while the weights now sit inside the interval:

``` r
X <- model.matrix(~ region + sex, sample_survey)
round(colSums((trimmed$final_weight - w) * X), 6)
#> (Intercept) regionSouth  regionEast  regionWest        sexM 
#>           0           0           0           0           0
range(trimmed$final_weight[trimmed$final_weight > 0])
#> [1] 10.61844 21.02522
```

### Bounds that differ by subgroup

The bounds can vary by subgroup: pass `lower` / `upper` as a **named
vector** whose names are the levels of `by`, and each subgroup is
trimmed to its own interval while the preserved totals of the formula
stay global. This helps when the weight scale differs across strata.
Here each region gets its own bounds, taken from that region’s 5th and
95th percentiles:

``` r
lo_by <- tapply(w, sample_survey$region, function(x) as.numeric(quantile(x[x > 0], 0.05)))
up_by <- tapply(w, sample_survey$region, function(x) as.numeric(quantile(x[x > 0], 0.95)))
lo_by                                   # a vector named by the levels of `by`
#>    North    South     East     West 
#> 19.09643 16.40679 16.83631 10.49093

trimmed_by <- base |>
  step_trim_calibrated(~ region + sex, lower = lo_by, upper = up_by, by = "region") |>
  prep()
tapply(trimmed_by$final_weight[trimmed_by$final_weight > 0],
       sample_survey$region[trimmed_by$final_weight > 0], range)
#> $North
#> [1] 19.09643 21.18463
#> 
#> $South
#> [1] 16.40679 18.31942
#> 
#> $East
#> [1] 16.83631 18.61255
#> 
#> $West
#> [1] 10.49093 11.66819
```

You can also write the vector by hand, naming each level, for example
`lower = c(North = 15, South = 12, East = 14, West = 10)`.

**Crossing two variables.** `by` takes a single column, so to trim by
the crossing of two variables you first build the interaction column and
pass that. For region-by-sex cells:

``` r
d <- sample_survey
d$reg_sex <- interaction(d$region, d$sex, sep = "_", drop = TRUE)

# build the recipe on `d`, then trim with bounds named "North_F", "North_M", ...
weighting_spec(d, base_weights = pw) |>
  # ... eligibility, nonresponse, calibration ...
  step_trim_calibrated(~ region + sex, lower = lo_cell, upper = up_cell,
                       by = "reg_sex")
```

Per-cell trimming only makes sense when the weights vary *within* the
cell: if an earlier step made them constant inside each cell (for
instance, calibrating to those very cells), there is nothing left to
trim there.

With `equal_within_cluster = TRUE` and a `cluster`, the trimming is
integrative: one factor per household, so weights that were constant
within household stay constant.

## Which one should I use?

- Use
  [`step_trim_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim_weights.md)
  for a quick, data-driven cap when you have not calibrated yet, or when
  small deviations from the totals are acceptable.
- Use
  [`step_trim()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim.md)
  when you want an explicit, interpretable rule (a multiple of the base
  weight or the median), possibly different per subgroup.
- Use
  [`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/dev/reference/step_trim_calibrated.md)
  when the weights are already calibrated and the totals must survive
  the trim: it is the only one of the three that does not break the
  calibration.

All three compose like any other step, and the recipe-aware bootstrap
and jackknife re-apply them on every replicate, so the standard errors
reflect the trimming, not just the final weights. See the *Variance
estimation* article for that, and *Get started* for the staged logic
these steps plug into.

## References

- Potter, F. J. (1990). A study of procedures to identify and trim
  extreme sample weights. *Proc. ASA Survey Research Methods Section*,
  225-230.
- Folsom, R. E., & Singh, A. C. (2000). The generalized exponential
  model for sampling weight calibration for extreme values, nonresponse,
  and poststratification. *Proc. ASA Survey Research Methods Section*,
  598-603.
- Kish, L. (1992). Weighting for unequal Pi. *Journal of Official
  Statistics*, 8(2), 183-200.
