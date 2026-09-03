# further step constructors: model-assisted calibration, assert, weight trimming (Tukey/Potter), calibration-preserving trimming, rescale.

#' Use a weighted survey as the calibration reference instead of a frame
#'
#' Wraps a reference-survey microdata `data.frame` together with its design
#' weights so it can be passed as the `population` argument of
#' [step_model_calibration()] (and any step that takes a `population` frame).
#' The calibration totals are then the *weighted* sums over the reference survey
#' -- an estimate of the population totals -- instead of unweighted sums over a
#' full frame. This is the model-assisted / two-survey setup: fit the model on
#' your sample, project it onto a larger reference survey, and calibrate to the
#' weighted totals of the projection (Wu and Sitter 2001; Kim and Rao 2012).
#'
#' A reference survey with all weights equal to 1 reproduces the plain-frame
#' behaviour exactly. To propagate the reference survey's own sampling variance
#' into the recipe-aware bootstrap, pass its replicate weights through
#' `replicates`: each bootstrap replicate then re-estimates the totals from the
#' paired reference replicate (Opsomer and Erciulescu 2021), so the extra
#' variance from estimating the totals is captured. Without `replicates` the
#' totals are treated as fixed (a reasonable approximation when the reference is
#' much larger than the sample, and the same assumption made when calibrating to
#' another survey's published totals).
#'
#' @param data a `data.frame` of reference-survey microdata, with the columns
#'   used in `x_formula` and the model predictors.
#' @param weights either the name (string) of a positive weight column in `data`,
#'   or a numeric vector with one weight per row.
#' @param replicates optional numeric matrix (or data.frame) of replicate weights
#'   for the reference survey -- one row per reference unit, one column per
#'   replicate -- used to propagate the reference sampling variance through
#'   [bootstrap_weights()]. `NULL` (default) treats the totals as fixed. Note that
#'   only [bootstrap_weights()] pairs the reference replicates and propagates this
#'   variance; [jackknife_weights()] treats the estimated totals as fixed even when
#'   `replicates` is supplied, so use the bootstrap when this component matters.
#' @return `data` tagged so that `step_model_calibration()` weights its totals by
#'   `weights`. It is still an ordinary `data.frame`.
#' @seealso [step_model_calibration()]
#' @examples
#' ref <- reference_sample(population, weights = rep(1, nrow(population)))
#' @export
reference_sample <- function(data, weights, replicates = NULL) {
  if (!is.data.frame(data))
    stop("`data` must be a data.frame (the reference survey microdata).", call. = FALSE)
  w <- if (is.character(weights) && length(weights) == 1L) {
    if (!weights %in% names(data))
      stop(sprintf("Weights column '%s' not found in the reference `data`.", weights), call. = FALSE)
    data[[weights]]
  } else weights
  if (!is.numeric(w) || length(w) != nrow(data))
    stop("`weights` must be the name of a weight column, or a numeric vector with ",
         "one value per row of `data`.", call. = FALSE)
  if (anyNA(w) || any(!is.finite(w)) || any(w <= 0))
    stop("Reference-sample weights must be finite and strictly positive ",
         "(no NA, zero or negative weights).", call. = FALSE)
  attr(data, "wf_ref_weights") <- as.numeric(w)
  if (!is.null(replicates)) {
    R <- as.matrix(replicates)
    if (!is.numeric(R) || nrow(R) != nrow(data) || ncol(R) < 2L)
      stop("`replicates` must be a numeric matrix (or data.frame) with one row per ",
           "reference unit and at least 2 replicate-weight columns.", call. = FALSE)
    if (anyNA(R) || any(!is.finite(R)) || any(R < 0))
      stop("Reference replicate weights must be finite and non-negative (no NA).", call. = FALSE)
    dimnames(R) <- NULL
    attr(data, "wf_ref_replicates") <- R
  }
  class(data) <- unique(c("wf_reference_sample", class(data)))
  data
}

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
#'   columns (the y variables are not needed; they are predicted). May instead be
#'   a weighted reference survey wrapped with [reference_sample()], in which case
#'   the totals are the design-weighted sums over that survey (estimated totals)
#'   rather than unweighted sums over a full frame. Always
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
#' @param calfun distance function for the calibration, as in [step_calibrate()]:
#'   `"linear"` (GREG, the default; closed form when unbounded), `"raking"` or
#'   `"logit"` (both solved by the Deville-Sarndal iteration). `"logit"` requires
#'   `bounds`.
#' @param bounds optional numeric `c(L, U)` with `L < 1 < U`, bounding the
#'   calibration g-factor so the final weights stay in `[L, U]` times the incoming
#'   weight (same meaning and validation as in [step_calibrate()]). `NULL`
#'   (default) leaves the calibration unbounded. When set, the g-factors are found
#'   by the bounded Deville-Sarndal iteration, which keeps weights from turning
#'   negative or exploding; an infeasible range raises a non-convergence warning.
#' @param maxit,tol iteration cap and convergence tolerance for the bounded /
#'   non-linear solver (ignored for unbounded `calfun = "linear"`).
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
#' @param id optional string: a stable identifier for this step, shown in the
#'   recipe print-out and usable to select it in `collect_step_detail()`; defaults
#'   to a derived `"<class>_<k>"`.
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
#' @family weighting steps
step_model_calibration <- function(spec, x_formula, models, population,
                                   x_totals = NULL, count = "Freq",
                                   cluster = NULL, equal_within_cluster = FALSE,
                                   calfun = c("linear", "logit", "raking"),
                                   bounds = NULL, maxit = 100L, tol = 1e-7,
                                   crossfit = NULL, crossfit_seed = NULL, id = NULL) {
  if (!inherits(spec, "weighting_spec"))
    stop("The first argument must be a weighting_spec.")
  if (missing(x_formula) || missing(models) || missing(population))
    stop("`x_formula`, `models` and `population` are required.")
  if (!inherits(x_formula, "formula")) stop("`x_formula` must be a formula ~ x.")
  calfun <- match.arg(calfun)
  # `bounds` on the g-factor, with the same meaning and validation as
  # step_calibrate(method = "linear"): keeps the final weight in [L, U] * base.
  if (calfun == "logit" && is.null(bounds))
    stop("calfun = 'logit' requires `bounds` = c(L, U).", call. = FALSE)
  if (!is.null(bounds)) {
    if (!is.numeric(bounds) || length(bounds) != 2L || anyNA(bounds) ||
        any(!is.finite(bounds)))
      stop("`bounds` must be a numeric vector c(L, U) of two finite numbers.",
           call. = FALSE)
    if (bounds[1] >= 1 || bounds[2] <= 1)
      stop("`bounds` must be c(L, U) with L < 1 < U.", call. = FALSE)
  }
  maxit <- .wf_count(maxit, "maxit", min = 1L)
  if (!is.numeric(tol) || length(tol) != 1L || !is.finite(tol) || tol <= 0)
    stop(sprintf("`tol` must be a single positive finite number; got %s.",
                 deparse(tol)[1]), call. = FALSE)
  if (!is.list(models) || is.null(names(models)))
    stop("`models` must be a named list of y_model().")
  # Each element must be a y_model() result, not a bare formula (a common slip:
  # models = list(y = y ~ x)), which would crash later reaching for $engine.
  if (!all(vapply(models, function(m) inherits(m, "wf_y_model"), logical(1))))
    stop("Each element of `models` must be a y_model() result, e.g. list(income = y_model(income ~ age + sex)).",
         call. = FALSE)
  if (!is.data.frame(population))
    stop("`population` must be a data.frame with the auxiliaries/predictors for the whole population.")
  equal_within_cluster <- .wf_flag(equal_within_cluster, "equal_within_cluster")
  id <- .wf_id(id)
  if (!is.null(crossfit)) {
    if (!is.numeric(crossfit) || length(crossfit) != 1L || !is.finite(crossfit) ||
        crossfit < 2 || crossfit != round(crossfit))
      stop("`crossfit` must be NULL or a single integer >= 2 (number of folds).", call. = FALSE)
    crossfit <- as.integer(crossfit)
  }
  if (!is.null(crossfit_seed) &&
      (!is.numeric(crossfit_seed) || length(crossfit_seed) != 1L || !is.finite(crossfit_seed)))
    stop("`crossfit_seed` must be NULL or a single finite number.", call. = FALSE)
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
      calfun     = calfun,
      bounds     = bounds,
      maxit      = maxit,
      tol        = tol,
      crossfit      = if (is.null(crossfit)) NULL else as.integer(crossfit),
      crossfit_seed = crossfit_seed
    ),
    class = c("step_model_calibration", "weighting_step")
  )
  .add_step(spec, step, id = id)
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
#' @param id optional string: a stable identifier for this step, shown in the
#'   recipe print-out; defaults to a derived `"<class>_<k>"`.
#' @examples
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_assert(max_deff = 5, on_fail = "warning") |> prep()
#' @return The input `weighting_spec` with this checkpoint appended to its
#'   recipe. The check is recorded only; it is evaluated when `prep()` is called
#'   and does not modify the weights.
#' @family weighting steps
step_assert <- function(spec, max_deff = NULL, max_weight_ratio = NULL,
                        min_n_eff = NULL, on_fail = c("error", "warning"), id = NULL) {
  on_fail <- match.arg(on_fail)
  # Validate the thresholds: a non-numeric threshold (e.g. "500") would be
  # compared lexicographically at apply time, silently inverting the assertion.
  .chk_thr <- function(x, nm) {
    if (!is.null(x) && (!is.numeric(x) || length(x) != 1L || !is.finite(x) || x <= 0))
      stop(sprintf("`%s` must be a single positive finite number (or NULL).", nm),
           call. = FALSE)
  }
  .chk_thr(max_deff, "max_deff")
  .chk_thr(max_weight_ratio, "max_weight_ratio")
  .chk_thr(min_n_eff, "min_n_eff")
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
  .add_step(spec, step, id = id)
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
#' @param id optional string: a stable identifier for this step, shown in the
#'   recipe print-out and usable to select it in `collect_step_detail()`; defaults
#'   to a derived `"<class>_<k>"`.
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
#' @family weighting steps
step_trim_weights <- function(spec, lower = 1, upper = NULL,
                              method = c("tukey", "potter"),
                              redistribute = c("proportional", "uniform"),
                              strict = TRUE, maxit = 50L, id = NULL) {
  method       <- match.arg(method)
  redistribute <- match.arg(redistribute)
  # M3: this step applies a single absolute band to every unit; it has no `by`.
  # A named or length > 1 `lower`/`upper` (e.g. `upper = c(North = 16)`) would be
  # recycled to a scalar and silently applied to everyone. Reject it and point to
  # step_trim_calibrated(), which does take per-subgroup bounds through `by`.
  chk_scalar <- function(x, nm) {
    if (is.null(x)) return(invisible())
    if (length(x) != 1L || !is.null(names(x)))
      stop(sprintf(paste0("`%s` in step_trim_weights() must be a single unnamed number; ",
                          "got %s. For per-group bounds use step_trim_calibrated(by = ...)."),
                   nm, deparse(x)[1]), call. = FALSE)
    if (!is.numeric(x) || is.na(x))
      stop(sprintf("`%s` in step_trim_weights() must be a single number (Inf/-Inf allowed for no bound); got %s.",
                   nm, deparse(x)[1]), call. = FALSE)
  }
  chk_scalar(lower, "lower"); chk_scalar(upper, "upper")
  if (!is.null(lower) && !is.null(upper) && lower >= upper)
    stop("`lower` must be strictly below `upper`.", call. = FALSE)
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
  .add_step(spec, step, id = id)
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
#' This step is meant to run **after** a `step_calibrate()` or a
#' `step_model_calibration()`: it acts on the active incoming weights (including
#' any negative weights an unbounded linear calibration produced, which it can
#' bring back into `[lower, upper]`) and leaves dropped units (weight 0) alone.
#' After a `step_model_calibration()` it preserves both the known-margin totals
#' and the model-prediction totals: that step saves its prediction columns, which
#' this step appends to `formula`'s design so the trimmed weights keep every total
#' the model calibration reproduced (pass the same `x_formula` as `formula`).
#'
#' @param spec a weighting_spec.
#' @param formula the auxiliaries whose calibration totals must be preserved
#'   (right-hand side only), e.g. `~ region + age_group`. Usually the same
#'   formula used in the preceding `step_calibrate()` (or the `x_formula` of the
#'   preceding `step_model_calibration()`, whose model-prediction totals are then
#'   preserved as well).
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
#' @references Deville, J.-C. and Sarndal, C.-E. (1992). Calibration estimators in
#'   survey sampling. Journal of the American Statistical Association, 87, 376-382.
#'   \doi{10.2307/2290268}. The totals-preserving trimming solves a bounded
#'   (range-restricted) calibration with the truncated distances introduced there.
#'   Folsom, R. E. and Singh, A. C. (2000). The generalized exponential model for
#'   sampling weight calibration for extreme values, nonresponse and
#'   poststratification. Proceedings of the ASA Survey Research Methods Section,
#'   598-603, formalises the same range-restricted (generalized exponential) family.
#' @examples
#' # calibrate, then trim the calibrated weights into [5.5, 13.5] without breaking
#' # the region/sex totals (the calibrated weights of sample_survey live in ~[5.4, 14])
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_calibrate(method = "raking",
#'                  margins = list(region = c(table(population$region)),
#'                                 sex    = c(table(population$sex)))) |>
#'   step_trim_calibrated(~ region + sex, lower = 5.5, upper = 13.5) |>
#'   prep()
#' @param id optional string: a stable identifier for this step, shown in the
#'   recipe print-out and usable to select it in `collect_step_detail()`; defaults
#'   to a derived `"<class>_<k>"`.
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
#' @family weighting steps
step_trim_calibrated <- function(spec, formula, lower = NULL, upper = NULL,
                                 calfun = c("linear", "raking"), by = NULL,
                                 cluster = NULL, equal_within_cluster = FALSE,
                                 maxit = 100L, tol = 1e-7, id = NULL) {
  calfun <- match.arg(calfun)
  equal_within_cluster <- .wf_flag(equal_within_cluster, "equal_within_cluster")
  id <- .wf_id(id)
  if (missing(formula) || !inherits(formula, "formula"))
    stop("`formula` must be a formula naming the auxiliaries to preserve, ",
         "e.g. ~ region + age_group.")
  maxit <- .wf_count(maxit, "maxit", min = 1L)
  if (!is.numeric(tol) || length(tol) != 1L || !is.finite(tol) || tol <= 0)
    stop("`tol` must be a single positive finite number.", call. = FALSE)
  # Validate the bounds are numeric BEFORE the lower >= upper comparison, which
  # would otherwise compare strings lexicographically (e.g. lower = "5").
  chk_bnd <- function(b, nm) {
    if (is.null(b)) return(invisible())
    if (!is.numeric(b) || anyNA(b))
      stop(sprintf(paste0("`%s` must be a numeric vector of bounds (a single number, or ",
                          "one per `by` group); got %s."), nm, deparse(b)[1]), call. = FALSE)
  }
  chk_bnd(lower, "lower"); chk_bnd(upper, "upper")
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
  .add_step(spec, step, id = id)
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
#' @param id optional string: a stable identifier for this step, shown in the
#'   recipe print-out and usable to select it in `collect_step_detail()`; defaults
#'   to a derived `"<class>_<k>"`.
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
#' @family weighting steps
step_rescale <- function(spec, to = c("n", "total"), total = NULL, by = NULL, id = NULL) {
  to <- match.arg(to)
  if (to == "total" && is.null(total)) stop("to = 'total' requires `total`.")
  # A4: `by` only makes sense with to = "n" (each group -> its own active size).
  # With to = "total" the whole sample is scaled to one number, so `by` would be
  # ignored -- refuse it instead of dropping it silently and mislabelling the step.
  if (to == "total" && !is.null(by))
    stop("`by` is only supported with to = \"n\" (each group is rescaled to its own ",
         "active size). With to = \"total\" the whole sample is rescaled to a single ",
         "total; drop `by`, or use to = \"n\".", call. = FALSE)
  # N4-3: a NAMED scalar (e.g. c(North = 1000)) is a common attempt at a per-group
  # total; it is not supported and would otherwise scale the whole sample to that
  # number silently. Reject it (length > 1 and non-finite are caught at prep()).
  if (to == "total" && !is.null(total) && length(total) == 1L && !is.null(names(total)))
    stop(sprintf(paste0("`total` must be a single unnamed number; got a named value (%s). ",
                        "A named scalar is not a per-group total -- step_rescale(to = \"total\") ",
                        "rescales the whole sample to one number."),
                 paste(names(total), collapse = ", ")), call. = FALSE)
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
  .add_step(spec, step, id = id)
}
