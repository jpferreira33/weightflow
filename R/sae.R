# Bridge to small-area estimation (SAE): export, per domain, the direct estimate,
# its design-based standard error (from the replicate weights) and the effective
# sample size -- the inputs a Fay-Herriot area-level model consumes. weightflow
# does NOT do SAE; this hands the design-based ingredients to emdi / sae / hbsae.

#' Direct estimates and design SEs per domain, ready for small-area estimation
#'
#' Small-area estimation (SAE) area-level models (Fay-Herriot) need, for each
#' domain, the *direct* estimate, its *design-based* variance and the effective
#' sample size. This function computes exactly those from a recipe-aware
#' replicate object, so the design-based ingredients flow into `emdi`, `sae` or
#' `hbsae` without leaving the weightflow variance machinery. It does not fit any
#' SAE model itself.
#'
#' The domain standard error is the recipe-aware replicate SE (it re-runs the
#' whole recipe per replicate), so it already reflects nonresponse and
#' calibration, not just the final weights.
#'
#' @param object a `weightflow_boot` or `weightflow_jack` object (from
#'   [bootstrap_weights()] / [jackknife_weights()]).
#' @param variable name of the study variable.
#' @param by name(s) of the domain column(s); several are crossed.
#' @param type `"mean"` (default) or `"total"`.
#' @param level confidence level for the interval.
#' @param cv_breaks two increasing CV cut-points for the publishability rating
#'   (default `c(0.165, 0.33)`, common in official statistics): a CV below the
#'   first is `"publishable"`, between the two `"review"`, above the second
#'   `"not publishable"`.
#' @return A data frame with one row per domain: `domain`, `n` (active units),
#'   `n_eff` (Kish effective sample size), `estimate`, `se`, `cv`, `ci_lower`,
#'   `ci_upper` and `rating`. Pass `estimate` and `se^2` (the sampling variance)
#'   to a Fay-Herriot model.
#'
#'   Note for very small domains: the domain estimates share one bootstrap, and a
#'   replicate in which any domain has no active unit is dropped for all domains
#'   (a conservative choice). With many tiny domains this wastes replicates; use
#'   more `replicates` in the bootstrap, or estimate sparse domains in a separate
#'   call.
#' @seealso [domain_summary()], [bootstrap_estimate()], [design_effect()]
#' @examples
#' spec <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_calibrate(method = "raking",
#'                  margins = list(region = c(table(population$region))))
#' boot <- bootstrap_weights(spec, replicates = 50, strata = "region",
#'                           psu = "psu", seed = 1)
#' as_sae_input(boot, "responded", by = "region")
#' @export
#' @family cascade audit
as_sae_input <- function(object, variable, by, type = c("mean", "total"),
                         level = 0.95, cv_breaks = c(0.165, 0.33)) {
  if (!inherits(object, c("weightflow_boot", "weightflow_jack")))
    stop("`object` must be a weightflow_boot or weightflow_jack object ",
         "(from bootstrap_weights() / jackknife_weights()).", call. = FALSE)
  type <- match.arg(type)
  variable <- .wf_var(variable, object)
  data <- object$data
  if (!is.character(by) || length(by) < 1L || !all(by %in% names(data)))
    stop("`by` must name one or more domain columns in the data.", call. = FALSE)
  if (!is.numeric(cv_breaks) || length(cv_breaks) != 2L || any(!is.finite(cv_breaks)) ||
      cv_breaks[1] >= cv_breaks[2] || any(cv_breaks < 0))
    stop("`cv_breaks` must be two increasing non-negative CV cut-points.", call. = FALSE)

  dom  <- do.call(paste, c(lapply(by, function(b) as.character(data[[b]])), sep = ":"))
  w0   <- object$weights
  x    <- data[[variable]]
  keep <- is.finite(w0) & w0 != 0 & !is.na(x)
  labs <- sort(unique(dom[keep]))
  if (!length(labs)) stop("No active units with an observed `variable` in any domain.", call. = FALSE)

  stat <- function(w, d) {
    xx <- d[[variable]]
    vapply(labs, function(L) {
      ok <- is.finite(w) & w != 0 & !is.na(xx) & dom == L
      s  <- sum(w[ok]); if (s == 0) return(NA_real_)
      if (type == "mean") sum(w[ok] * xx[ok]) / s else sum(w[ok] * xx[ok])
    }, numeric(1))
  }
  est <- if (inherits(object, "weightflow_boot"))
    bootstrap_estimate(object, stat, level = level)
  else jackknife_estimate(object, stat, level = level)

  # per-domain n and Kish effective n from the POINT weights
  base <- do.call(rbind, lapply(labs, function(L) {
    ok <- keep & dom == L; ww <- w0[ok]
    data.frame(domain = L, n = sum(ok),
               n_eff = if (sum(ww^2) > 0) sum(ww)^2 / sum(ww^2) else 0,
               stringsAsFactors = FALSE)
  }))
  out <- cbind(base, est[c("estimate", "se", "ci_lower", "ci_upper")])
  out$cv <- ifelse(out$estimate != 0 & is.finite(out$estimate), out$se / abs(out$estimate), NA_real_)
  out$rating <- cut(out$cv, breaks = c(-Inf, cv_breaks, Inf),
                    labels = c("publishable", "review", "not publishable"),
                    right = TRUE)
  out <- out[c("domain", "n", "n_eff", "estimate", "se", "cv",
               "ci_lower", "ci_upper", "rating")]
  rownames(out) <- NULL
  out
}
