# step_nr_sensitivity(): proxy pattern-mixture sensitivity to NONIGNORABLE
# nonresponse or selection (Andridge and Little 2011). A no-op on the weights: it
# does not adjust anything, it quantifies how far the weighted mean of a study
# variable could move if response/participation depended on the outcome itself
# beyond the observed auxiliaries, producing an ignorance interval to read next to
# the sampling confidence interval.
#
# Method. Reduce the auxiliaries to a single proxy X = the (weighted) respondent
# regression prediction of Y. With rho = respondent correlation of Y and X, a single
# sensitivity parameter phi in [0, 1] indexes the mechanism: phi = 0 is ignorable
# given the proxy (MAR), phi = 1 is missingness depending only on Y. Under bivariate
# normality with selection on V = (1 - phi) X + phi Y, the nonrespondent Y mean shifts
# proportionally to Cov(Y, V) / Cov(X, V), giving the slope multiplier
#   m(phi) = ((1 - phi) rho + phi) / ((1 - phi) + phi rho),   m(0) = rho, m(1) = 1/rho,
# and the adjusted overall mean
#   mu(phi) = ybar_r + (1 - pi) (s_yr / s_xr) m(phi) (xbar_nr - xbar_r),
# with pi the (weighted) respondent fraction. The same formula covers a
# non-probability sample: "respondents" are the participants, "nonrespondents" the
# reference units whose outcome is unobserved.

#' Sensitivity of a mean to nonignorable nonresponse or selection
#'
#' A diagnostic step (it does not change any weight) that gauges how much the
#' weighted mean of a study variable could move if response, or participation in a
#' non-probability sample, depended on the outcome itself beyond the observed
#' auxiliaries. It implements the proxy pattern-mixture model of Andridge and Little
#' (2011): the auxiliaries are reduced to a single proxy (the respondent regression
#' prediction of `y`), and a single sensitivity parameter `phi` in `[0, 1]` moves the
#' mechanism from ignorable given the proxy (`phi = 0`, MAR) to depending only on the
#' outcome (`phi = 1`). Evaluated over a grid of `phi`, the adjusted means form an
#' *ignorance interval* to read alongside the sampling confidence interval; see
#' [nr_sensitivity()] and the report block.
#'
#' The proxy correlation `rho` (the multiple correlation of `y` on the auxiliaries
#' among respondents) sets how informative the auxiliaries are: a weak proxy widens
#' the ignorance interval (at `phi = 1` the slope is `1/rho`). The step reads the
#' base design weights, so place it anywhere in the recipe; it needs the
#' nonrespondents still present (a study variable that is `NA` for them, or an
#' explicit `respondent` indicator).
#'
#' @param spec a `weighting_spec`.
#' @param y the study variable (bare column name), observed for respondents and
#'   `NA` for nonrespondents.
#' @param formula one-sided formula of the auxiliaries for the proxy, observed for
#'   all units, e.g. `~ region + sex + age`.
#' @param respondent optional response/participation indicator (bare column or
#'   condition). Defaults to `!is.na(y)`.
#' @param eligible optional in-scope indicator (bare column or condition), the
#'   mirror of the argument in [step_nonresponse()]. Out-of-scope (ineligible)
#'   units are neither respondents nor nonrespondents and must be excluded, or they
#'   would be counted as nonrespondents and pull the estimate toward their proxy
#'   mean. Give it in any household survey that has ineligible units. Default `NULL`
#'   treats every active unit as in scope.
#' @param phi the sensitivity grid, values in `[0, 1]`; `0` (MAR) is always added.
#'   Little et al. (2020) suggest `0.5` as a central value; above `0.5` the implied
#'   mechanism is often unrealistically strong.
#' @param id optional stable step id.
#' @return the input `weighting_spec` with this diagnostic step appended.
#' @references
#' Andridge, R. R. and Little, R. J. A. (2011). Proxy pattern-mixture analysis for
#' survey nonresponse. Journal of Official Statistics 27(2), 153-180.
#' @seealso [nr_sensitivity()], [step_assert()]
#' @export
#' @family weighting steps
step_nr_sensitivity <- function(spec, y, formula, respondent = NULL, eligible = NULL,
                                phi = c(0, 0.25, 0.5, 0.75, 1), id = NULL) {
  if (!inherits(spec, "weighting_spec"))
    stop("The first argument must be a weighting_spec.", call. = FALSE)
  if (missing(y)) stop("`y` (the study variable) is required.", call. = FALSE)
  if (missing(formula) || !inherits(formula, "formula"))
    stop("`formula` must be a one-sided formula of the auxiliaries, e.g. ~ sex + age.",
         call. = FALSE)
  if (!is.numeric(phi) || !length(phi) || any(!is.finite(phi)) || any(phi < 0) || any(phi > 1))
    stop("`phi` must be values in [0, 1].", call. = FALSE)
  step <- structure(
    list(label = "nonresponse sensitivity (proxy pattern-mixture)",
         y = substitute(y), respondent = substitute(respondent),
         eligible = substitute(eligible), env = parent.frame(), formula = formula,
         phi = sort(unique(c(0, phi)))),          # phi = 0 (MAR) always anchored
    class = c("step_nr_sensitivity", "weighting_step"))
  .add_step(spec, step, id = .wf_id(id))
}

