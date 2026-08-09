# weighting_spec() constructor and the internal .add_step() that appends recipe steps.

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
  if (nrow(data) == 0L) stop("`data` has 0 rows (an upstream filter may have emptied it).")
  if (!bw %in% names(data)) stop(sprintf("Base-weight column '%s' not found in the data.", bw))
  if (any(is.na(data[[bw]]))) stop("Base weights cannot contain NA.")
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
.add_step <- function(spec, step) {
  if (!inherits(spec, "weighting_spec"))
    stop("The first argument must be a weighting_spec (piped with |>).")
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
  spec$steps <- c(spec$steps, list(step))
  spec
}

# --- Step: unknown-eligibility adjustment ----------------------------------
