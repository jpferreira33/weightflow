## Variance estimation for weightflow ---------------------------------------
## Two routes:
##   1. bootstrap_weights(): resample PSUs within strata (Rao-Wu rescaling
##      bootstrap) and RE-APPLY the whole recipe on each replicate, so the
##      replicate weights carry the variability of every adjustment.
##   2. as_svydesign() / as_svrepdesign(): hand the weights to the 'survey'
##      package (ultimate-cluster linearization, or the replicate weights above).

#' Bootstrap replicate weights that re-apply the recipe
#'
#' Builds bootstrap replicate weights by resampling primary sampling units
#' (PSUs) with replacement within strata and re-running the whole recipe on
#' each replicate. Because every adjustment (nonresponse, calibration, ...) is
#' recomputed per replicate, the resulting replicate weights propagate the
#' variability introduced by each weighting stage.
#'
#' The multiplier is the Rao-Wu rescaling bootstrap: within a stratum with
#' \eqn{n} PSUs, \eqn{m} PSUs are drawn with replacement (default
#' \eqn{m = n - 1}) and unit \eqn{i} in PSU \eqn{k} gets
#' \eqn{\lambda = 1 - \sqrt{m/(n-1)} + \sqrt{m/(n-1)}\,(n/m)\,t_k}, with
#' \eqn{t_k} the number of times its PSU was drawn.
#'
#' @param object a `weighting_spec` (or a prepped one) holding the recipe.
#' @param replicates number of bootstrap replicates.
#' @param strata,psu column names of the stratum and the PSU. If `psu` is NULL
#'   each unit is its own PSU; if `strata` is NULL a single stratum is assumed.
#' @param m PSUs drawn per stratum (default `n - 1`).
#' @param seed optional RNG seed.
#' @param progress print progress every 25 replicates.
#' @return An object of class `weightflow_boot` with the `replicates` matrix
#'   (units x replicates), the point `weights`, and the design metadata.
#' @examples
#' spec <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_calibrate(method = "raking",
#'                  margins = list(region = c(table(population$region))))
#' boot <- bootstrap_weights(spec, replicates = 50, strata = "region",
#'                           psu = "psu", seed = 1)
#' boot_total(boot, "responded")
#' @export
bootstrap_weights <- function(object, replicates = 200L, strata = NULL,
                              psu = NULL, m = NULL, seed = NULL, progress = TRUE) {
  if (!inherits(object, "weighting_spec"))
    stop("`object` must be a weighting_spec or a prepped weighting_spec.")
  data <- object$data
  bw   <- object$base_weights
  spec <- structure(list(data = data, base_weights = bw, steps = object$steps),
                    class = "weighting_spec")
  point <- if (!is.null(object$final_weight)) object$final_weight else prep(spec)$final_weight
  n <- nrow(data)

  st <- if (is.null(strata)) rep("1", n) else {
    if (!strata %in% names(data)) stop(sprintf("Strata column '%s' not found.", strata))
    as.character(data[[strata]])
  }
  cl <- if (is.null(psu)) as.character(seq_len(n)) else {
    if (!psu %in% names(data)) stop(sprintf("PSU column '%s' not found.", psu))
    as.character(data[[psu]])
  }
  if (!is.null(seed)) set.seed(seed)

  reps      <- matrix(NA_real_, nrow = n, ncol = replicates)
  hs        <- unique(st)
  singleton <- character(0)
  failed    <- 0L
  for (b in seq_len(replicates)) {
    fac <- numeric(n)
    for (h in hs) {
      idx  <- which(st == h)
      psus <- unique(cl[idx])
      nh   <- length(psus)
      if (nh < 2L) { fac[idx] <- 1; if (b == 1L) singleton <- c(singleton, h); next }
      mh   <- if (is.null(m)) nh - 1L else min(as.integer(m), nh - 1L)
      cnt  <- tabulate(sample.int(nh, mh, replace = TRUE), nbins = nh)
      lam  <- 1 - sqrt(mh / (nh - 1)) + sqrt(mh / (nh - 1)) * (nh / mh) * cnt
      names(lam) <- psus
      fac[idx] <- lam[cl[idx]]
    }
    spec$data[[bw]] <- data[[bw]] * fac
    fw <- tryCatch(prep(spec)$final_weight, error = function(e) { rep(NA_real_, n) })
    if (anyNA(fw)) failed <- failed + 1L
    reps[, b] <- fw
    if (progress && b %% 25L == 0L) message("  bootstrap replicate ", b, "/", replicates)
  }
  if (length(singleton))
    warning("Strata with a single PSU were not resampled (no bootstrap variance there): ",
            paste(unique(singleton), collapse = ", "))
  if (failed > 0L)
    warning(failed, " replicate(s) failed to converge and were set to NA.")

  structure(list(replicates = reps, weights = point, data = data,
                 strata = strata, psu = psu, R = replicates,
                 base_weights = bw),
            class = "weightflow_boot")
}