#' @export
apply_step.step_nr_sensitivity <- function(step, data, w) {
  wb <- attr(data, "weightflow_base_w"); if (is.null(wb)) wb <- w
  active <- .wf_active(wb)
  y <- eval(step$y, envir = data, enclos = step$env %||% baseenv())
  if (!is.numeric(y) || length(y) != nrow(data))
    stop("`y` must be a numeric column of the data (NA for nonrespondents).", call. = FALSE)
  resp <- if (is.null(step$respondent)) !is.na(y)
          else as.logical(.eval_cond(step$respondent, data, step$env, active = active))
  # In-scope filter: ineligible (out-of-scope) units are neither respondents nor
  # nonrespondents. Without this they would be counted as nonrespondents (their y is
  # NA) and bias the analysis toward their proxy mean. Default: everyone in scope.
  elig <- if (is.null(step$eligible)) rep(TRUE, nrow(data))
          else as.logical(.eval_cond(step$eligible, data, step$env, active = active))
  elig[is.na(elig)] <- FALSE

  # Auxiliaries must be genuine data columns (an object living in the environment
  # would slip past the NA check and later misalign the design matrix).
  av <- all.vars(step$formula)
  ext <- setdiff(av, names(data))
  if (length(ext))
    stop(sprintf(paste0("Proxy auxiliary(ies) %s are not columns of the data. The formula ",
                        "must name columns observed for the respondents and nonrespondents."),
                 paste(ext, collapse = ", ")), call. = FALSE)

  R  <- which(active & elig & resp & !is.na(y))
  NR <- which(active & elig & !resp)
  if (length(NR) < 1L || length(R) < 5L) {
    diag <- data.frame(phi = numeric(0), mu = numeric(0))
    attr(diag, "nr_sensitivity") <- list(ok = FALSE)
    return(list(weights = w, diagnostics = diag))          # no-op, nothing to assess
  }

  # Work on the units that enter the analysis (respondents + nonrespondents). The
  # proxy auxiliaries must be observed for THESE units (other rows, e.g. ineligible
  # ones dropped earlier, may carry NA auxiliaries and are irrelevant here).
  used <- c(R, NR)
  isR  <- rep(c(TRUE, FALSE), c(length(R), length(NR)))
  amiss <- av[vapply(av, function(v) anyNA(data[[v]][used]), logical(1))]
  if (length(amiss))
    stop(sprintf(paste0("Proxy auxiliary(ies) %s have missing values among the respondents ",
                        "and nonrespondents; the proxy must be observed for both. Impute or ",
                        "drop them, or restrict `respondent` to units with the auxiliaries."),
                 paste(amiss, collapse = ", ")), call. = FALSE)

  # proxy = weighted respondent regression prediction of y (lm.wfit avoids the NSE
  # weight lookup); build the design on the used units so NA elsewhere is irrelevant.
  du  <- data[used, , drop = FALSE]
  yU  <- y[used]; wU <- wb[used]
  mm  <- stats::model.matrix(step$formula, du)
  if (nrow(mm) != length(used))
    stop("The proxy design matrix dropped rows with missing auxiliaries.", call. = FALSE)
  cf  <- stats::lm.wfit(mm[isR, , drop = FALSE], yU[isR], wU[isR])$coefficients
  cf[!is.finite(cf)] <- 0                       # a collinear column contributes nothing
  proxy <- as.numeric(mm %*% cf)

  cw    <- stats::cov.wt(cbind(y = yU[isR], x = proxy[isR]), wt = wU[isR], cor = TRUE)
  ybar1 <- unname(cw$center["y"]); xbar1 <- unname(cw$center["x"])
  s_y1  <- sqrt(cw$cov["y", "y"]); s_x1 <- sqrt(cw$cov["x", "x"])
  rho   <- cw$cor["y", "x"]
  xbar0 <- stats::weighted.mean(proxy[!isR], wU[!isR])
  pi_r  <- sum(wU[isR]) / (sum(wU[isR]) + sum(wU[!isR]))
  if (!is.finite(s_x1) || s_x1 <= 0 || !is.finite(s_y1)) {
    diag <- data.frame(phi = numeric(0), mu = numeric(0))
    attr(diag, "nr_sensitivity") <- list(ok = FALSE)
    return(list(weights = w, diagnostics = diag))          # degenerate proxy; cannot assess
  }

  # a near-zero proxy correlation makes 1/rho (phi -> 1) explode; clamp for numerics
  # and flag, because it means the auxiliaries barely predict y (wide ignorance).
  weak <- is.na(rho) || abs(rho) < 0.05
  rho_e <- if (is.na(rho)) 0.05 else min(max(abs(rho), 0.05), 0.999)
  if (weak)
    warning(sprintf(paste0("The proxy is weak (respondent correlation of y and the ",
                           "auxiliaries = %.3f); the ignorance interval is wide and driven ",
                           "by the near-1/rho extreme. Add auxiliaries more predictive of y."),
                    if (is.na(rho)) 0 else rho), call. = FALSE)

  m   <- function(p) ((1 - p) * rho_e + p) / ((1 - p) + p * rho_e)
  mu  <- ybar1 + (1 - pi_r) * (s_y1 / s_x1) * vapply(step$phi, m, numeric(1)) * (xbar0 - xbar1)

  diag <- data.frame(phi = step$phi, mu = mu, stringsAsFactors = FALSE)
  attr(diag, "nr_sensitivity") <- list(
    ok = TRUE, rho = rho, pi = pi_r, y_var = deparse(step$y),
    ybar_r = ybar1,                             # respondent (weighted) mean of y
    mu_mar = mu[step$phi == 0],                 # phi = 0 (MAR / regression adjustment)
    ignorance_lo = min(mu), ignorance_hi = max(mu),
    n_resp = length(R), n_nonresp = length(NR))
  list(weights = w, diagnostics = diag)          # NO-OP on the weights
}

