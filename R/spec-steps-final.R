# further step constructors: model-assisted calibration, assert, weight trimming (Tukey/Potter), calibration-preserving trimming, rescale.

#' Model-assisted calibration (Wu and Sitter 2001)
#'
#' Fits a working model for each study variable, predicts it over the whole
#' population, and calibrates the weights so that the sample total of every
#' prediction matches its population total, on top of the usual auxiliary totals
#' -- which may come from the population frame itself or from an external source
#' (a census table, an administrative register). Reach for it when you hold, or
#' can supply, those control totals and the outcome is well predicted by the
#' auxiliaries: the predictions act as extra, highly relevant controls and buy
#' precision that calibrating on `x` alone cannot.
#'
#' Requires COMPLETE auxiliary information: a data.frame `population` with the
#' `x_formula` columns and the model predictors for the whole population (or a
#' reference frame/census).
#'
#' The predictions \eqn{\hat y_i}{yhat_i} enter as extra constraints,
#' \eqn{\sum_{i \in s} w_i \hat y_i = \sum_{i \in U} \hat y_i}{sum_(i in s) w_i yhat_i = sum_(i in U) yhat_i},
#' solved together with the benchmark auxiliary totals \eqn{\mathbf{X}}{X}. When
#' the working model is linear this reduces to GREG; a nonlinear learner adds
#' efficiency through the prediction constraint while the totals \eqn{\mathbf{X}}{X}
#' preserve design consistency even if the model is misspecified.
#'
#' @param spec a weighting_spec.
#' @param x_formula formula of the consistency auxiliaries, e.g. ~ sex + region.
#' @param models named list of models created with y_model(). The names label
#'   the prediction constraints.
#' @param population population data.frame with the auxiliary and predictor
#'   columns (the y variables are not needed; they are predicted). Always
#'   required: the model-assisted block predicts each y over every population
#'   unit, which cannot be done from aggregated totals.
#' @param x_totals optional population totals for the consistency auxiliaries
#'   (`x_formula`), for when they come from an external source rather than from
#'   `population` (e.g. an official control total, a variable not present in the
#'   frame). Two shapes, the same as `step_calibrate(method = "linear")`: the
#'   tidy format, a named list matching the formula terms with a data frame (all
#'   categories + a counts column named by `count`) per factor and a single
#'   number per continuous total; or the classic model-matrix vector (intercept
#'   plus treatment contrasts). When NULL (default) the X totals are taken from
#'   `population`. When given, the X totals no longer require `x_formula` columns
#'   to exist in `population` (only in the sample), and `population` is used only
#'   for the model predictions.
#' @param count name of the counts column in the tidy `x_totals` data frames.
#'   Only used when `x_totals` is given in the tidy (data-frame) format.
#' @param cluster name of the cluster id column (e.g. "household"), for equal
#'   weights within the cluster.
#' @param equal_within_cluster logical. If TRUE, integrative calibration: a
#'   single weight per cluster. Requires `cluster` and that the incoming weight
#'   be uniform within the cluster.
#' @param crossfit integer or NULL. If given (K >= 2 folds), the outcome models
#'   are fitted by K-fold cross-fitting: the sample predictions are out-of-fold
#'   (each unit predicted by a model that did not see it), which avoids
#'   overfitting with flexible engines; the population total of the predictions
#'   uses the full model. Folds are formed by `cluster` when given. NULL
#'   (default) fits and predicts in-sample. For flexible learners cross-fitting
#'   is also what keeps the variance honest: same-sample residuals are shrunk by
#'   overfitting and can understate the variance even under recipe-aware
#'   replication (Dagdoug, Goga and Haziza 2023; Chernozhukov et al. 2018), so it
#'   is recommended whenever a model uses a non-glm engine.
#' @param crossfit_seed integer or NULL. Seed for reproducible fold assignment.
#' @references Wu, C. and Sitter, R. R. (2001). A model-calibration approach to
#'   using complete auxiliary information from survey data. \emph{Journal of the
#'   American Statistical Association}, 96(453), 185-193.
#'   \doi{10.1198/016214501750333054}.
#' @examples
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_model_calibration(
#'     x_formula  = ~ sex + region,
#'     models     = list(income = y_model(income ~ age + sex, engine = "glm")),
#'     population = population) |>
#'   prep()
#'
#' # with cross-fitting (out-of-fold predictions, avoids overfitting)
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_model_calibration(
#'     x_formula  = ~ sex + region,
#'     models     = list(income = y_model(income ~ age + sex, engine = "glm")),
#'     population = population, crossfit = 5, crossfit_seed = 1) |>
#'   prep()
#'
#' # consistency totals from an external source (tidy format): a data frame per
#' # factor and a single number per continuous total. `population` is still used
#' # for the model predictions. Adjust for nonresponse first, since the outcome
#' # is only observed for respondents.
#' m_region <- as.data.frame(table(region = population$region))
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_model_calibration(
#'     x_formula  = ~ region + age,
#'     models     = list(income = y_model(income ~ age + sex, engine = "glm")),
#'     population = population,
#'     x_totals   = list(region = m_region, age = sum(population$age)),
#'     count      = "Freq") |>
#'   prep()
#'
#' # equal weights within a household (integrative, Lemaitre-Dufour): one weight
#' # per cluster, so person and household estimates stay coherent. The final
#' # weights are constant within each cluster among its active members.
#' fit_hh <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_model_calibration(
#'     x_formula  = ~ sex + region,
#'     models     = list(income = y_model(income ~ age + sex, engine = "glm")),
#'     population  = population,
#'     cluster = "household_id", equal_within_cluster = TRUE) |>
#'   prep()
#' w <- fit_hh$final_weight
#' max(tapply(w[w > 0], sample_survey$household_id[w > 0],
#'            function(x) diff(range(x))))    # 0: one weight per household
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
step_model_calibration <- function(spec, x_formula, models, population,
                                   x_totals = NULL, count = "Freq",
                                   cluster = NULL, equal_within_cluster = FALSE,
                                   crossfit = NULL, crossfit_seed = NULL) {
  if (!inherits(spec, "weighting_spec"))
    stop("The first argument must be a weighting_spec.")
  if (missing(x_formula) || missing(models) || missing(population))
    stop("`x_formula`, `models` and `population` are required.")
  if (!inherits(x_formula, "formula")) stop("`x_formula` must be a formula ~ x.")
  if (!is.list(models) || is.null(names(models)))
    stop("`models` must be a named list of y_model().")
  if (!is.data.frame(population))
    stop("`population` must be a data.frame with the auxiliaries/predictors for the whole population.")
  if (equal_within_cluster && is.null(cluster))
    stop("equal_within_cluster = TRUE requires `cluster`.")
  if (!is.null(crossfit) && (!is.numeric(crossfit) || crossfit < 2))
    stop("`crossfit` must be NULL or an integer >= 2 (number of folds).")
  if (!is.null(x_totals) &&
      !(is.numeric(x_totals) || (is.list(x_totals) && !is.data.frame(x_totals))))
    stop(paste0("`x_totals` must be NULL, a named list (tidy format) or a named ",
                "numeric vector aligned with the model matrix (classic format)."))
  detail <- if (equal_within_cluster)
              sprintf("%d y variables, equal weights by %s", length(models), cluster)
            else sprintf("%d y variables", length(models))
  step <- structure(
    list(
      label      = sprintf("model calibration (%s)", detail),
      x_formula  = x_formula,
      models     = models,
      population = population,
      x_totals   = x_totals,
      count      = count,
      cluster    = cluster,
      equal_within_cluster = equal_within_cluster,
      crossfit      = if (is.null(crossfit)) NULL else as.integer(crossfit),
      crossfit_seed = crossfit_seed
    ),
    class = c("step_model_calibration", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Optional step: assertions / checkpoint --------------------------------

#' Assert quality conditions on the weights
#'
#' A checkpoint that leaves the weights untouched and instead verifies that they
#' meet quality thresholds at this point of the cascade, raising an error or a
#' warning when they do not. Use it to stop a production pipeline before bad
#' weights are published, in the spirit of a validation step inside a recipe.
#'
#' @param spec a weighting_spec.
#' @param max_deff numeric or NULL. Maximum acceptable Kish design effect.
#' @param max_weight_ratio numeric or NULL. Maximum allowed final/base weight
#'   ratio (per active unit).
#' @param min_n_eff numeric or NULL. Minimum acceptable effective sample size.
#' @param on_fail "error" (stop the cascade) or "warning".
#' @examples
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_assert(max_deff = 5, on_fail = "warning") |> prep()
#' @return The input `weighting_spec` with this checkpoint appended to its
#'   recipe. The check is recorded only; it is evaluated when `prep()` is called
#'   and does not modify the weights.
step_assert <- function(spec, max_deff = NULL, max_weight_ratio = NULL,
                        min_n_eff = NULL, on_fail = c("error", "warning")) {
  on_fail <- match.arg(on_fail)
  step <- structure(
    list(
      label            = "assert (checkpoint)",
      max_deff         = max_deff,
      max_weight_ratio = max_weight_ratio,
      min_n_eff        = min_n_eff,
      on_fail          = on_fail
    ),
    class = c("step_assert", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Optional step: automatic weight trimming ------------------------------

#' Automatic weight trimming to an absolute band
#'
#' Caps the weights into an absolute interval `[lower, upper]` and hands the
#' removed mass back to the units that were not capped, so the weighted total is
#' preserved. This is the step to use when you have **not calibrated yet** (or
#' will calibrate afterwards) and you want the cutoff chosen from the data rather
#' than argued for: with `upper = NULL` it picks one by the Tukey far-out fence or
#' by Potter's MSE rule.
#'
#' @param spec a weighting_spec.
#' @param lower numeric. Lower floor (default 1: no weight below 1).
#' @param upper numeric or NULL. Upper cap. If NULL, the cap is chosen
#'   automatically by `method`.
#' @param method rule for the automatic cap when `upper = NULL`: "tukey"
#'   (default, Q3 + 3*IQR far-out fence) or "potter" (Potter's MSE-optimal cutoff,
#'   which over a grid of candidate cutoffs minimizes an estimate of bias^2 +
#'   variance and so balances the bias of trimming against the variance from
#'   extreme weights). Ignored when `upper` is supplied.
#' @param redistribute how the trimmed mass is shared among the untrimmed units:
#'   "proportional" (default; in proportion to their weights, preserving relative
#'   sizes) or "uniform" (an equal amount to each untrimmed unit, and units
#'   already trimmed are not reused, exactly reproducing survey::trimWeights()).
#' @param strict logical. If TRUE (default), iterate cap+redistribution until no
#'   weight is outside `[lower, upper]` (like survey's strict = TRUE). If FALSE, a
#'   single pass (redistribution may push some weights slightly past the cap).
#' @param maxit integer. Maximum iterations when strict = TRUE.
#' @examples
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_trim_weights(lower = 1, strict = TRUE) |> prep()
#'
#' # Potter MSE-optimal cutoff chosen from the data
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_trim_weights(method = "potter") |> prep()
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
step_trim_weights <- function(spec, lower = 1, upper = NULL,
                              method = c("tukey", "potter"),
                              redistribute = c("proportional", "uniform"),
                              strict = TRUE, maxit = 50L) {
  method       <- match.arg(method)
  redistribute <- match.arg(redistribute)
  step <- structure(
    list(
      label  = if (method == "potter") "auto weight trimming (Potter MSE)"
               else "auto weight trimming",
      lower        = lower,
      upper        = upper,
      method       = method,
      redistribute = redistribute,
      strict       = strict,
      maxit        = maxit
    ),
    class = c("step_trim_weights", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Optional step: trimmed (range-restricted) calibration -----------------

#' Trimmed calibration (range-restricted, totals-preserving)
#'
#' Pulls already-calibrated weights into an absolute interval `[lower, upper]`
#' without breaking the calibration: instead of capping and redistributing, it
#' re-solves a bounded calibration whose targets are the totals the incoming
#' weights already reproduce, optionally with its own band per subgroup through
#' `by`. It is the only one of the three trimming steps that leaves the
#' calibration totals intact.
#'
#' The absolute-weight bound is imposed as a per-unit factor bound
#' `w_new / w in [lower/w, upper/w]` on top of the incoming weights, using a
#' bounded (range-restricted) calibration with the truncated Deville-Sarndal
#' distances: the range-restricted Euclidean distance (`calfun = "linear"`, the
#' default) or the multiplicative one (`calfun = "raking"`). Weights inside the
#' range that are not needed to restore the totals stay put; the out-of-range ones
#' saturate at their bound and the rest move as little as possible. If the range
#' is too tight to preserve every total, the totals that cannot be met are relaxed
#' and a warning is raised.
#'
#' This step is meant to run **after** a `step_calibrate()`: it acts on the
#' positive incoming weights and leaves dropped units (weight 0) alone.
#'
#' @param spec a weighting_spec.
#' @param formula the auxiliaries whose calibration totals must be preserved
#'   (right-hand side only), e.g. `~ region + age_group`. Usually the same
#'   formula used in the preceding `step_calibrate()`.
#' @param lower,upper numeric. Absolute bounds on the trimmed weight. At least
#'   one must be supplied; the other defaults to no bound. For positive variance,
#'   use a positive `lower`. Each may be a single number (the same bound for every
#'   unit) or, together with `by`, a named vector of bounds per subgroup (names =
#'   the `by` group levels), for differentiated trimming.
#' @param calfun distance function: "linear" (default; the range-restricted
#'   Euclidean distance) or "raking" (the multiplicative distance, which keeps
#'   the adjustment factors positive).
#' @param by character or NULL. Subgroup column for differentiated bounds: with a
#'   named-vector `lower`/`upper`, each subgroup is trimmed to its own bounds
#'   while the preserved totals of `formula` stay global. NULL (default) uses the
#'   same bounds for all units.
#' @param cluster character or NULL. Cluster (e.g. household) id column, for
#'   integrative trimming (with `equal_within_cluster = TRUE`).
#' @param equal_within_cluster logical. If TRUE, integrative trimming: one
#'   trimming factor per `cluster`, so weights stay constant within household.
#'   The incoming weights must already be constant within cluster (e.g. from
#'   `step_calibrate(equal_within_cluster = TRUE)`); the absolute bound then
#'   applies to that common household weight. Requires `cluster`. FALSE
#'   (default) trims each unit on its own.
#' @param maxit integer. Maximum iterations for the bounded solver.
#' @param tol numeric. Convergence tolerance for the bounded solver.
#' @examples
#' # calibrate, then trim the calibrated weights into [6, 13] without breaking
#' # the region/sex totals (the calibrated weights of sample_survey live in ~[5.4, 14])
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_calibrate(method = "raking",
#'                  margins = list(region = c(table(population$region)),
#'                                 sex    = c(table(population$sex)))) |>
#'   step_trim_calibrated(~ region + sex, lower = 6, upper = 13) |>
#'   prep()
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
step_trim_calibrated <- function(spec, formula, lower = NULL, upper = NULL,
                                 calfun = c("linear", "raking"), by = NULL,
                                 cluster = NULL, equal_within_cluster = FALSE,
                                 maxit = 100L, tol = 1e-7) {
  calfun <- match.arg(calfun)
  if (missing(formula) || !inherits(formula, "formula"))
    stop("`formula` must be a formula naming the auxiliaries to preserve, ",
         "e.g. ~ region + age_group.")
  if (is.null(lower) && is.null(upper))
    stop("Supply at least one of `lower` / `upper` (the absolute weight bounds).")
  # `lower`/`upper` may be a single number (same bound for every unit) or, with
  # `by`, a named vector of bounds per subgroup (names = the `by` group levels).
  if (!is.null(lower) && !is.null(upper) &&
      length(lower) == 1L && length(upper) == 1L && lower >= upper)
    stop("`lower` must be strictly below `upper`.")
  if ((length(lower) > 1L || length(upper) > 1L) && is.null(by))
    stop("A vector `lower`/`upper` needs `by` (the subgroup column): give a ",
         "named vector of bounds per group, or a single number.")
  if (isTRUE(equal_within_cluster) && is.null(cluster))
    stop("equal_within_cluster = TRUE requires `cluster` (the household id).")
  fmt <- function(b) if (is.null(b)) NA else if (length(b) > 1L) "by group" else format(b)
  step <- structure(
    list(
      label   = sprintf("trimmed calibration [%s, %s]%s%s",
                        if (is.null(lower)) "-Inf" else fmt(lower),
                        if (is.null(upper)) "Inf"  else fmt(upper),
                        if (!is.null(by)) sprintf(" by %s", by) else "",
                        if (isTRUE(equal_within_cluster)) " (integrative)" else ""),
      formula = formula,
      lower   = lower,
      upper   = upper,
      calfun  = calfun,
      by      = by,
      cluster = cluster,
      equal_within_cluster = equal_within_cluster,
      maxit   = maxit,
      tol     = tol
    ),
    class = c("step_trim_calibrated", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Optional step: rescale / normalize weights ----------------------------

#' Rescale the weights to a fixed sum
#'
#' Multiplies the active weights by a single constant so that they add up to a
#' chosen total: either the number of active units (mean weight 1) or an arbitrary
#' number. Use it as a presentation step, when the analysis wants normalized
#' weights rather than population-scale ones.
#'
#' @param spec a weighting_spec.
#' @param to "n" (weights sum to the number of active units, i.e. mean weight 1)
#'   or "total" (weights sum to `total`).
#' @param total numeric. Target sum when to = "total".
#' @param by character. Rescale within these groups (optional). With to = "n",
#'   each group sums to its own active count.
#' @examples
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_rescale(to = "n") |> prep()
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
step_rescale <- function(spec, to = c("n", "total"), total = NULL, by = NULL) {
  to <- match.arg(to)
  if (to == "total" && is.null(total)) stop("to = 'total' requires `total`.")
  step <- structure(
    list(
      label = sprintf("rescale (to %s%s)", to,
                      if (!is.null(by)) paste0(" by ", paste(by, collapse = "+")) else ""),
      to    = to,
      total = total,
      by    = by
    ),
    class = c("step_rescale", "weighting_step")
  )
  .add_step(spec, step)
}
