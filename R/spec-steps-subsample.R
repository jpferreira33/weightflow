# Step: second-phase subsampling (two-phase / double sampling).
# Records the phase-2 design so the recipe-aware bootstrap can add the phase-2
# variance component to the phase-1 resampling (two-phase coupling).

#' Second-phase subsampling (two-phase sampling)
#'
#' Undoes a second phase of sampling: when a subsample of the first-phase units
#' was drawn for a more expensive follow-up (measuring an outcome, a longer
#' questionnaire), the subsampled units must represent the whole first-phase
#' sample. Their weight is multiplied by the inverse of the phase-2 selection
#' probability, and the not-subsampled units leave the cascade (weight 0).
#'
#' The step also *records the phase-2 design* (the selection probability, the
#' phase-2 sampling unit, its stratification, and the selection scheme) so that
#' [bootstrap_weights()] can reproduce the two-phase variance
#' \eqn{V = V_1 + V_2}{V = V1 + V2}: the phase-1 sampling variance plus the
#' expected conditional variance of the phase-2 subsample. A single-phase
#' bootstrap would only capture \eqn{V_1}{V1} and undercover.
#'
#' The coupling is additive, not multiplicative: the per-unit resampling factor
#' has variance \eqn{(1-f_1)\pi_2 + (1-\pi_2)}{(1 - f1) * prob + (1 - prob)}, the
#' sum of the phase-1 component \eqn{(1-f_1)\pi_2}{(1 - f1) * prob} (seen through
#' the subsample) and the phase-2 conditional component
#' \eqn{1-\pi_2}{1 - prob}. A naive product of two factors adds a spurious
#' interaction term and is too wide. In practice the factor is drawn once per
#' phase-2 sampling unit from a strictly positive Gamma of that mean and
#' variance, so every replicate weight stays positive (a downstream
#' propensity/GLM step re-runs cleanly). See the package's two-phase methodology
#' notes.
#'
#' This first version covers a Poisson (independent) second phase whose sampling
#' unit is nested in the first phase (e.g. households subsampled from a
#' first-phase household sample). The phase-1 sampling fraction \eqn{f_1}{f1} is
#' taken from the `fpc` argument of [bootstrap_weights()] and defaults to 0
#' (negligible, the usual case in household surveys), which reduces the coupling
#' to a single independent per-unit factor of variance 1 -- a Gamma of variance 1,
#' i.e. an Exponential(1) (the Bayesian-bootstrap multiplier): valid and strictly
#' positive, but right-skewed, which is part of why replicate-to-replicate
#' variance estimates have heavier tails.
#'
#' @param spec a weighting_spec.
#' @param selected a 0/1 dummy column (1 = selected in phase 2) or any logical
#'   condition (unquoted) TRUE for the subsampled units. Units that are not
#'   selected leave the cascade (weight 0).
#' @param prob unquoted column with the phase-2 selection probability
#'   \eqn{\pi_2}{pi2} of the selected units. The weight is multiplied by
#'   1/prob. Must be in (0, 1] for every selected unit and constant within each
#'   phase-2 sampling unit.
#' @param psu character. The phase-2 sampling unit column (e.g. the household id
#'   at which the subsample was drawn). The two-phase resampling factor is
#'   generated at this level and shared by the members of the unit.
#' @param strata character. Phase-2 design strata (where `prob` is constant),
#'   optional.
#' @param design the phase-2 selection scheme: "poisson" (independent /
#'   Bernoulli selection, the default) or "srswor" (simple random sampling
#'   without replacement within a stratum). Only "poisson" is fully implemented
#'   in this version.
#' @param id optional string: a stable identifier for this step, shown in the
#'   recipe print-out and usable to select it in `collect_step_detail()`;
#'   defaults to a derived `"<class>_<k>"`.
#' @return The input `weighting_spec` with this step appended to its recipe. The
#'   step is recorded only; it is evaluated when `prep()` is called.
#' @seealso [bootstrap_weights()] for the two-phase variance; [step_select_within()]
#'   for within-cluster subsampling that is not a separate sampling phase.
#' @examples
#' # households subsampled for a follow-up module, selected with prob p2
#' df <- transform(sample_survey,
#'                 in_phase2 = as.integer(runif(nrow(sample_survey)) < 0.3),
#'                 p2 = 0.3)
#' weighting_spec(df, base_weights = pw) |>
#'   step_subsample(selected = in_phase2, prob = p2, psu = "household_id")
#' @family weighting steps
#' @export
step_subsample <- function(spec, selected, prob, psu, strata = NULL,
                           design = c("poisson", "srswor"), id = NULL) {
  design <- match.arg(design)
  if (missing(psu) || is.null(psu) || !is.character(psu) || length(psu) != 1L || !nzchar(psu))
    stop("`psu` (the phase-2 sampling unit column, e.g. a household id) is required ",
         "and must be a single column name.", call. = FALSE)
  if (!is.null(strata) && (!is.character(strata)))
    stop("`strata` must be NULL or a character vector of column names.", call. = FALSE)
  step <- structure(
    list(label    = "phase-2 subsample",
         selected = substitute(selected),
         prob     = substitute(prob),
         psu      = psu,
         strata   = strata,
         design   = design,
         env      = parent.frame()),
    class = c("step_subsample", "weighting_step")
  )
  .add_step(spec, step, id = id)
}

