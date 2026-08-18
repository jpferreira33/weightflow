# collect_step_detail(): generic per-unit view of a single step. `.weight_in` and
# `.factor` are computed centrally from `object$history` (so the invariant
# `.weight_in * .factor = weight out` holds by construction for EVERY step); any
# step-specific native columns are harvested from attr(diagnostics, "unit_detail").

# --- contract validation (runs when harvesting) ----------------------------
.wf_validate_unit_detail <- function(ud, n) {
  if (!is.list(ud) || is.null(ud$idx) || is.null(ud$detail))
    stop("Malformed `unit_detail`: it needs `idx` and `detail`.", call. = FALSE)
  idx <- ud$idx; det <- ud$detail
  if (!is.data.frame(det))
    stop("`unit_detail$detail` must be a data.frame.", call. = FALSE)
  if (nrow(det) != length(idx))
    stop("`unit_detail`: nrow(detail) must equal length(idx).", call. = FALSE)
  if (anyNA(idx) || any(idx < 1L) || any(idx > n) || anyDuplicated(idx))
    stop("`unit_detail`: `idx` must be unique indices within 1..nrow(data).", call. = FALSE)
  bad <- names(det)[!startsWith(names(det), ".")]
  if (length(bad))
    stop(sprintf("`unit_detail` columns must start with '.': %s", paste(bad, collapse = ", ")),
         call. = FALSE)
  invisible(TRUE)
}

# --- expand a native column to full length, NA outside idx, keeping type ----
.wf_expand_native <- function(x, idx, n) {
  if (is.factor(x)) {
    out <- factor(rep(NA_character_, n), levels = levels(x))
    out[idx] <- as.character(x)
  } else if (is.character(x)) {
    out <- rep(NA_character_, n); out[idx] <- x
  } else if (is.logical(x)) {
    out <- rep(NA, n); out[idx] <- x
  } else {
    out <- rep(NA_real_, n); out[idx] <- as.numeric(x)
  }
  out
}

.wf_step_label <- function(object, k)
  sub("^step_", "", class(object$steps[[k]])[1])

#' Per-unit detail of one step of the cascade
#'
#' A generic companion to [collect_weights()] that returns, for a single step, the
#' weight it received and the multiplier it applied to every unit, plus any
#' quantities that step computed internally (for a propensity step, the fitted
#' propensity and its class). `.weight_in` and `.factor` are read from the
#' stage-by-stage weights that [prep()] already stores, so
#' `.weight_in * .factor` equals the weight leaving the step by construction,
#' for any step. Native columns (those a step exposes on its own) are `NA` for
#' units the step did not touch.
#'
#' @param object a prepped `weighting_spec` (the output of [prep()]).
#' @param step optional integer, which step to inspect (1 for the first piped
#'   step). If `NULL` (default): a single step exposing native detail is used; if
#'   several do, or if none do and the recipe has more than one step, an error
#'   lists the steps so you can choose.
#' @return The sample `data.frame` with `.weight_in` (the weight reaching the
#'   step, carrying every earlier adjustment) and `.factor` (the multiplier the
#'   step applied to each unit, `NA` where the incoming weight is zero) appended,
#'   plus any native columns of the chosen step (for a propensity step:
#'   `.propensity`, `.responded`, and `.class` when propensity classes are used),
#'   which are `NA` outside the units the step covers. Here `.factor` is defined
#'   for every unit with a nonzero incoming weight, so an active unit the step did
#'   not touch reports `.factor = 1`; this differs from [collect_propensities()],
#'   where `.factor` is `NA` outside the propensity model (see its `.status`).
#' @seealso [collect_weights()], [collect_propensities()], [weight_factors()]
#' @examples
#' fit <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "propensity",
#'                    formula = ~ sex + region, engine = "logit") |>
#'   prep()
#' d <- collect_step_detail(fit, step = 1)
#' head(d[!is.na(d$.factor), c(".weight_in", ".factor", ".propensity")])
#' @export
collect_step_detail <- function(object, step = NULL) {
  if (!inherits(object, "prepped_weighting_spec"))
    stop("`object` must be a prepped weighting_spec (the output of prep()).", call. = FALSE)
  ns <- length(object$steps)
  if (ns < 1L)
    stop("The recipe has no steps to inspect.", call. = FALSE)
  n <- nrow(object$data)

  have <- which(vapply(object$steps,
                       function(s) !is.null(attr(s$diagnostics, "unit_detail")),
                       logical(1)))

  if (is.null(step)) {
    if (length(have) == 1L) {
      step <- have
    } else if (length(have) > 1L) {
      lbl <- vapply(have, function(k) sprintf("step %d: %s", k, .wf_step_label(object, k)),
                    character(1))
      stop("Several steps expose per-unit detail; pass `step =` to choose one. ",
           paste(lbl, collapse = "; "), ".", call. = FALSE)
    } else if (ns == 1L) {
      step <- 1L
    } else {
      stop(sprintf("The recipe has %d steps; pass `step =` (1..%d) to choose one.", ns, ns),
           call. = FALSE)
    }
  }
  if (!is.numeric(step) || length(step) != 1L || is.na(step) ||
      step < 1L || step > ns || step %% 1 != 0)
    stop(sprintf("`step` must be a single integer in 1..%d.", ns), call. = FALSE)
  step <- as.integer(step)

  # Central: weight reaching the step and the multiplier it applied.
  h     <- object$history
  w_in  <- h[[step]]
  w_out <- h[[step + 1L]]
  fac   <- ifelse(w_in != 0, w_out / w_in, NA_real_)

  out <- object$data
  put <- function(df, nm, val) {
    if (nm %in% names(df))
      warning(sprintf("Column `%s` already exists in the data and will be overwritten.", nm),
              call. = FALSE)
    df[[nm]] <- val
    df
  }
  out <- put(out, ".weight_in", w_in)
  out <- put(out, ".factor",    fac)

  ud <- attr(object$steps[[step]]$diagnostics, "unit_detail")
  if (!is.null(ud)) {
    .wf_validate_unit_detail(ud, n)
    for (nm in names(ud$detail))
      out <- put(out, nm, .wf_expand_native(ud$detail[[nm]], ud$idx, n))
  }
  out
}
