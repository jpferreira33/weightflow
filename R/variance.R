## Variance estimation for weightflow ---------------------------------------
## Two routes:
##   1. bootstrap_weights(): resample PSUs within strata (Rao-Wu rescaling
##      bootstrap) and RE-APPLY the whole recipe on each replicate, so the
##      replicate weights carry the variability of every adjustment.
##   2. as_svydesign() / as_svrepdesign(): hand the weights to the 'survey'
##      package (ultimate-cluster linearization, or the replicate weights above).

#' Recipe-aware bootstrap replicate weights
#'
#' Builds bootstrap replicate weights by resampling primary sampling units
#' (PSUs) with replacement within strata and re-running the **entire** weighting
#' recipe on each replicate -- every estimated stage (nonresponse, calibration,
#' model calibration, trimming), not just one. Reach for this when those stages
#' are estimated from the sample and you want their uncertainty inside the
#' standard error, instead of conditioning on them as if they were known.
#'
#' The multiplier is the Rao-Wu rescaling bootstrap: within a stratum with
#' \eqn{n} PSUs, \eqn{m} PSUs are drawn with replacement (default
#' \eqn{m = n - 1}) and unit \eqn{i} in PSU \eqn{k} gets
#' \eqn{\lambda = 1 - \sqrt{m/(n-1)} + \sqrt{m/(n-1)}\,(n/m)\,t_k}{lambda = 1 - sqrt(m/(n-1)) + sqrt(m/(n-1)) * (n/m) * t_k}, with
#' \eqn{t_k} the number of times its PSU was drawn.
#'
#' @param object a `weighting_spec` (or a prepped one) holding the recipe.
#' @param replicates number of bootstrap replicates.
#' @param strata,psu column names of the stratum and the PSU. If `psu` is NULL
#'   each unit is its own PSU; if `strata` is NULL a single stratum is assumed.
#' @param m PSUs drawn per stratum (default `n - 1`).
#' @param fpc optional first-stage finite-population correction: the name of a
#'   column holding the first-stage sampling fraction f_h (constant within
#'   stratum, in `[0, 1]`), a single number applied to every stratum, or a numeric
#'   vector named by stratum level. `NULL` (default) is the with-replacement
#'   bootstrap (no correction). The correction folds `(1 - f_h)` into the Rao-Wu
#'   rescaling (Rao, Wu and Yue 1992; Beaumont and Patak 2012); `f_h = 0`
#'   reproduces the uncorrected result. Only available for the bootstrap.
#' @param lonely_psu how to treat strata with a single PSU (which a
#'   with-replacement bootstrap cannot resample): "certainty" (default) treats
#'   them as self-representing, so they contribute no bootstrap variance, and
#'   warns; "collapse" merges the single-PSU strata into a pseudo-stratum (with
#'   the smallest other stratum if there is only one), so they are resampled and
#'   do contribute a (conservative) variance. For full control, build your own
#'   collapsed stratum column and pass it as `strata`.
#' @param seed optional RNG seed.
#' @param cores number of parallel workers for the replicates (default 1 =
#'   serial). With `cores > 1` the replicate re-preps run in parallel via
#'   `parallel::mclapply` (forking; on Windows it falls back to serial). Results
#'   are identical to the serial run: the resampling is drawn up front with the
#'   seed and only the deterministic re-prep is parallelised.
#' @param progress print progress every 25 replicates (serial only).
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
                              psu = NULL, m = NULL, fpc = NULL,
                              lonely_psu = c("certainty", "collapse"),
                              seed = NULL, cores = 1L, progress = TRUE) {
  if (!inherits(object, "weighting_spec"))
    stop("`object` must be a weighting_spec or a prepped weighting_spec.")
  lonely_psu <- match.arg(lonely_psu)
  replicates <- .wf_count(replicates, "replicates", min = 2L)
  if (!is.null(m)) m <- .wf_count(m, "m", min = 1L)
  # Snapshot the caller's RNG so the per-replicate seeding below does not leak
  # into their stream (restored on exit, once the replicate seeds are drawn).
  .rng_entry <- if (exists(".Random.seed", envir = .GlobalEnv))
    get(".Random.seed", envir = .GlobalEnv) else NULL
  t0 <- Sys.time()
  data <- object$data
  bw   <- object$base_weights
  spec <- structure(list(data = data, base_weights = bw, steps = object$steps),
                    class = "weighting_spec")
  point <- if (!is.null(object$final_weight)) object$final_weight else prep(spec)$final_weight
  n   <- nrow(data)
  bw0 <- data[[bw]]

  st <- if (is.null(strata)) rep("1", n) else {
    if (!strata %in% names(data)) stop(sprintf("Strata column '%s' not found.", strata))
    as.character(data[[strata]])
  }
  cl <- if (is.null(psu)) as.character(seq_len(n)) else {
    if (!psu %in% names(data)) stop(sprintf("PSU column '%s' not found.", psu))
    as.character(data[[psu]])
  }
  .assert_design_complete(data, strata, psu)
  # First-stage sampling fraction f_h for the finite-population correction, resolved
  # to one value per row NOW (before any lonely-PSU collapse), keyed by stratum.
  # f = 0 (the default) reproduces the with-replacement bootstrap exactly.
  fvec <- rep(0, n)
  if (!is.null(fpc)) {
    fvec <- if (is.character(fpc) && length(fpc) == 1L) {
      if (!fpc %in% names(data)) stop(sprintf("`fpc` column '%s' not found.", fpc), call. = FALSE)
      as.numeric(data[[fpc]])
    } else if (is.numeric(fpc) && length(fpc) == 1L) {
      rep(as.numeric(fpc), n)
    } else if (is.numeric(fpc) && !is.null(names(fpc))) {
      out <- unname(fpc[st])
      if (anyNA(out)) stop("`fpc` (named vector) is missing some stratum level(s).", call. = FALSE)
      as.numeric(out)
    } else stop("`fpc` must be a column name, a single number, or a numeric vector named by stratum.",
                call. = FALSE)
    if (any(!is.finite(fvec)) || any(fvec < 0 | fvec > 1))
      stop("`fpc` (first-stage sampling fraction) must be in [0, 1].", call. = FALSE)
  }
  if (lonely_psu == "collapse") {
    cl <- paste(st, cl, sep = "||")     # nest PSU ids so distinct PSUs stay distinct after merging strata
    st <- .collapse_lonely(st, cl)
  }
  hs <- unique(st)
  # f_h per final stratum; a collapsed pseudo-stratum must have a single fraction.
  fh_by <- stats::setNames(numeric(length(hs)), hs)
  for (h in hs) {
    fu <- unique(fvec[st == h])
    if (length(fu) != 1L)
      stop(sprintf(paste0("`fpc` is not constant within stratum '%s'. Collapsing strata with ",
                          "different sampling fractions is not valid; give them the same fpc, or ",
                          "do not collapse them."), h), call. = FALSE)
    fh_by[[h]] <- fu
  }
  if (!is.null(seed)) set.seed(seed)

  # --- Phase 1 (serial, uses the RNG): draw every resampling factor vector and a
  # per-replicate seed. This is the ONLY random part; capturing it up front makes
  # the parallel run bit-identical to the serial one and reproducible via `seed`.
  singleton <- character(0)
  facs   <- vector("list", replicates)
  rseeds <- sample.int(.Machine$integer.max, replicates)
  # Restore the RNG on exit so one_rep()'s per-replicate set.seed() does not leak.
  # With an explicit `seed`: restore the caller's state entirely (no leak, fully
  # reproducible). Unseeded: restore the state just after the replicate seeds were
  # drawn, so consecutive unseeded calls still differ.
  .rng_restore <- if (is.null(seed) && exists(".Random.seed", envir = .GlobalEnv))
    get(".Random.seed", envir = .GlobalEnv) else .rng_entry
  if (!is.null(.rng_restore))
    on.exit(assign(".Random.seed", .rng_restore, envir = .GlobalEnv), add = TRUE)
  for (b in seq_len(replicates)) {
    fac <- numeric(n)
    for (h in hs) {
      idx  <- which(st == h)
      psus <- unique(cl[idx])
      nh   <- length(psus)
      if (nh < 2L) { fac[idx] <- 1; if (b == 1L) singleton <- c(singleton, h); next }
      mh   <- if (is.null(m)) nh - 1L else min(as.integer(m), nh - 1L)
      cnt  <- tabulate(sample.int(nh, mh, replace = TRUE), nbins = nh)
      # Rao-Wu rescaling, with the (1 - f_h) finite-population correction folded
      # into the scale term (Rao, Wu and Yue 1992; Beaumont and Patak 2012). With
      # f_h = 0 this is the plain with-replacement bootstrap. E[lambda] = 1 always.
      ah   <- sqrt(mh * (1 - fh_by[[h]]) / (nh - 1))
      lam  <- 1 - ah + ah * (nh / mh) * cnt
      names(lam) <- psus
      fac[idx] <- lam[cl[idx]]
    }
    facs[[b]] <- fac
  }

  # --- Phase 2 (serial or parallel): re-prep each replicate. Pure deterministic
  # computation given (fac, seed), so it parallelises cleanly.
  one_rep <- function(b) {
    set.seed(rseeds[b])                       # only matters if a step is stochastic
    sp <- spec; sp$data[[bw]] <- bw0 * facs[[b]]
    attr(sp$data, "wf_replicate") <- TRUE          # step_assert becomes a no-op in replicates
    attr(sp$data, "wf_replicate_idx") <- b         # pairs with a reference_sample() replicate column
    tryCatch(prep(sp)$final_weight, error = function(e) rep(NA_real_, n))
  }
  fw_list <- .par_lapply(seq_len(replicates), one_rep, cores = cores,
                         progress = progress, label = "bootstrap")
  # A dead mclapply worker (OOM-killed) returns NULL, and a serialization error a
  # try-error; do.call(cbind, ) would silently drop the NULLs or coerce the whole
  # matrix to character. Normalise every element to an n-vector so failures become
  # NA columns and are counted, not lost.
  fw_list <- lapply(fw_list, function(z)
    if (is.numeric(z) && length(z) == n) z else rep(NA_real_, n))
  reps   <- do.call(cbind, fw_list)
  failed <- sum(vapply(fw_list, anyNA, logical(1)))

  if (length(singleton))
    warning("Strata with a single PSU were not resampled (no bootstrap variance there): ",
            paste(unique(singleton), collapse = ", "),
            ". Use lonely_psu = \"collapse\" to give them a (conservative) variance.")
  if (failed > 0L)
    warning(failed, " replicate(s) failed to converge and were set to NA.")

  # Degrees of freedom = (total PSUs) - (strata), the standard survey convention,
  # computed post-collapse. Used by the t / percentile confidence intervals.
  df <- sum(vapply(hs, function(h) length(unique(cl[st == h])), integer(1))) - length(hs)
  structure(list(replicates = reps, weights = point, data = data,
                 strata = strata, psu = psu, R = replicates,
                 base_weights = bw, method = "bootstrap", lonely_psu = lonely_psu,
                 fpc = fpc, df = df,
                 seed = seed, cores = as.integer(cores),
                 elapsed = as.numeric(difftime(Sys.time(), t0, units = "secs"))),
            class = "weightflow_boot")
}

