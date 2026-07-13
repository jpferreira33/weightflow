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
#' @param min_cell_n integer. Minimum number of cases per adjustment cell
#'   (weighting class, poststratum). Cells below this raise a (non-fatal)
#'   warning recommending collapsing or switching to raking. Default 30,
#'   following Kalton and Flores-Cervantes (2003). Set to NULL to disable.
#' @param max_factor numeric. Adjustment factor above which a cell is flagged
#'   as excessive. Default 2.5. Set to NULL to disable.
#' @param warn logical. If TRUE, the quality alerts are also raised as R
#'   warnings during prep(). Default FALSE: alerts are always computed, stored
#'   on the object (`$alerts`) and shown in the HTML report, but not raised as
#'   warnings, so they do not flood bootstrap/jackknife replicate fits.
#' @return a "prepped_weighting_spec" object.
#' @examples
#' rec <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region")
#' prep(rec)
prep <- function(spec, min_cell_n = 30, max_factor = 2.5, warn = FALSE) {
  if (!inherits(spec, "weighting_spec"))
    stop("`spec` must be a weighting_spec.")
  data <- spec$data
  w    <- data[[spec$base_weights]]
  attr(data, "weightflow_base_w") <- w     # available to step_trim(reference = "base")

  history <- list(base = w)             # weight at each stage
  steps   <- spec$steps
  all_alerts <- character(0)

  for (i in seq_along(steps)) {
    w_before               <- w
    res                    <- apply_step(steps[[i]], data, w)
    w                      <- res$weights
    steps[[i]]$diagnostics <- res$diagnostics
    step_cls  <- class(steps[[i]])[1]
    is_calib  <- inherits(steps[[i]], c("step_calibrate", "step_model_calibration"))
    cell_step <- inherits(steps[[i]], c("step_nonresponse", "step_unknown_eligibility",
                                        "step_calibrate"))
    alerts <- .wf_alerts(w_before, w, res$diagnostics, is_calib, cell_step,
                         min_cell_n = min_cell_n, max_factor = max_factor)
    if (length(alerts)) {
      steps[[i]]$alerts <- alerts
      tagged <- sprintf("[%s] %s", step_cls, alerts)
      all_alerts <- c(all_alerts, tagged)
      if (isTRUE(warn)) for (a in tagged) warning(a, call. = FALSE)
    }
    history[[paste0("stage_", i, "_", step_cls)]] <- w
  }

  structure(
    list(
      data         = data,
      base_weights = spec$base_weights,
      steps        = steps,
      history      = history,
      final_weight = w,
      alerts       = all_alerts
    ),
    class = c("prepped_weighting_spec", "weighting_spec")
  )
}

# ---------------------------------------------------------------------------
# Non-fatal quality alerts for a single step. Returns a character vector of
# messages (possibly empty). These are surfaced as warnings by prep() and in
# the HTML report; they never stop the cascade.
#
#  - negative or < 1 weights: can arise from linear/GREG calibration, and also
#    from poststratification or raking. Flagged only for calibration steps.
#  - g-factors outside the Deville-Sarndal bounds [0.1, 10] (a common default
#    in survey calibration software). Flagged only for calibration steps.
#  - small adjustment cells (< min_cell_n) and excessive adjustment factors
#    (> max_factor), read from the step's own diagnostics table. The 30-per-cell
#    default follows Kalton and Flores-Cervantes (2003).
# ---------------------------------------------------------------------------
.wf_alerts <- function(w_before, w_after, diag, is_calib, cell_step = FALSE,
                       min_cell_n = 30, max_factor = 2.5,
                       g_lower = 0.1, g_upper = 10) {
  msgs <- character(0)

  if (isTRUE(is_calib)) {
    neg <- sum(w_after < 0, na.rm = TRUE)
    if (neg > 0)
      msgs <- c(msgs, sprintf(
        paste0("%d negative weight(s) after calibration. This can occur with ",
               "linear/GREG calibration; consider a bounded distance (logit or ",
               "truncated linear) and review the auxiliaries."), neg))
    sub1 <- sum(w_after > 0 & w_after < 1, na.rm = TRUE)
    if (sub1 > 0)
      msgs <- c(msgs, sprintf(
        paste0("%d weight(s) below 1 (under-weighting) after calibration. ",
               "Consider bounds L<1<U (e.g. a logit distance) to avoid it."), sub1))
    keep <- is.finite(w_before) & is.finite(w_after) & w_before > 0 & w_after != 0
    if (any(keep)) {
      g  <- w_after[keep] / w_before[keep]
      lo <- sum(g < g_lower, na.rm = TRUE)
      hi <- sum(g > g_upper, na.rm = TRUE)
      if (lo + hi > 0)
        msgs <- c(msgs, sprintf(
          paste0("%d case(s) with a g-factor outside the Deville-Sarndal bounds ",
                 "[%.2f, %.2f]: %d below, %d above."),
          lo + hi, g_lower, g_upper, lo, hi))
    }
  }

  if (isTRUE(cell_step) && is.data.frame(diag)) {
    if (!is.null(max_factor) && "factor" %in% names(diag)) {
      fac <- suppressWarnings(as.numeric(diag$factor))
      big <- which(is.finite(fac) & fac > max_factor)
      if (length(big) > 0)
        msgs <- c(msgs, sprintf(
          paste0("%d cell(s) with an adjustment factor > %.2f (max %.2f). ",
                 "Large factors inflate variance; consider collapsing cells."),
          length(big), max_factor, max(fac[big])))
    }
    if (!is.null(min_cell_n)) {
      ncol_name <- intersect(c("n_respondents", "n_known", "n_resp_hh", "n_hh", "n"),
                             names(diag))
      if (length(ncol_name) >= 1L) {
        cnt <- suppressWarnings(as.numeric(diag[[ncol_name[1]]]))
        few <- which(is.finite(cnt) & cnt < min_cell_n)
        if (length(few) > 0)
          msgs <- c(msgs, sprintf(
            paste0("%d cell(s) with fewer than %d cases (smallest observed %d). ",
                   "Kalton and Flores-Cervantes (2003) recommend at least 30 per ",
                   "cell; consider collapsing cells or switching to raking."),
            length(few), as.integer(min_cell_n), as.integer(min(cnt[few]))))
      }
    }
  }
  msgs
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
