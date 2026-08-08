# pre-calibration step constructors: unknown eligibility, within-household selection, drop-ineligible, nonresponse.

#' Unknown-eligibility adjustment
#'
#' Redistributes the weight of unknown-eligibility cases among the
#' known-eligibility cases, within the cells defined by `by`.
#'
#' @param spec a weighting_spec.
#' @param unknown a 0/1 dummy column (1 = eligibility unknown) or any logical
#'   condition (unquoted) that is TRUE for unknown-eligibility cases. Evaluated
#'   on the data.
#' @param by character. Variables defining the adjustment cells (optional).
#' @param cluster character. Cluster (e.g. household) id column. If given, the
#'   redistribution is done at the cluster level: each cluster counts once with
#'   its (uniform) weight, the weight of unknown-eligibility clusters is
#'   redistributed among the known ones, and the adjusted weight is assigned to
#'   every member. Use this when unknown-eligibility units have no roster (one
#'   row per address) while resolved units are expanded by person.
#' @examples
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_unknown_eligibility(unknown = unknown_elig, by = "region")
#'
#' # household-level redistribution (unknown units without roster)
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_unknown_eligibility(unknown = unknown_elig, by = "region",
#'                            cluster = "household_id")
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
step_unknown_eligibility <- function(spec, unknown, by = NULL, cluster = NULL) {
  step <- structure(
    list(
      label   = if (is.null(cluster)) "unknown eligibility"
                else sprintf("unknown eligibility (by %s)", cluster),
      unknown = substitute(unknown),
      by      = by,
      cluster = cluster,
      env     = parent.frame()
    ),
    class = c("step_unknown_eligibility", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Step: within-household (sub)selection ---------------------------------

#' Within-household selection adjustment
#'
#' When one (or a subsample) of the eligible persons is selected within each
#' household, the selected person represents all eligible persons, so the weight
#' is multiplied by the inverse of the within-household selection probability.
#' Apply it after the (household-level) eligibility adjustment and before the
#' nonresponse adjustment.
#'
#' @param spec a weighting_spec.
#' @param prob unquoted column with the within-household selection probability of
#'   the selected person (need not be 1/n_eligible). The weight is multiplied by
#'   1/prob.
#' @param n_eligible unquoted column with the number of eligible persons in the
#'   household, for simple random selection within the household. When a single
#'   person is selected (the default), the weight is multiplied by n_eligible
#'   (equivalent to prob = 1/n_eligible).
#' @param n_selected optional number of persons selected per household under
#'   simple random selection, when more than one person is subsampled. Either a
#'   single number (same subsample size in every household) or an unquoted column
#'   (subsample size varying by household). The weight is multiplied by
#'   n_eligible / n_selected (equivalent to prob = n_selected/n_eligible).
#'   Defaults to 1. Only used together with `n_eligible`.
#' @examples
#' # simple random selection of one eligible person per household
#' df <- transform(sample_survey,
#'                 n_elig = ave(person_id, household_id, FUN = length))
#' weighting_spec(df, base_weights = pw) |>
#'   step_select_within(n_eligible = n_elig)
#'
#' # simple random selection of two eligible persons per household
#' weighting_spec(df, base_weights = pw) |>
#'   step_select_within(n_eligible = n_elig, n_selected = 2)
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
step_select_within <- function(spec, prob = NULL, n_eligible = NULL,
                               n_selected = NULL) {
  p <- substitute(prob)
  k <- substitute(n_eligible)
  m <- substitute(n_selected)
  if (!is.null(m) && is.null(k))
    stop("`n_selected` only applies together with `n_eligible`.")
  if (is.null(p) && is.null(k))
    stop("Provide either `prob` or `n_eligible`.")
  if (!is.null(p) && !is.null(k))
    stop("Provide only one of `prob` or `n_eligible`.")
  step <- structure(
    list(label = "within-household selection", prob = p,
         n_eligible = k, n_selected = m, env = parent.frame()),
    class = c("step_select_within", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Step: drop ineligible (out-of-scope) units ----------------------------

#' Drop ineligible (out-of-scope) units
#'
#' Sets the weight of known-ineligible units to zero so they leave the cascade
#' (excluded from every later step and from collect_weights). No redistribution
#' is done.
#'
#' Apply it AFTER step_unknown_eligibility: ineligibles must be present and NOT
#' flagged as unknown during that step, so they take part in the
#' known-eligibility group and receive their share of the redistributed unknown
#' weight. Their weight is then correctly discarded here (it represents the
#' ineligible share of the unknown units, which are out of scope).
#'
#' @param spec a weighting_spec.
#' @param ineligible a 0/1 dummy column (1 = ineligible) or any logical
#'   condition (unquoted) that is TRUE for out-of-scope units.
#' @examples
#' df <- transform(sample_survey,
#'                 ineligible = as.integer(region == "West" & age > 90))
#' weighting_spec(df, base_weights = pw) |>
#'   step_drop_ineligible(ineligible = ineligible) |>
#'   prep()
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
step_drop_ineligible <- function(spec, ineligible) {
  step <- structure(
    list(label = "drop ineligible", ineligible = substitute(ineligible),
         env = parent.frame()),
    class = c("step_drop_ineligible", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Step: nonresponse adjustment ------------------------------------------

#' Nonresponse adjustment
#'
#' Inflates the weights of respondents to represent the nonrespondents, under the
#' assumption that response is ignorable given the information used. The response
#' propensity can be estimated by weighting classes (cells), by a model
#' ("propensity"), with engines ranging from logistic regression to machine
#' learning (regression tree, random forest, gradient boosting), or the
#' adjustment can be made by calibrating the respondents to auxiliary totals
#' ("calibration", the two-phase / Sarndal-Lundstrom approach). Optional
#' K-fold cross-fitting estimates the propensity out-of-sample to avoid the
#' overfitting that flexible engines can introduce. The adjustment can be applied
#' at the person or, via `cluster`, the household level.
#'
#' @param spec a weighting_spec.
#' @param respondent a 0/1 dummy column (1 = responded) or any logical condition
#'   (unquoted) TRUE for respondents. Eligible cases that are not respondents
#'   are treated as nonresponse.
#' @param method "weighting_class" (cells), "propensity" (predictive model) or
#'   "calibration" (calibrate the respondents to auxiliary totals; two-phase /
#'   Sarndal-Lundstrom).
#' @param by character. Adjustment cells for method = "weighting_class".
#' @param formula predictor formula (right-hand side only), e.g. ~ age + region,
#'   used when method = "propensity".
#' @param engine engine to estimate the propensity when method = "propensity":
#'   "logit" (logistic regression, base R), "tree" (CART via package 'rpart'),
#'   "forest" (random forest via package 'ranger') or "boost" (gradient boosting
#'   via package 'xgboost'). 'rpart', 'ranger' and 'xgboost' are optional: only
#'   needed if you pick that engine. The flexible learners run with fixed default
#'   settings and their hyperparameters are not currently exposed: "tree" and
#'   "forest" use the 'rpart' and 'ranger' defaults, and "boost" uses xgboost
#'   with nrounds = 150, max_depth = 4 and eta = 0.1.
#' @param weight_model logical. Only for method = "propensity": whether to fit
#'   the response-propensity model with the incoming weights (`TRUE`,
#'   the default) or unweighted (`FALSE`). Fitting unweighted can reduce the
#'   variance of the propensity estimates when the weights are unrelated to
#'   response given the model covariates, at the cost of possible bias if they
#'   are (Little & Vartivarian 2003). The 1/p (or class) adjustment always uses
#'   the design weights; only the model fit is affected.
#' @param num_classes integer or NULL. Controls how propensities are used:
#'   an integer forms that many propensity classes (cell adjustment within each
#'   class); NULL applies the direct factor 1/p to each unit.
#' @param crossfit integer or NULL. If given (number of folds K >= 2), the
#'   propensity is estimated by K-fold cross-fitting: for each fold the model is
#'   trained on the other folds and used to predict the held-out fold, so each
#'   unit's propensity comes from a model that did not see it. This avoids the
#'   overfitting that flexible engines (forest, boost) can produce, which would
#'   otherwise inflate the weights. Folds are formed by `cluster` when given (so
#'   correlated units stay together). NULL (default) fits and predicts in-sample.
#' @param crossfit_seed integer or NULL. Seed for reproducible fold assignment
#'   when `crossfit` is used.
#' @param cluster character or NULL. If given, the adjustment is done at the
#'   cluster (e.g. household) level for whole-household nonresponse: each
#'   household counts once with its (uniform) weight; in "weighting_class" the
#'   redistribution is between responding and nonresponding households within
#'   the cells, and in "propensity" the model is fitted with one row per
#'   household (household auxiliaries), predicting the household response. The
#'   resulting factor is assigned to every member; nonresponding households go to
#'   zero. As always, only active units (weight > 0) take part, so units already
#'   dropped (unknown eligibility, ineligible) are excluded automatically. For
#'   `method = "calibration"`, `cluster` is used together with
#'   `equal_within_cluster = TRUE` for integrative (one weight per household)
#'   calibration.
#' @param totals (method = "calibration") calibration targets. NULL (default)
#'   calibrates the respondents to the R+NR design-weighted totals of `formula`
#'   at that stage (the two-phase / sample-level case; Sarndal & Lundstrom 2005);
#'   a named vector or a tidy `totals`/`count` input (as in `step_calibrate()`)
#'   calibrates to population totals instead.
#' @param count (method = "calibration", tidy `totals`) string naming the counts
#'   column of the totals data frame(s).
#' @param calfun (method = "calibration") distance function for the calibration
#'   factor: "linear", "raking" or "logit", as in `step_calibrate(method = "linear")`.
#' @param bounds (method = "calibration") numeric c(L, U) with L < 1 < U. Bounds
#'   on the calibration factor, to keep the nonresponse factors positive.
#' @param penalty (method = "calibration", unbounded) NULL or positive cost(s)
#'   for ridge (penalized) calibration.
#' @param equal_within_cluster (method = "calibration") logical. If TRUE,
#'   integrative (Lemaitre-Dufour) nonresponse calibration: the responding
#'   members of a household (`cluster`) share a single calibration factor, so
#'   the adjustment keeps the weights constant within household. Requires
#'   `cluster`. FALSE (default) calibrates each responding unit on its own.
#' @param maxit,tol (method = "calibration") convergence control for the bounded
#'   or exponential-distance calibration solver.
#' @examples
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class",
#'                    by = "region")
#'
#' # household-level nonresponse (whole household responds or not)
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class",
#'                    by = "region", cluster = "household_id") |>
#'   prep()
#' # propensity with cross-fitting (out-of-sample, avoids overfitting)
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "propensity",
#'                    formula = ~ region + sex, engine = "logit",
#'                    num_classes = 5, crossfit = 5, crossfit_seed = 1) |>
#'   prep()
#'
#' # gradient boosting engine (requires the 'xgboost' package)
#' \donttest{
#' if (requireNamespace("xgboost", quietly = TRUE)) {
#'   weighting_spec(sample_survey, base_weights = pw) |>
#'     step_nonresponse(respondent = responded, method = "propensity",
#'                      formula = ~ region + sex + age, engine = "boost",
#'                      num_classes = 5, crossfit = 5) |>
#'     prep()
#' }
#' }
#'
#' # nonresponse by calibration (two-phase): calibrate the respondents to the
#' # R+NR design-weighted totals of the auxiliaries at that stage, so their
#' # estimates reproduce the pre-nonresponse ones (Sarndal & Lundstrom 2005)
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "calibration",
#'                    formula = ~ region + sex) |>
#'   prep()
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
step_nonresponse <- function(spec, respondent,
                             method = c("weighting_class", "propensity", "calibration"),
                             by = NULL, formula = NULL,
                             engine = c("logit", "tree", "forest", "boost"),
                             weight_model = TRUE,
                             num_classes = 5L, cluster = NULL,
                             crossfit = NULL, crossfit_seed = NULL,
                             totals = NULL, count = NULL,
                             calfun = c("linear", "logit", "raking"),
                             bounds = NULL, penalty = NULL,
                             equal_within_cluster = FALSE,
                             maxit = 50L, tol = 1e-6) {
  method <- match.arg(method)
  engine <- match.arg(engine)
  calfun <- match.arg(calfun)
  if (!is.null(crossfit) && (!is.numeric(crossfit) || crossfit < 2))
    stop("`crossfit` must be NULL or an integer >= 2 (number of folds).")
  if (!is.null(num_classes) &&
      (!is.numeric(num_classes) || length(num_classes) != 1L || num_classes < 2))
    stop("`num_classes` must be NULL (continuous 1/p) or a single integer >= 2.")

  # warn about arguments this method ignores, so incompatible combinations are
  # not silently dropped (e.g. engine = "forest" with method = "weighting_class").
  ignored <- character(0)
  if (method != "propensity") {
    if (!identical(engine, "logit")) ignored <- c(ignored, "engine")
    if (!is.null(crossfit))          ignored <- c(ignored, "crossfit")
  }
  if (method == "weighting_class" && !is.null(formula))
    ignored <- c(ignored, "formula")
  if (method != "calibration") {
    if (!identical(calfun, "linear")) ignored <- c(ignored, "calfun")
    if (!is.null(bounds))             ignored <- c(ignored, "bounds")
    if (!is.null(penalty))            ignored <- c(ignored, "penalty")
    if (!is.null(totals))             ignored <- c(ignored, "totals")
    if (isTRUE(equal_within_cluster)) ignored <- c(ignored, "equal_within_cluster")
  }
  if (length(ignored))
    warning(sprintf("For method = \"%s\", these argument(s) are ignored: %s.",
                    method, paste(unique(ignored), collapse = ", ")), call. = FALSE)

  if (method == "calibration") {
    # Calibration approach to nonresponse (two-phase; Sarndal & Lundstrom 2005).
    if (is.null(formula))
      stop("nonresponse method = 'calibration' requires `formula` (the auxiliaries).")
    if (calfun == "logit" && is.null(bounds))
      stop("calfun = 'logit' requires `bounds` = c(L, U).")
    if (!is.null(bounds) && (length(bounds) != 2L || bounds[1] >= 1 || bounds[2] <= 1))
      stop("`bounds` must be c(L, U) with L < 1 < U.")
    if (!is.null(penalty)) {
      if (!is.null(bounds) || calfun == "logit")
        stop("`penalty` (ridge) cannot be combined with bounded calibration.")
      if (!is.numeric(penalty) || any(penalty <= 0))
        stop("`penalty` must be a positive scalar or a positive named vector.")
    }
    if (isTRUE(equal_within_cluster) && is.null(cluster))
      stop("equal_within_cluster = TRUE requires `cluster` (the household id).")
  }

  mode   <- if (is.null(num_classes)) "1/p per unit" else
            sprintf("%d classes", num_classes)
  lvl    <- if (is.null(cluster)) "" else sprintf(", by %s", cluster)
  label  <- if (method == "propensity")
              sprintf("nonresponse (propensity: %s, %s%s%s)", engine, mode, lvl,
                      if (isTRUE(weight_model)) "" else ", unweighted model")
            else if (method == "calibration") {
              tlab <- if (is.null(totals)) "sample-level" else "population"
              det  <- calfun                       # linear / raking / logit distance
              if (calfun != "logit" && !is.null(bounds)) det <- paste0(det, ", bounded")
              if (!is.null(penalty)) det <- paste0(det, ", ridge")
              if (isTRUE(equal_within_cluster)) det <- paste0(det, ", integrative")
              sprintf("nonresponse (calibration: %s, %s)", det, tlab)
            }
            else sprintf("nonresponse (weighting class%s)", lvl)
  step <- structure(
    list(
      label       = label,
      respondent  = substitute(respondent),
      env         = parent.frame(),
      method      = method,
      by          = by,
      formula     = formula,
      engine      = engine,
      weight_model = isTRUE(weight_model),
      num_classes = num_classes,
      cluster     = cluster,
      crossfit      = if (is.null(crossfit)) NULL else as.integer(crossfit),
      crossfit_seed = crossfit_seed,
      totals      = totals,
      count       = count,
      calfun      = calfun,
      bounds      = bounds,
      penalty     = penalty,
      equal_within_cluster = equal_within_cluster,
      maxit       = maxit,
      tol         = tol
    ),
    class = c("step_nonresponse", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Step: calibration -----------------------------------------------------
