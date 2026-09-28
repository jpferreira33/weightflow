# step_pseudoweight(): pseudo-weighting for a NON-probability sample against a
# probability reference. Stacks the two samples internally (the user never writes
# bind_rows), estimates the participation propensity, and returns the inverse-
# propensity pseudo-weight on the non-probability units.
#
# Wang, Valliant & Li (2021) adjusted logistic propensity (ALP); see also Elliott &
# Valliant (2017) and Valliant (2020, JSSAM). The reference design weights enter the
# pooled fit as given (population scale); the pseudo-weight is the participation odds
# (1 - p)/p.
#
# What the sum of those weights is, exactly: an ESTIMATOR of N, not N. Under the
# pooled fit the fitted p estimates n(x)/(n(x) + N(x)), so (1 - p)/p = N(x)/n(x) and
# sum((1 - p)/p) over the volunteers has expectation N -- it is unbiased, and nothing
# constrains the realised sum. Measured with a correctly specified model: mean 0.994
# and sd 2.0% of N with a reference of 500, mean 0.988 and sd 1.0% with 3000, i.e.
# +-5% between samples is ordinary. A calibration step imposes its totals exactly;
# this does not, and describing it as an identity (as this file did until 2026-09-27)
# is wrong.

#' Pseudo-weights for a non-probability sample against a reference
#'
#' For a non-probability sample (opt-in panel, volunteer or river sample) with no
#' design weights, `step_pseudoweight()` estimates each unit's *participation
#' propensity* \eqn{\hat p} against a probability `reference_sample()` and assigns
#' the pseudo-weight \eqn{(1 - \hat{p})/\hat{p}}{(1 - p)/p} (the participation odds;
#' the adjusted logistic propensity of Wang, Valliant and Li 2021, after Elliott and
#' Valliant 2017), which inflates each unit to the population. Their sum *estimates*
#' the reference's estimated population size -- it is unbiased for it, not equal to
#' it, and varies from sample to sample like any other estimator. It stacks the non-probability sample and the
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
#' Wang, L., Valliant, R. and Li, Y. (2021). Adjusted logistic propensity weighting
#' methods for population inference using nonprobability volunteer-based epidemiologic
#' cohorts. Statistics in Medicine 40(24), 5237-5250. \doi{10.1002/sim.9122}
#'
#' Elliott, M. R. and Valliant, R. (2017). Inference for non-probability samples.
#' Statistical Science 32(2), 249-264.
#' @seealso [reference_sample()], [step_calibrate()], [step_model_calibration()]
#' @examples
#' set.seed(1)
#' N   <- nrow(population)
#' # a biased volunteer sample (men over-participate) and a probability reference
#' vol <- population[rbinom(N, 1, plogis(-2 + 0.9 * (population$sex == "M"))) == 1,
#'                   c("region", "sex", "income")]
#' ref <- population[sample(N, 600), c("region", "sex")]
#' ref$d <- N / 600                                   # its design weights
#' fit <- weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
#'   step_pseudoweight(reference = reference_sample(ref, "d"),
#'                     formula = ~ region + sex, engine = "logit") |>
#'   prep()
#' # the pseudo-weighted mean corrects the volunteer bias
#' c(naive = mean(vol$income),
#'   pseudo = weighted.mean(vol$income, fit$final_weight),
#'   truth = mean(population$income))
#' @export
#' @family weighting steps
#' @param by NULL (default), or a single column name: fit **one participation model per
#'   domain**, on that domain's units of both samples and on nothing else. The
#'   `reference` must carry the same domain column, and is split by it, so the
#'   pseudo-weights of a domain sum to that domain's reference total rather than to the
#'   national one -- which is what lets a following domain-partitioned calibration start
#'   from a coherent input weight. Use it when the participation mechanism differs
#'   across domains (a covariate whose effect changes sign by region is the clear case);
#'   a single national model cannot represent that, and the resulting pseudo-weights
#'   miss the domain totals in both directions. Each domain needs enough units on **each**
#'   side to fit its own model; those that do not are reported by name.
step_pseudoweight <- function(spec, reference, formula,
                              engine = c("logit", "tree", "forest", "boost"),
                              num_classes = NULL, by = NULL, crossfit = NULL,
                              crossfit_seed = NULL, id = NULL) {
  if (!inherits(spec, "weighting_spec"))
    stop("The first argument must be a weighting_spec.", call. = FALSE)
  if (!isTRUE(spec$nonprob))
    stop(paste0("step_pseudoweight() is for a NON-probability sample: build the recipe with ",
                "weighting_spec(..., nonprob = TRUE)."), call. = FALSE)
  engine <- match.arg(engine)
  id <- .wf_id(id)
  if (!is.null(by) && (!is.character(by) || length(by) != 1L || is.na(by)))
    stop("`by` must be NULL or a single column name naming the domain to fit within.",
         call. = FALSE)
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
         num_classes = num_classes, by = by,
         crossfit = crossfit, crossfit_seed = crossfit_seed),
    class = c("step_pseudoweight", "weighting_step"))
  .add_step(spec, step, id = id)
}