#' @export
apply_step.step_subsample <- function(step, data, w) {
  ecenv  <- if (is.null(step$env)) baseenv() else step$env
  active <- .wf_active(w)
  sel    <- .eval_cond(step$selected, data, step$env, active = active)
  p2     <- .eval_num(step$prob, "prob", data, ecenv)
  use    <- active & sel
  if (!any(use))
    stop("`step_subsample`: no active unit is selected in phase 2 (`selected` is ",
         "never TRUE among the units still in scope).", call. = FALSE)
  if (any(is.na(p2[use])) || any(p2[use] <= 0) || any(p2[use] > 1))
    stop("`prob` (phase-2 selection probability) must be in (0, 1] for every ",
         "selected unit.", call. = FALSE)
  if (!step$psu %in% names(data))
    stop(sprintf("`psu` column '%s' not found in the data.", step$psu), call. = FALSE)
  # prob must be constant within the phase-2 sampling unit (one selection per PSU).
  psu_id <- as.character(data[[step$psu]])
  if (anyNA(psu_id[use]))
    stop(sprintf("`psu` column '%s' has missing values among the selected units.",
                 step$psu), call. = FALSE)
  nuniq <- tapply(p2[use], psu_id[use], function(z) length(unique(round(z, 12))))
  if (any(nuniq > 1L))
    stop(sprintf(paste0("`prob` is not constant within %d phase-2 sampling unit(s) of '%s'. ",
                        "A phase-2 selection draws the whole unit once, so its probability ",
                        "must be a single value per unit."),
                 sum(nuniq > 1L), step$psu), call. = FALSE)

  new_w              <- w
  new_w[use]         <- w[use] * (1 / p2[use])   # expand the subsample
  new_w[active & !sel] <- 0                       # not-subsampled units leave the cascade

  diag <- data.frame(
    n_selected = sum(use),
    n_dropped  = sum(active & !sel),
    psu        = step$psu,
    n_psu2     = length(unique(psu_id[use])),
    design     = step$design,
    min_prob   = round(min(p2[use]), 4),
    max_prob   = round(max(p2[use]), 4),
    stringsAsFactors = FALSE
  )
  list(weights = new_w, diagnostics = diag)
}

# Locate a step_subsample in a recipe (the first one), returning it or NULL.
# Used by bootstrap_weights() to switch to the two-phase resampling factor.
.find_subsample_step <- function(steps) {
  for (s in steps) if (inherits(s, "step_subsample")) return(s)
  NULL
}

