# Pure panels: the longitudinal weight and gross flows

A **pure panel** follows one sample over several waves without rotating
it. Nobody enters after the first wave; people only leave. That makes it
the right instrument for questions a series of cross-sections cannot
answer – who moved between states, how long spells last, whether the
same households are poor two years running – and it makes its weight a
different object from the cross-sectional one, with a different target
population, a different denominator and a different failure mode.

This vignette builds a longitudinal weight over four waves and uses it
for gross flows. The rotating case, where the sample is partly renewed
each period and the quantity of interest is usually the net change, is
[`vignette("rotating-panels")`](https://jpferreira33.github.io/weightflow/articles/rotating-panels.md).

## The longitudinal file is an intersection

``` r

waves <- split(panel_puro, panel_puro$ola)
names(waves) <- paste0("T", 1:4)

wide <- panel_merge(waves, by = c("id_hogar", "nper"), require = "all")
c(T1_sample = nrow(waves$T1), linked_all_four = nrow(wide))
#>       T1_sample linked_all_four 
#>            2314            2142
```

`require = "all"` keeps the units observed in **every** wave;
`require = "any"` would keep the union. Each repeated variable is
suffixed by wave, and a `.wf_in_<wave>` indicator records presence.
Adding a wave can only remove units, never add them, which is the
defining property of the design and worth checking as you go:

``` r

vapply(2:4, function(k)
  nrow(panel_merge(waves[1:k], by = c("id_hogar", "nper"), require = "all")),
  integer(1))
#> [1] 2314 2239 2142
```

## Three ways to be missing, and only one of them is nonresponse

The field disposition in these data distinguishes three things that a
single “missing” flag would collapse:

``` r

table(wave_4 = wide$disp_T4)
#> wave_4
#>   NR   OS    R  UNK 
#>  176  100 1804   62
```

- **`OS` – out of scope.** The unit left the target population: it died,
  emigrated, the dwelling was demolished. It is not a nonrespondent; it
  is no longer a member of the universe. Its weight must be **removed**,
  not redistributed, or the estimated population grows every wave.
- **`UNK` – unknown eligibility.** Nobody knows whether the unit is
  still in scope. Treating it as eligible inflates the population;
  treating it as out of scope deflates it. The standard answer is to
  split it in the observed proportion of known-eligible units, which is
  what
  [`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md)
  does.
- **`NR` – nonresponse.** The unit is still in the universe and did not
  answer. Its weight **is** redistributed, among the units that remain.

The order of the steps follows the same logic: leave the universe first,
resolve what is unknown second, and only then adjust for the nonresponse
of those who are certainly in.

``` r

resp <- vapply(1:4, function(k) wide[[paste0("disp_T", k)]] == "R", logical(nrow(wide)))
wide$responded_always <- rowSums(resp) == 4

lw <- weighting_spec(wide, base_weights = w_base_T1) |>
  step_drop_ineligible(disp_T4 == "OS", reason = "left the target population") |>
  step_unknown_eligibility(disp_T4 == "UNK", by = "region_T1") |>
  step_attrition(respondent = responded_always, method = "propensity",
                 formula = ~ edad_T1 + sexo_T1 + region_T1) |>
  prep()

lw
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 2142 cases
#> Base wts: w_base_T1
#> Steps   :
#>   1. drop ineligible (left the target population)  [drop_ineligible_1]
#>   2. unknown eligibility  [unknown_eligibility_1]
#>   3. attrition (propensity)  [nonresponse_1]
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                             stage n_active sum_wts cv_wts deff_kish n_eff
#>                              base     2142  307536  0.300     1.090  1966
#>      stage_1_step_drop_ineligible     2042  293772  0.298     1.089  1875
#>  stage_2_step_unknown_eligibility     1980  293772  0.297     1.088  1820
#>            stage_3_step_attrition     1363  293769  0.297     1.088  1252
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
```

Two things to read there. The **sum of the weights** barely moves at the
attrition step (293,772 to 293,769, one part in a hundred thousand)
while the active sample falls from 1,980 to 1,363: that is what an
adjustment by the inverse of an estimated response propensity is
supposed to do, and
[`weighting_alerts()`](https://jpferreira33.github.io/weightflow/reference/weighting_alerts.md)
says so out loud if the total moves by more than 5%. The **effective
sample size** is the price: 1,820 to 1,252.

Note also how the respondent condition is defined. “Responded in **all**
waves” is the definition of the longitudinal respondent set: someone who
answered three of four waves contributes no complete trajectory and is a
nonrespondent here, however useful they are for the cross-section.

### Attrition compounds

``` r

data.frame(through = paste0("T", 1:4),
           complete = vapply(1:4, function(k) sum(rowSums(resp[, 1:k, drop = FALSE]) == k), 0L))
#>   through complete
#> 1      T1     2040
#> 2      T2     1814
#> 3      T3     1622
#> 4      T4     1363
```

Each wave keeps between 84% and 89% of the previous one, so by the
fourth only two of every three initial respondents are left. This is the
structural reason a longitudinal weight carries more adjustment than a
cross-sectional one, and why the propensity model deserves more care: by
the fourth wave it is doing the work of a much larger correction.

## Calibrate to the **first** wave

A panel adds no elements over time, so it is representative only of the
population of the period in which it was selected. ECLAC’s
household-survey manual (ch. XVI, sec. B.2.c) is explicit that the
auxiliary totals must therefore represent the population of the
**first** period of interest.

``` r

t1 <- waves$T1
sex_tab <- data.frame(sexo_T1   = names(tapply(t1$w_base, t1$sexo, sum)),
                      Freq      = as.numeric(tapply(t1$w_base, t1$sexo, sum)))
reg_tab <- data.frame(region_T1 = names(tapply(t1$w_base, t1$region, sum)),
                      Freq      = as.numeric(tapply(t1$w_base, t1$region, sum)))

lw <- weighting_spec(wide, base_weights = w_base_T1) |>
  step_drop_ineligible(disp_T4 == "OS", reason = "left the target population") |>
  step_unknown_eligibility(disp_T4 == "UNK", by = "region_T1") |>
  step_attrition(respondent = responded_always, method = "propensity",
                 formula = ~ edad_T1 + sexo_T1 + region_T1) |>
  step_calibrate(method = "raking", totals = list(sex_tab, reg_tab), count = "Freq") |>
  prep()

c(calibrated = sum(lw$final_weight), T1_population = sum(t1$w_base))
#>    calibrated T1_population 
#>      333288.2      333288.2
```

(In production those totals are demographic projections; here the
design-weighted totals of the full first wave stand in for them.)

This is the one convention in the whole cascade that **nothing can check
for you**. A vector of control totals carries no label saying which
period it belongs to, so passing the fourth wave’s projections converges
just as happily, closes just as cleanly, and produces weights that
represent a population the sample never had a chance to cover. The
recipe is auditable; the provenance of the totals is yours.

## Gross flows

A net change is a difference of aggregates: it cannot tell an immobile
population from one where equal numbers enter and leave employment. The
longitudinal weight can.

``` r

STATES <- c("emp", "unemp", "inact")
transition_matrix(lw, from = "condicion_T1", to = "condicion_T4",
                  states = STATES, format = "row")
#> <weightflow transition: condicion_T1 -> condicion_T4  [row]>
#>        to
#> from       emp  unemp inact
#>   emp   0.8929 0.1071     0
#>   unemp 0.3086 0.6914     0
#>   inact 0.0000 0.0000     1
```

`format = "row"` gives the conditional distribution of the destination
given the origin – each row sums to one. `"joint"` gives the joint
distribution and `"counts"` the weighted counts. For standard errors,
resample the whole recipe and read the transitions off the replicates:

``` r

b <- bootstrap_weights(lw, replicates = 100, strata = "estrato_T1", psu = "psu_T1",
                       seed = 1, progress = FALSE)
boot_transition(b, "condicion_T1", "condicion_T4", states = STATES, format = "row")
#> <weightflow transition: condicion_T1 -> condicion_T4  [row]  with bootstrap SE>
#> estimate:
#>        to
#> from       emp  unemp inact
#>   emp   0.8929 0.1071     0
#>   unemp 0.3086 0.6914     0
#>   inact 0.0000 0.0000     1
#> SE:
#>        to
#> from       emp  unemp inact
#>   emp   0.0116 0.0116     0
#>   unemp 0.0269 0.0269     0
#>   inact 0.0000 0.0000     0
```

Every replicate re-runs the eligibility drop, the unknown-eligibility
split, the propensity model and the calibration, so the standard errors
include the cost of having estimated the adjustments – not just the
sampling of the units.

[`boot_flows()`](https://jpferreira33.github.io/weightflow/reference/boot_flows.md)
reports the same information as population totals, adds the **net** flow
`i -> j` minus `j -> i`, and gives the margins: how many started in each
state, how many ended in each, how many stayed and how many moved.

``` r

boot_flows(b, "condicion_T1", "condicion_T4", states = STATES)
#> <weightflow gross flows (population totals): condicion_T1 -> condicion_T4  with bootstrap SE>
#> counts (gross flow):
#>        to
#> from         emp   unemp   inact
#>   emp   156012.6 18706.4     0.0
#>   unemp  19272.7 43176.1     0.0
#>   inact      0.0     0.0 96120.4
#> SE:
#>        to
#> from       emp  unemp  inact
#>   emp   5401.4 2108.4    0.0
#>   unemp 2169.9 2867.7    0.0
#>   inact    0.0    0.0 4646.7
#> net flow (i->j minus j->i):
#>        to
#> from      emp  unemp inact
#>   emp     0.0 -566.2     0
#>   unemp 566.2    0.0     0
#>   inact   0.0    0.0     0
#> margins (origin = started in state, dest = ended in state):
#>  state   origin origin_se     dest dest_se
#>    emp 174719.1    5595.3 175285.3  5348.6
#>  unemp  62448.8    3764.0  61882.6  3440.4
#>  inact  96120.4    4646.7  96120.4  4646.7
#> stayers 295309 (SE 2943)  |  movers 37979 (SE 2943)
```

A caveat about the illustration, not the method: the shipped panel
datasets are synthetic, and in all of them **inactivity is an absorbing
state** – nobody enters or leaves it. So the matrices above show
movement only between employment and unemployment, and the `inact` row
and column are degenerate. On real microdata the transitions in and out
of inactivity are usually the interesting ones.

## Cross-sectional estimates from a longitudinal file are reference only

They will not reproduce the published cross-sectional figures, and they
should not. The target population of a four-wave panel combination is
the set of units that were in the universe at T1 **and stayed** through
T4; the target population of the T4 cross-section is everyone in the
universe at T4, including those who entered after T1. Two different
populations, two different weights, both correct for their own question.
Use the longitudinal weight for flows, transitions and durations, and
the cross-sectional weight for levels.

[`step_cross_sectional()`](https://jpferreira33.github.io/weightflow/reference/step_cross_sectional.md)
marks a recipe as the second kind, which is what stops the
panel-specific guards from firing on a recipe that is not trying to be
longitudinal.

## Where to look next

[`?panel_merge`](https://jpferreira33.github.io/weightflow/reference/panel_merge.md)
for the linkage,
[`?step_attrition`](https://jpferreira33.github.io/weightflow/reference/step_attrition.md)
for the adjustment families,
[`?step_unknown_eligibility`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md)
and
[`?step_drop_ineligible`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md)
for the two things that are not nonresponse,
[`?transition_matrix`](https://jpferreira33.github.io/weightflow/reference/transition_matrix.md)
and
[`?boot_flows`](https://jpferreira33.github.io/weightflow/reference/boot_flows.md)
for the flows, and
[`?step_cross_sectional`](https://jpferreira33.github.io/weightflow/reference/step_cross_sectional.md)
for the ECLAC conventions in full. The rotating case, net change and the
chained production workflow are in
[`vignette("rotating-panels")`](https://jpferreira33.github.io/weightflow/articles/rotating-panels.md).