#' @export
# --- Pseudo-weighting by domain (PSW-BY) -----------------------------------
# One participation model per domain, fitted on that domain's units of BOTH
# samples and on nothing else. The reference is split by the same column, so the
# pseudo-weights of a domain sum to that domain's reference total rather than to
# the national one -- which is what makes a later domain-partitioned calibration
# start from a coherent input weight.
#
# It is also what makes the pooled fit self-calibrating WITHIN the domain: the
# score equations of the logistic force sum_i d_i x_i to match the reference total
# of x over that domain, for every x in `formula`.
.pseudoweight_by_domain <- function(step, data, w) {
  byvar <- step$by
  if (!byvar %in% names(data))
    stop(sprintf("Domain column '%s' not found in the non-probability sample.", byvar),
         call. = FALSE)
  ref <- step$reference
  if (!byvar %in% names(ref))
    stop(sprintf(paste0("Domain column '%s' not found in the `reference`. With `by`, the ",
                        "reference must carry the same domain column as the sample, because ",
                        "each domain gets its own participation model."), byvar), call. = FALSE)
  active <- .wf_active(w)
  dom  <- as.character(data[[byvar]])
  rdom <- as.character(ref[[byvar]])
  if (any(is.na(dom[active])))
    stop(sprintf("Domain column '%s' has missing values (NA) in %d active unit(s).",
                 byvar, sum(is.na(dom[active]))), call. = FALSE)
  if (anyNA(rdom))
    stop(sprintf("Domain column '%s' has missing values (NA) in the `reference`.", byvar),
         call. = FALSE)

  doms <- unique(dom[active])
  miss <- setdiff(doms, unique(rdom))
  if (length(miss))
    stop(sprintf(paste0("Domain(s) of '%s' present in the sample but absent from the ",
                        "`reference`: %s. A participation model needs both samples in the ",
                        "domain; there is nothing to compare those units against."),
                 byvar, paste(utils::head(miss, 10L), collapse = ", ")), call. = FALSE)

  # A domain has to support its own model: p coefficients need rows on BOTH sides,
  # and cross-fitting needs every fold to leave both classes behind.
  npar <- length(all.vars(step$formula)) + 1L
  Fd   <- if (is.null(step$crossfit)) 1L else as.integer(step$crossfit)
  need <- if (Fd > 1L) ceiling(Fd * npar / (Fd - 1)) else npar
  n_s  <- table(dom[active]); n_r <- table(rdom)
  bad  <- doms[vapply(doms, function(d)
    as.integer(n_s[d]) < need || as.integer(n_r[d]) < need, logical(1))]
  if (length(bad))
    stop(sprintf(paste0("With `by = \"%s\"` each domain fits its own participation model, so it ",
                        "needs at least %d unit(s) on EACH side (%d model coefficient(s)%s). ",
                        "Domain(s) below that: %s. Collapse them, simplify `formula`, or drop ",
                        "`by`."),
                 byvar, need, npar,
                 if (Fd > 1L) sprintf(", and with crossfit = %d each fold must leave that many behind", Fd) else "",
                 paste(vapply(bad, function(d) sprintf("%s (sample %d, reference %d)",
                                                       d, as.integer(n_s[d]), as.integer(n_r[d])),
                              character(1)), collapse = ", ")), call. = FALSE)

  new_w <- w; diags <- list(); pmin_all <- 1; pmax_all <- 0
  for (d in doms) {
    idx_d <- which(dom == d)
    step_d <- step
    step_d$by        <- NULL                    # avoid recursion
    step_d$reference <- .wf_ref_subset(ref, which(rdom == d))
    keep <- intersect(idx_d, which(active))
    res_d <- apply_step(step_d, data[idx_d, , drop = FALSE], w[idx_d])
    new_w[idx_d] <- res_d$weights
    dg <- res_d$diagnostics
    if (!is.null(dg) && nrow(dg) > 0L)
      diags[[length(diags) + 1L]] <- cbind(domain = d, dg, stringsAsFactors = FALSE)
    pm <- attr(dg, "p_min"); pM <- attr(dg, "p_max")
    if (!is.null(pm)) pmin_all <- min(pmin_all, pm)
    if (!is.null(pM)) pmax_all <- max(pmax_all, pM)
  }
  diag <- if (length(diags)) do.call(rbind, diags) else NULL
  if (!is.null(diag)) {
    rownames(diag) <- NULL
    attr(diag, "p_min") <- pmin_all
    attr(diag, "p_max") <- pmax_all
    attr(diag, "odds")  <- TRUE   # weight is (1 - p)/p, not 1/p
    attr(diag, "note")  <- sprintf(paste0("one participation model per domain of '%s' (%d ",
                                          "domains); each is fitted on its own domain in both ",
                                          "samples"), byvar, length(doms))
  }
  list(weights = new_w, diagnostics = diag)
}