#' Read the nonresponse-sensitivity analysis from a prepped recipe
#'
#' Returns the proxy pattern-mixture ignorance analysis stored by
#' [step_nr_sensitivity()]: the adjusted mean of the study variable at each `phi`,
#' with the ignorance interval and the proxy strength.
#'
#' @param object a prepped `weighting_spec` containing a [step_nr_sensitivity()].
#' @param step optional step id to select among several sensitivity steps (for
#'   example one per study variable). With one step it can be left `NULL`.
#' @return a list (class `weightflow_nr_sensitivity`) with `table` (`phi`, `mu`),
#'   `rho`, `ybar_r`, `ignorance` (the min-max interval over `phi`), `mu_mar` (the
#'   `phi = 0` estimate) and the respondent/nonrespondent counts.
#' @seealso [step_nr_sensitivity()]
#' @export
#' @family diagnostics
nr_sensitivity <- function(object, step = NULL) {
  if (!inherits(object, "prepped_weighting_spec"))
    stop("`object` must be a prepped weighting_spec (the output of prep()).", call. = FALSE)
  done <- Filter(function(s) isTRUE(attr(s$diagnostics, "nr_sensitivity")$ok), object$steps)
  if (!length(done))
    stop("No completed step_nr_sensitivity() found in the recipe.", call. = FALSE)
  ids <- vapply(done, function(s) s$id %||% "", character(1))
  if (!is.null(step)) {
    done <- done[ids == step]
    if (!length(done))
      stop(sprintf("No sensitivity step with id '%s'. Available: %s.",
                   step, paste(ids, collapse = ", ")), call. = FALSE)
  } else if (length(done) > 1L) {
    message(sprintf("The recipe has several sensitivity steps (%s); returning the first. Pass `step =` to choose.",
                    paste(ids, collapse = ", ")))
  }
  hit <- done[[1L]]
  a <- attr(hit$diagnostics, "nr_sensitivity")
  structure(list(
    table = hit$diagnostics[, c("phi", "mu")],
    rho = a$rho, y_var = a$y_var, ybar_r = a$ybar_r, mu_mar = a$mu_mar,
    ignorance = c(a$ignorance_lo, a$ignorance_hi),
    n_resp = a$n_resp, n_nonresp = a$n_nonresp),
    class = "weightflow_nr_sensitivity")
}

#' @export
print.weightflow_nr_sensitivity <- function(x, ...) {
  cat(sprintf("Nonresponse sensitivity (proxy pattern-mixture) for %s\n", x$y_var))
  cat(sprintf("  proxy strength rho = %.3f   respondents %d / nonrespondents %d\n",
              x$rho, x$n_resp, x$n_nonresp))
  cat(sprintf("  MAR estimate (phi = 0): %.4g\n", x$mu_mar))
  cat(sprintf("  ignorance interval over phi: [%.4g, %.4g]\n",
              x$ignorance[1], x$ignorance[2]))
  print(x$table, row.names = FALSE)
  invisible(x)
}