# Merge single-PSU strata into a pseudo-stratum so a with-replacement bootstrap
# (or delete-a-PSU jackknife) can resample them. With >= 2 lonely strata they are
# pooled together; with exactly one, it is merged with the smallest other stratum.
# Best-effort: if only one stratum exists overall, it is left unchanged.
.collapse_lonely <- function(st, cl) {
  st    <- as.character(st)
  npsu  <- tapply(cl, st, function(z) length(unique(z)))
  lonely <- names(npsu)[npsu < 2L]
  if (length(lonely) == 0L) return(st)
  new <- st
  if (length(lonely) >= 2L) {
    new[st %in% lonely] <- "__collapsed__"
  } else {
    others <- npsu[setdiff(names(npsu), lonely)]
    if (length(others) == 0L) return(st)          # single stratum overall
    target <- names(others)[which.min(others)]
    new[st %in% c(lonely, target)] <- paste0("__collapsed_", target)
  }
  new
}

# Apply `fun` over `x`, serially (cores = 1) or forking with parallel::mclapply
# (cores > 1). Kept dependency-free: `parallel` is a base R package.
.par_lapply <- function(x, fun, cores = 1L, progress = FALSE, label = "") {
  cores <- max(1L, as.integer(cores))
  if (cores > 1L && .Platform$OS.type == "windows") cores <- 1L   # mclapply has no forking on Windows
  if (cores > 1L && requireNamespace("parallel", quietly = TRUE)) {
    return(parallel::mclapply(x, fun, mc.cores = cores, mc.preschedule = TRUE))
  }
  lapply(x, function(i) {
    if (progress && i %% 25L == 0L) message("  ", label, " replicate ", i, "/", length(x))
    fun(i)
  })
}

