# ---------------------------------------------------------------------------
# Nonprobability-sample entry point and initial-weights step.
#
# weighting_spec_nonprob(data): start a recipe on a nonprobability sample that
# has no design weights. It creates a provisional unit weight column so the rest
# of the recipe machinery works unchanged; step_initial_weights() then sets the
# real initial weights, and step_pseudo_weight() adjusts them by the estimated
# participation propensity.
# ---------------------------------------------------------------------------

#' Start a weighting recipe on a nonprobability sample
#'
#' Like [weighting_spec()], but for a nonprobability sample that has no design
#' weights of its own. It seeds a provisional unit weight (1 for every unit), so
#' the recipe can begin; use [step_initial_weights()] as the first step to set
#' the initial weights explicitly, then [step_pseudo_weight()] to adjust them by
#' the estimated participation propensity against a probability reference sample.
#'
#' @param data the nonprobability sample (a data frame).
#' @return a `weighting_spec` whose base weights are a provisional column of 1s.
#' @seealso [step_initial_weights()], [step_pseudo_weight()]
#' @export
weighting_spec_nonprob <- function(data) {
  if (!is.data.frame(data)) stop("`data` must be a data.frame.")
  if (!is.null(data[[".init_w"]]))
    stop("`data` already has a `.init_w` column; please rename it.")
  data[[".init_w"]] <- 1
  spec <- structure(
    list(data = data, base_weights = ".init_w", steps = list(),
         nonprob = TRUE),
    class = "weighting_spec"
  )
  spec
}

#' Set the initial weights of a nonprobability sample
#'
#' First step of a nonprobability recipe: it fixes the starting weights of the
#' sample before the propensity adjustment. Several conventions from the
#' literature are offered.
#'
#' @param spec a weighting_spec (typically from [weighting_spec_nonprob()]).
#' @param method one of:
#'   * `"unity"` (default): unit weight for every case, normalized to sum to
#'     `pop_size` if given (the unity-with-normalization method, which performs
#'     well in simulations).
#'   * `"naive"`: weight 1 for every case, no normalization (a baseline that
#'     treats the sample as if it were already representative).
#'   * `"constant"`: a constant weight `value` for every case (e.g. N/n).
#'   * `"ipa"`: inclusion-probability-adjusted; each unit gets the design weight
#'     of the most similar reference unit (nearest on the covariates). Requires
#'     `reference`, `reference_weights` and `formula`.
#' @param pop_size optional population size for normalization (`"unity"`).
#' @param value the constant weight for `method = "constant"`.
#' @param reference,reference_weights,formula needed for `method = "ipa"`.
#' @return the spec with the step appended.
#' @seealso [weighting_spec_nonprob()], [step_pseudo_weight()]
#' @export
step_initial_weights <- function(spec,
                                 method = c("unity", "naive", "constant", "ipa"),
                                 pop_size = NULL, value = NULL,
                                 reference = NULL, reference_weights = NULL,
                                 formula = NULL) {
  method <- match.arg(method)
  if (method == "constant" && is.null(value))
    stop("method = 'constant' requires `value`.")
  if (method == "ipa") {
    if (is.null(reference) || is.null(reference_weights) || is.null(formula))
      stop("method = 'ipa' requires `reference`, `reference_weights` and `formula`.")
  }
  label <- switch(method,
    unity    = if (is.null(pop_size)) "initial weights (unity)" else
               "initial weights (unity, normalized)",
    naive    = "initial weights (naive)",
    constant = sprintf("initial weights (constant = %g)", value),
    ipa      = "initial weights (inclusion-prob adjusted)")
  step <- structure(
    list(label = label, method = method, pop_size = pop_size, value = value,
         reference = reference, reference_weights = reference_weights,
         formula = formula),
    class = c("step_initial_weights", "weighting_step")
  )
  .add_step(spec, step)
}

#' @export
apply_step.step_initial_weights <- function(step, data, w) {
  n <- length(w)
  if (step$method == "naive") {
    new_w <- rep(1, n)

  } else if (step$method == "unity") {
    new_w <- rep(1, n)
    if (!is.null(step$pop_size)) new_w <- new_w * (step$pop_size / sum(new_w))

  } else if (step$method == "constant") {
    new_w <- rep(step$value, n)

  } else if (step$method == "ipa") {
    ref  <- step$reference
    rw   <- ref[[step$reference_weights]]
    vars <- all.vars(step$formula)
    # nearest reference unit on standardized covariates (numeric + dummies)
    mm_np <- stats::model.matrix(step$formula, data)
    mm_rf <- stats::model.matrix(step$formula, ref)
    common <- intersect(colnames(mm_np), colnames(mm_rf))
    mm_np <- mm_np[, common, drop = FALSE]
    mm_rf <- mm_rf[, common, drop = FALSE]
    ctr <- colMeans(mm_rf); scl <- apply(mm_rf, 2, stats::sd); scl[scl == 0] <- 1
    znp <- scale(mm_np, center = ctr, scale = scl)
    zrf <- scale(mm_rf, center = ctr, scale = scl)
    new_w <- numeric(n)
    for (i in seq_len(n)) {
      d2 <- colSums((t(zrf) - znp[i, ])^2)
      new_w[i] <- rw[which.min(d2)]
    }
  }

  diagnostics <- data.frame(
    method = step$method, n = n,
    sum_w = sum(new_w), min_w = min(new_w), max_w = max(new_w),
    stringsAsFactors = FALSE
  )
  list(weights = new_w, diagnostics = diagnostics)
}
