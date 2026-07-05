# weightflow 0.1.0

First release.

A dependency-free, pipeable API to compute survey weights from design base
weights through a chain of hierarchical adjustment stages. Build a recipe
lazily, estimate it with `prep()`, and extract the weights with
`collect_weights()`. Separating *define* from *apply* makes the whole process
reproducible and auditable, and lets the bootstrap re-run the entire cascade on
each replicate.

## Adjustment steps

* `step_unknown_eligibility()` — redistribute the weight of unknown-eligibility
  cases to the known ones (person- or household-level via `cluster`).
* `step_drop_ineligible()` — zero out out-of-scope units.
* `step_select_within()` — within-household selection (unequal `prob` or equal
  `n_eligible`).
* `step_nonresponse()` — weighting-class or propensity adjustment, at the person
  or household level (`cluster`).
* `step_calibrate()` — raking, post-stratification and linear/GREG calibration,
  with bounded (Deville-Särndal) and integrative (one weight per household)
  cluster options.
* `step_model_calibration()` — Wu-Sitter model calibration.
* `step_trim()`, `step_trim_weights()`, `step_round()`, `step_rescale()` —
  trimming, rounding and rescaling.
* `step_assert()` — quality checkpoint (deff, weight ratio, effective n).

## Inspection and reporting

* `summary()`, `plot()` and `weight_factors()` for per-stage diagnostics.
* `design_effect()` for the Kish design effect and effective sample size.
* `report_weighting()` builds a self-contained HTML report with a pipeline
  diagram, the variables used, per-stage summaries and per-step visuals.

## Variance estimation

* `bootstrap_weights()` resamples PSUs within strata (Rao-Wu rescaling) and
  re-applies the whole recipe on each replicate, so the replicate weights carry
  the variability of every adjustment.
* `boot_mean()` and `boot_total()` return the estimate, standard error and CI.
* `as_svydesign()`, `as_svrepdesign()` and `collect_replicate_weights()` bridge
  to the `survey` and `srvyr` packages for design-based inference.

## Data

* Bundled example datasets `population`, `sample_survey` (take-all roster) and
  `sample_one` (multistage select-one design), all with stratum, PSU and design
  weight.

## Development version

The following are available in the development version on GitHub and are planned
for a future CRAN release:

* **Tidy population totals for `step_calibrate()`.** In addition to the classic
  `margins`/`totals` inputs (which keep working unchanged), calibration targets
  can now be given as tidy data frames, paired with the new `count` argument
  that names the counts column:
    - *Post-stratification*: a data frame with one or more category columns plus
      a counts column. Several category columns are crossed automatically, so
      there is no need to build a collapsed cell variable by hand.
    - *Raking*: a list of data frames, one per margin.
    - *Linear/GREG*: a named list matching the formula terms, with a data frame
      (all categories) for each factor and a single number for each continuous
      total; weightflow builds the model.matrix totals internally, so the user
      never drops a reference category or handles the intercept.
  Calibration also reports clearer diagnostics and warnings: post-stratification
  flags cells in the sample but missing from the totals (error) or in the totals
  but absent from the sample (warning); raking warns on mutually inconsistent
  margins or non-convergence; linear calibration warns when the constraints are
  not fully satisfied; and calibration variables with missing values raise an
  informative error.
* **Subsampling of more than one person per household in `step_select_within()`.**
  A new `n_selected` argument (a single number or an unquoted column) works
  alongside `n_eligible` for simple random selection of a subsample: the weight is
  multiplied by `n_eligible / n_selected` (equivalent to
  `prob = n_selected/n_eligible`). It defaults to 1, so selecting a single person
  keeps working unchanged.
* **External consistency totals for `step_model_calibration()`.** The totals of
  the `x_formula` auxiliaries can now be supplied through the new `x_totals`
  argument, in the same two shapes as `step_calibrate(method = "linear")`: the
  tidy format (a named list with a data frame per factor, paired with `count`,
  and a single number per continuous total) or the classic model-matrix vector.
  This covers the common case where the X control totals come from an external
  source rather than from the frame; the auxiliaries then need to be present only
  in the sample, not in `population`. When `x_totals` is `NULL` (default) the X
  totals are still taken from `population`, so existing code is unchanged.
  `population` remains required, because the model-assisted block predicts each
  outcome over every population unit. Model calibration now also warns, like
  linear calibration, when the achieved totals do not fully satisfy the
  constraints (collinear or ill-conditioned auxiliaries).
* **Machine-learning response propensities** (CART, random forest and gradient
  boosting via `xgboost`) for `step_nonresponse()` and `step_model_calibration()`.
* **k-fold cross-fitting** (`crossfit`) to estimate each unit out-of-sample,
  with folds formed by cluster to avoid leakage.
* **Ridge (penalized) calibration** (`penalty`) to keep weights stable with many
  auxiliaries.
* **Potter MSE-optimal trimming** (`method = "potter"`), a data-driven cutoff.

Install with `remotes::install_github("jpferreira33/weightflow")` to use them
today.