# Reject NA in the design identifiers (strata / PSU) before resampling: a unit
# with no stratum or no PSU cannot be resampled and would otherwise get a zero
# replicate weight (or fail every replicate) silently. Error early and clearly.
.assert_design_complete <- function(data, strata, psu) {
  if (!is.null(strata) && anyNA(data[[strata]]))
    stop(sprintf(paste0("Strata column '%s' has missing values (NA) in %d unit(s). ",
                        "Resampling is undefined for a unit with no stratum; assign a stratum ",
                        "to those units (or filter them) before bootstrap/jackknife."),
                 strata, sum(is.na(data[[strata]]))), call. = FALSE)
  if (!is.null(psu) && anyNA(data[[psu]]))
    stop(sprintf(paste0("PSU column '%s' has missing values (NA) in %d unit(s). ",
                        "Resampling is undefined for a unit with no PSU; assign a PSU to those ",
                        "units (or filter them) before bootstrap/jackknife."),
                 psu, sum(is.na(data[[psu]]))), call. = FALSE)
}

#' Print a bootstrap replicate-weight object
#'
#' Compact one-screen summary of a `weightflow_boot` object: how many replicates
#' were requested, how many units are in the data, how many of them are still
#' active (final weight above zero), and which columns defined the resampling
#' design.
#'
#' @param x a `weightflow_boot` object.
#' @param ... ignored.
#' @return (invisibly) the object.
#' @export
print.weightflow_boot <- function(x, ...) {
  cat("<weightflow bootstrap>\n")
  cat(sprintf("  replicates : %d\n", x$R))
  cat(sprintf("  units      : %d (active: %d)\n", nrow(x$replicates), sum(.wf_active(x$weights))))
  cat(sprintf("  strata     : %s\n", if (is.null(x$strata)) "(none)" else x$strata))
  cat(sprintf("  psu        : %s\n", if (is.null(x$psu)) "(unit-level)" else x$psu))
  if (!is.null(x$df)) cat(sprintf("  df         : %d%s\n", x$df,
      if (!is.null(x$fpc)) "  (fpc applied)" else ""))
  invisible(x)
}