#' @export
print.weightflow_boot <- function(x, ...) {
  cat("<weightflow bootstrap>\n")
  cat(sprintf("  replicates : %d\n", x$R))
  cat(sprintf("  units      : %d (active: %d)\n", nrow(x$replicates), sum(x$weights > 0)))
  cat(sprintf("  strata     : %s\n", if (is.null(x$strata)) "(none)" else x$strata))
  cat(sprintf("  psu        : %s\n", if (is.null(x$psu)) "(unit-level)" else x$psu))
  invisible(x)
}

#' Bootstrap estimate, standard error and confidence interval
#'
#' Applies a statistic to the point weights and to every replicate, and
#' summarises it with the bootstrap variance \eqn{(1/B)\sum(\theta^*_b -
#' \hat\theta)^2}.
#'
#' @param boot a `weightflow_boot` object.
#' @param statistic a function `function(w, data)` returning a numeric scalar
#'   (or vector) given a weight vector and the data.
#' @param level confidence level for the (normal) interval.
#' @return A data frame with `estimate`, `se`, `ci_lower`, `ci_upper`.
#' @export
bootstrap_estimate <- function(boot, statistic, level = 0.95) {
  if (!inherits(boot, "weightflow_boot")) stop("`boot` must be a weightflow_boot object.")
  theta_hat <- statistic(boot$weights, boot$data)
  thetas    <- apply(boot$replicates, 2L, function(w) statistic(w, boot$data))
  z <- stats::qnorm(1 - (1 - level) / 2)
  if (is.matrix(thetas)) {
    good <- apply(is.finite(thetas), 2L, all)
    dev  <- thetas[, good, drop = FALSE] - theta_hat
    se   <- sqrt(rowMeans(dev^2))
  } else {
    good <- is.finite(thetas)
    se   <- sqrt(mean((thetas[good] - theta_hat)^2))
  }
  if (sum(good) < length(good))
    warning(length(good) - sum(good), " non-finite replicate(s) dropped.")
  data.frame(estimate = theta_hat, se = se,
             ci_lower = theta_hat - z * se, ci_upper = theta_hat + z * se,
             row.names = if (is.matrix(thetas)) rownames(thetas) else NULL)
}

#' @rdname bootstrap_estimate
#' @param variable name of the variable to estimate.
#' @export
boot_total <- function(boot, variable)
  bootstrap_estimate(boot, function(w, d) sum(w * d[[variable]], na.rm = TRUE))

#' @rdname bootstrap_estimate
#' @export
boot_mean <- function(boot, variable)
  bootstrap_estimate(boot, function(w, d) {
    x <- d[[variable]]; ok <- !is.na(x) & w > 0
    sum(w[ok] * x[ok]) / sum(w[ok])
  })

