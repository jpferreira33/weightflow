# calibration step constructors: step_calibrate, step_trim, step_round, y_model() spec, design_effect().

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
#' @param formula (only method = "linear") auxiliary formula, e.g. ~ sex + income.
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
#' @param by (tidy `totals` only) NULL, or a string naming a domain (partition)
#'   column. When given, the weights are calibrated **independently within each
#'   domain**, each to its own totals (partitioned / domain calibration). The
#'   totals tables carry the domain as a column, and each `count` table is split
#'   by it; a continuous total becomes a data frame `domain, value` (one total per
#'   domain). The domain variable must NOT appear in `formula` / the margins: it
#'   is the partition. Composes with `calfun`, `bounds`, `penalty` and
#'   `equal_within_cluster`, applied within each domain. NULL (default) calibrates
#'   globally, as before.
#' @param cluster (only method = "linear") name of the cluster id column
#'   (e.g. "household"), for equal weights within the cluster.
#' @param equal_within_cluster (only method = "linear") logical. If TRUE,
#'   Lemaitre-Dufour (1987) integrative calibration: a single weight per cluster.
#'   Requires `cluster`. Final weights are equal within the cluster provided the
#'   incoming weight is also uniform within the cluster. Works with any `calfun`
#'   distance ("linear", "raking" or "logit"), with `bounds` and with `by`.
#' @param calfun (only method = "linear") distance function for the calibration
#'   factor g: "linear" (g = 1 + u, closed form), "raking" (g = exp(u), the
#'   exponential/multiplicative distance, which keeps the weights positive and
#'   still satisfies the constraints exactly) or "logit" (bounded by
#'   construction; requires `bounds`). "raking" and "logit" use the iterative
#'   Deville-Sarndal solver and work with the integrative option
#'   (`equal_within_cluster`) too.
#' @param bounds (only method = "linear") numeric c(L, U) with L < 1 < U. Bounds on the
#'   calibration factor g (g-weights). With "linear" it truncates; with "logit"
#'   it is enforced smoothly. Avoids extreme/negative weights without a separate
#'   trimming step.
#' @param maxit,tol convergence control for raking and bounded calibration.
#' @param penalty (only method = "linear", unbounded) NULL or positive cost(s) for ridge
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
#'
#' # Domain (partitioned) calibration: `by` calibrates independently within each
#' # domain, each to its own totals. The domain is an extra column in the tidy
#' # totals, not a term in the formula/margins. Here we rake two margins (sex and
#' # age group) within each region, which a single global cross could not express.
#' pop  <- transform(population,
#'   age_grp = cut(age, c(0, 30, 45, 60, Inf), labels = c("18-30","31-45","46-60","60+")))
#' samp <- transform(sample_survey,
#'   age_grp = cut(age, c(0, 30, 45, 60, Inf), labels = c("18-30","31-45","46-60","60+")))
#' sex_by_region <- as.data.frame(table(region = pop$region, sex     = pop$sex))
#' age_by_region <- as.data.frame(table(region = pop$region, age_grp = pop$age_grp))
#' weighting_spec(samp, base_weights = pw) |>
#'   step_calibrate(method = "raking",
#'                  totals = list(sex_by_region, age_by_region),
#'                  count = "Freq", by = "region") |>
#'   prep()
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
step_calibrate <- function(spec, margins = NULL,
                           method = c("raking", "poststratify", "linear"),
                           formula = NULL, totals = NULL, count = NULL, by = NULL,
                           cluster = NULL, equal_within_cluster = FALSE,
                           calfun = c("linear", "logit", "raking"), bounds = NULL,
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
    if (has_margins) {
      bad <- setdiff(names(margins), names(spec$data))
      if (length(bad))
        stop(sprintf("These `margins` variable(s) are not columns of the data: %s.",
                     paste(bad, collapse = ", ")))
    }
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
  if (!is.null(by)) {
    if (!is.character(by) || length(by) != 1L)
      stop("`by` must be a single string naming the domain (partition) column.")
    if (!(totals_is_df || totals_is_list))
      stop(paste0("`by` (domain calibration) requires the tidy `totals` format ",
                  "(a data frame, or a list of data frames, carrying the domain ",
                  "as a column), not `margins`."))
    if (method == "linear" && !is.null(formula) && by %in% all.vars(formula))
      stop(sprintf(paste0("The domain variable '%s' must not appear in `formula`; ",
                          "it is the partition, and the totals tables carry it as ",
                          "a column."), by))
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
      by      = by,
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
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
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
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
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
#'   The flexible learners run with fixed default settings (hyperparameters are
#'   not currently exposed): "tree"/"forest" use the 'rpart'/'ranger' defaults,
#'   and "boost" uses xgboost with nrounds = 150, max_depth = 4 and eta = 0.1.
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
