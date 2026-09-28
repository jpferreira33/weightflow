# Composite estimation: borrowing strength from the previous wave

In a rotating panel most of this month’s sample was also in last
month’s. The **composite estimator** uses that: it adds the previous
wave’s labour status to the calibration as an auxiliary variable, with
control totals taken from the previous wave’s own composite estimates.
The result is a level series that is smoother and, much more to the
point, a **change** measured far more precisely – because the estimator
is partly built from the same units twice.

[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
implements the regression composite estimator of Fuller and Rao (2001)
and Gambino, Kennedy and Singh (2001), in the form specified for the
Canadian Labour Force Survey (Statistics Canada, cat. 71-526-X,
sec. 6.3.1) and used by Uruguay’s ECH (sec. 8.4). This article states
that form, maps it onto the arguments of
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md),
measures what it buys, and explains the one thing that makes its
variance a special case.

## The estimator

Start from the nonresponse-adjusted weights $`w_l^{NA}`$ – whatever the
recipe produced up to this step. Composite calibration looks for final
weights $`w_l^{CC}`$ as close as possible to those, in the chi-square
distance

``` math
\min_{w^{CC}} \; \sum_{l \in s_r} \frac{\left(w_l^{CC} - w_l^{NA}\right)^2}{w_l^{NA}}
```

subject to **two** blocks of constraints rather than the usual one:

``` math
\sum_{l \in s_r} w_l^{CC} \begin{pmatrix} \mathbf{x}_l \\ \mathbf{z}_{\bullet l} \end{pmatrix} = \begin{pmatrix} \mathbf{X} \\ \widehat{\mathbf{Z}} \end{pmatrix}
```

The upper block is ordinary calibration: $`\mathbf{x}_l`$ are the
demographic auxiliaries and $`\mathbf{X}`$ their **known** population
totals (census projections). The lower block is what makes the estimator
composite: $`\mathbf{z}_{\bullet l}`$ are indicators of the *previous*
wave’s labour status and $`\widehat{\mathbf{Z}}`$ are their totals
**estimated from the previous wave**. The solution is the familiar GREG
form,

``` math
w_l^{CC} = w_l^{NA} g_l^{CC}, \qquad g_l^{CC} = \left(\mathbf{x}_l', \mathbf{z}_{\bullet l}'\right) \left[\sum_{l \in s_r} w_l^{NA} \begin{pmatrix} \mathbf{x}_l \\ \mathbf{z}_{\bullet l}\end{pmatrix}\left(\mathbf{x}_l', \mathbf{z}_{\bullet l}'\right)\right]^{-1} \begin{pmatrix} \mathbf{X} \\ \widehat{\mathbf{Z}} \end{pmatrix}
```

with $`g_l^{CC}`$ near 1 when the sample already reproduces both blocks.

## The birth rotation group, and why there are two imputations

$`\mathbf{z}_{\bullet l}`$ is not observed for everyone: the units that
entered the sample this wave – the **birth rotation group** $`s_r^b`$ –
have no previous month. Their values have to be imputed, and the LFS
methodology uses *two* imputations because they are efficient for two
different things.

**MR1, mean imputation**, is efficient for the **level** at month $`t`$:

``` math
\mathbf{z}_{\bullet l}^{(1)} = \begin{cases} \mathbf{z}_{t-1,l} & l \in s_r - s_r^b \\ \widehat{\mathbf{Z}} / N_{15+} & l \in s_r^b \end{cases}
```

**MR2, carry-backward imputation**, is efficient for the **difference**
between two successive months. The birth group carries its current value
backwards, and the non-birth groups are corrected for the change that
this erases:

``` math
\mathbf{z}_{\bullet l}^{(2)} = \begin{cases} \mathbf{z}_{t-1,l} + \left(\delta_l^{-1} - 1\right)\left(\mathbf{z}_{t-1,l} - \mathbf{z}_{t,l}\right) & l \in s_r - s_r^b \\ \mathbf{z}_{t,l} & l \in s_r^b \end{cases}
```

