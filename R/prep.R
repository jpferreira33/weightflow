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
  warn <- .wf_flag(warn, "warn")                 # "yes"/1/NA would silently disable warnings
  if (!is.null(min_cell_n) && (!is.numeric(min_cell_n) || length(min_cell_n) != 1L ||
                               is.na(min_cell_n) || min_cell_n < 0))
    stop("`min_cell_n` must be NULL (no small-cell check) or a single non-negative number.",
         call. = FALSE)
  if (!is.null(max_factor) && (!is.numeric(max_factor) || length(max_factor) != 1L ||
                               is.na(max_factor) || max_factor <= 0))
    stop("`max_factor` must be NULL (no large-factor check) or a single positive number.",
         call. = FALSE)
  data <- spec$data
  w    <- data[[spec$base_weights]]
  attr(data, "weightflow_base_w") <- w     # available to step_trim(reference = "base")

  history <- list(base = w)             # weight at each stage
  steps   <- spec$steps
  all_alerts <- character(0)

  for (i in seq_along(steps)) {
    w_before               <- w
    .check_step_labelled(steps[[i]], data)
    res                    <- apply_step(steps[[i]], data, w)
    w                      <- res$weights
    if (any(!is.finite(w)))
      stop(sprintf(paste0("Step %d (%s) produced %d non-finite weight(s) (Inf/NaN), which ",
                          "would corrupt every later step and the diagnostics silently. This ",
                          "usually comes from a zero or missing selection probability, a zero ",
                          "cell total, or an extreme calibration factor -- check that step's ",
                          "inputs."),
                   i, class(steps[[i]])[1], sum(!is.finite(w))), call. = FALSE)
    steps[[i]]$diagnostics <- res$diagnostics
    step_cls  <- class(steps[[i]])[1]
    is_calib  <- inherits(steps[[i]], c("step_calibrate", "step_model_calibration"))
    cell_step <- inherits(steps[[i]], c("step_nonresponse", "step_unknown_eligibility",
                                        "step_calibrate"))
    alerts <- .wf_alerts(w_before, w, res$diagnostics, is_calib, cell_step,
                         min_cell_n = min_cell_n, max_factor = max_factor,
                         step_class = step_cls)
    ca <- .crossfit_alert(steps[[i]])
    if (!is.null(ca)) alerts <- c(alerts, ca)
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

# Quality alert: a flexible learner (tree / forest / boost) used WITHOUT
# cross-fitting. Same-sample predictions keep each unit in the training set of
# its own prediction, so the residuals are shrunk by overfitting and the variance
# can be understated even under recipe-aware replication (re-fitting the learner
# per replicate does not break that unit-prediction dependence; only sample
# splitting does). Cross-fitting (crossfit = K) removes it. Applies to
# step_nonresponse(method = "propensity") and step_model_calibration.
# Refs: Dagdoug, Goga & Haziza (2023); Chernozhukov et al. (2018).
.crossfit_alert <- function(step) {
  flexible <- c("tree", "forest", "boost")
  eng <- character(0)
  if (inherits(step, "step_nonresponse") && identical(step$method, "propensity"))
    eng <- step$engine
  else if (inherits(step, "step_model_calibration"))
    eng <- vapply(step$models, function(m) if (is.null(m$engine)) "glm" else m$engine,
                  character(1))
  hit <- intersect(unique(eng), flexible)
  if (length(hit) && is.null(step$crossfit))
    return(sprintf(paste0(
      "Flexible learner (%s) without cross-fitting: same-sample predictions can ",
      "understate the variance even under recipe-aware replication, because each ",
      "unit stays in the training set of its own prediction. Set crossfit = 5 to ",
      "break it (Dagdoug, Goga and Haziza 2023; Chernozhukov et al. 2018)."),
      paste(hit, collapse = ", ")))
  NULL
}

# Guard: a haven_labelled (SPSS/Stata) column used in a MODEL FORMULA enters the
# model.matrix as its numeric codes (1, 2, 3, ...) -- a continuous term, not the
# categories the user intends -- silently mis-specifying the calibration / model.
# Cell (`by`) grouping and 0/1 dispositions are fine on labelled vectors (they go
# by the codes, which is correct there); only formula terms are affected.
.check_step_labelled <- function(step, data) {
  fs   <- Filter(function(f) inherits(f, "formula"),
                 c(list(step$formula), list(step$x_formula)))
  vars <- unique(unlist(lapply(fs, all.vars)))
  vars <- intersect(vars, names(data))
  bad  <- vars[vapply(vars, function(v) inherits(data[[v]], "haven_labelled"),
                      logical(1))]
  if (length(bad))
    stop(sprintf(paste0("Formula variable(s) %s are haven_labelled (from an SPSS/Stata ",
                        "import). In a model formula they enter as their numeric codes ",
                        "(1, 2, 3, ...), i.e. a continuous term -- not as categories -- a ",
                        "silent, semantically wrong calibration/model. Convert them first, ",
                        "e.g. `data <- haven::as_factor(data)` or `haven::as_factor()` the ",
                        "specific columns."),
                 paste(bad, collapse = ", ")), call. = FALSE)
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
                       g_lower = 0.1, g_upper = 10, step_class = NULL) {
  msgs <- character(0)

  # Control totals that did not sum to a common N and were reconciled: surface
  # what happened / what was done in the quality report (attention panel + card).
  rec <- attr(diag, "reconcile")
  if (!is.null(rec) && nzchar(rec)) msgs <- c(msgs, rec)

  # An adjustment cell with no units to adjust to (no respondents / all unknown)
  # gets an NA factor; the affected units were set to weight 0. Surface it.
  if (!is.null(diag) && is.data.frame(diag) && "factor" %in% names(diag) &&
      any(is.na(diag$factor)))
    msgs <- c(msgs, sprintf(
      paste0("%d adjustment cell(s) had no units to adjust to (no respondents, ",
             "or all of unknown eligibility); the affected units were set to ",
             "weight 0. Consider collapsing cells or using a coarser grouping."),
      sum(is.na(diag$factor))))

  # Very small response propensities blow up the 1/p weights; flag it.
  pm <- attr(diag, "p_min")
  if (!is.null(pm) && is.finite(pm) && pm < 0.01)
    msgs <- c(msgs, sprintf(
      paste0("Very small response propensities (min p = %.4f among respondents) ",
             "produce extreme 1/p weights (up to %.0fx). Check the propensity model, ",
             "or trim with step_trim_weights()."),
      pm, 1 / pm))

  # Propensity classes collapsed: the fitted propensities were ~constant, so the
  # requested num_classes quantile cut-points could not be formed and every unit
  # went to a single adjustment class. Surface it (the correction did nothing).
  if (isTRUE(attr(diag, "classes_collapsed")))
    msgs <- c(msgs, paste0(
      "The response propensities were nearly constant, so the requested ",
      "num_classes could not be formed (the quantile cut-points collapsed); ",
      "all units were placed in a single adjustment class -- the class-based ",
      "correction had no effect. Drop num_classes (use 1/p weighting) or revise ",
      "the propensity model."))

  # Miscalibrated response propensities distort the 1/p weights: flag a
  # calibration slope far from 1 (weighted logistic of response on logit(p-hat)).
  cs <- attr(diag, "propensity")$cal_slope
  if (!is.null(cs) && is.finite(cs) && abs(cs - 1) > 0.3)
    msgs <- c(msgs, sprintf(
      paste0("The response propensities look miscalibrated (calibration slope %.2f, ",
             "ideal 1). For 1/p weighting the probabilities must be honest, not just ",
             "discriminative. Set num_classes (e.g. 5) to bin by propensity quantiles ",
             "-- which use only the ranking of the propensities and so are robust to ",
             "this shrinkage -- or review the propensity model."),
      cs))

  # Nonresponse by calibration: non-positive g-weights imply an invalid response
  # probability (<= 0 or undefined) and a non-positive weight; surface it.
  cnr <- attr(diag, "calib_nr")
  if (!is.null(cnr) && !is.null(cnr$g) && length(cnr$g)) {
    gg <- cnr$g[is.finite(cnr$g)]
    if (length(gg) && sum(gg <= 0) > 0)
      msgs <- c(msgs, sprintf(
        paste0("%d respondent(s) have a non-positive calibration g-weight (implied ",
               "response probability <= 0 or undefined). The nonresponse-calibration ",
               "auxiliaries are ill-behaved; use a bounded distance (logit) or a ",
               "different auxiliary vector."), sum(gg <= 0)))
  }

  # Ill-conditioned linear/GREG calibration: near-collinear auxiliaries make the
  # calibration factors unstable; point to the ridge penalty.
  cbd <- attr(diag, "calibrate")
  if (!is.null(cbd) && !is.null(cbd$cond) && is.finite(cbd$cond) && cbd$cond > 1e10)
    msgs <- c(msgs, sprintf(
      paste0("The calibration system is ill-conditioned (condition number %.1e): ",
             "near-collinear auxiliaries can make the weights unstable. Drop a ",
             "redundant auxiliary, or set penalty = <lambda> (ridge)."), cbd$cond))
  # Negative calibration weights: a valid but unusual output of unbounded linear
  # calibration. They stay active (in the cascade, collect_weights() and the deff),
  # so the totals are honest -- but surface them, since a negative survey weight is
  # rarely wanted and makes the estimator erratic.
  if (!is.null(cbd) && !is.null(cbd$g)) {
    nneg <- sum(cbd$g < 0, na.rm = TRUE)
    if (nneg > 0L)
      msgs <- c(msgs, sprintf(
        paste0("%d unit(s) received a NEGATIVE calibration weight. They remain active (counted ",
               "in the totals, the design effect and collect_weights()), but a negative weight ",
               "is rarely intended; set `bounds` to keep the calibration factor positive."),
        nneg))
  }

  # Trimming that could not preserve the weight total: the requested bounds were
  # infeasible, so part of the trimmed mass was absorbed instead of redistributed
  # and the point estimates shift. Covers step_trim and step_trim_weights (the
  # range-restricted step_trim_calibrated preserves the totals by construction).
  tr <- attr(diag, "trim_rec")
  if (!is.null(tr) && !identical(tr$redistribute, "calibration") &&
      !is.null(tr$wb) && !is.null(tr$wa)) {
    sb <- sum(tr$wb, na.rm = TRUE); sa <- sum(tr$wa, na.rm = TRUE)
    if (is.finite(sb) && sb > 0 && abs(sb - sa) > 0.01 * sb)
      msgs <- c(msgs, sprintf(
        paste0("Trimming %s the weight total by %.1f%% (from %s to %s): the mass was not ",
               "preserved (infeasible bounds absorbed, or a floor above the cap). The point ",
               "estimates shift; check the bounds, or use step_trim_calibrated() to trim while ",
               "preserving totals."),
        if (sa < sb) "reduced" else "increased", abs(100 * (sa - sb) / sb),
        format(round(sb), big.mark = ","), format(round(sa), big.mark = ",")))
  }

  # Partial-response households treated as whole-household nonresponse: flag how
  # many responding members were discarded (so the assumption is visible).
  ph <- attr(diag, "partial_hh")
  if (!is.null(ph) && ph > 0)
    msgs <- c(msgs, sprintf(
      paste0("%d household(s) responded only partially and were treated as ",
             "whole-household nonresponse, discarding %d responding member(s). ",
             "If you meant person-level nonresponse, drop `cluster`."),
      ph, attr(diag, "discarded_resp")))

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
        if (length(few) > 0) {
          advice <- if (identical(step_class, "step_unknown_eligibility"))
            "consider collapsing cells (a coarser grouping)."
          else "consider collapsing cells or switching to raking."
          msgs <- c(msgs, sprintf(
            paste0("%d cell(s) with fewer than %d cases (smallest observed %d). ",
                   "Kalton and Flores-Cervantes (2003) recommend at least 30 per cell; %s"),
            length(few), as.integer(min_cell_n), as.integer(min(cnt[few])), advice))
        }
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
  weight_name <- .wf_outname(weight_name, "weight_name")   # 1 / NA / "" would silently overwrite
  out <- object$data
  if (weight_name %in% names(out))
    warning(sprintf(paste0("Column '%s' already in the data was overwritten with the ",
                           "computed weights; pass weight_name= to keep both."), weight_name),
            call. = FALSE)
  out[[weight_name]] <- object$final_weight

  if (keep_intermediate) {
    h <- object$history
    for (nm in names(h)) out[[paste0(".wt_", nm)]] <- h[[nm]]
  }
  # which() (not a bare logical) so any NA weight is dropped rather than inserting
  # a phantom all-NA row (which later breaks summary()). drop_zero drops the exact
  # zeros (the "dropped" marker); negative weights are active and are kept, so the
  # data.frame total matches sum(final_weight).
  if (drop_zero) out <- out[which(.wf_active(object$final_weight)), , drop = FALSE]
  out
}
