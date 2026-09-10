# Composite estimation: borrowing strength from the previous wave

In a rotating panel most of this month’s sample was also in last
month’s. The **composite estimator** uses that: it adds the previous
wave’s labour status to the calibration as an auxiliary variable, with
control totals taken from the previous wave’s own composite estimates.
The result is a level series that is smoother and, much more to the
point, a **change** that is measured far more precisely – because the
estimator is partly built from the same units twice.

[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
implements the regression composite estimator of Fuller and Rao (2001)
and Gambino, Kennedy and Singh (2001), in the form the Canadian LFS and
Uruguay’s ECH use. This article covers what it does, what it costs, and
the one thing that makes its variance different from every other step in
the package.

## The recursion

The estimator is defined by a recursion, so a chain needs a starting
point. The **seed** wave has no `t-1`: with `previous = NULL` the
composite block is empty and
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
reduces to an ordinary linear calibration to the demographic totals `X`.
From the second wave on, `previous` is the prepped recipe of the wave
before, and the calibration targets `X` **and** the composite totals
`Zhat` built from it.

``` r

wv <- lapply(1:3, function(k) {
  d <- subset(panel_ine, ola == k & disp == "R"); d$sexo <- factor(d$sexo); d
})
Xtot <- function(d) colSums(d$w_base * model.matrix(~ sexo, data = d))
```

``` r

seed <- weighting_spec(wv[[1]], base_weights = w_base) |>
  step_cre(previous = NULL, status = condicion, formula = ~ sexo,
           totals = Xtot(wv[[1]]), status_ref = "inact") |>
  prep()

wave2 <- weighting_spec(wv[[2]], base_weights = w_base) |>
  step_cre(previous = seed, status = condicion, composite = list(NULL, "sexo"),
           id_unit = c("id_hogar", "nper"), formula = ~ sexo,
           totals = Xtot(wv[[2]]), alpha = 2/3, status_ref = "inact")
```

`composite` is the list of domain crossings that define the composite
blocks: `NULL` is the country total, `"sexo"` is status crossed by sex,
and a character vector is status crossed by the interaction. The ECH’s
own list is `list(NULL, "sex", "department")`. `status_ref` names the
status level left implicit in each block – one level must always be
dropped, or the block is collinear with the intercept of `X`; naming it
only decides which one is implied. `alpha` mixes the MR1 and MR2
variants: 0 targets the level alone, 1 the change alone, and 2/3 is the
Chen and Liu (2002) compromise both agencies use.

`id_unit` is how a unit finds its own `t-1` status. Units with no
previous value – the birth rotation group, new household members, people
newly of working age – are handled by `birth` and `on_missing_prev`; by
default they carry their current status backward.

## What it buys

The comparison worth making is against the same recipe with an ordinary
calibration, over the same chain, with the same replicates:

``` r

EST <- list(unemp_rate = function(w, d) weighted.mean(d$desocupado, w, na.rm = TRUE))

run <- function(composite) {
  prev <- NULL; out <- list()
  for (k in 1:3) {
    sp <- weighting_spec(wv[[k]], base_weights = w_base)
    sp <- if (composite)
      step_cre(sp, previous = if (k == 1) NULL else out[[k - 1]]$prepped,
               status = condicion, composite = list(NULL, "sexo"),
               id_unit = c("id_hogar", "nper"), formula = ~ sexo,
               totals = Xtot(wv[[k]]), alpha = 2/3, status_ref = "inact")
    else
      step_calibrate(sp, method = "linear", formula = ~ sexo, totals = Xtot(wv[[k]]))
    s <- wave_step(sp, previous = prev, estimands = EST, replicates = 150,
                   strata = "estrato", psu = "psu", period = paste0("T", k),
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
#> 1   composite (CRE)   T2 0.00699 0.854       0.150
#> 2   composite (CRE)   T1 0.00918 0.708       0.292
#> 3 plain calibration   T2 0.01087 0.619       0.381
#> 4 plain calibration   T1 0.01257 0.460       0.540
```

Against the previous month the standard error of the change falls by
about a third, and the correlation between the two periods’ estimates
rises from roughly 0.6 to roughly 0.84. That is the whole point of the
method: the composite auxiliaries make consecutive estimates share more
of their sampling error, and shared error cancels in a difference.

It is not free. The level of period *t* now depends on the previous
wave’s estimates, so an error propagates forward, and the series is
smoother than the data alone would justify – which is why `alpha` exists
and why agencies do not set it to 1.

## The variance trap

Here is the part that makes
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
different from every other step. Its control totals `Zhat` are **not
known population figures**. They are *estimated* from the previous wave,
with the previous wave’s weights, and they carry that wave’s sampling
error.

A single-sample bootstrap does not know this. It resamples the current
wave and re-runs the recipe, but `Zhat` was computed once, from the
previous wave’s frozen point weights, so every replicate calibrates to
the *same* control totals – as if they were census figures. The
resulting variance is too small, and it is too small in precisely the
direction that matters, because the understated part is the one the
change depends on.

The package refuses to let this happen quietly:

``` r

b <- tryCatch(bootstrap_weights(wave2, replicates = 5, strata = "estrato",
                                psu = "psu", progress = FALSE),
              warning = function(w) conditionMessage(w))
b
#> [1] "bootstrap_weights(): the recipe contains step_cre() (composite regression). This single-sample bootstrap treats the composite control totals Zhat as FIXED, so it understates the variance. Use wave_bootstrap() for the coordinated, honest variance of the recursive composite estimator."
```

The honest version re-estimates `Zhat` inside every replicate: replicate
*b* of period *t* rebuilds its control totals from replicate *b* of
period *t-1*. That is what
[`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
and
[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md)
do, and it is the reason a chain that contains
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
needs the previous period’s **replicate weights**, not just its
replicate estimates.

## The fat carry

Hence the two shapes of the carry. `carry = "auto"`, the default,
inspects the recipe: with no
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
it stores only the replicate values of the declared estimands, and with
one it stores the replicate weight matrix as well.

``` r

c(thin_KB = as.numeric(object.size(plain[[1]]$carry)) / 1024,
  fat_KB  = as.numeric(object.size(cre[[1]]$carry))   / 1024)
#>    thin_KB     fat_KB 
#>   85.88281 2614.17188
```

Thirty times larger, and the difference is entirely the `R * n` matrix
of replicate weights. For a monthly production chain that is a few
megabytes per period, which is the price of an honest variance for the
composite estimator.

The injection is audited, so you can confirm it happened rather than
assuming it:

``` r

c(injected = cre[[2]]$step$n_cre_injected, skipped = cre[[2]]$step$n_cre_skipped)
#> injected  skipped 
#>        1        0
```

`n_cre_injected` counts the CRE steps that received the previous
period’s replicate weights; `n_cre_skipped` counts those that did not –
because no carry contained them, or because the carry was thin. A chain
running with `skipped > 0` is producing the anticonservative variance
the warning above is about, and the number is there so that a production
run can assert on it.

## Equal representation across rotation groups

Both methodologies impose one more constraint: each rotation group must
weight to the same working-age total, `N / G` (ECH sec. 8.4.1; LFS
sec. 6.3.1). Passing `rotation_group` adds it, as `G - 1` extra columns
in the demographic block – the last group’s total follows from the
others and `N`, so constraining it too would be redundant.

``` r

step_cre(spec, previous = seed, status = condicion, composite = list(NULL, "sexo"),
         id_unit = c("id_hogar", "nper"), formula = ~ sexo, totals = Xtot(wv[[2]]),
         rotation_group = "grupo_rotacion", status_ref = "inact")
```

## Where to look next

[`?step_cre`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
for the full argument list and the references,
[`vignette("coordinated-replication")`](https://jpferreira33.github.io/weightflow/articles/coordinated-replication.md)
for the mechanism that pairs the replicates across waves,
[`vignette("rotating-panels")`](https://jpferreira33.github.io/weightflow/articles/rotating-panels.md)
for the production workflow, and
[`?wave_carry`](https://jpferreira33.github.io/weightflow/reference/wave_carry.md)
for what travels between runs.
