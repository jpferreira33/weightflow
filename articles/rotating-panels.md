# Rotating panels: net change, chaining and gross flows

A continuous household survey with a rotating design measures the same
units more than once. That is what makes the **change** between two
periods far more precise than the levels themselves – the shared sample
cancels part of the sampling error – and it is also what makes the
change **harder** to estimate: the two samples are not independent, so
`V(change)` is not `V1 + V2`.

This vignette covers the three things a rotating panel makes possible,
in the order an office needs them:

1.  the **net change** between two periods, with its honest variance;
2.  **chaining** period after period the way production actually runs,
    one month at a time, with only a small object traveling between
    runs;
3.  the **gross flows** – who moved between states – which need a
    longitudinal weight.

The package’s panel layer follows the methodology of Statistics Canada’s
Labour Force Survey (cat. 71-526-X, sec. 7.2.2) for the coordinated
replication, and ECLAC’s household-survey manual (chapters XVI-XVII) for
the longitudinal weight and the flows.

## The structure comes first

Before any weighting,
[`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)
reads the unit x wave crossing and describes what is actually there. It
computes nothing about weights.

``` r

pd <- panel_design(panel_ine, unit = c("id_hogar", "nper"), wave = "ola",
                   rotation_group = "grupo_rotacion", pattern = "6")
pd
#> <weightflow panel design>
#>   waves      : 3 (1, 2, 3)
#>   unit       : id_hogar + nper
#>   rotation   : grupo_rotacion  pattern: 6
#>   units      : 2783 (linked in >=2 waves: 2063, 74%)
#>   overlap (row wave retained in column wave):
#>   1    2    3   
#> 1 1.00 0.83 0.64
#> 2 0.83 1.00 0.81
#> 3 0.65 0.82 1.00
#>   Pr(panel selection), adjacent : 0.833, 0.833  (full combination: 0.667)
#>   overlap implied by pattern    : 0.83 0.67   (lag 1 2)
#>   pattern                       : 6 group(s) in sample, cycle 6, useful lags 1, 2, 3, 4, 5
```

Two things to read in that output.

The **overlap matrix** is observed, from the data. The **profile implied
by the pattern** is theoretical, derived from the rotation calendar. The
declared `pattern` is therefore *verification*, not configuration: when
the observed overlap falls below what the design implies, the linkage
key is suspect, and `PN-01` says so. Ordinary attrition pulls the
observed overlap down a little; a broken key pulls it down a lot.

The pattern is parsed into the whole profile, not just the adjacent lag,
because the informative lag is not always lag 1:

``` r

prof <- function(p) round(weightflow:::.wf_pattern_overlap(p)$profile[1:5], 3)
rbind(`6        (Canada LFS, ECH Uruguay)` = prof("6"),
      `4(0)1    (ECLAC ch. XVI example)`   = prof("4(0)1"),
      `2-(2)-2  (Chile ENE, Italy)`        = prof("2-(2)-2"),
      `4-8-4    (US CPS)`                  = prof("4-8-4"),
      `1(2)5    (PNAD Continua)`           = prof("1(2)5"))
#>                                        1     2    3     4     5
#> 6        (Canada LFS, ECH Uruguay) 0.833 0.667 0.50 0.333 0.167
#> 4(0)1    (ECLAC ch. XVI example)   0.750 0.500 0.25 0.000 0.000
#> 2-(2)-2  (Chile ENE, Italy)        0.500 0.000 0.25 0.500 0.250
#> 4-8-4    (US CPS)                  0.750 0.500 0.25 0.000 0.000
#> 1(2)5    (PNAD Continua)           0.000 0.000 0.80 0.000 0.000
```

`2-(2)-2` shares **no** sample at lag 2 and half of it at lag 4 – as
much as at lag 1 – so a year-on-year change there needs as much
coordination as a quarter-on-quarter one. The PNAD Continua design
`1(2)5` shares nothing with the adjacent quarter at all: a design built
around “the previous period” would be exactly backwards for it. Both
notations are accepted and describe the same calendar: `"2-(2)-2"` and
`"2(2)2"` are the same design.

## Net change between two periods

The coordinated bootstrap resamples **PSUs**, and a PSU present in both
waves is resampled the same way in both. That is what lets the overlap
show up as covariance.

``` r

w1 <- subset(panel_ine, ola == 1 & disp == "R")
w2 <- subset(panel_ine, ola == 2 & disp == "R")
rec <- function(d) weighting_spec(d, base_weights = w_base) |>
  step_nonresponse(respondent = disp == "R", by = "sexo")

wb <- wave_bootstrap(list(T1 = rec(w1), T2 = rec(w2)), replicates = 100,
                     strata = "estrato", psu = "psu", seed = 1, progress = FALSE)
change_mean(wb, "desocupado")
#> <weightflow net change>
#>   T1 -> T2
#>   change     : -0.0149512   SE 0.010056
#>   95% CI    : [-0.0346606, 0.00475807]
#>   V1 0.0001126 | V2 0.0001035 | Cov 5.75e-05 | rho 0.533   (levels)
#>   V = 0.0001011  vs  V1+V2 = 0.0002161  (deff_change 0.468: overlap saved 53%)
```

`rho` is the correlation the overlap induces and `deff_change` is
`V / (V1 + V2)`: the ratio between the variance reported here and what
an office would report if it treated the two periods as independent
samples. Ignoring the overlap does not give a conservative answer – it
gives a wrong one, in either direction depending on the sign of the
covariance.

For a combination over more than two waves – a rolling quarter, an
annual average –
[`panel_estimate()`](https://jpferreira33.github.io/weightflow/reference/panel_estimate.md)
takes an arbitrary contrast:

``` r

panel_estimate(wb, mean_of("desocupado"), contrast = c(-1, 1))   # the net change
panel_estimate(wb, mean_of("desocupado"))                        # the average
```

## Chaining: how production actually runs

[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md)
wants every wave at once. An office does not have them: it publishes
month `t` weeks after month `t-1`, and the twelfth month of the year
cannot wait for the first eleven to be reprocessed.
[`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
runs **one period at a time** and hands the next period a small object –
the *carry* – that is all it needs.

``` r

# period 1: nothing to coordinate with yet
s1 <- wave_step(rec(w1), estimands = EST, replicates = 500,
                strata = "estrato", psu = "psu", period = "2026-01", seed = 1)
saveRDS(wave_carry(s1), "carry/2026-01.rds")

# period 2, weeks later, in a fresh session
prev <- readRDS("carry/2026-01.rds")
s2 <- wave_step(rec(w2), previous = prev, estimands = EST, replicates = 500,
                strata = "estrato", psu = "psu", period = "2026-02", seed = 2)
s2$weights   # the cross-sectional weights the office publishes
s2$change    # the net change against 2026-01, with rho and deff_change
s2$strata    # the coordination diagnostic, stratum by stratum
saveRDS(wave_carry(s2), "carry/2026-02.rds")
```

Three properties worth stating plainly.

**The cross-sectional weights are untouched.** `s2$weights` is identical
to `prep(spec)$final_weight`. Coordination adds the change and the
carry; it never moves the point estimate the office publishes.

**`previous` is a list, not a file.** Which earlier periods share sample
with this one is decided by the rotation calendar, not by proximity:
with `2-(2)-2` the useful lags are 1, 3, 4 and 5, and lag 2 is empty.
Each PSU inherits its multiplicity from the most recent carry that
contains it, so gaps and returning cohorts resolve themselves.

**The coordination is exact when the stratum keeps its size.**
Coordination transfers the PSU *multiplicities*, and when `n_h` is
unchanged the transfer is a permutation – case (ii) of the LFS
methodology – so no replicate needs adjusting. `$strata` reports the
case and the share of replicates that closed without adjustment, per
stratum. That column is the quality indicator that decides whether a
figure is publishable.

### Combinations over the chain

[`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
reports pairwise changes. A rolling quarter is not pairwise, and
[`wave_contrast()`](https://jpferreira33.github.io/weightflow/reference/wave_contrast.md)
estimates any linear combination straight from the saved carries:

``` r

tr <- lapply(c("2026-01", "2026-02", "2026-03"),
             \(m) readRDS(sprintf("carry/%s.rds", m)))

wave_contrast(tr, "unemployment_rate")                          # rolling quarter
wave_contrast(tr, "unemployment_rate", contrast = c(-1, 0, 1))  # T3 - T1
```

This works without the waves being in memory because each carry stores
the `R` replicate values of every declared estimand, and those
replicates are **paired across periods** – the coordination transferred
the multiplicities. Stacking them recovers the full covariance matrix,
and any contrast follows from it.

### The composite estimator

When the recipe ends in
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md),
the level of period `t` depends on control totals **estimated** with the
previous wave. Treating them as known constants makes the variance
anticonservative, so replicate *b* of period `t` rebuilds `Zhat*` from
replicate *b* of period `t-1`. That is why a chain with
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
needs the “fat” carry, which weighs a few hundred KB instead of a few
dozen: it must carry the previous period’s replicate weights.
`$n_cre_injected` and `$n_cre_skipped` are the audit that it actually
happened.

## Gross flows: who moved

A net change is a difference of aggregates. It cannot distinguish an
immobile population from one where equal numbers enter and leave
employment. For that you need the **longitudinal** file and a
longitudinal weight.

``` r

wide <- panel_merge(list(T1 = subset(panel_ine, ola == 1),
                         T2 = subset(panel_ine, ola == 2)),
                    by = c("id_hogar", "nper"), require = "all")

lw <- weighting_spec(wide, base_weights = w_base_T1) |>
  step_drop_ineligible(disp_T2 == "OS", reason = "left the target population") |>
  step_attrition(respondent = disp_T2 == "R", method = "propensity",
                 formula = ~ edad_T1 + sexo_T1) |>
  prep()

transition_matrix(lw, from = "condicion_T1", to = "condicion_T2", format = "row")
#> <weightflow transition: condicion_T1 -> condicion_T2  [row]>
#>        to
#> from       emp inact  unemp
#>   emp   0.9547     0 0.0453
#>   inact 0.0000     1 0.0000
#>   unemp 0.1120     0 0.8880
```

[`boot_transition()`](https://jpferreira33.github.io/weightflow/reference/boot_transition.md)
adds a standard error per cell, and
[`boot_flows()`](https://jpferreira33.github.io/weightflow/reference/boot_flows.md)
gives the same information as population totals plus the net flows
`i->j` minus `j->i` and the margins – how many started in each state,
ended in each, stayed, and moved.

A caveat about the illustration, not the method: the four shipped panel
datasets are synthetic, and in all of them **inactivity is an absorbing
state** – nobody enters or leaves it. So the matrix above shows movement
only between employment and unemployment, and the `inact` row and column
are degenerate. The mechanics are the point here; on real microdata the
transitions in and out of inactivity are usually the interesting ones.

Note the order of the two steps, which is not cosmetic. **Leaving the
target population is not nonresponse.** Someone who died or emigrated is
removed from the universe with
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md);
their weight is not redistributed to anyone. Someone who is still in the
universe but did not answer is attrition, and their weight *is*
redistributed, among the units that remain. Collapsing the two inflates
the population.

### Three ECLAC conventions the package cannot enforce

These are decisions the analyst makes; the package has no way to check
them, so they are stated here (ECLAC, ch. XVI).

**The longitudinal population** is the units that were in the target
population at the first period **and stayed** through the last. Those
who left are out; those who *entered* later are out too. A panel adds no
elements over time.

**Calibrate to the first period’s totals.** The manual is explicit that
the auxiliary totals must represent the population of the *first*
period, because a panel that adds no elements is representative only of
the period in which it was selected. Passing the later period’s
projections is a silent error: the recipe converges, the totals close,
and the weights represent a population the sample never had a chance to
cover. A vector of control totals carries no label saying which period
it is, so nothing but you can catch this.

**Cross-sectional estimates from a longitudinal file are reference
only.** They will not match the published cross-sectional figures, and
they should not: the target population of the panel combination is not
the target population of the cross-section. Use the longitudinal weight
for flows, transitions and durations; use the cross-sectional weight for
levels.

## Where to look next

This vignette is the entry point; three companions go deeper into the
pieces it uses.

- [`vignette("coordinated-replication")`](https://jpferreira33.github.io/weightflow/articles/coordinated-replication.md)
  – what actually travels between waves, the four coordination cases,
  and how to read the `$strata` diagnostic that decides whether a change
  is publishable.
- [`vignette("composite-estimation")`](https://jpferreira33.github.io/weightflow/articles/composite-estimation.md)
  –
  [`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
  in full: what the composite estimator buys, and why its control totals
  make its variance a special case.
- [`vignette("panel-longitudinal")`](https://jpferreira33.github.io/weightflow/articles/panel-longitudinal.md)
  – the **pure** panel: attrition over many waves, the longitudinal
  weight, and gross flows.

For the reference pages:
[`?wave_step`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
and
[`?wave_carry`](https://jpferreira33.github.io/weightflow/reference/wave_carry.md)
for the chaining engine,
[`?wave_contrast`](https://jpferreira33.github.io/weightflow/reference/wave_contrast.md)
for combinations over a chain,
[`?panel_design`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)
for the structure layer,
[`?transition_matrix`](https://jpferreira33.github.io/weightflow/reference/transition_matrix.md)
for the flows, and
[`?report_panel`](https://jpferreira33.github.io/weightflow/reference/report_panel.md)
for a quality report of a panel run.
[`vignette("variance-estimation")`](https://jpferreira33.github.io/weightflow/articles/variance-estimation.md)
covers the single-period bootstrap this one builds on, and
[`vignette("validation")`](https://jpferreira33.github.io/weightflow/articles/validation.md)
checks the change variance against an analytic estimator from a
different family.
