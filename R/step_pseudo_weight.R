# ---------------------------------------------------------------------------
# step_pseudo_weight(): inverse-propensity pseudo-weights for a nonprobability
# sample, using a probability reference sample to anchor to the population.
#
# The nonprobability sample (the data of the spec) is stacked with a reference
# probability sample; a participation-propensity model P(in NPS | x) is fitted
# on the pooled data; and each NPS unit receives a pseudo-weight equal to the
# inverse of its estimated propensity, scaled so the reference (which carries
# design weights) represents the population. Reuses the package's propensity
# engines (logit / tree / forest / boost) and optional cross-fitting.
#
# `pooling` controls how the two samples' weights enter the propensity model:
#   "unweighted_nps" : NPS units weight 1; reference units their design weight
#                      (Valliant-Dever style). The default.
#   "weighted"       : both samples enter with their weights as model case
#                      weights (NPS unit weight 1, reference design weight).
#   "pseudo_lik"     : Chen-Li-Wu pseudo-likelihood; reference design weights
#                      enter the estimating equations (handled via case weights).
# ---------------------------------------------------------------------------

#' Pseudo-weights for a nonprobability sample (inverse propensity)
#'
#' Adds a step that derives inverse-propensity pseudo-weights for a
#' nonprobability sample, using a probability **reference** sample to anchor the
#' estimates to the population. It is meant as the first step of a recipe built
#' on the nonprobability sample (which has no design weights of its own); the
#' resulting pseudo-weights can then be calibrated, trimmed, etc. like any other
#' weights.
#'
#' The nonprobability sample and the reference are stacked, a participation
#' propensity \eqn{P(\text{in NPS} \mid x)} is fitted on the pooled data with the
#' chosen engine, and each nonprobability unit gets a pseudo-weight proportional
#' to the inverse of its estimated propensity. The reference design weights are
#' always used so that the propensity targets the population rather than the
#' (unweighted) reference.
#'
#' @param spec a weighting_spec built on the nonprobability sample.
#' @param reference a data frame: the probability reference sample, with the
#'   covariates in `formula` and a design-weight column.
#' @param reference_weights name of the design-weight column in `reference`.
#' @param formula one-sided formula of the common covariates, e.g.
#'   `~ region + sex + age`.
#' @param pooling how the samples' weights enter the propensity model:
#'   "unweighted_nps" (default), "weighted", or "pseudo_lik". See Details.
#' @param engine propensity engine: "logit", "tree", "forest" or "boost".
#' @param num_classes optional integer; if given, smooth the pseudo-weights into
#'   that many propensity classes instead of using 1/p per unit.
#' @param crossfit optional integer K >= 2 for K-fold cross-fitting of the
#'   propensity (recommended with flexible engines).
#' @param crossfit_seed optional seed for the cross-fitting folds.
#' @return The spec with the step appended (evaluated later by `prep()`).
#' @export
step_pseudo_weight <- function(spec, reference, reference_weights,
                               formula,
                               pooling = c("unweighted_nps", "weighted", "pseudo_lik"),
                               engine = c("logit", "tree", "forest", "boost"),
                               num_classes = NULL,
                               crossfit = NULL, crossfit_seed = NULL) {
  pooling <- match.arg(pooling)
  engine  <- match.arg(engine)
  if (missing(reference) || !is.data.frame(reference))
    stop("`reference` must be a data frame (the probability reference sample).")
  if (missing(reference_weights) || !is.character(reference_weights) ||
      is.null(reference[[reference_weights]]))
    stop("`reference_weights` must name a design-weight column in `reference`.")
  if (missing(formula) || !inherits(formula, "formula"))
    stop("`formula` must be a one-sided formula of the common covariates.")
  if (!is.null(crossfit) && (!is.numeric(crossfit) || crossfit < 2))
    stop("`crossfit` must be NULL or an integer >= 2 (number of folds).")

  mode  <- if (is.null(num_classes)) "1/p per unit" else sprintf("%d classes", num_classes)
  label <- sprintf("pseudo-weight (propensity: %s, %s, pooling: %s)",
                   engine, mode, pooling)
  step <- structure(
    list(
      label             = label,
      reference         = reference,
      reference_weights = reference_weights,
      formula           = formula,
      pooling           = pooling,
      engine            = engine,
      num_classes       = num_classes,
      crossfit          = if (is.null(crossfit)) NULL else as.integer(crossfit),
      crossfit_seed     = crossfit_seed
    ),
    class = c("step_pseudo_weight", "weighting_step")
  )
  .add_step(spec, step)
}

