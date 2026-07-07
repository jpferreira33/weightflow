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

# ==========================================================================
# Delete-a-PSU jackknife (recipe-aware)
# ==========================================================================

#' Delete-a-PSU jackknife replicate weights that re-apply the recipe
#'
#' Builds jackknife replicate weights by deleting one primary sampling unit
#' (PSU) at a time and re-running the whole recipe on each replicate, so the
#' replicate weights carry the variability of every adjustment (like
#' `bootstrap_weights()`, but with the delete-a-PSU jackknife instead of a
#' resampling bootstrap).
#'
#' For a stratum \eqn{h} with \eqn{n_h} PSUs, the replicate that deletes PSU
#' \eqn{i} zeros the base weight of that PSU and inflates the remaining PSUs of
#' the stratum by \eqn{n_h/(n_h-1)}; other strata are unchanged. There is one
#' replicate per PSU. Strata with a single PSU contribute no variance and are
#' skipped. This is the stratified jackknife (JKn); with `strata = NULL` it is
#' the unstratified jackknife (JK1), and with `psu = NULL` each unit is its own
#' PSU (delete-one-unit jackknife).
#'
#' @param object a weighting_spec (inert recipe) or a prepped weighting_spec.
#'   Pass the recipe *before* `prep()`: the jackknife preps it once per replicate.
#' @param strata name of the stratum column, or NULL for a single stratum.
#' @param psu name of the PSU column, or NULL to delete one unit at a time.
#' @param progress print progress every 25 replicates.
#' @return An object of class `weightflow_jack` with the `replicates` matrix
#'   (units x replicates), the point `weights`, the per-replicate stratum and
#'   stratum size (used by `jackknife_estimate()`), and the design metadata.
#' @examples
#' spec <- weighting_spec(sample_one, base_weights = pw) |>
#'   step_calibrate(method = "raking",
#'                  margins = list(region = c(table(population$region))))
#' jk <- jackknife_weights(spec, strata = "region", psu = "psu", progress = FALSE)
#' jack_total(jk, "employed")
#' @export
jackknife_weights <- function(object, strata = NULL, psu = NULL, progress = TRUE) {
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

  # one replicate per PSU, in strata with >= 2 PSUs
  rep_stratum <- character(0); rep_psu <- character(0); rep_nh <- integer(0)
  singleton   <- character(0)
  for (h in unique(st)) {
    psus <- unique(cl[st == h]); nh <- length(psus)
    if (nh < 2L) { singleton <- c(singleton, h); next }
    rep_stratum <- c(rep_stratum, rep(h, nh))
    rep_psu     <- c(rep_psu, psus)
    rep_nh      <- c(rep_nh, rep(nh, nh))
  }
  R <- length(rep_psu)
  if (R == 0L)
    stop("No stratum has >= 2 PSUs; the jackknife has no replicates.")

  reps   <- matrix(NA_real_, nrow = n, ncol = R)
  failed <- 0L
  for (r in seq_len(R)) {
    h <- rep_stratum[r]; nh <- rep_nh[r]
    fac <- rep(1, n)
    in_h <- st == h
    fac[in_h & cl == rep_psu[r]] <- 0            # delete this PSU
    fac[in_h & cl != rep_psu[r]] <- nh / (nh - 1) # inflate the rest of the stratum
    spec$data[[bw]] <- data[[bw]] * fac
    fw <- tryCatch(prep(spec)$final_weight, error = function(e) rep(NA_real_, n))
    if (anyNA(fw)) failed <- failed + 1L
    reps[, r] <- fw
    if (progress && r %% 25L == 0L) message("  jackknife replicate ", r, "/", R)
  }
  if (length(singleton))
    warning("Strata with a single PSU contribute no jackknife variance: ",
            paste(unique(singleton), collapse = ", "))
  if (failed > 0L)
    warning(failed, " replicate(s) failed and were set to NA.")

  structure(list(replicates = reps, weights = point, data = data,
                 strata = strata, psu = psu, R = R,
                 rep_stratum = rep_stratum, rep_nh = rep_nh, base_weights = bw),
            class = "weightflow_jack")
}

#' @export
print.weightflow_jack <- function(x, ...) {
  cat("<weightflow jackknife>\n")
  cat(sprintf("  replicates : %d (delete-a-PSU)\n", x$R))
  cat(sprintf("  units      : %d (active: %d)\n", nrow(x$replicates), sum(x$weights > 0)))
  cat(sprintf("  strata     : %s\n", if (is.null(x$strata)) "(none)" else x$strata))
  cat(sprintf("  psu        : %s\n", if (is.null(x$psu)) "(unit-level)" else x$psu))
  invisible(x)
}

