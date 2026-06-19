# weightflow

Declarative, pipeable API to build **survey weights** through
hierarchical stages, tidymodels-style. It starts from design base
weights and chains adjustments:

1.  **Unknown eligibility** — redistributes the weight of
    unknown-eligibility cases among the known-eligibility ones.
2.  **Nonresponse** — by weighting classes (cells) or by **propensity**
    estimated with logistic regression (`engine = "logit"`), CART trees
    (`engine = "tree"`, via `rpart`) or random forest
    (`engine = "forest"`, via `ranger`). Propensities are used as a
    direct `1/p` factor per unit (`num_classes = NULL`) or grouped into
    classes (`num_classes = k`).
3.  **Calibration** — *raking* (IPF, categorical margins),
    *post-stratification* (one categorical variable) or *linear / GREG*
    (`method = "linear"`, with a formula and population totals; handles
    **continuous** and categorical auxiliaries). Linear calibration also
    offers **equal weights within a cluster**
    (`equal_within_cluster = TRUE` with `cluster`), via Lemaitre-Dufour
    1987. integrative calibration — handy so all members of a household
          share the same weight. Plus **model calibration**
          (`step_model_calibration`, Wu & Sitter 2001): predicts several
          `y` variables with working models (glm/tree/random forest) and
          calibrates to their population totals for model-assisted
          efficiency, on top of calibrating to the `X` totals for
          consistency.

Plus an optional **trimming** step (`step_trim`) insertable anywhere in
the cascade, even several times; an optional final **rounding** step
(`step_round`, simple or total-preserving); and the **Kish design
effect** (deff = 1 + CV², with effective sample size) reported at every
stage. `plot(fitted)` shows a diagnostic grid (per-step factor
histograms plus a summary panel) and `weight_factors(fitted)` returns
the per-unit, per-step factors for custom plots.
`report_weighting(fitted)` writes a self-contained HTML report (recipe,
requested parameters per step, per-stage summary and diagnostics) (with
per-step plots — weight before-vs-after scatter and the
adjustment-factor histogram, drawn as inline SVG with no graphics device
required) and opens it in the browser — no Shiny/server needed.

Optional **bounded calibration** (`calfun = "logit"` or
`bounds = c(L, U)` in the linear method) keeps the g-weights within
range without a separate trim. Other optional steps: **assertions**
(`step_assert`, a checkpoint that errors/warns if deff, weight ratio or
effective n cross a threshold), **automatic survey-style trimming**
(`step_trim_weights`: no weight below 1, auto upper cap, `strict = TRUE`
like `survey::trimWeights`), and **rescaling** (`step_rescale`:
normalize weights to the sample size or a target total).

Response and eligibility can be supplied as **0/1 dummy columns** (1 =
responded / 1 = unknown) or as any logical condition.

> Follows the classic framework of Valliant, Dever & Kreuter (*Practical
> Tools for Designing and Weighting Survey Samples*). **It computes
> weights only; it does not estimate variances.** For inference, export
> the weights and use them with `survey`/`srvyr`.

## The design idea

The recipe is **inert**: building it computes nothing.
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
walks the steps *in order* and estimates the cascade of factors;
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md)
extracts the final weights. Separating *define* from *apply* is what
makes it reproducible and auditable.

``` r

recipe <- weighting_spec(survey, base_weights = pw) |>
  step_unknown_eligibility(unknown = unknown_elig, by = "region") |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = c("region", "sex")) |>
  step_trim(max_ratio = 3, reference = "base", redistribute = FALSE) |>
  step_calibrate(margins = list(sex    = c(M = 49000, F = 51000),
                                region = c(North = 42000, South = 58000)),
                 method = "raking")

fitted <- prep(recipe)          # estimate the cascade
summary(fitted)                 # per-stage diagnostics + Kish deff
plot(fitted)                    # diagnostic plots
wts    <- collect_weights(fitted)   # data.frame with .weight
```

## Try it

No installation needed (base R, R \>= 4.1):

``` r

setwd("path/to/weightflow")
source("demo.R")          # full household pipeline
source("demo_model.R")    # model-assisted calibration, tested against a population
```

## Adding a new adjustment

`apply_step()` is the internal S3 generic that computes each step. To
add a new adjustment: define a `step_*()` constructor (inert) and its
`apply_step.<class>()` method. Nothing else changes.

## References

- Valliant, Dever & Kreuter. *Practical Tools for Designing and
  Weighting Survey Samples.*
- Kish (1965, 1990). Design effect from unequal weighting.
- Potter (1988, 1990); Potter & Zheng (2015); Liu et al. (2004). Weight
  trimming.
- Lemaitre & Dufour (1987). Integrative (one weight per household)
  calibration.
- Wu & Sitter (2001). Model-calibration / model-assisted estimation.
