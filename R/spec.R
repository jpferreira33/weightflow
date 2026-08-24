# weighting_spec() constructor and the internal .add_step() that appends recipe steps.

# ---------------------------------------------------------------------------
# weightflow: declarative API to build survey weights through hierarchical
# stages, with recipe-aware bootstrap / jackknife variances on top.
# ---------------------------------------------------------------------------

#' Start a weighting specification
#'
#' Opens a weighting recipe on a sample and its design base weights. The object
#' it returns is inert: it holds the data, the name of the base-weight column and
#' an empty list of steps, and computes nothing. Every `step_*()` function takes
#' such an object and returns it with one more step appended; [prep()] estimates
#' the result.
#'
#' @param data data.frame with the sample units (one row per case).
#' @param base_weights unquoted name of the design base-weight column.
#' @return an object of class "weighting_spec".
#' @examples
#' rec <- weighting_spec(sample_survey, base_weights = pw)
#' rec
weighting_spec <- function(data, base_weights) {
  bw_expr <- substitute(base_weights)
  if (!is.data.frame(data)) stop("`data` must be a data.frame.")
  if (nrow(data) == 0L) stop("`data` has 0 rows (an upstream filter may have emptied it).")
  if (anyDuplicated(names(data)))
    stop(sprintf(paste0("`data` has duplicate column names: %s. Rename them before ",
                        "building a weighting_spec."),
                 paste(unique(names(data)[duplicated(names(data))]), collapse = ", ")),
         call. = FALSE)
  # Accept a bare column name (NSE) or a length-1 character string naming a column.
  bw <- if (is.character(bw_expr) && length(bw_expr) == 1L) bw_expr else deparse(bw_expr)
  if (!bw %in% names(data)) stop(sprintf("Base-weight column '%s' not found in the data.", bw))
  if (!is.numeric(data[[bw]]))
    stop(sprintf("Base weights must be numeric; column '%s' is a %s.",
                 bw, class(data[[bw]])[1]), call. = FALSE)
  if (any(is.na(data[[bw]]))) stop("Base weights cannot contain NA.")
  if (!all(is.finite(data[[bw]]))) stop("Base weights must be finite (no Inf or NaN).")
  if (any(data[[bw]] < 0)) stop("Base weights cannot be negative.")
  if (any(data[[bw]] == 0))
    warning("Some base weights are 0; those units start inactive and are dropped ",
            "from every step.", call. = FALSE)
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
.add_step <- function(spec, step, id = NULL) {
  if (!inherits(spec, "weighting_spec"))
    stop("The first argument must be a weighting_spec (piped with |>).")
  if (!is.null(id)) step$id <- id
  if (inherits(spec, "prepped_weighting_spec")) {
    # Iterative refinement workflow: prep() -> inspect the realized weights ->
    # add a step (e.g. a trim whose bounds come from that distribution) ->
    # prep() again. Downgrade to an unprepped spec so no stale results can be
    # read; the whole cascade re-runs with the new step on the next prep().
    message("Adding a step to a prepped recipe: previous results cleared. ",
            "Call prep() to re-run the full cascade with the new step.")
    data <- spec$data
    attr(data, "weightflow_base_w") <- NULL
    spec <- structure(
      list(data         = data,
           base_weights = spec$base_weights,
           steps        = lapply(spec$steps, function(s) {
             s$diagnostics <- NULL; s$alerts <- NULL; s })),
      class = "weighting_spec")
  }
  # Stable step id for referencing (history, collect_step_detail, alerts, report).
  # A constructor may set `step$id` explicitly; otherwise derive "<class>_<k>" with
  # k the ordinal of that class, bumping until unique so it never clashes.
  existing <- vapply(spec$steps, function(s) if (is.null(s$id)) "" else s$id, character(1))
  if (is.null(step$id)) {
    cls <- sub("^step_", "", class(step)[1])
    k   <- 1L + sum(vapply(spec$steps,
                           function(s) identical(sub("^step_", "", class(s)[1]), cls), logical(1)))
    id  <- sprintf("%s_%d", cls, k)
    while (id %in% existing) { k <- k + 1L; id <- sprintf("%s_%d", cls, k) }
    step$id <- id
  } else {
    if (!is.character(step$id) || length(step$id) != 1L || !nzchar(step$id))
      stop("`id` must be a single non-empty string.", call. = FALSE)
    if (step$id %in% existing)
      stop(sprintf("A step with id '%s' already exists in the recipe.", step$id), call. = FALSE)
  }
  spec$steps <- c(spec$steps, list(step))
  spec
}

# --- Step: unknown-eligibility adjustment ----------------------------------