#' Bootstrap estimate, standard error and confidence interval
#'
#' Applies a statistic to the point weights and to every bootstrap replicate, and
#' returns the estimate with its bootstrap standard error and a normal confidence
#' interval. `boot_total()` and `boot_mean()` are the two shortcuts you will use
#' most: a weighted total and a weighted mean of one column.
#'
#' The bootstrap variance takes the replicate estimates
#' \eqn{\hat\theta^{*}_b}{theta*_b} around the point estimate
#' \eqn{\hat\theta}{theta_hat} (the `mse = TRUE` convention of `survey`), over the
#' \eqn{R}{R} valid replicates (a failed replicate is dropped, not counted),
#' \deqn{\widehat V_{\mathrm{boot}}(\hat\theta) = \frac{1}{R}\sum_{b=1}^{R}\big(\hat\theta^{*}_b - \hat\theta\big)^2.}{V_boot = (1/R) sum_b (theta*_b - theta_hat)^2.}
#'
#' @param boot a `weightflow_boot` object.
#' @param statistic a function `function(w, data)` returning a numeric scalar
#'   (or vector) given a weight vector and the data.
#' @param level confidence level for the interval.
#' @param ci_type interval type: "normal" (default, z-based), "t" (Student t with
#'   the design degrees of freedom, wider and less anticonservative with few PSUs),
#'   or "percentile" (empirical quantiles of the valid replicates).
#' @param df degrees of freedom for the t interval; `NULL` (default) uses the
#'   design df stored on the object (total PSUs minus strata).
#' @return A data frame with `estimate`, `se`, `ci_lower`, `ci_upper`.
#' @export
bootstrap_estimate <- function(boot, statistic, level = 0.95,
                               ci_type = c("normal", "t", "percentile"), df = NULL) {
  if (!inherits(boot, "weightflow_boot")) stop("`boot` must be a weightflow_boot object.")
  .wf_level(level)
  ci_type <- match.arg(ci_type)
  df <- if (is.null(df)) boot$df else df
  theta_hat <- statistic(boot$weights, boot$data)
  thetas    <- apply(boot$replicates, 2L, function(w) statistic(w, boot$data))
  a   <- (1 - level) / 2
  mat <- is.matrix(thetas)
  good   <- if (mat) apply(is.finite(thetas), 2L, all) else is.finite(thetas)
  nvalid <- sum(good)
  if (nvalid < length(good))
    warning(length(good) - nvalid, " non-finite replicate(s) dropped.")
  if (mat) { dev <- thetas[, good, drop = FALSE] - theta_hat; se <- sqrt(rowMeans(dev^2)) }
  else       se <- sqrt(mean((thetas[good] - theta_hat)^2))
  if (ci_type == "percentile") {
    if (nvalid < 50L)
      warning("A percentile interval with fewer than 50 valid replicates is unstable.", call. = FALSE)
    qf <- function(v) stats::quantile(v, c(a, 1 - a), names = FALSE, na.rm = TRUE)
    if (mat) { q <- apply(thetas[, good, drop = FALSE], 1L, qf); lo <- q[1, ]; hi <- q[2, ] }
    else     { q <- qf(thetas[good]); lo <- q[1]; hi <- q[2] }
  } else {
    crit <- if (ci_type == "t") {
      if (is.null(df) || !is.finite(df) || df <= 0)
        stop(sprintf(paste0("A t interval needs positive degrees of freedom, but the design has ",
                            "df = %s (e.g. one PSU per stratum). Use ci_type = \"normal\", ",
                            "collapse lonely strata, or pass `df`."),
                     if (is.null(df)) "NULL" else as.character(df)), call. = FALSE)
      stats::qt(1 - a, df)
    } else stats::qnorm(1 - a)
    lo <- theta_hat - crit * se; hi <- theta_hat + crit * se
  }
  data.frame(estimate = theta_hat, se = se, ci_lower = lo, ci_upper = hi,
             row.names = if (mat) rownames(thetas) else NULL)
}

#' @rdname bootstrap_estimate
#' @param variable name of the variable to estimate.
#' @export
boot_total <- function(boot, variable) {
  variable <- .wf_var(variable, boot)
  bootstrap_estimate(boot, function(w, d)
    if (anyNA(w)) NA_real_ else sum(w * d[[variable]], na.rm = TRUE))
}

#' @rdname bootstrap_estimate
#' @export
boot_mean <- function(boot, variable) {
  variable <- .wf_var(variable, boot)
  bootstrap_estimate(boot, function(w, d) {
    x <- d[[variable]]; ok <- !is.na(x) & .wf_active(w)   # keep active negatives, as totals do
    sum(w[ok] * x[ok]) / sum(w[ok])
  })
}

# ==========================================================================
# Delete-a-PSU jackknife (recipe-aware)
# ==========================================================================