Here $`\delta_l`$ is the probability of *not* being in the birth group –
the overlap rate, $`5/6`$ in a six-month rotation – estimated from the
weights themselves as
$`\hat\delta = \sum_{s_r - s_r^b} w_l^{NA} \big/ \sum_{s_r} w_l^{NA}`$.
The correction factor $`\delta^{-1} - 1`$ is what preserves asymptotic
unbiasedness: without it, carry-backward would quietly remove one sixth
of the month-to-month change.

Neither is used alone. The composite auxiliaries are the mix

``` math
\mathbf{z}_{\bullet l} = (1 - \alpha)\,\mathbf{z}_{\bullet l}^{(1)} + \alpha\,\mathbf{z}_{\bullet l}^{(2)}, \qquad \alpha = 2/3
```

with $`\alpha`$ a tuning constant: $`\alpha = 0`$ targets the level
alone, $`\alpha = 1`$ the change alone. Both the LFS and the ECH use
$`2/3`$, following the study of Chen and Liu (2002).

### Where each symbol lives in the call

| symbol | argument |  |
|----|----|----|
| $`w_l^{NA}`$ | — | whatever the recipe produced before this step |
| $`\mathbf{x}_l`$, $`\mathbf{X}`$ | `formula`, `totals` | as in `step_calibrate(method = "linear")` |
| $`\mathbf{z}_{\bullet l}`$ | `status`, `composite` | status indicators, crossed by the domains in `composite` |
| $`\widehat{\mathbf{Z}}`$ | `previous` | re-estimated from the prepped previous wave |
| $`\alpha`$ | `alpha` | default `2/3` |
| $`\delta`$ | `overlap` | `"auto"` estimates $`\hat\delta`$ from the weights; or give it (e.g. `5/6`) |
| $`s_r^b`$ | `birth`, `id_unit` | the birth group, named or derived by unit key |
| $`N/G`$ | `rotation_group` | equal-representation constraints, see below |

`composite` is the list of domain crossings that define the blocks of
$`\widehat{\mathbf{Z}}`$: `NULL` is the country total, `"sex"` is status
crossed by sex, a character vector is status crossed by the interaction.
The ECH’s own list is `list(NULL, "sex", "department")`. `status_ref`
names the status level left implicit in each block – one level must
always be dropped, or the block is collinear with the intercept of
$`\mathbf{x}`$; naming it only decides which.

Units that are neither birth nor matched – new household members, people
newly of working age, people out of scope last month – are handled by
`on_missing_prev`: `"carry_backward"` sets
$`\mathbf{z}_{t-1} = \mathbf{z}_t`$, `"zero"` sets
$`\mathbf{z}_{\bullet l} = \mathbf{0}`$, which is what the LFS does for
the out-of-scope (Gambino, Kennedy and Singh 2001).

## The recursion

The estimator is defined recursively, so a chain needs a starting point.
The **seed** wave has no $`t-1`$: with `previous = NULL` the composite
block is empty and
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
reduces to an ordinary linear calibration to $`\mathbf{X}`$. From the
second wave on, `previous` is the prepped recipe of the wave before.

``` r

wv <- lapply(1:3, function(k) {
  d <- subset(panel_ine, wave == k & disposition == "R"); d$sex <- factor(d$sex); d
})
# ONE population vector for every wave, as a series of projections would be. `Zhat`
# is a total estimated on the PREVIOUS wave's scale, so giving each wave its own
# design-weighted total puts two population scales in the same system: the composite
# block stops being a smoother and the whole gap lands on the status estimate, with
# every constraint met and `converged = TRUE`. On `panel_ine` the design totals drift
# 12.9% between waves 1 and 2, which moves the employment rate by 7 points.
Xpop <- colSums(wv[[1]]$pw * model.matrix(~ sex, data = wv[[1]]))
Xtot <- function(d) Xpop
```