# Two-phase resampling setup, computed once from the phase-2 design recorded by
# step_subsample(). `fvec` is the per-row phase-1 sampling fraction f1 (0 by
# default). Returns, per selected phase-2 sampling unit (PSU), the target
# variance of the resampling factor,
#   d = (1 - f1) * pi2 + (1 - pi2) = 1 - f1 * pi2   (in (0, 1]),
# the sum of the phase-1 component (1 - f1) * pi2 (seen through the subsample) and
# the phase-2 conditional component (1 - pi2). Two independent additive factors
# lambda1 + lambda2 - 1 have exactly this variance, so a single per-PSU factor of
# variance d is equivalent for the estimator variance; drawing it from a strictly
# positive smooth distribution (see .twophase_fac) keeps every replicate weight
# positive. See METODO_dos_fases.
.twophase_setup <- function(sub, data, fvec) {
  n   <- nrow(data)
  sel <- .eval_cond(sub$selected, data, sub$env)
  p2  <- .eval_num(sub$prob, "prob", data, sub$env)
  sel[is.na(sel)] <- FALSE
  psu <- as.character(data[[sub$psu]])
  use <- sel & is.finite(p2) & p2 > 0 & p2 <= 1 & !is.na(psu)
  if (!any(use))
    stop("bootstrap_weights(): step_subsample selects no usable phase-2 unit ",
         "(check `selected` and `prob`).", call. = FALSE)
  selpsu <- unique(psu[use])
  idx    <- match(psu, selpsu)                       # unit -> selected-PSU index (NA otherwise)
  p2_psu <- as.numeric(tapply(p2[use],   psu[use], function(z) z[1])[selpsu])
  # f1 (first-phase fraction) must be constant within a phase-2 sampling unit, the
  # same way `prob` is (checked in apply_step). A column `fpc` that varied inside a
  # PSU would otherwise be read from its first row silently.
  f1_nu  <- tapply(fvec[use], psu[use], function(z) length(unique(round(z, 12))))
  if (any(f1_nu > 1L))
    stop("bootstrap_weights(): `fpc` (first-phase fraction f1) is not constant within ",
         sum(f1_nu > 1L), " phase-2 sampling unit(s) of '", sub$psu,
         "'; it must be a single value per unit.", call. = FALSE)
  f1_psu <- as.numeric(tapply(fvec[use], psu[use], function(z) z[1])[selpsu])
  f1_psu[is.na(f1_psu)] <- 0
  d      <- (1 - f1_psu) * p2_psu + (1 - p2_psu)     # = 1 - f1 * pi2, in (0, 1]
  list(n = n, use = use, unit_psu_idx = idx, selpsu = selpsu,
       d = d, design = sub$design)
}

# One replicate's two-phase factor vector (Poisson second phase): a single
# strictly-positive per-PSU multiplier of mean 1 and variance d, drawn from a
# Gamma(shape = 1/d, scale = d). This is equivalent in variance to the additive
# coupling lambda1 + lambda2 - 1 but, being positive and smooth, never yields a
# negative or zero replicate weight -- so a downstream propensity / GLM step
# re-runs cleanly on every replicate -- and gives slightly better coverage than a
# two-point factor. Non-selected units get factor 1 (they leave the cascade at
# step_subsample anyway). Units with d ~ 0 (no sampling variance) keep factor 1.
.twophase_fac <- function(setup) {
  v    <- setup$d
  npsu <- length(setup$selpsu)
  lam  <- rep(1, npsu)
  pos  <- v > 1e-12
  if (any(pos))
    lam[pos] <- stats::rgamma(sum(pos), shape = 1 / v[pos], scale = v[pos])
  fac  <- rep(1, setup$n)
  su   <- which(setup$use)
  fac[su] <- lam[setup$unit_psu_idx[su]]
  fac
}
