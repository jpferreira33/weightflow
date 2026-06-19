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
#' @param spec a weighting_spec.
#' @param respondent a 0/1 dummy column (1 = responded) or any logical condition
#'   (unquoted) TRUE for respondents. Eligible cases that are not respondents
#'   are treated as nonresponse.
#' @param method "weighting_class" (cells) or "propensity" (predictive model).
#' @param by character. Adjustment cells for method = "weighting_class".
#' @param formula predictor formula (right-hand side only), e.g. ~ age + region,
#'   used when method = "propensity".
#' @param engine engine to estimate the propensity when method = "propensity":
#'   "logit" (logistic regression, base R), "tree" (CART via package 'rpart') or
#'   "forest" (random forest via package 'ranger'). 'rpart' and 'ranger' are
#'   optional: only needed if you pick that engine.
#' @param num_classes integer or NULL. Controls how propensities are used:
#'   an integer forms that many propensity classes (cell adjustment within each
#'   class); NULL applies the direct factor 1/p to each unit.
#' @examples
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class",
#'                    by = "region")
step_nonresponse <- function(spec, respondent,
                             method = c("weighting_class", "propensity"),
                             by = NULL, formula = NULL,
                             engine = c("logit", "tree", "forest"),
                             num_classes = 5L) {
  method <- match.arg(method)
  engine <- match.arg(engine)
  mode   <- if (is.null(num_classes)) "1/p per unit" else
            sprintf("%d classes", num_classes)
  label  <- if (method == "propensity")
              sprintf("nonresponse (propensity: %s, %s)", engine, mode)
            else "nonresponse (weighting class)"
  step <- structure(
    list(
      label       = label,
      respondent  = substitute(respondent),
      method      = method,
      by          = by,
      formula     = formula,
      engine      = engine,
      num_classes = num_classes
    ),
    class = c("step_nonresponse", "weighting_step")
  )
  .add_step(spec, step)
}

# --- Step: calibration -----------------------------------------------------

#' Calibration to population totals
#'
#' @param spec a weighting_spec.
#' @param margins named list (for "raking"/"poststratify"). Each element is a
#'   named numeric vector with the target totals per category. E.g.:
#'   list(sex = c(M = 5000, F = 5200), region = c(N = 3000, S = 7200)).
#' @param method "raking" (IPF, categorical margins), "poststratify" (a single
#'   categorical variable) or "linear" (GREG / regression estimator; handles
#'   continuous and categorical auxiliaries together).
#' @param formula (only "linear") auxiliary formula, e.g. ~ sex + income.
#'   Uses model.matrix; includes the intercept unless you write ~ 0 + ...
#' @param totals (only "linear") named numeric vector with the population
#'   totals, names matching the model.matrix columns (including "(Intercept)" =
#'   N if there is an intercept). If names do not match, the error lists the
#'   expected ones.
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
#' @examples
#' # Raking to population margins
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_calibrate(method = "raking",
#'                  margins = list(sex    = c(table(population$sex)),
#'                                 region = c(table(population$region)))) |>
#'   prep()
step_calibrate <- function(spec, margins = NULL,
                           method = c("raking", "poststratify", "linear"),
                           formula = NULL, totals = NULL,
                           cluster = NULL, equal_within_cluster = FALSE,
                           calfun = c("linear", "logit"), bounds = NULL,
                           maxit = 50L, tol = 1e-6) {
  method <- match.arg(method)
  calfun <- match.arg(calfun)
  if (method %in% c("raking", "poststratify")) {
    if (!is.list(margins) || is.null(names(margins)))
      stop("'raking'/'poststratify' require `margins` (a named list).")
  } else {                                   # linear
    if (is.null(formula) || is.null(totals))
      stop("method = 'linear' requires `formula` and `totals`.")
  }
  if (calfun == "logit" && is.null(bounds))
    stop("calfun = 'logit' requires `bounds` = c(L, U).")
  if (!is.null(bounds)) {
    if (length(bounds) != 2L || bounds[1] >= 1 || bounds[2] <= 1)
      stop("`bounds` must be c(L, U) with L < 1 < U.")
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
  step <- structure(
    list(
      label   = sprintf("calibration (%s)", detail),
      margins = margins,
      method  = method,
      formula = formula,
      totals  = totals,
      cluster = cluster,
      equal_within_cluster = equal_within_cluster,
      calfun  = calfun,
      bounds  = bounds,
      maxit   = maxit,
      tol     = tol
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
  deff <- m * sum(wa^2) / (sum(wa)^2)
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
#' @param engine "glm", "tree" (rpart) or "forest" (ranger).
#' @param family for engine = "glm": "gaussian", "binomial" or "poisson".
#'   For tree/forest, regression vs classification is inferred from y.
#' @return a model specification list.
#' @examples
#' y_model(income ~ age + sex, engine = "glm")
y_model <- function(formula, engine = c("glm", "tree", "forest"), family = NULL) {
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
#' @examples
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_model_calibration(
#'     x_formula  = ~ sex + region,
#'     models     = list(income = y_model(income ~ age + sex, engine = "glm")),
#'     population = population) |>
#'   prep()
step_model_calibration <- function(spec, x_formula, models, population,
                                   cluster = NULL, equal_within_cluster = FALSE) {
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
      equal_within_cluster = equal_within_cluster
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
#' By default no weight may fall below 1, and the upper cap is set by an
#' automatic empirical rule (Tukey far-out fence: Q3 + 3*IQR).
#'
#' @param spec a weighting_spec.
#' @param lower numeric. Lower floor (default 1: no weight below 1).
#' @param upper numeric or NULL. Upper cap. If NULL, automatic rule
#'   Q3 + 3*IQR of the active weights.
#' @param strict logical. If TRUE (default), iterate cap+redistribution until no
#'   weight is outside `[lower, upper]` (like survey's strict = TRUE). If FALSE, a
#'   single pass (redistribution may push some weights slightly past the cap).
#' @param maxit integer. Maximum iterations when strict = TRUE.
#' @examples
#' weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_trim_weights(lower = 1, strict = TRUE) |> prep()
step_trim_weights <- function(spec, lower = 1, upper = NULL,
                              strict = TRUE, maxit = 50L) {
  step <- structure(
    list(
      label  = "auto weight trimming",
      lower  = lower,
      upper  = upper,
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
