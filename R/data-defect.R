# Data-defect diagnostics for a non-probability sample (Meng 2018). The error of
# a non-probability sample mean is governed by the correlation between the outcome
# and the participation indicator (the data-defect correlation, ddc), not by the
# sample size, so a large sample can carry a small EFFECTIVE size. The ddc on the
# target variable is not observable from the sample, so we report the mapping from
# a grid of plausible residual ddc values to the effective size (an ignorance
# range), together with the measurable selection strength on the covariates.

#' Data-defect diagnostics for a non-probability sample
#'
#' For a non-probability sample, Meng (2018) decomposes the error of the sample
#' mean into the data-defect correlation (`rho`, the population correlation between
#' the target variable and the participation indicator), the sampling fraction and
#' the problem difficulty. The effective sample size a probability sample would need
#' to match the same mean-squared error is
#' \deqn{n_{\mathrm{eff}} = \frac{f/(1-f)}{\rho^2}, \qquad f = n/N,}
#' which does not depend on the outcome except through `rho`. Because `rho` on the
#' target variable is not observable from the sample alone, `data_defect()` returns
#' the effective size across a grid of plausible residual `rho` (read it as an
#' ignorance range, not a single number), plus the measurable selection strength on
#' the covariates used for pseudo-weighting (the largest correlation between an
#' auxiliary and participation, which pseudo-weighting neutralises).
#'
#' @param object a prepped non-probability `weighting_spec` (from [prep()], built
#'   with `weighting_spec(..., nonprob = TRUE)`).
#' @param ddc_grid the residual data-defect correlations to tabulate. Positive
#'   values; only their magnitude matters.
#' @return a list (class `weightflow_data_defect`) with the sample size `n`, the
#'   estimated population size `N` (the sum of the final weights), the fraction `f`,
#'   the sensitivity `grid` (`ddc`, `n_eff`), and `aux`, a data frame of the
#'   covariate-participation correlations (or `NULL` when the recipe has no
#'   pseudo-weighting step).
#' @references
#' Meng, X.-L. (2018). Statistical paradises and paradoxes in big data (I).
#' Annals of Applied Statistics 12(2), 685-726.
#' @seealso [step_pseudoweight()], [report_weighting()]
#' @export
#' @family non-probability tools
data_defect <- function(object, ddc_grid = c(0.001, 0.005, 0.01, 0.05, 0.10)) {
  if (!inherits(object, "prepped_weighting_spec"))
    stop("`object` must be a prepped weighting_spec (the output of prep()).", call. = FALSE)
  if (!isTRUE(object$nonprob))
    stop(paste0("data_defect() is for a non-probability sample. Build the recipe with ",
                "weighting_spec(..., nonprob = TRUE)."), call. = FALSE)
  if (!is.numeric(ddc_grid) || !length(ddc_grid) || any(!is.finite(ddc_grid)) ||
      any(ddc_grid <= 0) || any(ddc_grid >= 1))
    stop("`ddc_grid` must be positive correlations in (0, 1).", call. = FALSE)

  w   <- object$final_weight
  act <- .wf_active(w)
  n   <- sum(act)
  N   <- sum(w[act])
  if (!is.finite(N) || N <= n)
    stop(paste0("The estimated population size (sum of the weights, N = ",
                format(round(N), big.mark = ","), ") must exceed the sample size (n = ",
                format(n, big.mark = ","), ") for the data-defect formula to apply."),
         call. = FALSE)
  f <- n / N
  # Meng (2018): n_eff = (f / (1 - f)) / rho^2, the SRS size matching the MSE.
  grid <- data.frame(ddc = sort(ddc_grid),
                     n_eff = (f / (1 - f)) / sort(ddc_grid)^2)

  # Measurable selection strength on the auxiliaries: the correlation between each
  # model covariate and the participation indicator, read from the pooled
  # propensity a pseudo-weighting step stored. This is the part pseudo-weighting
  # corrects; the residual defect on the outcome is what stays unobservable.
  aux <- NULL
  for (s in object$steps) {
    pr <- attr(s$diagnostics, "propensity")
    if (is.null(pr) || is.null(pr$covars) || is.null(pr$resp)) next
    R  <- as.numeric(pr$resp)
    mm <- tryCatch(stats::model.matrix(~ ., data = pr$covars)[, -1, drop = FALSE],
                   error = function(e) NULL)
    if (is.null(mm) || !ncol(mm)) next
    cc <- vapply(seq_len(ncol(mm)),
                 function(j) suppressWarnings(stats::cor(mm[, j], R)), numeric(1))
    ok <- is.finite(cc)
    if (!any(ok)) next
    aux <- data.frame(covariate = colnames(mm)[ok], corr = cc[ok],
                      stringsAsFactors = FALSE)
    aux <- aux[order(-abs(aux$corr)), , drop = FALSE]
    rownames(aux) <- NULL
    break
  }
  structure(list(n = n, N = N, f = f, grid = grid, aux = aux),
            class = "weightflow_data_defect")
}

#' @export
print.weightflow_data_defect <- function(x, ...) {
  cat("Data-defect diagnostics (non-probability sample)\n")
  cat(sprintf("  n = %s   N = %s   f = %.4f\n",
              format(x$n, big.mark = ","), format(round(x$N), big.mark = ","), x$f))
  if (!is.null(x$aux) && nrow(x$aux))
    cat(sprintf("  strongest covariate-participation correlation: |r| = %.3f (%s)\n",
                abs(x$aux$corr[1]), x$aux$covariate[1]))
  cat("  effective size by residual data-defect correlation (Meng 2018):\n")
  g <- x$grid
  for (i in seq_len(nrow(g)))
    cat(sprintf("    |rho| = %.3f  ->  n_eff = %s\n",
                g$ddc[i], format(round(g$n_eff[i]), big.mark = ",")))
  cat("  (rho on the target variable is not observable; read as an ignorance range)\n")
  invisible(x)
}