#' Recipe-aware delete-a-PSU jackknife replicate weights
#'
#' Builds jackknife replicate weights by deleting one primary sampling unit
#' (PSU) at a time and re-running the **entire** weighting recipe on each
#' replicate. This is the deterministic sibling of [bootstrap_weights()]: same
#' recipe-aware variance, no random number generation, and a replicate count
#' fixed by the design rather than chosen by the analyst.
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
#' @param lonely_psu how to treat strata with a single PSU: "certainty"
#'   (default) skips them (no variance) and warns; "collapse" merges them into a
#'   pseudo-stratum so they yield delete-a-PSU replicates.
#' @param cores number of parallel workers for the replicates (default 1 =
#'   serial). With `cores > 1` the replicate re-preps run in parallel via
#'   `parallel::mclapply` (forking; serial on Windows). For a deterministic
#'   recipe the result is identical to the serial run.
#' @param progress print progress every 25 replicates (serial only).
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
jackknife_weights <- function(object, strata = NULL, psu = NULL,
                              lonely_psu = c("certainty", "collapse"),
                              cores = 1L, progress = TRUE) {
  if (!inherits(object, "weighting_spec"))
    stop("`object` must be a weighting_spec or a prepped weighting_spec.")
  lonely_psu <- match.arg(lonely_psu)
  t0 <- Sys.time()
  data <- object$data
  bw   <- object$base_weights
  spec <- structure(list(data = data, base_weights = bw, steps = object$steps),
                    class = "weighting_spec")
  point <- if (!is.null(object$final_weight)) object$final_weight else prep(spec)$final_weight
  n   <- nrow(data)
  bw0 <- data[[bw]]

  st <- if (is.null(strata)) rep("1", n) else {
    if (!strata %in% names(data)) stop(sprintf("Strata column '%s' not found.", strata))
    as.character(data[[strata]])
  }
  cl <- if (is.null(psu)) as.character(seq_len(n)) else {
    if (!psu %in% names(data)) stop(sprintf("PSU column '%s' not found.", psu))
    as.character(data[[psu]])
  }
  .assert_design_complete(data, strata, psu)
  if (lonely_psu == "collapse") {
    cl <- paste(st, cl, sep = "||")     # nest PSU ids so distinct PSUs stay distinct after merging strata
    st <- .collapse_lonely(st, cl)
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

  one_rep <- function(r) {
    h <- rep_stratum[r]; nh <- rep_nh[r]
    fac <- rep(1, n)
    in_h <- st == h
    fac[in_h & cl == rep_psu[r]] <- 0             # delete this PSU
    fac[in_h & cl != rep_psu[r]] <- nh / (nh - 1) # inflate the rest of the stratum
    sp <- spec; sp$data[[bw]] <- bw0 * fac
    attr(sp$data, "wf_replicate") <- TRUE          # step_assert becomes a no-op in replicates
    tryCatch(prep(sp)$final_weight, error = function(e) rep(NA_real_, n))
  }
  fw_list <- .par_lapply(seq_len(R), one_rep, cores = cores,
                         progress = progress, label = "jackknife")
  # normalise dead-worker NULLs / try-errors to NA columns (see bootstrap above)
  fw_list <- lapply(fw_list, function(z)
    if (is.numeric(z) && length(z) == n) z else rep(NA_real_, n))
  reps   <- do.call(cbind, fw_list)
  failed <- sum(vapply(fw_list, anyNA, logical(1)))

  if (length(singleton))
    warning("Strata with a single PSU contribute no jackknife variance: ",
            paste(unique(singleton), collapse = ", "),
            ". Use lonely_psu = \"collapse\" to include them.")
  if (failed > 0L)
    warning(failed, " replicate(s) failed and were set to NA.")

  # Degrees of freedom = (total PSUs) - (strata): one delete-a-PSU replicate per PSU.
  df <- length(rep_stratum) - length(unique(rep_stratum))
  structure(list(replicates = reps, weights = point, data = data,
                 strata = strata, psu = psu, R = R,
                 rep_stratum = rep_stratum, rep_nh = rep_nh, base_weights = bw,
                 method = "jackknife", lonely_psu = lonely_psu, df = df,
                 cores = as.integer(cores),
                 elapsed = as.numeric(difftime(Sys.time(), t0, units = "secs"))),
            class = "weightflow_jack")
}

#' Print a jackknife replicate-weight object
#'
#' Compact one-screen summary of a `weightflow_jack` object: how many
#' delete-a-PSU replicates were built, how many units are in the data, how many of
#' them are still active (final weight above zero), and which columns defined the
#' deletion design.
#'
#' @param x a `weightflow_jack` object.
#' @param ... ignored.
#' @return (invisibly) the object.
#' @export
print.weightflow_jack <- function(x, ...) {
  cat("<weightflow jackknife>\n")
  cat(sprintf("  replicates : %d (delete-a-PSU)\n", x$R))
  cat(sprintf("  units      : %d (active: %d)\n", nrow(x$replicates), sum(.wf_active(x$weights))))
  cat(sprintf("  strata     : %s\n", if (is.null(x$strata)) "(none)" else x$strata))
  cat(sprintf("  psu        : %s\n", if (is.null(x$psu)) "(unit-level)" else x$psu))
  if (!is.null(x$df)) cat(sprintf("  df         : %d\n", x$df))
  invisible(x)
}

#' Jackknife estimate, standard error and confidence interval
#'
#' Applies a statistic to the point weights and to every delete-a-PSU replicate,
#' and returns the estimate with its stratified jackknife (JKn) standard error and
#' a normal confidence interval. `jack_total()` and `jack_mean()` are the
#' shortcuts for a weighted total and a weighted mean of one column.
#'
#' The stratified (JKn) variance sums each stratum's delete-a-PSU spread,
#' \deqn{\widehat V_{JK} = \sum_h \frac{n_h - 1}{n_h}\sum_{i \in h}\big(\hat\theta_{(hi)} - \hat\theta_h\big)^2,}{V_JK = sum_h (n_h - 1)/n_h * sum_(i in h) (theta_(hi) - theta_h)^2,}
#' with \eqn{\hat\theta_{(hi)}}{theta_(hi)} the estimate with PSU \eqn{i}{i} of
#' stratum \eqn{h}{h} deleted and \eqn{\hat\theta_h}{theta_h} their within-stratum
#' mean; the unstratified JK1 uses a single stratum. No finite population
#' correction is applied.
#'
#' @param jack a `weightflow_jack` object.
#' @param statistic a function `function(w, data)` returning a numeric scalar (or
#'   vector) given a weight vector and the data.
#' @param level confidence level for the interval.
#' @param ci_type interval type: "normal" (default) or "t" (Student t with the
#'   design degrees of freedom). The percentile interval is not defined for the
#'   jackknife.
#' @param df degrees of freedom for the t interval; `NULL` (default) uses the
#'   design df stored on the object (total PSUs minus strata).
#' @param variable name of the variable to estimate (for `jack_total`/`jack_mean`).
#' @return A data frame with `estimate`, `se`, `ci_lower`, `ci_upper`.
#' @note `jack_total()` / `jack_mean()` center the replicate deviations on the
#'   per-stratum mean of the deleted-PSU estimates (the standard JKn). The
#'   `survey` design built by `as_svrepdesign()` instead uses `mse = TRUE`, which
#'   centers on the point estimate. Both are legitimate, so the standard errors
#'   from `jack_total()` and from `svytotal()` on the same object can differ
#'   slightly.
#' @examples
#' spec <- weighting_spec(sample_one, base_weights = pw) |>
#'   step_calibrate(method = "raking",
#'                  margins = list(region = c(table(population$region))))
#' jk <- jackknife_weights(spec, strata = "region", psu = "psu", progress = FALSE)
#' jackknife_estimate(jk, function(w, d) sum(w * d$employed, na.rm = TRUE))
#' @export
jackknife_estimate <- function(jack, statistic, level = 0.95,
                               ci_type = c("normal", "t"), df = NULL) {
  if (!inherits(jack, "weightflow_jack")) stop("`jack` must be a weightflow_jack object.")
  .wf_level(level)
  ci_type <- match.arg(ci_type)   # percentile is not a jackknife interval
  df <- if (is.null(df)) jack$df else df
  a  <- (1 - level) / 2
  crit <- if (ci_type == "t") {
    if (is.null(df) || !is.finite(df) || df <= 0)
      stop(sprintf(paste0("A t interval needs positive degrees of freedom, but the design has ",
                          "df = %s. Use ci_type = \"normal\", collapse lonely strata, or pass `df`."),
                   if (is.null(df)) "NULL" else as.character(df)), call. = FALSE)
    stats::qt(1 - a, df)
  } else stats::qnorm(1 - a)
  z <- crit
  theta_hat <- statistic(jack$weights, jack$data)
  thetas    <- apply(jack$replicates, 2L, function(w) statistic(w, jack$data))
  strat <- jack$rep_stratum

  jkn_var <- function(th, nh_vec) {                 # th: numeric over replicates
    good <- is.finite(th)
    V <- 0
    for (h in unique(strat[good])) {
      sel <- strat == h & good
      m   <- sum(sel)
      if (m < 2L) next
      nh  <- nh_vec[which(sel)[1]]
      # If some of the nh delete-a-PSU replicates in this stratum failed, the sum
      # runs over m < nh terms; scaling (nh-1)/nh up by nh/m (i.e. (nh-1)/m) makes
      # the partial sum still estimate the full stratum contribution, instead of
      # biasing the variance low.
      V  <- V + (nh - 1) / m * sum((th[sel] - mean(th[sel]))^2)
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
jack_total <- function(jack, variable) {
  variable <- .wf_var(variable, jack)
  jackknife_estimate(jack, function(w, d)
    if (anyNA(w)) NA_real_ else sum(w * d[[variable]], na.rm = TRUE))
}

#' @rdname jackknife_estimate
#' @export
jack_mean <- function(jack, variable) {
  variable <- .wf_var(variable, jack)
  jackknife_estimate(jack, function(w, d) {
    x <- d[[variable]]; ok <- !is.na(x) & .wf_active(w)   # keep active negatives, as totals do
    sum(w[ok] * x[ok]) / sum(w[ok])
  })
}

#' Export weightflow weights to a survey design
#'
#' `as_svydesign()` builds a linearization (ultimate-cluster) `survey.design`
#' from a prepped recipe, treating the final weights as fixed constants.
#' `as_svrepdesign()` builds a replicate-weights `svyrep.design` from a
#' [bootstrap_weights()] or [jackknife_weights()] object. Both are the bridge to
#' the `survey` package, and therefore to `svytotal()`, `svymean()`, `svyratio()`,
#' `svyby()`, `svyglm()` and domain estimation generally.
#'
#' Only `as_svrepdesign()` propagates the variability of the weighting adjustments
#' (nonresponse, calibration, ...), because each replicate re-runs the whole
#' recipe. `as_svydesign()` is design-based linearization on the *fixed* final
#' weights: its standard errors reflect the sampling design but treat the
#' adjustments as known without error, so they are usually smaller. Use
#' `as_svrepdesign()` (with `bootstrap_weights()` / `jackknife_weights()`) when
#' the adjustment variability should be included.
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
  # Keep the same active set the rest of the package uses (negatives are active;
  # only 0 / non-finite are dropped), so svytotal reproduces sum(w * y).
  wcol <- df[[weight_name]]
  keep <- .wf_active(wcol)
  if (any(wcol[keep] < 0))
    warning(sprintf(paste0("%d negative weight(s) are included in the survey design; ",
                           "survey variance formulas assume positive weights."),
                    sum(wcol[keep] < 0)), call. = FALSE)
  df <- df[keep, , drop = FALSE]                             # drop inactive units
  # accept either a bare column name (string) or a formula; build a safe formula
  f  <- function(v) if (inherits(v, "formula")) v else stats::reformulate(v)
  survey::svydesign(ids = f(ids), strata = if (is.null(strata)) NULL else f(strata),
                    weights = f(weight_name), data = df, nest = TRUE, ...)
}

#' @rdname as_svydesign
#' @export
as_svrepdesign <- function(object, ...) {
  if (!requireNamespace("survey", quietly = TRUE))
    stop("Install the 'survey' package to use as_svrepdesign().")
  keep <- .wf_active(object$weights)   # keep negatives (active); drop 0 / non-finite
  if (any(object$weights[keep] < 0))
    warning(sprintf(paste0("%d negative weight(s) are included in the survey design; ",
                           "survey variance formulas assume positive weights."),
                    sum(object$weights[keep] < 0)), call. = FALSE)
  rw    <- object$replicates[keep, , drop = FALSE]
  valid <- which(!apply(rw, 2, anyNA))              # drop failed replicates (NA columns)
  ndrop <- ncol(rw) - length(valid)
  if (!length(valid))
    stop("All replicates have NA weights (every replicate failed); cannot build a ",
         "replicate design.")
  if (ndrop > 0L)
    warning(sprintf(paste0("%d failed replicate(s) with NA weights were dropped ",
                           "from the survey design; the scale is set to 1/%d valid ",
                           "replicates."), ndrop, length(valid)), call. = FALSE)
  rw <- rw[, valid, drop = FALSE]
  Rv <- length(valid)
  if (inherits(object, "weightflow_boot")) {
    survey::svrepdesign(
      data = object$data[keep, , drop = FALSE],
      weights = object$weights[keep],
      repweights = rw,
      type = "bootstrap", combined.weights = TRUE,
      scale = 1 / Rv, rscales = rep(1, Rv), mse = TRUE, ...)
  } else if (inherits(object, "weightflow_jack")) {
    # delete-a-PSU jackknife: full (combined) replicate weights; survey centers at
    # the point estimate (mse = TRUE). When some replicates failed, the per-replicate
    # scale must be (n_h - 1)/m_h with m_h the SURVIVING replicates in the stratum,
    # not (n_h - 1)/n_h -- otherwise survey sums m_h < n_h terms with the full-n_h
    # scale and biases the variance low (matches jackknife_estimate()'s correction).
    strat_v <- object$rep_stratum[valid]
    nh_v    <- object$rep_nh[valid]
    mh_v    <- stats::ave(seq_along(strat_v), strat_v, FUN = length)  # survivors per stratum
    rsc     <- (nh_v - 1) / mh_v
    rsc[mh_v < 2L] <- 0          # a stratum reduced to <2 replicates contributes no variance
    survey::svrepdesign(
      data = object$data[keep, , drop = FALSE],
      weights = object$weights[keep],
      repweights = rw,
      type = "other", combined.weights = TRUE,
      scale = 1, rscales = rsc,
      mse = TRUE, ...)
  } else {
    stop("`object` must be a weightflow_boot or weightflow_jack object.")
  }
}

#' Collect replicate weights into a data frame ready for srvyr
#'
#' Returns the data with the point weight and every replicate weight as ordinary
#' columns, plus the replication design as attributes. This is the form
#' `srvyr::as_survey_rep()` and `survey::svrepdesign()` expect, and the form to
#' write out when the analysis continues in another session, another script or
#' another language.
#'
#' @param object a `weightflow_boot` or `weightflow_jack` object.
#' @param weight_name name of the point-weight column to add.
#' @param prefix prefix for the replicate-weight columns (`rep_1`, `rep_2`, ...).
#' @param drop_zero keep only active units (point weight > 0).
#' @return A data frame: the original columns, `weight_name`, and one column per
#'   replicate. The number of replicates is in attribute `"R"`, and the
#'   replication design in attributes `"type"`, `"scale"` and `"rscales"`.
#' @examples
#' spec <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_calibrate(method = "raking",
#'                  margins = list(region = c(table(population$region))))
#' boot <- bootstrap_weights(spec, replicates = 30, strata = "region",
#'                           psu = "psu", seed = 1, progress = FALSE)
#' df <- collect_replicate_weights(boot)   # or a weightflow_jack object
#' \donttest{
#' if (requireNamespace("srvyr", quietly = TRUE) &&
#'     requireNamespace("dplyr", quietly = TRUE)) {
#'   srvyr::as_survey_rep(df, weights = .weight,
#'                        repweights = dplyr::starts_with("rep_"),
#'                        type = attr(df, "type"), combined.weights = TRUE,
#'                        scale = attr(df, "scale"), rscales = attr(df, "rscales"),
#'                        mse = TRUE)
#' }
#' }
#' @export
collect_replicate_weights <- function(object, weight_name = ".weight",
                                      prefix = "rep_", drop_zero = TRUE) {
  if (!inherits(object, c("weightflow_boot", "weightflow_jack")))
    stop("`object` must be a weightflow_boot or weightflow_jack object.")
  weight_name <- .wf_outname(weight_name, "weight_name")
  prefix      <- .wf_outname(prefix, "prefix")
  # Keep active units: finite and non-zero. Negative weights (a valid unbounded
  # linear-calibration output) are ACTIVE and are kept, matching as_svrepdesign()
  # and the totals estimators; only weight 0 / non-finite are dropped.
  keep <- if (drop_zero) .wf_active(object$weights) else rep(TRUE, length(object$weights))
  out  <- object$data[keep, , drop = FALSE]
  reps <- object$replicates[keep, , drop = FALSE]
  # Drop failed replicates (all-NA columns) so downstream survey / srvyr does not
  # return NA standard errors, and keep scale / rscales / R consistent with the
  # survivors. Same rule (and message) as as_svrepdesign().
  valid <- which(!apply(reps, 2, anyNA))
  ndrop <- ncol(reps) - length(valid)
  if (!length(valid))
    stop("All replicates have NA weights (every replicate failed); cannot build ",
         "replicate weights.", call. = FALSE)
  if (ndrop > 0L)
    warning(sprintf(paste0("%d failed replicate(s) with NA weights were dropped; ",
                           "the replicate design now uses %d valid replicate(s)."),
                    ndrop, length(valid)), call. = FALSE)
  reps <- reps[, valid, drop = FALSE]
  colnames(reps) <- paste0(prefix, seq_len(ncol(reps)))
  # N-19 sibling: warn if the point-weight column overwrites an existing one
  # (collect_weights() already does this).
  if (weight_name %in% names(out))
    warning(sprintf("Column `%s` already exists and will be overwritten.", weight_name),
            call. = FALSE)
  out[[weight_name]] <- object$weights[keep]
  # N-25: refuse to create duplicate column names. If the data already carries
  # columns matching the replicate prefix (e.g. a stray `rep_1`), cbind() would
  # produce two `rep_1` columns and the documented starts_with("rep_") flow would
  # silently pick the wrong one.
  clash <- intersect(colnames(reps), names(out))
  if (length(clash))
    stop(sprintf(paste0("The data already has column(s) %s, which collide with the ",
                        "replicate columns produced by prefix = \"%s\". Pass a different ",
                        "`prefix` (or rename those columns) before collecting."),
                 paste(sQuote(clash), collapse = ", "), prefix), call. = FALSE)
  out <- cbind(out, as.data.frame(reps))
  rownames(out) <- NULL
  attr(out, "R") <- length(valid)
  # Replication design for survey/srvyr, correct per method: the bootstrap uses
  # scale 1/R with unit rscales; the delete-a-PSU jackknife uses scale 1 with
  # per-replicate rscales (n_h - 1)/m_h, where m_h is the SURVIVING replicates in
  # the stratum (= n_h when none failed), so dropping a failed replicate does not
  # bias the variance low -- consistent with jackknife_estimate() and as_svrepdesign().
  if (inherits(object, "weightflow_jack")) {
    strat_v <- object$rep_stratum[valid]
    nh_v    <- object$rep_nh[valid]
    mh_v    <- stats::ave(seq_along(strat_v), strat_v, FUN = length)
    rsc     <- (nh_v - 1) / mh_v
    rsc[mh_v < 2L] <- 0
    attr(out, "type")    <- "other"
    attr(out, "scale")   <- 1
    attr(out, "rscales") <- rsc
  } else {
    attr(out, "type")    <- "bootstrap"
    attr(out, "scale")   <- 1 / length(valid)
    attr(out, "rscales") <- rep(1, length(valid))
  }
  out
}
