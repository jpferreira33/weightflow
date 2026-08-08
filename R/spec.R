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
  spec$steps <- c(spec$steps, list(step))
  spec
}

# --- Step: unknown-eligibility adjustment ----------------------------------
