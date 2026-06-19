# Calibration to population totals

Calibration to population totals

## Usage

``` r
step_calibrate(
  spec,
  margins = NULL,
  method = c("raking", "poststratify", "linear"),
  formula = NULL,
  totals = NULL,
  cluster = NULL,
  equal_within_cluster = FALSE,
  calfun = c("linear", "logit"),
  bounds = NULL,
  maxit = 50L,
  tol = 1e-06
)
```

## Arguments

- spec:

  a weighting_spec.

- margins:

  named list (for "raking"/"poststratify"). Each element is a named
  numeric vector with the target totals per category. E.g.: list(sex =
  c(M = 5000, F = 5200), region = c(N = 3000, S = 7200)).

- method:

  "raking" (IPF, categorical margins), "poststratify" (a single
  categorical variable) or "linear" (GREG / regression estimator;
  handles continuous and categorical auxiliaries together).

- formula:

  (only "linear") auxiliary formula, e.g. ~ sex + income. Uses
  model.matrix; includes the intercept unless you write ~ 0 + ...

- totals:

  (only "linear") named numeric vector with the population totals, names
  matching the model.matrix columns (including "(Intercept)" = N if
  there is an intercept). If names do not match, the error lists the
  expected ones.

- cluster:

  (only "linear") name of the cluster id column (e.g. "household"), for
  equal weights within the cluster.

- equal_within_cluster:

  (only "linear") logical. If TRUE, Lemaitre-Dufour (1987) integrative
  calibration: a single weight per cluster. Requires `cluster`. Final
  weights are equal within the cluster provided the incoming weight is
  also uniform within the cluster.

- calfun:

  (only "linear") distance function: "linear" (g = 1 + u) or "logit"
  (bounded by construction). With "logit", `bounds` is required.

- bounds:

  (only "linear") numeric c(L, U) with L \< 1 \< U. Bounds on the
  calibration factor g (g-weights). With "linear" it truncates; with
  "logit" it is enforced smoothly. Avoids extreme/negative weights
  without a separate trimming step.

- maxit, tol:

  convergence control for raking and bounded calibration.

## Examples

``` r
# Raking to population margins
weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  step_calibrate(method = "raking",
                 margins = list(sex    = c(table(population$sex)),
                                region = c(table(population$region)))) |>
  prep()
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. nonresponse (weighting class)
#>   2. calibration (raking)
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                     stage n_active sum_wts cv_wts deff_kish n_eff
#>                      base      467    4371  0.236     1.056   442
#>  stage_1_step_nonresponse      270    4371  0.144     1.021   265
#>    stage_2_step_calibrate      270    4495  0.211     1.045   258
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
```