#' Jackknife estimate, standard error and confidence interval
#'
#' Applies a statistic to the point weights and to every delete-a-PSU replicate,
#' and summarises it with the stratified jackknife (JKn) variance
#' \deqn{\sum_h \frac{n_h - 1}{n_h} \sum_{i \in h} (\theta_{(hi)} - \bar\theta_h)^2,}
#' where \eqn{\theta_{(hi)}} is the estimate with PSU \eqn{i} of stratum \eqn{h}
#' deleted and \eqn{\bar\theta_h} the mean of those over the stratum. No finite
#' population correction is applied.
#'
#' @param jack a `weightflow_jack` object.
#' @param statistic a function `function(w, data)` returning a numeric scalar (or
#'   vector) given a weight vector and the data.
#' @param level confidence level for the (normal) interval.
#' @param variable name of the variable to estimate (for `jack_total`/`jack_mean`).
#' @return A data frame with `estimate`, `se`, `ci_lower`, `ci_upper`.
#' @examples
#' spec <- weighting_spec(sample_one, base_weights = pw) |>
#'   step_calibrate(method = "raking",
#'                  margins = list(region = c(table(population$region))))
#' jk <- jackknife_weights(spec, strata = "region", psu = "psu", progress = FALSE)
#' jackknife_estimate(jk, function(w, d) sum(w * d$employed, na.rm = TRUE))
#' @export
jackknife_estimate <- function(jack, statistic, level = 0.95) {
  if (!inherits(jack, "weightflow_jack")) stop("`jack` must be a weightflow_jack object.")
  theta_hat <- statistic(jack$weights, jack$data)
  thetas    <- apply(jack$replicates, 2L, function(w) statistic(w, jack$data))
  z <- stats::qnorm(1 - (1 - level) / 2)
  strat <- jack$rep_stratum

  jkn_var <- function(th, nh_vec) {                 # th: numeric over replicates
    good <- is.finite(th)
    V <- 0
    for (h in unique(strat[good])) {
      sel <- strat == h & good
      if (sum(sel) < 2L) next
      nh <- nh_vec[which(sel)[1]]
      V  <- V + (nh - 1) / nh * sum((th[sel] - mean(th[sel]))^2)
    }
    V
  }

  if (is.matrix(thetas)) {
    se <- sqrt(vapply(seq_len(nrow(thetas)),
                      function(k) jkn_var(thetas[k, ], jack$rep_nh), numeric(1)))
  } else {
    se <- sqrt(jkn_var(thetas, jack$rep_nh))
  }
  n_bad <- if (is.matrix(thetas)) sum(!apply(is.finite(thetas), 2L, all)) else sum(!is.finite(thetas))
  if (n_bad > 0L) warning(n_bad, " non-finite replicate(s) dropped.")
  data.frame(estimate = theta_hat, se = se,
             ci_lower = theta_hat - z * se, ci_upper = theta_hat + z * se,
             row.names = if (is.matrix(thetas)) rownames(thetas) else NULL)
}

#' @rdname jackknife_estimate
#' @export
jack_total <- function(jack, variable)
  jackknife_estimate(jack, function(w, d) sum(w * d[[variable]], na.rm = TRUE))

#' @rdname jackknife_estimate
#' @export
jack_mean <- function(jack, variable)
  jackknife_estimate(jack, function(w, d) {
    x <- d[[variable]]; ok <- !is.na(x) & w > 0
    sum(w[ok] * x[ok]) / sum(w[ok])
  })

#' Export weightflow weights to a survey design
#'
#' `as_svydesign()` builds a linearization (ultimate-cluster) design from a
#' prepped recipe; `as_svrepdesign()` builds a replicate-weights design from a
#' bootstrap (`weightflow_boot`) or jackknife (`weightflow_jack`) object, so
#' survey/srvyr standard errors include the recipe's adjustments. Both require
#' the 'survey' package. With replicate weights you can then estimate any
#' statistic for any domain (`svytotal`, `svymean`, `svyratio`, `svyby`, ...)
#' with variances that reflect the whole recipe.
#'
#' @param object for `as_svydesign`, a prepped recipe or a data frame with the
#'   weight and design columns; for `as_svrepdesign`, a `weightflow_boot` or
#'   `weightflow_jack` object.
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
#' @export
as_svrepdesign <- function(object, ...) {
  if (!requireNamespace("survey", quietly = TRUE))
    stop("Install the 'survey' package to use as_svrepdesign().")
  keep <- object$weights > 0
  if (inherits(object, "weightflow_boot")) {
    survey::svrepdesign(
      data = object$data[keep, , drop = FALSE],
      weights = object$weights[keep],
      repweights = object$replicates[keep, , drop = FALSE],
      type = "bootstrap", combined.weights = TRUE,
      scale = 1 / object$R, rscales = rep(1, object$R), mse = TRUE, ...)
  } else if (inherits(object, "weightflow_jack")) {
    # delete-a-PSU jackknife: full (combined) replicate weights with per-replicate
    # scale (n_h - 1)/n_h; survey centres at the point estimate (mse = TRUE).
    survey::svrepdesign(
      data = object$data[keep, , drop = FALSE],
      weights = object$weights[keep],
      repweights = object$replicates[keep, , drop = FALSE],
      type = "other", combined.weights = TRUE,
      scale = 1, rscales = (object$rep_nh - 1) / object$rep_nh, mse = TRUE, ...)
  } else {
    stop("`object` must be a weightflow_boot or weightflow_jack object.")
  }
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
