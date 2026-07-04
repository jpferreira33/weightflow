# ---------------------------------------------------------------------------
# weightflow: declarative API to build survey weights through hierarchical
# stages. It computes weights only; it does NOT compute variances.
# ---------------------------------------------------------------------------

#' Start a weighting specification
#'
#' Creates an inert recipe object. Nothing is computed until prep() is called.
#'
#' @param data data.frame with the sample units (one row per case).
#' @param base_weights unquoted name of the design base-weight column.
#' @return an object of class "weighting_spec".
#' @examples
#' rec <- weighting_spec(sample_survey, base_weights = pw)
#' rec
weighting_spec <- function(data, base_weights) {
  bw <- deparse(substitute(base_weights))
  if (!is.data.frame(data)) stop("`data` must be a data.frame.")
  if (!bw %in% names(data)) stop(sprintf("Base-weight column '%s' not found in the data.", bw))
  if (any(is.na(data[[bw]]))) stop("Base weights cannot contain NA.")
  structure(
    list(
      data         = data,
      base_weights = bw,
      steps        = list()
    ),
    class = "weighting_spec"
  )
}

# Internal helper: append a step to the recipe -----------------------------
.add_step <- function(spec, step) {
  if (!inherits(spec, "weighting_spec"))
    stop("The first argument must be a weighting_spec (piped with |>).")
  spec$steps <- c(spec$steps, list(step))
  spec
}

