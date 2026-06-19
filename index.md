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
stage.

`plot(fitted)` shows a diagnostic grid (per-step factor histograms plus
a summary panel) and `weight_factors(fitted)` returns the per-unit,
per-step factors for custom plots. `report_weighting(fitted)` writes a
self-contained HTML report — recipe, requested parameters per step,
per-stage summary and diagnostics, plus per-step plots (weight
before-vs-after scatter and the adjustment-factor histogram, drawn as
inline SVG with no graphics device required). It opens in the browser —
no Shiny or server needed.

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

## Installation

``` r

# install.packages("remotes")
remotes::install_github("jpferreira33/weightflow")
```

weightflow is dependency-free (base R, R \>= 4.1). `rpart` and `ranger`
are optional, needed only for the tree/forest nonresponse engines.

## The design idea

The recipe is **inert**: building it computes nothing.
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
walks the steps *in order* and estimates the cascade of factors;
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md)
extracts the final weights. Separating *define* from *apply* is what
makes it reproducible and auditable.

The package ships with two example datasets, `sample_survey` (a
household sample with design weights, an unknown-eligibility flag and a
response indicator) and `population` (the frame, used for calibration
targets), so the example below runs as-is:

``` r

library(weightflow)

recipe <- weighting_spec(sample_survey, base_weights = pw) |>
  step_unknown_eligibility(unknown = unknown_elig, by = "region") |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = c("region", "sex")) |>
  step_trim(max_ratio = 3, reference = "base", redistribute = FALSE) |>
  step_calibrate(method = "raking",
                 margins = list(sex    = c(table(population$sex)),
                                region = c(table(population$region))))

fitted <- prep(recipe)              # estimate the cascade
summary(fitted)                     # per-stage diagnostics + Kish deff
plot(fitted)                        # diagnostic plots
wts    <- collect_weights(fitted)   # data.frame with .weight
```

## Try it

After installing, the bundled datasets let you run the whole pipeline
right away — no data prep needed:

``` r

library(weightflow)

fitted <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = "region") |>
  step_calibrate(method = "raking",
                 margins = list(sex    = c(table(population$sex)),
                                region = c(table(population$region)))) |>
  prep()

summary(fitted)
collect_weights(fitted)
```

The `data-raw/weightflow_data.R` script shows how `population` and
`sample_survey` are generated, if you want to reproduce or tweak them.

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
- Deville & Särndal (1992). Calibration estimators (bounded / logit
  distance).

## License

MIT © 2026 Juan Pablo Ferreira