``` r

seed <- weighting_spec(wv[[1]], base_weights = pw) |>
  step_cre(previous = NULL, status = lf_status, formula = ~ sex,
           totals = Xtot(wv[[1]]), status_ref = "inact") |>
  prep()

wave2 <- weighting_spec(wv[[2]], base_weights = pw) |>
  step_cre(previous = seed, status = lf_status, composite = list(NULL, "sex"),
           id_unit = c("household_id", "person_no"), formula = ~ sex,
           totals = Xtot(wv[[2]]), alpha = 2/3, status_ref = "inact")
```

## What it buys

The comparison worth making is against the same recipe with an ordinary
calibration, over the same chain, with the same replicates:

``` r

EST <- list(unemp_rate = function(w, d) weighted.mean(d$unemployed, w, na.rm = TRUE))

run <- function(composite) {
  prev <- NULL; out <- list()
  for (k in 1:3) {
    sp <- weighting_spec(wv[[k]], base_weights = pw)
    sp <- if (composite)
      step_cre(sp, previous = if (k == 1) NULL else out[[k - 1]]$prepped,
               status = lf_status, composite = list(NULL, "sex"),
               id_unit = c("household_id", "person_no"), formula = ~ sex,
               totals = Xtot(wv[[k]]), alpha = 2/3, status_ref = "inact")
    else
      step_calibrate(sp, method = "linear", formula = ~ sex, totals = Xtot(wv[[k]]))
    s <- wave_step(sp, previous = prev, estimands = EST, replicates = 150,
                   strata = "stratum", psu = "psu", period = paste0("T", k),
                   seed = 100 + k, progress = FALSE)
    out[[k]] <- list(step = s, carry = wave_carry(s), prepped = prep(sp))
    prev <- rev(lapply(out, function(z) z$carry))
  }
  out
}

cre   <- run(TRUE)
plain <- run(FALSE)

tab <- function(o, label) {
  ch <- o[[3]]$step$change
  data.frame(recipe = label, from = ch$from, se = round(ch$se, 5),
             rho = round(ch$rho, 3), deff_change = round(ch$deff_change, 3))
}
rbind(tab(cre, "composite (CRE)"), tab(plain, "plain calibration"))
#>              recipe from      se   rho deff_change
#> 1   composite (CRE)   T2 0.00704 0.851       0.152
#> 2   composite (CRE)   T1 0.00922 0.705       0.295
#> 3 plain calibration   T2 0.01082 0.627       0.373
#> 4 plain calibration   T1 0.01257 0.468       0.532
```

Against the previous month the standard error of the change falls by
about a third, and the correlation between the two periods’ estimates
rises from roughly 0.6 to roughly 0.85. That is the whole point: the
composite auxiliaries make consecutive estimates share more of their
sampling error, and shared error cancels in a difference. Statistics
Canada reports the same qualitative result – composite estimation
“significantly reduces the sampling errors” of the LFS (cat. 71-526-X,
ch. 8).

It is not free. The level at period $`t`$ now depends on the previous
wave’s estimates, so an error propagates forward and the series is
smoother than the data alone would justify. That is why $`\alpha`$
exists and why neither agency sets it to 1.

## The variance trap

Here is what makes
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
different from every other step. Its control totals
$`\widehat{\mathbf{Z}}`$ are **not known population figures**. They are
*estimated* from the previous wave, with the previous wave’s weights,
and they carry that wave’s sampling error.

A single-sample bootstrap does not know this. It resamples the current
wave and re-runs the recipe, but $`\widehat{\mathbf{Z}}`$ was computed
once, from the previous wave’s frozen point weights, so every replicate
calibrates to the *same* control totals – as if they were census
figures. Writing the change as

``` math
V(\hat\theta_t - \hat\theta_{t-1}) = V(\hat\theta_t) + V(\hat\theta_{t-1}) - 2\,\mathrm{Cov}(\hat\theta_t, \hat\theta_{t-1})
```

the single-sample engine gets the first term wrong *and* has no way to
produce the third. The result is too small, and too small in precisely
the direction that matters. The package refuses to let this happen
quietly:

``` r

b <- tryCatch(bootstrap_weights(wave2, replicates = 5, strata = "stratum",
                                psu = "psu", progress = FALSE),
              warning = function(w) conditionMessage(w))
b
#> [1] "bootstrap_weights(): the recipe contains step_cre() (composite regression). This single-sample bootstrap treats the composite control totals Zhat as FIXED, so it understates the variance. Use wave_bootstrap() for the coordinated, honest variance of the recursive composite estimator."
```

The honest version re-estimates $`\widehat{\mathbf{Z}}`$ inside every
replicate: replicate $`b`$ of period $`t`$ rebuilds its control totals
from replicate $`b`$ of period $`t-1`$. That is what
[`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
and
[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md)
do, and it is the reason a chain containing
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
needs the previous period’s **replicate weights**, not just its
replicate estimates.

## The fat carry

Hence the two shapes of the carry. `carry = "auto"`, the default,
inspects the recipe: with no
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
it stores only the replicate values of the declared estimands; with one,
it stores the $`R \times n`$ matrix of replicate weights as well.

``` r

c(thin_KB = as.numeric(object.size(plain[[1]]$carry)) / 1024,
  fat_KB  = as.numeric(object.size(cre[[1]]$carry))   / 1024)
#>    thin_KB     fat_KB 
#>   85.88281 2614.19531
```

Thirty times larger, and the difference is entirely that matrix. For a
monthly production chain it is a few megabytes per period – the price of
an honest variance for the composite estimator.

The injection is audited, so you can confirm it happened rather than
assume it:

``` r

c(injected = cre[[2]]$step$n_cre_injected, skipped = cre[[2]]$step$n_cre_skipped)
#> injected  skipped 
#>        1        0
```

`n_cre_injected` counts the CRE steps that received the previous
period’s replicate weights; `n_cre_skipped` those that did not, because
no carry contained them or the carry was thin. A chain running with
`skipped > 0` is producing exactly the anticonservative variance the
warning above is about, and the number is there so a production run can
assert on it.

## Equal representation across rotation groups

Both methodologies impose one more constraint: each rotation group must
weight to the same working-age total,

``` math
\sum_{l \in s_g} w_l^{CC} = \frac{N_{15+}}{G}, \qquad g = 1, \dots, G-1
```

(ECH sec. 8.4.1; LFS sec. 6.3.1, “additional control totals are used to
ensure that the estimated number of people aged 15 and over is the same
for each rotation group”). Passing `rotation_group` adds it as $`G-1`$
extra columns in the demographic block – the last group’s total follows
from the others and $`N_{15+}`$, so constraining it too would be
redundant.

``` r

step_cre(spec, previous = seed, status = lf_status, composite = list(NULL, "sex"),
         id_unit = c("household_id", "person_no"), formula = ~ sex,
         totals = Xtot(wv[[2]]), rotation_group = "rotation_group",
         status_ref = "inact")
```

## References

Chen, E. J., and Liu, T. P. (2002). Choices of alpha value in regression
composite estimation for the Canadian Labour Force Survey. *Proceedings
of the Survey Methods Section, SSC*.

Fuller, W. A., and Rao, J. N. K. (2001). A regression composite
estimator with application to the Canadian Labour Force Survey. *Survey
Methodology* 27(1), 45-51.

Gambino, J., Kennedy, B., and Singh, M. P. (2001). Regression composite
estimation for the Canadian Labour Force Survey: evaluation and
implementation. *Survey Methodology* 27(1), 65-74.

Statistics Canada (2017). *Methodology of the Canadian Labour Force
Survey*, catalogue no. 71-526-X, sec. 6.3.1.

## Where to look next

[`?step_cre`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
for the full argument list,
[`vignette("coordinated-replication")`](https://jpferreira33.github.io/weightflow/articles/coordinated-replication.md)
for the mechanism that pairs the replicates across waves,
[`vignette("rotating-panels")`](https://jpferreira33.github.io/weightflow/articles/rotating-panels.md)
for the production workflow, and
[`?wave_carry`](https://jpferreira33.github.io/weightflow/reference/wave_carry.md)
for what travels between runs.