# --- Step: unknown-eligibility adjustment ----------------------------------

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
step_unknown_eligibility <- function(spec, unknown, by = NULL, cluster = NULL) {
  step <- structure(
    list(
      label   = if (is.null(cluster)) "unknown eligibility"
                else sprintf("unknown eligibility (by %s)", cluster),
      unknown = substitute(unknown),
      by      = by,
      cluster = cluster
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
#'   household, for simple random selection of one person. The weight is
#'   multiplied by n_eligible (equivalent to prob = 1/n_eligible).
#' @examples
#' # simple random selection of one eligible person per household
#' df <- transform(sample_survey,
#'                 n_elig = ave(person_id, household_id, FUN = length))
#' weighting_spec(df, base_weights = pw) |>
#'   step_select_within(n_eligible = n_elig)
step_select_within <- function(spec, prob = NULL, n_eligible = NULL) {
  p <- substitute(prob)
  k <- substitute(n_eligible)
  if (is.null(p) && is.null(k))
    stop("Provide either `prob` or `n_eligible`.")
  if (!is.null(p) && !is.null(k))
    stop("Provide only one of `prob` or `n_eligible`.")
  step <- structure(
    list(label = "within-household selection", prob = p, n_eligible = k),
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
step_drop_ineligible <- function(spec, ineligible) {
  step <- structure(
    list(label = "drop ineligible", ineligible = substitute(ineligible)),
    class = c("step_drop_ineligible", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Step: nonresponse adjustment ------------------------------------------

#' Nonresponse adjustment
#'
#' Inflates the weights of respondents to represent the nonrespondents, under the
#' assumption that response is ignorable given the information used. The response
#' propensity can be estimated by weighting classes (cells) or by a model
#' ("propensity"), with engines ranging from logistic regression to machine
#' learning (regression tree, random forest, gradient boosting). Optional
#' K-fold cross-fitting estimates the propensity out-of-sample to avoid the
#' overfitting that flexible engines can introduce. The adjustment can be applied
#' at the person or, via `cluster`, the household level.
#'
#' @param spec a weighting_spec.
#' @param respondent a 0/1 dummy column (1 = responded) or any logical condition
#'   (unquoted) TRUE for respondents. Eligible cases that are not respondents
#'   are treated as nonresponse.
#' @param method "weighting_class" (cells) or "propensity" (predictive model).
#' @param by character. Adjustment cells for method = "weighting_class".
#' @param formula predictor formula (right-hand side only), e.g. ~ age + region,
#'   used when method = "propensity".
#' @param engine engine to estimate the propensity when method = "propensity":
#'   "logit" (logistic regression, base R), "tree" (CART via package 'rpart'),
#'   "forest" (random forest via package 'ranger') or "boost" (gradient boosting
#'   via package 'xgboost'). 'rpart', 'ranger' and 'xgboost' are optional: only
#'   needed if you pick that engine.
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
#'   dropped (unknown eligibility, ineligible) are excluded automatically.
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
#' if (requireNamespace("xgboost", quietly = TRUE)) {
#'   weighting_spec(sample_survey, base_weights = pw) |>
#'     step_nonresponse(respondent = responded, method = "propensity",
#'                      formula = ~ region + sex + age, engine = "boost",
#'                      num_classes = 5, crossfit = 5) |>
#'     prep()
#' }
step_nonresponse <- function(spec, respondent,
                             method = c("weighting_class", "propensity"),
                             by = NULL, formula = NULL,
                             engine = c("logit", "tree", "forest", "boost"),
                             num_classes = 5L, cluster = NULL,
                             crossfit = NULL, crossfit_seed = NULL) {
  method <- match.arg(method)
  engine <- match.arg(engine)
  if (!is.null(crossfit) && (!is.numeric(crossfit) || crossfit < 2))
    stop("`crossfit` must be NULL or an integer >= 2 (number of folds).")
  mode   <- if (is.null(num_classes)) "1/p per unit" else
            sprintf("%d classes", num_classes)
  lvl    <- if (is.null(cluster)) "" else sprintf(", by %s", cluster)
  label  <- if (method == "propensity")
              sprintf("nonresponse (propensity: %s, %s%s)", engine, mode, lvl)
            else sprintf("nonresponse (weighting class%s)", lvl)
  step <- structure(
    list(
      label       = label,
      respondent  = substitute(respondent),
      method      = method,
      by          = by,
      formula     = formula,
      engine      = engine,
      num_classes = num_classes,
      cluster     = cluster,
      crossfit      = if (is.null(crossfit)) NULL else as.integer(crossfit),
      crossfit_seed = crossfit_seed
    ),
    class = c("step_nonresponse", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Step: calibration -----------------------------------------------------

#' Calibration to population totals
#'
#' Adjusts the weights so that the weighted sample reproduces known population
#' totals of auxiliary variables, while staying as close as possible to the input
#' weights (Deville & Sarndal 1992). Supports raking (IPF on categorical
#' margins), post-stratification, and linear/GREG calibration, optionally bounded
#' (a logit distance or explicit bounds on the calibration factor). For linear
#' calibration, `penalty` enables ridge (penalized) calibration, which relaxes
#' the targets to control extreme weights when there are many auxiliaries.
#'
#' @param spec a weighting_spec.
#' @param margins named list (classic format for "raking"/"poststratify"). Each
#'   element is a named numeric vector with the target totals per category. E.g.:
#'   list(sex = c(M = 5000, F = 5200), region = c(N = 3000, S = 7200)). Still
#'   fully supported; for a tidy alternative see `totals` and `count`.
#' @param method "raking" (IPF, categorical margins), "poststratify"
#'   (post-strata: one or more categorical variables crossed) or "linear"
#'   (GREG / regression estimator; handles continuous and categorical
#'   auxiliaries together).
#' @param formula (only "linear") auxiliary formula, e.g. ~ sex + income.
#'   Uses model.matrix; includes the intercept unless you write ~ 0 + ...
#' @param totals population totals, in one of two forms. Classic (all methods):
#'   for "linear" a named numeric vector aligned with the model.matrix columns
#'   (including "(Intercept)" = N); for "raking"/"poststratify" use `margins`.
#'   Tidy (recommended): a data frame or a named list of data frames/numbers
#'   giving the totals in a friendly way, paired with `count`. For
#'   "poststratify", a single data frame with one or more category columns plus
#'   a counts column. For "raking", a list of data frames, one per margin. For
#'   "linear", a named list whose names match the formula terms: a data frame
#'   with all categories for each factor, and a single number for each
#'   continuous auxiliary; weightflow builds the model.matrix totals internally
#'   (you never handle the intercept or dropped reference category).
#' @param count (tidy `totals` only) string naming the counts column in the
#'   totals data frame(s). All other columns are treated as category variables.
#' @param cluster (only "linear") name of the cluster id column (e.g. "household"),
#'   for equal weights within the cluster.
#' @param equal_within_cluster (only "linear") logical. If TRUE, Lemaitre-Dufour
#'   (1987) integrative calibration: a single weight per cluster. Requires
#'   `cluster`. Final weights are equal within the cluster provided the incoming
#'   weight is also uniform within the cluster.
#' @param calfun (only "linear") distance function: "linear" (g = 1 + u) or
#'   "logit" (bounded by construction). With "logit", `bounds` is required.
#' @param bounds (only "linear") numeric c(L, U) with L < 1 < U. Bounds on the
#'   calibration factor g (g-weights). With "linear" it truncates; with "logit"
#'   it is enforced smoothly. Avoids extreme/negative weights without a separate
#'   trimming step.
#' @param maxit,tol convergence control for raking and bounded calibration.
#' @param penalty (only "linear", unbounded) NULL or positive cost(s) for ridge
#'   (penalized) calibration. A positive scalar applies the same cost to every
#'   constraint; a named vector sets a cost per constraint (matched to the
#'   model.matrix columns). The cost is scale-free: a large value keeps the
#'   constraint (near) exact, a small value relaxes it to control extreme weights
#'   when there are many auxiliaries. Under ridge the achieved totals no longer
#'   match the targets exactly; the diagnostics report the deviation.
#' @examples
#' # Raking to population margins
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_calibrate(method = "raking",
#'                  margins = list(sex    = c(table(population$sex)),
#'                                 region = c(table(population$region)))) |>
#'   prep()
#'
#' # ridge (penalized) calibration: relaxes the targets to control extreme
#' # weights; a smaller penalty relaxes more. Uses only base R.
#' pop_tot <- c("(Intercept)" = nrow(population),
#'              regionSouth = sum(population$region == "South"),
#'              regionEast  = sum(population$region == "East"),
#'              regionWest  = sum(population$region == "West"),
#'              sexM        = sum(population$sex == "M"))
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_calibrate(method = "linear", formula = ~ region + sex,
#'                  totals = pop_tot, penalty = 1) |>
#'   prep()
#'
#' # --- Tidy `totals` format (recommended) ---------------------------------
#' # Post-stratification: give the population counts as a data frame with one or
#' # more category columns plus a counts column named by `count`.
#' ps_totals <- as.data.frame(table(region = population$region, sex = population$sex))
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_calibrate(method = "poststratify", totals = ps_totals, count = "Freq") |>
#'   prep()
#'
#' # Raking: a list of data frames, one per margin.
#' m_region <- as.data.frame(table(region = population$region))
#' m_sex    <- as.data.frame(table(sex = population$sex))
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_calibrate(method = "raking",
#'                  totals = list(m_region, m_sex), count = "Freq") |>
#'   prep()
#'
#' # Linear/GREG with mixed auxiliaries: data frames for categoricals (all
#' # categories) and a single number for a continuous total. weightflow builds
#' # the model.matrix totals internally, so you never drop a reference category.
#' resp <- subset(sample_survey, responded == 1)
#' weighting_spec(resp, base_weights = pw) |>
#'   step_calibrate(method = "linear", formula = ~ region + sex + income,
#'                  totals = list(region = m_region, sex = m_sex,
#'                                income = sum(population$income)),
#'                  count = "Freq") |>
#'   prep()
step_calibrate <- function(spec, margins = NULL,
                           method = c("raking", "poststratify", "linear"),
                           formula = NULL, totals = NULL, count = NULL,
                           cluster = NULL, equal_within_cluster = FALSE,
                           calfun = c("linear", "logit"), bounds = NULL,
                           maxit = 50L, tol = 1e-6, penalty = NULL) {
  method <- match.arg(method)
  calfun <- match.arg(calfun)
  totals_is_df   <- is.data.frame(totals)
  totals_is_list <- is.list(totals) && !is.data.frame(totals) &&
                    length(totals) > 0L &&
                    all(vapply(totals, function(t)
                          is.data.frame(t) || (is.numeric(t) && length(t) == 1L),
                          logical(1)))
  if (method %in% c("raking", "poststratify")) {
    # Accept the classic `margins` (named list of named vectors) or the tidy
    # `totals`: a data frame (post-stratification) or a list of data frames
    # (raking), each with category columns + a counts column named by `count`.
    has_margins <- is.list(margins) && !is.null(names(margins)) &&
                   !is.data.frame(margins)
    if (!has_margins && !totals_is_df && !totals_is_list)
      stop(paste0("'", method, "' requires either `margins` (a named list) or ",
                  "`totals` (a data frame, or a list of data frames for raking, ",
                  "with category columns and a counts column named by `count`)."))
    if (totals_is_df || totals_is_list) {
      if (is.null(count) || !is.character(count) || length(count) != 1L)
        stop("When `totals` is provided, `count` must be a single string naming the counts column.")
      dfs <- if (totals_is_df) list(totals) else totals
      for (d in dfs)
        if (!count %in% names(d))
          stop(sprintf("`count = \"%s\"` is not a column of every `totals` data frame. Columns seen: %s",
                       count, paste(names(d), collapse = ", ")))
    }
  } else {                                   # linear
    if (is.null(formula) || is.null(totals))
      stop("method = 'linear' requires `formula` and `totals`.")
    if (totals_is_df) {
      if (is.null(count) || !is.character(count) || length(count) != 1L ||
          !count %in% names(totals))
        stop("When `totals` is a data frame, `count` must name the counts column of `totals`.")
    }
    if (totals_is_list) {
      # tidy linear: named list of data frames (categorical) / numbers (continuous)
      if (is.null(names(totals)))
        stop("For the tidy linear format, `totals` must be a NAMED list (one entry per auxiliary variable).")
      if (any(vapply(totals, is.data.frame, logical(1))) &&
          (is.null(count) || !is.character(count) || length(count) != 1L))
        stop("When `totals` contains data frames, `count` must name their counts column.")
    }
  }
  if (calfun == "logit" && is.null(bounds))
    stop("calfun = 'logit' requires `bounds` = c(L, U).")
  if (!is.null(bounds)) {
    if (length(bounds) != 2L || bounds[1] >= 1 || bounds[2] <= 1)
      stop("`bounds` must be c(L, U) with L < 1 < U.")
  }
  if (!is.null(penalty)) {
    if (method != "linear")
      stop("`penalty` (ridge calibration) is only available with method = 'linear'.")
    if (!is.null(bounds) || calfun == "logit")
      stop("`penalty` (ridge calibration) cannot be combined with bounded calibration.")
    if (!is.numeric(penalty) || any(penalty <= 0))
      stop("`penalty` must be a positive scalar or a positive named vector of costs.")
  }
  if (equal_within_cluster) {
    if (method != "linear")
      stop("Equal weights within cluster are only available with method = 'linear'.")
    if (is.null(cluster))
      stop("equal_within_cluster = TRUE requires `cluster`.")
  }
  detail <- if (method == "linear" && equal_within_cluster)
              sprintf("linear, equal weights by %s", cluster) else method
  if (method == "linear" && (calfun == "logit" || !is.null(bounds)))
    detail <- paste0(detail, ", bounded")
  if (!is.null(penalty)) detail <- paste0(detail, ", ridge")
  step <- structure(
    list(
      label   = sprintf("calibration (%s)", detail),
      margins = margins,
      method  = method,
      formula = formula,
      totals  = totals,
      count   = count,
      cluster = cluster,
      equal_within_cluster = equal_within_cluster,
      calfun  = calfun,
      bounds  = bounds,
      maxit   = maxit,
      tol     = tol,
      penalty = penalty
    ),
    class = c("step_calibrate", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Optional step: weight trimming ----------------------------------------

#' Trim extreme weights
#'
#' Caps weights above a limit and, optionally, redistributes the excess among
#' the others to preserve the weighted total (Potter 1988, 1990; Liu et al.
#' 2004). Optional step that can be inserted anywhere in the recipe, even
#' several times. Operates on the CURRENT weights at that point of the cascade.
#'
#' There is no standard threshold: `max_ratio` is an analyst decision, a
#' bias-variance trade-off. Use Kish's design effect (see summary) to judge
#' whether trimming is worth it.
#'
#' @param spec a weighting_spec.
#' @param max_ratio number. Upper cap. Its meaning depends on `reference`. E.g.
#'   with reference = "base" and max_ratio = 4, no weight may exceed 4 times its
#'   design weight.
#' @param min_ratio number or NULL. Lower floor (same units as max_ratio).
#' @param reference "base" (multiple of each unit's base weight),
#'   "median" (multiple of the median of current weights) or
#'   "value" (absolute weight value).
#' @param redistribute logical. If TRUE, redistributes the trimmed excess among
#'   the uncapped weights to preserve the total (iterating). If you calibrate
#'   afterwards you can use FALSE: calibration restores the totals.
#' @param by character. Groups within which to redistribute (optional).
#' @param maxit integer. Maximum cap+redistribution iterations.
#' @examples
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_trim(max_ratio = 3, reference = "base")
step_trim <- function(spec, max_ratio, min_ratio = NULL,
                      reference = c("base", "median", "value"),
                      redistribute = TRUE, by = NULL, maxit = 50L) {
  reference <- match.arg(reference)
  if (missing(max_ratio)) stop("`max_ratio` is required.")
  step <- structure(
    list(
      label        = sprintf("trimming (%s, cap %s)", reference, max_ratio),
      max_ratio    = max_ratio,
      min_ratio    = min_ratio,
      reference    = reference,
      redistribute = redistribute,
      by           = by,
      maxit        = maxit
    ),
    class = c("step_trim", "weighting_step")
  )
  .add_step(spec, step)
}

#' Kish design effect from unequal weighting
#'
#' deff = 1 + CV^2(w) = m * sum(w^2) / (sum(w))^2, over the active weights.
#' The effective sample size is n_eff = m / deff.
#'
#' @param w vector of weights (zeros are dropped).
#' @return list with deff, n_eff, cv and n.
#' @examples
#' design_effect(sample_survey$pw)
design_effect <- function(w) {
  wa <- w[w > 0]
  m  <- length(wa)
  if (m == 0L) return(list(deff = NA_real_, n_eff = 0, cv = NA_real_, n = 0L))
  sw   <- sum(wa)
  deff <- if (sw == 0) NA_real_ else m * sum(wa^2) / (sw^2)
  deff <- max(deff, 1)                 # guard against floating-point dip below 1
  list(deff = deff, n_eff = m / deff, cv = sqrt(deff - 1), n = m)
}

# --- Optional final step: weight rounding ----------------------------------

#' Round the final weights
#'
#' Optional step, typically the last one (after calibration). Simple rounding
#' ("nearest") slightly breaks the calibrated totals; "preserve_total" uses the
#' largest-remainder method to keep the exact total.
#'
#' @param spec a weighting_spec.
#' @param digits integer. Decimals to keep (0 = integers).
#' @param method "nearest" (simple rounding) or "preserve_total" (keeps the sum
#'   of weights). Note: "preserve_total" can break equality of weights within a
#'   cluster; if you need integer and equal weights per household, use "nearest".
#' @examples
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_round(digits = 0) |> prep()
step_round <- function(spec, digits = 0L, method = c("nearest", "preserve_total")) {
  method <- match.arg(method)
  step <- structure(
    list(
      label  = sprintf("rounding (%s, %d decimals)", method, digits),
      digits = digits,
      method = method
    ),
    class = c("step_round", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Model calibration (Wu & Sitter 2001) ----------------------------------

#' Specify a working model for a study variable y
#'
#' @param formula full formula, e.g. income ~ sex + age_g.
#' @param engine "glm", "tree" (rpart), "forest" (ranger) or "boost" (xgboost).
#' @param family for engine = "glm": "gaussian", "binomial" or "poisson".
#'   For tree/forest, regression vs classification is inferred from y.
#' @return a model specification list.
#' @examples
#' y_model(income ~ age + sex, engine = "glm")
y_model <- function(formula, engine = c("glm", "tree", "forest", "boost"), family = NULL) {
  engine <- match.arg(engine)
  if (!inherits(formula, "formula")) stop("`formula` must be a formula y ~ x.")
  list(formula = formula, engine = engine, family = family)
}

#' Model calibration (model-assisted, Wu & Sitter 2001)
#'
#' Fits a working model for each study variable y, predicts over the population,
#' and calibrates the weights so that the sample total of each prediction equals
#' its population total (model-assisted efficiency). It also calibrates to the X
#' totals (consistency with the auxiliary controls).
#'
#' Requires COMPLETE auxiliary information: a data.frame `population` with the
#' `x_formula` columns and the model predictors for the whole population (or a
#' reference frame/census).
#'
#' @param spec a weighting_spec.
#' @param x_formula formula of the consistency auxiliaries, e.g. ~ sex + region.
#' @param models named list of models created with y_model(). The names label
#'   the prediction constraints.
#' @param population population data.frame with the auxiliary and predictor
#'   columns (the y variables are not needed; they are predicted).
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
#'   (default) fits and predicts in-sample.
#' @param crossfit_seed integer or NULL. Seed for reproducible fold assignment.
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
step_model_calibration <- function(spec, x_formula, models, population,
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
  detail <- if (equal_within_cluster)
              sprintf("%d y variables, equal weights by %s", length(models), cluster)
            else sprintf("%d y variables", length(models))
  step <- structure(
    list(
      label      = sprintf("model calibration (%s)", detail),
      x_formula  = x_formula,
      models     = models,
      population = population,
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

#' Assert conditions on the weights at this point of the cascade
#'
#' A checkpoint that does NOT change the weights; it verifies conditions and
#' fails (error) or warns if they are not met. Useful to guard a production
#' pipeline (tidymodels-style tests inside the recipe).
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

#' Automatic weight trimming (survey-style)
#'
#' Caps weights into `[lower, upper]` and redistributes the change among the
#' untrimmed units to preserve the total, mirroring survey::trimWeights().
#' By default no weight may fall below 1, and the upper cap is chosen by an
#' automatic rule: the Tukey far-out fence (Q3 + 3*IQR) or, with
#' `method = "potter"`, Potter's MSE-optimal cutoff.
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
step_trim_weights <- function(spec, lower = 1, upper = NULL,
                              method = c("tukey", "potter"),
                              strict = TRUE, maxit = 50L) {
  method <- match.arg(method)
  step <- structure(
    list(
      label  = if (method == "potter") "auto weight trimming (Potter MSE)"
               else "auto weight trimming",
      lower  = lower,
      upper  = upper,
      method = method,
      strict = strict,
      maxit  = maxit
    ),
    class = c("step_trim_weights", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Optional step: rescale / normalize weights ----------------------------

#' Rescale (normalize) the weights
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
