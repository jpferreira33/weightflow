# step_pseudoweight(): pseudo-weighting for a NON-probability sample against a
# probability reference. Stacks the two samples internally (the user never writes
# bind_rows), estimates the participation propensity, and returns the inverse-
# propensity pseudo-weight on the non-probability units.
#
# Elliott & Valliant (2017); Valliant (2020, JSSAM). The reference design weights
# enter the pooled fit as given (population scale); the pseudo-weight is the
# participation odds (1 - p)/p, which inflates each unit to the population so the
# weights sum to N. (An adjusted-logistic-propensity refinement, Wang-Valliant-Li
# 2021, is on the roadmap for smaller-sample bias.)

#' Pseudo-weights for a non-probability sample against a reference
#'
#' For a non-probability sample (opt-in panel, volunteer or river sample) with no
#' design weights, `step_pseudoweight()` estimates each unit's *participation
#' propensity* `p` against a probability `reference_sample()` and assigns the
#' pseudo-weight `(1 - p)/p` (the participation odds; Elliott and Valliant 2017),
#' which inflates each unit to the population so the weights sum to the reference's
#' estimated population size. It stacks the non-probability sample and the
#' reference internally (the participation indicator and the two samples' weights
#' are built for you), fits the propensity, and returns the pseudo-weight on the
#' non-probability units only; the reference is used to train the model and then
#' dropped.
#'
#' The recipe must be a non-probability spec: `weighting_spec(..., nonprob =
#' TRUE)`. This step is the inverse-propensity (IPW) route; you can instead, or
#' additionally, calibrate to a `reference_sample()` with [step_calibrate()] /
#' [step_model_calibration()] (mass imputation / model-based), and combining both
#' gives the doubly robust estimator.
#'
#' @param spec a non-probability `weighting_spec`.
#' @param reference a [reference_sample()] (the probability reference with its
#'   design weights). Pass the reference's replicate weights through
#'   `reference_sample(replicates = )` to propagate its sampling variance through
#'   the recipe-aware bootstrap: each replicate refits the propensity from the
#'   paired reference replicate. Without them the reference is treated as fixed,
#'   so the bootstrap reflects only the variability of the non-probability sample
#'   (which it resamples as a with-replacement sample of units, a slightly
#'   conservative approximation when that sample is a large fraction of the
#'   population).
#' @param formula one-sided formula of the covariates shared by both samples,
#'   e.g. `~ sex + age + region`.
#' @param engine propensity learner: `"logit"` (default), `"tree"`, `"forest"` or
#'   `"boost"`.
#' @param num_classes NULL (default, direct `1/pi`) or an integer: group the
#'   fitted propensities into that many quantile classes and use the class-average
#'   pseudo-weight, which is more robust to a misspecified model.
#' @param crossfit,crossfit_seed optional K-fold cross-fitting of the propensity
#'   (recommended for the flexible learners), and its seed.
#' @param id optional stable step id.
#' @return the input `weighting_spec` with this step appended.
#' @references
#' Elliott, M. R. and Valliant, R. (2017). Inference for non-probability samples.
#' Statistical Science 32(2), 249-264.
#' @seealso [reference_sample()], [step_calibrate()], [step_model_calibration()]
#' @export
#' @family weighting steps
step_pseudoweight <- function(spec, reference, formula,
                              engine = c("logit", "tree", "forest", "boost"),
                              num_classes = NULL, crossfit = NULL,
                              crossfit_seed = NULL, id = NULL) {
  if (!inherits(spec, "weighting_spec"))
    stop("The first argument must be a weighting_spec.", call. = FALSE)
  if (!isTRUE(spec$nonprob))
    stop(paste0("step_pseudoweight() is for a NON-probability sample: build the recipe with ",
                "weighting_spec(..., nonprob = TRUE)."), call. = FALSE)
  engine <- match.arg(engine)
  id <- .wf_id(id)
  if (missing(reference) || !inherits(reference, "wf_reference_sample"))
    stop("`reference` must be a reference_sample() (the probability reference with its weights).",
         call. = FALSE)
  if (missing(formula) || !inherits(formula, "formula"))
    stop("`formula` must be a one-sided formula of the shared covariates, e.g. ~ sex + age.",
         call. = FALSE)
  if (!is.null(crossfit)) {
    if (!is.numeric(crossfit) || length(crossfit) != 1L || !is.finite(crossfit) ||
        crossfit < 2 || crossfit != round(crossfit))
      stop("`crossfit` must be NULL or a single integer >= 2 (number of folds).", call. = FALSE)
    crossfit <- as.integer(crossfit)
  }
  if (!is.null(num_classes)) {
    if (!is.numeric(num_classes) || length(num_classes) != 1L || !is.finite(num_classes) ||
        num_classes < 2 || num_classes != round(num_classes))
      stop("`num_classes` must be NULL (direct 1/pi) or a single integer >= 2.", call. = FALSE)
    num_classes <- as.integer(num_classes)
  }
  step <- structure(
    list(label = "pseudo-weights (participation propensity vs reference)",
         reference = reference, formula = formula, engine = engine,
         num_classes = num_classes, crossfit = crossfit, crossfit_seed = crossfit_seed),
    class = c("step_pseudoweight", "weighting_step"))
  .add_step(spec, step, id = id)
}