#' @export
apply_step.step_pseudo_weight <- function(step, data, w) {
  ref      <- step$reference
  rw       <- ref[[step$reference_weights]]
  vars     <- all.vars(step$formula)
  miss_np  <- setdiff(vars, names(data))
  miss_rf  <- setdiff(vars, names(ref))
  if (length(miss_np)) stop("nonprobability sample lacks covariates: ",
                            paste(miss_np, collapse = ", "))
  if (length(miss_rf)) stop("reference sample lacks covariates: ",
                            paste(miss_rf, collapse = ", "))

  n_np <- nrow(data)
  n_rf <- nrow(ref)

  # pooled data: NPS (.y = 1) stacked over reference (.y = 0), with a .y column
  # and the covariates. .estimate_propensity expects the predictors formula and
  # a data frame carrying .y; it builds .y ~ . internally.
  pooled <- rbind(
    data.frame(data[vars], stringsAsFactors = FALSE),
    data.frame(ref[vars],  stringsAsFactors = FALSE)
  )
  pooled$.y <- c(rep(1L, n_np), rep(0L, n_rf))

  # case weights for the model, per pooling scheme
  cw <- switch(step$pooling,
    "unweighted_nps" = c(rep(1, n_np), rw),
    "weighted"       = c(rep(1, n_np), rw),
    "pseudo_lik"     = c(rep(1, n_np), rw)
  )

  # estimate participation propensity P(in NPS | x) on the pooled data,
  # reusing the package engine + optional cross-fitting. Pass the PREDICTORS
  # formula (the helper adds .y ~ . itself). Predictions come back for all
  # pooled rows; we keep the NPS rows (the first n_np).
  phat_all <- .estimate_propensity(step$engine, step$formula, pooled, cw,
                                   crossfit = step$crossfit,
                                   cluster_id = NULL, seed = step$crossfit_seed)
  phat_np <- phat_all[seq_len(n_np)]
  phat_np <- pmin(pmax(phat_np, 1e-6), 1 - 1e-6)

  # pseudo-weight = (1 - p)/p scaled to the population, or 1/p depending on the
  # parameterization. Here we use the odds form d_i = (1 - phat)/phat, which is
  # the Wang-Valliant-Li (2021) reference-odds pseudo-weight, then rescale so
  # the pseudo-weights sum to the population size implied by the reference.
  pop_size <- sum(rw)
  raw      <- (1 - phat_np) / phat_np

  if (is.null(step$num_classes)) {
    pw_np <- raw
  } else {
    # smooth into propensity classes: constant pseudo-weight within each class
    br  <- stats::quantile(phat_np, probs = seq(0, 1, length.out = step$num_classes + 1),
                           na.rm = TRUE, type = 8)
    br[1] <- -Inf; br[length(br)] <- Inf
    cls <- cut(phat_np, breaks = unique(br), include.lowest = TRUE)
    pw_np <- stats::ave(raw, cls, FUN = function(z) mean(z))
  }

  # rescale so the pseudo-weights represent the population total
  pw_np <- pw_np * (pop_size / sum(pw_np))

  diagnostics <- data.frame(
    n_nps          = n_np,
    n_reference    = n_rf,
    pop_size       = pop_size,
    mean_propensity = mean(phat_np),
    min_pw          = min(pw_np),
    max_pw          = max(pw_np),
    sum_pw          = sum(pw_np),
    stringsAsFactors = FALSE
  )

  list(weights = pw_np, diagnostics = diagnostics)
}