#' Export weightflow weights to a survey design
#'
#' `as_svydesign()` builds a linearization (ultimate-cluster) design from a
#' prepped recipe; `as_svrepdesign()` builds a replicate-weights design from a
#' bootstrap object, so survey/srvyr standard errors include the recipe's
#' adjustments. Both require the 'survey' package.
#'
#' @param object a prepped recipe (for `as_svydesign`) or a data frame with the
#'   weight and design columns.
#' @param ids,strata column names of the PSU and the stratum.
#' @param weight_name name of the weight column.
#' @param ... passed to the survey constructor.
#' @return A `survey.design` / `svyrep.design` object.
#' @export
as_svydesign <- function(object, ids, strata = NULL, weight_name = ".weight", ...) {
  if (!requireNamespace("survey", quietly = TRUE))
    stop("Install the 'survey' package to use as_svydesign().")
  if (inherits(object, "prepped_weighting_spec")) {
    df <- object$data; df[[weight_name]] <- object$final_weight
  } else if (is.data.frame(object)) {
    df <- object
    if (!weight_name %in% names(df))
      stop(sprintf("Column '%s' not found; pass weight_name=.", weight_name))
  } else stop("`object` must be a prepped recipe or a data frame.")
  df <- df[df[[weight_name]] > 0, , drop = FALSE]            # drop inactive units
  f  <- function(v) stats::as.formula(paste("~", v))
  survey::svydesign(ids = f(ids), strata = if (is.null(strata)) NULL else f(strata),
                    weights = f(weight_name), data = df, nest = TRUE, ...)
}

#' @rdname as_svydesign
#' @param boot a `weightflow_boot` object.
#' @export
as_svrepdesign <- function(boot, ...) {
  if (!requireNamespace("survey", quietly = TRUE))
    stop("Install the 'survey' package to use as_svrepdesign().")
  if (!inherits(boot, "weightflow_boot")) stop("`boot` must be a weightflow_boot object.")
  keep <- boot$weights > 0
  survey::svrepdesign(
    data = boot$data[keep, , drop = FALSE],
    weights = boot$weights[keep],
    repweights = boot$replicates[keep, , drop = FALSE],
    type = "bootstrap", combined.weights = TRUE,
    scale = 1 / boot$R, rscales = rep(1, boot$R), mse = TRUE, ...)
}

#' Collect replicate weights into a data frame ready for srvyr
#'
#' Returns the data with the point weight and the bootstrap replicate weights
#' as columns, so it can be fed directly to `srvyr::as_survey_rep()` (or
#' `survey::svrepdesign()`). Replicate columns are full weights, so use
#' `combined.weights = TRUE`, `scale = 1 / R`, `rscales = 1`, `mse = TRUE`.
#'
#' @param boot a `weightflow_boot` object.
#' @param weight_name name of the point-weight column to add.
#' @param prefix prefix for the replicate-weight columns (`rep_1`, `rep_2`, ...).
#' @param drop_zero keep only active units (point weight > 0).
#' @return A data frame: the original columns, `weight_name`, and one column per
#'   replicate. The number of replicates is stored in attribute `"R"`.
#' @examples
#' spec <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_calibrate(method = "raking",
#'                  margins = list(region = c(table(population$region))))
#' boot <- bootstrap_weights(spec, replicates = 30, strata = "region",
#'                           psu = "psu", seed = 1, progress = FALSE)
#' df <- collect_replicate_weights(boot)
#' \donttest{
#' if (requireNamespace("srvyr", quietly = TRUE) &&
#'     requireNamespace("dplyr", quietly = TRUE)) {
#'   srvyr::as_survey_rep(df, weights = .weight,
#'                        repweights = dplyr::starts_with("rep_"),
#'                        type = "bootstrap", combined.weights = TRUE,
#'                        scale = 1 / attr(df, "R"), rscales = 1, mse = TRUE)
#' }
#' }
#' @export
collect_replicate_weights <- function(boot, weight_name = ".weight",
                                      prefix = "rep_", drop_zero = TRUE) {
  if (!inherits(boot, "weightflow_boot")) stop("`boot` must be a weightflow_boot object.")
  keep <- if (drop_zero) boot$weights > 0 else rep(TRUE, length(boot$weights))
  out  <- boot$data[keep, , drop = FALSE]
  reps <- boot$replicates[keep, , drop = FALSE]
  colnames(reps) <- paste0(prefix, seq_len(ncol(reps)))
  out[[weight_name]] <- boot$weights[keep]
  out <- cbind(out, as.data.frame(reps))
  rownames(out) <- NULL
  attr(out, "R") <- boot$R
  out
}