#' @export
apply_step.step_pseudoweight <- function(step, data, w) {
  active <- .wf_active(w)
  ref    <- step$reference
  wref   <- attr(ref, "wf_ref_weights")
  if (is.null(wref)) stop("`reference` has no weights (not a reference_sample()).", call. = FALSE)
  # Propagate the reference's sampling variance: in a bootstrap replicate, refit the
  # propensity using the PAIRED reference replicate weights (same mechanism as
  # reference_sample() in model calibration). Point prep, or a reference with no
  # replicate weights, uses the point weights, so the reference is treated as fixed.
  rep_mat <- attr(ref, "wf_ref_replicates")
  ridx    <- attr(data, "wf_replicate_idx")
  if (!is.null(rep_mat) && !is.null(ridx))
    wref <- rep_mat[, ((ridx - 1L) %% ncol(rep_mat)) + 1L]
  vars <- all.vars(step$formula)

  # Both samples must carry the shared covariates, with compatible types.
  miss_np <- setdiff(vars, names(data))
  miss_rf <- setdiff(vars, names(ref))
  if (length(miss_np) || length(miss_rf))
    stop(sprintf(paste0("Pseudo-weighting covariate(s) missing: %s%s. The `formula` variables ",
                        "must exist with the same name in BOTH the non-probability sample and ",
                        "the reference."),
                 if (length(miss_np)) sprintf("%s in the sample", paste(miss_np, collapse = ", ")) else "",
                 if (length(miss_rf)) sprintf("%s%s in the reference",
                                              if (length(miss_np)) "; " else "",
                                              paste(miss_rf, collapse = ", ")) else ""),
         call. = FALSE)
  for (v in vars) {
    tn <- class(data[[v]])[1]; tr <- class(ref[[v]])[1]
    if (!identical(tn, tr))
      stop(sprintf(paste0("Covariate '%s' has type %s in the sample but %s in the reference; ",
                          "harmonise the two samples (same type and factor levels) before ",
                          "pseudo-weighting."), v, tn, tr), call. = FALSE)
    # NP-04: types match but the factor levels may not. A level present in only one
    # sample biases the pooled fit: a level only in the sample can push its fitted p
    # toward 1 (pseudo-weight toward 0; see the p_max alert), and with cross-fitting
    # it can fall wholly into a test fold and error. Warn (prep records it in $alerts).
    if (is.factor(data[[v]]) || is.factor(ref[[v]])) {
      only_np <- setdiff(levels(as.factor(data[[v]])), levels(as.factor(ref[[v]])))
      only_rf <- setdiff(levels(as.factor(ref[[v]])),  levels(as.factor(data[[v]])))
      if (length(only_np) || length(only_rf))
        warning(sprintf(paste0("Covariate '%s' has factor levels that differ between the sample ",
          "and the reference (%s%s); unmatched levels bias the propensity fit and can push ",
          "pseudo-weights to extremes. Harmonise the levels before pseudo-weighting."),
          v,
          if (length(only_np)) sprintf("only in the sample: %s", paste(only_np, collapse = ", ")) else "",
          if (length(only_rf)) sprintf("%sonly in the reference: %s",
            if (length(only_np)) "; " else "", paste(only_rf, collapse = ", ")) else ""),
          call. = FALSE)
    }
  }

  # --- pool the two samples internally (the user never writes bind_rows) ------
  np <- data[active, vars, drop = FALSE]; np$.y <- 1; np$.w <- w[active]
  rf <- ref[, vars, drop = FALSE];       rf$.y <- 0
  n_np  <- nrow(np)
  # The reference design weights enter the pooled fit as given, so they represent
  # the population and the pseudo-weight 1/pi inflates each non-prob unit to it
  # (Elliott and Valliant 2017).
  rf$.w  <- as.numeric(wref)
  pooled <- rbind(np, rf)

  pi_all <- .estimate_propensity(step$engine, step$formula, pooled, pooled$.w,
                                 crossfit = step$crossfit, seed = step$crossfit_seed)
  # NP-01: symmetric clamp. .estimate_propensity only FLOORS p (it guards 1/p in the
  # nonresponse path). Here the pseudo-weight is the participation ODDS (1 - p)/p, so
  # the dangerous end is the mirror one: p -> 1 sends the pseudo-weight to 0 and the
  # unit silently adopts the "dropped" sentinel (a pure leaf in tree/forest gives
  # p == 1 exactly; glm can give 1 - eps). Cap p away from 1 as well.
  pi_all <- pmin(pmax(pi_all, 1e-6), 1 - 1e-6)
  pi_np  <- pi_all[seq_len(n_np)]

  # Pseudo-weight = participation ODDS (1 - p)/p. In the Elliott-Valliant pooled
  # fit (reference weighted to the population N, non-prob units weight 1) the
  # fitted p estimates n(x)/(n(x)+N(x)), so (1 - p)/p = N(x)/n(x) inflates each
  # unit to the population and the weights sum to N. Using 1/p would add a spurious
  # +1 per unit (weights sum to N + n), mixing in the unweighted naive mean.
  factor <- (1 - pi_np) / pi_np
  collapsed <- FALSE
  if (!is.null(step$num_classes)) {
    cls <- .propensity_classes(pi_np, step$num_classes)
    collapsed <- isTRUE(attr(cls, "collapsed"))   # NP-05: quantile cut-points collapsed
    # within each class, the average applied factor (weighted by incoming weight)
    for (g in unique(cls)) {
      in_g <- cls == g
      factor[in_g] <- stats::weighted.mean((1 - pi_np[in_g]) / pi_np[in_g], np$.w[in_g])
    }
  }
  psw <- np$.w * factor

  new_w <- w
  new_w[active] <- psw

  diag <- data.frame(
    quantity = c("non-prob units", "reference units", "min propensity",
                 "pseudo-weight sum", "mean pseudo-weight"),
    value = c(n_np, nrow(rf), round(min(pi_np), 4), round(sum(psw)), round(mean(psw), 2)),
    stringsAsFactors = FALSE)
  attr(diag, "p_min") <- min(pi_np)      # reuse the tiny-propensity alert
  attr(diag, "p_max") <- max(pi_np)      # NP-01 mirror: participation ~ 1 -> pseudo-weight ~ 0
  if (collapsed) attr(diag, "classes_collapsed") <- TRUE   # NP-05
  # NP-02: expose the pooled propensity so the report renders the common-support /
  # overlap, calibration, Brier and AUC diagnostics -- the central assumption of
  # non-probability inference. resp = the participation indicator (non-prob vs
  # reference). idx = NULL so collect_propensities() cleanly skips this pooled fit
  # (its p is not aligned to the sample rows) rather than mis-indexing.
  attr(diag, "propensity") <- list(
    p = as.numeric(pi_all), resp = as.logical(pooled$.y == 1),
    dw = as.numeric(pooled$.w), idx = NULL, level = "unit", class = NULL,
    covars = pooled[, vars, drop = FALSE], engine = step$engine,
    formula = step$formula, crossfit = step$crossfit,
    num_classes = step$num_classes,
    cal_slope = tryCatch(unname(stats::coef(suppressWarnings(stats::glm(
      as.integer(pooled$.y == 1) ~ stats::qlogis(pmin(pmax(pi_all, 1e-6), 1 - 1e-6)),
      family = stats::binomial(), weights = pooled$.w)))[2]), error = function(e) NA_real_))
  list(weights = new_w, diagnostics = diag)
}