apply_step.step_pseudoweight <- function(step, data, w) {
  if (!is.null(step$by)) return(.pseudoweight_by_domain(step, data, w))
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
                                 crossfit = step$crossfit, seed = step$crossfit_seed,
                                 raw_inverse = is.null(step$num_classes), odds = TRUE)
  # NP-01: symmetric clamp. .estimate_propensity only FLOORS p (it guards 1/p in the
  # nonresponse path). Here the pseudo-weight is the participation ODDS (1 - p)/p, so
  # the dangerous end is the mirror one: p -> 1 sends the pseudo-weight to 0 and the
  # unit silently adopts the "dropped" sentinel (a pure leaf in tree/forest gives
  # p == 1 exactly; glm can give 1 - eps). Cap p away from 1 as well.
  pi_all <- pmin(pmax(pi_all, 1e-6), 1 - 1e-6)
  pi_np  <- pi_all[seq_len(n_np)]

  # Pseudo-weight = participation ODDS (1 - p)/p. In the pooled fit (reference
  # weighted to the population N, non-prob units weight 1) the fitted p estimates
  # n(x)/(n(x)+N(x)), so (1 - p)/p = N(x)/n(x) inflates each unit to the population
  # and the weights sum to N IN EXPECTATION -- see the note at the top of this file;
  # the realised sum is an estimate. Using 1/p would add a spurious +1 per unit
  # (weights sum to N + n), mixing in the unweighted naive mean.
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

  # NP-06. sum(psw) estimates the population the reference estimates, and only
  # estimates it: with a correctly specified model the ratio still moves by a few per
  # cent between samples (sd 2.0% at n_ref = 500, 1.0% at 3000, in simulation), and how
  # much depends on the reference size, the participation rate and how strong the
  # selection is. So this is NOT a violated identity, and the threshold below cannot be
  # calibrated to separate sampling noise from bias -- it is set where only a gross
  # level error trips it, and a ratio inside it says nothing either way. Report the
  # ratio (it is in the diagnostics table) rather than reading the absence of a warning
  # as a pass.
  #
  # What makes the ratio worth watching anyway: a level error here is the one failure a
  # later calibration step hides completely -- calibrating to known totals re-imposes
  # the level and the pseudo-weights are never seen again -- and the one `num_classes`
  # cannot touch, because binning changes the dispersion of the factors within a class,
  # not their sum.
  N_ref     <- sum(rf$.w)
  sum_ratio <- if (is.finite(N_ref) && N_ref > 0) sum(psw) / N_ref else NA_real_
  if (!is.na(sum_ratio) && abs(sum_ratio - 1) > 0.2)
    warning(sprintf(paste0(
      "Pseudo-weights sum to %s, while the reference estimates a population of %s ",
      "(ratio %.2f). The sum is an unbiased ESTIMATOR of that population, not an ",
      "identity, so a few per cent apart is ordinary; a gap this size is not, and it ",
      "is a level error in every total this recipe produces. `num_classes` will not ",
      "fix it -- binning changes how dispersed the pseudo-weights are, not what they ",
      "sum to. Check the participation model first: a misspecified one moves this ",
      "ratio%s."),
      format(round(sum(psw)), big.mark = ","), format(round(N_ref), big.mark = ","),
      sum_ratio,
      if (identical(step$engine, "forest"))
        paste0(". With engine = \"forest\" there is a second cause specific to it: ranger ",
               "reads `case.weights` as bootstrap SAMPLING probabilities, not as counts, ",
               "so the fitted p is close to an unweighted proportion and the odds are off ",
               "by roughly the design weight (measured: 0.83 against 1.00 for engine = ",
               "\"tree\" on the same data). `tree` and `boost` pass the weights to rpart ",
               "and xgboost as analytic weights and are not affected")
      else ""),
      call. = FALSE)

  new_w <- w
  new_w[active] <- psw

  diag <- data.frame(
    quantity = c("non-prob units", "reference units", "min propensity",
                 "pseudo-weight sum", "reference population", "sum / reference",
                 "mean pseudo-weight"),
    value = c(n_np, nrow(rf), round(min(pi_np), 4), round(sum(psw)),
              round(N_ref), round(sum_ratio, 3), round(mean(psw), 2)),
    stringsAsFactors = FALSE)
  attr(diag, "sum_ratio") <- sum_ratio   # NP-06
  attr(diag, "p_min") <- min(pi_np)      # reuse the tiny-propensity alert
  attr(diag, "p_max") <- max(pi_np)      # NP-01 mirror: participation ~ 1 -> pseudo-weight ~ 0
  attr(diag, "odds")  <- TRUE            # weight is (1 - p)/p, not 1/p
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
      family = stats::binomial(), weights = .wf_model_wts(pooled$.w))))[2]), error = function(e) NA_real_))
  list(weights = new_w, diagnostics = diag)
}
