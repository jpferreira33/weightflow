# ---------------------------------------------------------------------------
# prep(): walks the steps in order and estimates the cascade of factors.
# collect_weights(): extracts the data.frame with the final weights.
# ---------------------------------------------------------------------------

#' Estimate the weighting cascade
#'
#' Walks the steps in the order they were added, starting from the base
#' weights. Each step multiplies the current weight by its adjustment factor.
#'
#' @param spec a weighting_spec.
#' @return a "prepped_weighting_spec" object.
#' @examples
#' rec <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region")
#' prep(rec)
prep <- function(spec) {
  if (!inherits(spec, "weighting_spec"))
    stop("`spec` must be a weighting_spec.")
  data <- spec$data
  w    <- data[[spec$base_weights]]
  attr(data, "weightflow_base_w") <- w     # available to step_trim(reference = "base")

  history <- list(base = w)             # weight at each stage
  steps   <- spec$steps

  for (i in seq_along(steps)) {
    res                    <- apply_step(steps[[i]], data, w)
    w                      <- res$weights
    steps[[i]]$diagnostics <- res$diagnostics
    history[[paste0("stage_", i, "_", class(steps[[i]])[1])]] <- w
  }

  structure(
    list(
      data         = data,
      base_weights = spec$base_weights,
      steps        = steps,
      history      = history,
      final_weight = w
    ),
    class = c("prepped_weighting_spec", "weighting_spec")
  )
}

#' Extract the data with the computed weights
#'
#' @param object a prepped object (output of prep()).
#' @param drop_zero logical. If TRUE, drops rows with final weight 0
#'   (ineligible / nonresponse). Default TRUE.
#' @param keep_intermediate logical. If TRUE, adds one column per stage.
#' @param weight_name name of the final weight column. Default ".weight".
#' @return data.frame.
#' @examples
#' fitted <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   prep()
#' head(collect_weights(fitted))
collect_weights <- function(object, drop_zero = TRUE,
                            keep_intermediate = FALSE, weight_name = ".weight") {
  if (!inherits(object, "prepped_weighting_spec"))
    stop("Call prep() first.")
  out <- object$data
  out[[weight_name]] <- object$final_weight

  if (keep_intermediate) {
    h <- object$history
    for (nm in names(h)) out[[paste0(".wt_", nm)]] <- h[[nm]]
  }
  if (drop_zero) out <- out[object$final_weight > 0, , drop = FALSE]
  out
}
