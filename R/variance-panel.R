# Coordinated bootstrap for panel change (the heart of the panel-variance work).
# SELF-CONTAINED on purpose: it copies the ~5-line Rao-Wu draw and re-runs the recipe
# through the PUBLIC prep(), so it does NOT touch R/variance.R (frozen, CRAN, guarded by
# test-blindaje-bootstrap-firewall.R). Validated by Monte Carlo (see
# weightflow_pruebas/prototipo_bootstrap_coordinado.py): the coordinated bootstrap
# recovers Var(change); the naive independent one over-estimates it up to ~11x.
#
# v1 ("permanent"): each PSU carries permanent uniforms u[psu, b]; in each wave the
# Rao-Wu count is the Binomial(m_h, 1/n_h) quantile of that uniform, so SHARED PSUs
# (same id across waves) reuse the same uniform and their resampling is correlated ->
# the covariance of the change emerges from the replicates. For ratio-type estimands
# (rates, proportions, means) this matches the exact multinomial bootstrap; totals may
# want the exact variant (future v2).

# ---------------------------------------------------------------------------
# refit_steps: which recipe steps are re-run per replicate. This is what makes the
# engine a SUPERSET of the world's NSOs on the "what is refit" axis. Our honest
# default re-preps the WHOLE recipe (refit_steps = "all"); Statistics Canada's LFS
# freezes the household subweights and re-runs ONLY the composite calibration
# (refit_steps = "calibration"), which this reproduces. The literature endorses the
# honest default: Roberts, Kovacevic, Mantel & Phillips (2001) state nonresponse and
# calibration SHOULD be re-applied to each replicate; StatCan's calibration-only is a
# documented cost simplification. Uses only the PUBLIC prep(); variance.R untouched.
#
# Mechanism: split the recipe at the FIRST step whose class is in refit_steps. The
# prefix (frozen) is run once on the point sample; the perturbation (Rao-Wu / delete)
# enters at that frozen pre-weight; the suffix is re-prepped per replicate. This
# matches StatCan exactly (factor applied to the subweight, then re-calibrate).
.wf_refit_alias <- function(refit_steps) {
  if (identical(refit_steps, "all")) return("all")
  out <- unlist(lapply(refit_steps, function(x)
    if (identical(x, "calibration"))
      c("step_calibrate", "step_model_calibration", "step_cre") else x),
    use.names = FALSE)
  unique(out)
}

# Split a spec into a frozen prefix + a refit suffix. Returns the point weights (full
# recipe, always), the pre-weight feeding the first refit step, and a suffix spec whose
# base column is a placeholder overwritten with (pre-weight x replicate factor).
.wf_freeze_split <- function(sp, refit_steps) {
  refit_steps <- .wf_refit_alias(refit_steps)
  full  <- prep(sp)
  point <- full$final_weight
  steps <- sp$steps
  if (identical(refit_steps, "all") || length(steps) == 0L)
    return(list(point = point, w_pre = sp$data[[sp$base_weights]],
                spec = sp, base = sp$base_weights, k0 = 1L))
  hit <- vapply(steps, function(s) any(inherits(s, refit_steps)), logical(1))
  if (!any(hit))
    stop(sprintf(paste0("refit_steps = {%s} matches no step in the recipe (step classes: ",
                        "%s). Use \"all\", \"calibration\", or a step class present here."),
                 paste(refit_steps, collapse = ", "),
                 paste(unique(vapply(steps, function(s) class(s)[1], character(1))),
                       collapse = ", ")), call. = FALSE)
  k0    <- which(hit)[1]
  w_pre <- full$history[[k0]]                       # weight feeding step k0 (history[[1]] = base)
  spb   <- sp
  spb$steps        <- steps[k0:length(steps)]
  spb$base_weights <- ".wf_refit_base"
  spb$data[[".wf_refit_base"]] <- w_pre             # placeholder; set per replicate
  list(point = point, w_pre = w_pre, spec = spb, base = ".wf_refit_base", k0 = k0)
}

# --- coordinated Zhat* for the composite (CRE) estimator --------------------
# step_cre reads only two things from `previous`: its final_weight (to estimate
# the previous-wave composite totals Zhat) and its data. To make Zhat vary per
# bootstrap replicate -- so the reported variance includes the sampling variance
# of the estimated control totals, not just of the current calibration -- we swap
# the frozen point weights of `previous` for the PREVIOUS WAVE'S replicate-b
# weights. Because both waves share the PSU-keyed uniforms, replicate b is the
# same resampling in both waves, so the overlap correlation is preserved. This is
# orthogonal to refit_steps: it only rewrites `previous$final_weight` on whatever
# step_cre lands in the re-prepped suffix. Chain assumption: a wave's step_cre
# `previous` is the immediately preceding wave in `specs`; the length guard skips
# injection (leaving the fixed point `previous`) when they do not align.
.wf_cre_inject_prev <- function(spec, w_prev) {
  if (is.null(w_prev)) return(spec)
  for (j in seq_along(spec$steps)) {
    s <- spec$steps[[j]]
    if (!inherits(s, "step_cre") || is.null(s$previous)) next
    pd <- s$previous$data
    if (is.null(pd) || nrow(pd) != length(w_prev)) next   # not the aligned wave: keep fixed
    spec$steps[[j]]$previous$final_weight <- w_prev
  }
  spec
}

# Injection alignment is a property of the recipe + the previous wave's size, not of any
# one replicate (the length guard in .wf_cre_inject_prev decides the same way for every b).
# So classify it ONCE per wave: how many step_cre would receive the coordinated Zhat*
# (`injected`) vs be silently left at their fixed point `previous` (`skipped`). A skip means
# the reported variance treats Zhat as fixed -> anticonservative, the exact error this
# module exists to avoid, so wave_bootstrap()/wave_jackknife() warn and expose the counts.
.wf_cre_inject_status <- function(spec, w_prev_len) {
  injected <- 0L; skipped <- 0L
  for (s in spec$steps) {
    if (!inherits(s, "step_cre") || is.null(s$previous)) next
    pd <- s$previous$data
    if (!is.null(pd) && !is.null(w_prev_len) && nrow(pd) == w_prev_len) injected <- injected + 1L
    else skipped <- skipped + 1L
  }
  list(injected = injected, skipped = skipped)
}

# Rao-Wu resample counts for one stratum: an (nh x R) matrix of how many times each PSU
# is drawn. "multinom" (default): an EXACT multinomial (colSums == mh) via sequential
# conditional binomials on the shared per-PSU uniforms; this is the centred Rao-Wu draw.
# "binom" (legacy): independent qbinom per PSU on the same uniforms -- the marginal is
# correct but colSums != mh, so it loses the multinomial's negative between-PSU covariance
# and estimates an UNCENTRED Var = sum(z_k^2) instead of n_h/(n_h-1) sum((z-zbar)^2). For a
# self-centring estimand (a ratio or mean) the difference is small (~+8-10%); for a TOTAL it
# overestimates the variance badly (up to an order of magnitude). Prefer "multinom" for
# totals. NB: the multinomial coordinates across rotating waves only approximately (each
# conditional depends on the stratum's PSU set; the first PSU coordinates exactly, later
# ones drift).
.wf_rao_wu_counts <- function(Uph, mh, nh, resample) {
  if (resample == "binom" || nh < 2L)
    return(matrix(stats::qbinom(Uph, mh, 1 / nh), nrow = nh))
  cnt <- matrix(0, nrow = nh, ncol = ncol(Uph)); rem <- rep(mh, ncol(Uph))
  for (i in seq_len(nh - 1L)) {
    ci <- stats::qbinom(Uph[i, ], rem, 1 / (nh - i + 1L))
    cnt[i, ] <- ci; rem <- rem - ci
  }
  cnt[nh, ] <- rem
  cnt
}

# Confidence-interval multiplier for the panel estimators: z (normal, default) or Student t
# with `df` degrees of freedom. With few PSUs the normal interval is too narrow, so `"t"`
# uses the design df (total PSUs minus strata) stored on the coordinated object. (VAR-14)
.wf_panel_cimult <- function(level, ci_type, df) {
  a <- 1 - (1 - level) / 2
  if (identical(ci_type, "t") && !is.null(df) && is.finite(df) && df >= 1)
    stats::qt(a, df) else stats::qnorm(a)
}

#' Coordinated bootstrap across panel waves
#'
#' Builds recipe-aware bootstrap replicate weights for two or more waves that are
#' **coordinated** by PSU: a PSU present in several waves gets the same resampling in
#' all of them, so the sampling covariance between waves -- which the overlap of a
#' rotating panel induces -- is captured. Feed the result to [change_estimate()] for the
#' honest variance of a net change. Ignoring the coordination (a separate per-wave
#' bootstrap) over-estimates the variance of change whenever the waves overlap and are
#' correlated.
#'
#' Self-contained: it does not modify [bootstrap_weights()]; each wave's recipe is
#' re-run through [prep()] on perturbed base weights, exactly as the single-sample
#' bootstrap does, but with a PSU-coordinated Rao-Wu draw shared across waves.
#'
#' Composite (CRE) recursion is handled automatically: when a wave's recipe holds a
#' [step_cre()] whose `previous` is the preceding wave, that wave's estimated control
#' totals `Zhat*` are re-estimated per replicate from the previous wave's replicate-b
#' weights (not the frozen point weights), so the reported variance includes the
#' sampling variance of `Zhat` itself. Waves are processed in order and each wave's
#' replicate matrix is carried into the next, giving the full coordinated variance of
#' the recursive estimator. (Assumes each `step_cre`'s `previous` is the immediately
#' preceding wave in `specs`; otherwise that step keeps its fixed point `previous`.)
#'
#' @param specs a **named** list of `weighting_spec` objects, one per wave; the names are
#'   the wave labels used by [change_estimate()].
#' @param replicates number of bootstrap replicates.
#' @param strata,psu column names of the design strata and PSU, present in every wave's
#'   data. The PSU id must be **consistent across waves** (the same value = the same PSU):
#'   that consistency is what makes the coordination possible. `strata = NULL` treats the
#'   whole sample as one stratum; `psu = NULL` treats each row as its own PSU.
#' @param m optional PSU resample size per stratum (default `n_h - 1`, the Rao-Wu choice).
#' @param seed optional integer seed for the permanent uniforms (reproducibility).
#' @param refit_steps which recipe steps to re-run per replicate. `"all"` (default, the
#'   honest recipe-aware bootstrap) re-preps the whole recipe, propagating the variance of
#'   every step. `"calibration"` freezes everything up to the first calibration step and
#'   re-runs only calibration per replicate -- the Statistics Canada LFS convention (the
#'   Rao-Wu factor is applied to the frozen pre-calibration subweight). A character vector
#'   of step classes (e.g. `c("step_nonresponse", "step_calibrate")`) splits at the first
#'   one matched: the prefix is frozen, the suffix re-prepped. The point estimate always
#'   uses the full recipe; only the replicate variance is affected.
#' @param resample the Rao-Wu resample scheme. `"multinom"` (default) draws an exact
#'   multinomial per stratum (counts sum to `m_h`), the centred Rao-Wu draw, which gives an
#'   unbiased replicate variance for composite/calibration estimators and for totals;
#'   `"binom"` (legacy) draws an independent binomial per PSU (counts need not sum to
#'   `m_h`), which loses the multinomial's negative between-PSU covariance and estimates an
#'   uncentred variance -- only mildly high for a ratio or mean (~+8-10%) but a large
#'   overestimate for a **total** (up to an order of magnitude), so use `"multinom"` when
#'   estimating totals. Both
#'   share the per-PSU uniforms; the multinomial coordinates across rotating waves exactly
#'   when the PSU sets match (identical or disjoint waves) and approximately otherwise.
#' @param progress show a progress message per wave.
#' @return an object of class `weightflow_wave_boot`: per-wave point weights, replicate
#'   matrices (aligned by replicate index across waves), the per-wave data, and the design.
#' @seealso [change_estimate()], [bootstrap_weights()], [panel_design()]
#' @examples
#' \donttest{
#' t1 <- subset(panel_ine, ola == 1 & disp == "R")
#' t2 <- subset(panel_ine, ola == 2 & disp == "R")
#' wb <- wave_bootstrap(
#'   list(T1 = weighting_spec(t1, base_weights = w_base),
#'        T2 = weighting_spec(t2, base_weights = w_base)),
#'   replicates = 200, strata = "estrato", psu = "psu", seed = 1, progress = FALSE)
#' change_estimate(wb, function(w, d) weighted.mean(d$desocupado, w, na.rm = TRUE))
#' }
#' @export
wave_bootstrap <- function(specs, replicates = 500L, strata = NULL, psu = NULL,
                           m = NULL, seed = NULL, refit_steps = "all",
                           resample = c("multinom", "binom"), progress = TRUE) {
  resample <- match.arg(resample)
  if (!is.list(specs) || is.null(names(specs)) || any(!nzchar(names(specs))) ||
      length(specs) < 2L)
    stop("`specs` must be a NAMED list of at least 2 weighting_spec objects (one per wave).",
         call. = FALSE)
  if (!all(vapply(specs, inherits, logical(1), "weighting_spec")))
    stop("Every element of `specs` must be a weighting_spec.", call. = FALSE)
  for (s in specs)
    if (any(vapply(s$steps, inherits, logical(1), "step_subsample")))
      stop("wave_bootstrap() does not support step_subsample() (two-phase) recipes: the ",
           "two-phase factor replaces the Rao-Wu draw and does not compose with the ",
           "coordination.", call. = FALSE)
  R <- as.integer(replicates)
  if (is.na(R) || R < 2L) stop("`replicates` must be >= 2.", call. = FALSE)
  if (is.null(psu))
    warning("wave_bootstrap: `psu = NULL` makes each ROW its own PSU and coordinates waves ",
            "BY POSITION -- row i of one wave is treated as the same PSU as row i of another, ",
            "which is only correct if the waves are row-aligned to the same units. Pass a ",
            "`psu` column consistent across waves for the overlap covariance to be real.",
            call. = FALSE)

  # --- permanent uniforms, keyed by PSU id across the union of all waves ---
  # Nest the PSU id within its stratum: published microdata often RESTART PSU ids at 1 in
  # each stratum, so a bare id would collapse "psu 1" of stratum A with "psu 1" of stratum B
  # into one unit (anticonservative). A physical PSU belongs to one stratum, so (stratum, id)
  # is a stable identity across waves; when ids are already unique this is a no-op. (VAR-09)
  psu_of <- function(sp) {
    p <- if (is.null(psu)) paste0(".row", seq_len(nrow(sp$data))) else as.character(sp$data[[psu]])
    if (is.null(strata)) p else paste(as.character(sp$data[[strata]]), p, sep = "\r")
  }
  union_psu <- unique(unlist(lapply(specs, psu_of), use.names = FALSE))
  # Restore the caller's RNG state on exit: set.seed() here would otherwise leave the global
  # stream advanced, so an unrelated random draw after wave_bootstrap() would differ (the
  # single-sample bootstrap already does this). (VAR-10)
  if (!is.null(seed)) {
    if (exists(".Random.seed", envir = .GlobalEnv)) {
      old_seed <- get(".Random.seed", envir = .GlobalEnv)
      on.exit(assign(".Random.seed", old_seed, envir = .GlobalEnv), add = TRUE)
    } else {
      on.exit(if (exists(".Random.seed", envir = .GlobalEnv))
                rm(".Random.seed", envir = .GlobalEnv), add = TRUE)
    }
    set.seed(as.integer(seed))
  }
  U <- matrix(stats::runif(length(union_psu) * R), nrow = length(union_psu),
              dimnames = list(union_psu, NULL))

  one_wave <- function(sp, label, prev_reps = NULL) {
    if (progress) message("wave_bootstrap: '", label, "' (", R, " replicates)")
    if (!is.null(strata) && !strata %in% names(sp$data))
      stop(sprintf("`strata` column '%s' not in wave '%s'.", strata, label), call. = FALSE)
    if (!is.null(psu) && !psu %in% names(sp$data))
      stop(sprintf("`psu` column '%s' not in wave '%s'.", psu, label), call. = FALSE)
    n    <- nrow(sp$data)
    fr   <- .wf_freeze_split(sp, refit_steps)           # point weights + frozen-prefix split
    pw   <- fr$point                                    # point weights (FULL recipe, always)
    w_pre <- fr$w_pre                                   # weight the perturbation enters at
    ps   <- psu_of(sp)
    st   <- if (is.null(strata)) rep("1", n) else as.character(sp$data[[strata]])
    # SORT the unique PSUs: the exact multinomial draws the per-stratum counts by sequential
    # conditional binomials in PSU order, so an unsorted `unique()` (order of row appearance)
    # would make the coordination between waves depend on the incidental row order of each
    # wave's file. Sorting fixes a canonical order shared by both waves. (VAR-01)
    upsu <- sort(unique(ps))
    psu_str <- st[match(upsu, ps)]                      # stratum of each PSU (first row)
    # lambda per unique PSU x replicate (Rao-Wu; f = 0, with-replacement)
    Lam <- matrix(1, nrow = length(upsu), ncol = R, dimnames = list(upsu, NULL))
    for (h in unique(st)) {
      ph <- upsu[psu_str == h]; nh <- length(ph)
      if (nh < 2L) next                                 # singleton stratum -> lambda 1
      mh  <- if (is.null(m)) nh - 1L else min(as.integer(m), nh - 1L)
      cnt <- .wf_rao_wu_counts(U[ph, , drop = FALSE], mh, nh, resample)
      a   <- sqrt(mh / (nh - 1))
      Lam[ph, ] <- 1 - a + a * (nh / mh) * cnt
    }
    ridx <- match(ps, upsu)                             # row -> PSU index into Lam
    # Classify the coordinated-Zhat* injection once (deterministic across replicates) and
    # warn if any step_cre is left un-injected (fixed Zhat -> anticonservative variance).
    inj <- if (is.null(prev_reps)) list(injected = 0L, skipped = 0L)
           else .wf_cre_inject_status(fr$spec, nrow(prev_reps))
    if (inj$skipped > 0L)
      warning(sprintf(paste0(
        "wave_bootstrap: wave '%s' has %d step_cre whose `previous` did not align with the ",
        "preceding wave (row-count mismatch); its Zhat* is held FIXED, so the change variance ",
        "for it is anticonservative. Ensure each step_cre's `previous` is the immediately ",
        "preceding wave in `specs`."), label, inj$skipped), call. = FALSE)
    reps <- vapply(seq_len(R), function(b) {
      spb <- fr$spec; spb$data[[fr$base]] <- w_pre * Lam[ridx, b]   # perturb, re-prep suffix
      attr(spb$data, "wf_replicate")     <- TRUE   # step_assert -> no-op in replicates (VAR-06)
      attr(spb$data, "wf_replicate_idx") <- b      # pairs with a reference_sample() replicate (VAR-03)
      # coordinated Zhat*: feed the previous wave's replicate-b weights into step_cre
      spb <- .wf_cre_inject_prev(spb, if (is.null(prev_reps)) NULL else prev_reps[, b])
      tryCatch(prep(spb)$final_weight, error = function(e) rep(NA_real_, n))
    }, numeric(n))
    list(point = pw, replicates = reps, data = sp$data,
         n_injected = inj$injected, n_skipped = inj$skipped)
  }

  # Process waves in order, carrying each wave's replicate matrix forward so the
  # next wave's step_cre estimates Zhat* from the SAME replicate (chain recursion).
  out <- vector("list", length(specs)); names(out) <- names(specs)
  prev_reps <- NULL
  for (i in seq_along(specs)) {
    out[[i]]  <- one_wave(specs[[i]], names(specs)[i], prev_reps)
    prev_reps <- out[[i]]$replicates
  }
  # design df for a Student-t interval: total (nested) PSUs minus strata (VAR-14)
  n_strata <- if (is.null(strata)) 1L else
    length(unique(unlist(lapply(specs, function(sp) as.character(sp$data[[strata]])),
                         use.names = FALSE)))
  structure(list(
    waves      = names(specs),
    point      = lapply(out, `[[`, "point"),
    reps       = lapply(out, `[[`, "replicates"),
    data       = lapply(out, `[[`, "data"),
    n_cre_injected = sum(vapply(out, function(o) o$n_injected %||% 0L, integer(1))),
    n_cre_skipped  = sum(vapply(out, function(o) o$n_skipped  %||% 0L, integer(1))),
    df = max(length(union_psu) - n_strata, 1L),
    R = R, strata = strata, psu = psu, seed = seed, refit_steps = refit_steps),
    class = "weightflow_wave_boot")
}

#' @export
print.weightflow_wave_boot <- function(x, ...) {
  cat("<weightflow coordinated bootstrap>\n")
  cat(sprintf("  waves      : %d (%s)\n", length(x$waves), paste(x$waves, collapse = ", ")))
  cat(sprintf("  replicates : %d\n", x$R))
  cat(sprintf("  psu / strata: %s / %s\n",
              if (is.null(x$psu)) "(unit-level)" else x$psu,
              if (is.null(x$strata)) "(none)" else x$strata))
  cat(sprintf("  refit_steps : %s%s\n", paste(x$refit_steps %||% "all", collapse = ", "),
              if (identical(x$refit_steps, "calibration")) "  (StatCan LFS convention)" else
              if (!identical(x$refit_steps %||% "all", "all")) "" else "  (full recipe-aware)"))
  if ((x$n_cre_injected %||% 0L) + (x$n_cre_skipped %||% 0L) > 0L)
    cat(sprintf("  CRE Zhat*   : %d injected%s\n", x$n_cre_injected %||% 0L,
                if ((x$n_cre_skipped %||% 0L) > 0L)
                  sprintf(", %d SKIPPED (fixed Zhat -> anticonservative)", x$n_cre_skipped)
                else ""))
  invisible(x)
}

#' Net change between two panel waves, with honest variance
#'
#' Estimates a net change (a statistic in wave 2 minus the same statistic in wave 1) from a
#' [wave_bootstrap()], decomposing its variance into `V1`, `V2` and the sampling covariance
#' the overlap induces: `V = V1 + V2 - 2*Cov`. Because the bootstrap replicates are
#' coordinated by PSU, `Cov` emerges from them -- no analytic covariance formula. Reports
#' the correlation `rho` and `deff_change = V / (V1 + V2)`, i.e. how much the overlap
#' lowered the variance of the change relative to treating the waves as independent.
#'
#' @param wb a `weightflow_wave_boot` from [wave_bootstrap()].
#' @param statistic a function `function(w, data)` returning a single number, evaluated on
#'   each wave's weights and data (e.g. `function(w, d) weighted.mean(d$y, w)`).
#' @param waves optional length-2 character vector naming the two waves (defaults to the
#'   first two).
#' @param level confidence level for the interval.
#' @param type `"absolute"` (default) for the net change `theta2 - theta1`, or `"relative"`
#'   for the relative change `theta2 / theta1 - 1` (e.g. the percent change of a rate). The
#'   relative change's variance comes from the coordinated replicate distribution of the
#'   ratio (bootstrap) or the delta method on the level pieces (jackknife), so the overlap
#'   covariance is captured either way. `V1`, `V2`, `cov`, `rho` always describe the levels.
#' @param by optional name of a grouping column present in both waves: returns one change
#'   per domain (a `weightflow_change_by` table) instead of a single change.
#' @param ci_type interval type: `"normal"` (default, z-based), `"t"` (Student t with `df`
#'   degrees of freedom, wider and safer with few PSUs) or `"percentile"` (bootstrap only).
#' @param df degrees of freedom for the `"t"` interval; `NULL` (default) uses the design df
#'   stored on the object (total PSUs minus strata).
#' @return an object of class `weightflow_change` with the estimate, `se`, `V`, `V1`, `V2`,
#'   `Vind = V1 + V2`, `cov`, `rho`, `deff_change` and the confidence interval; or, with
#'   `by=`, a `weightflow_change_by` holding one row per domain.
#' @seealso [wave_bootstrap()], [change_mean()], [change_total()], [level_estimate()]
#' @export
change_estimate <- function(wb, statistic, waves = NULL, level = 0.95,
                            type = c("absolute", "relative"), by = NULL,
                            ci_type = c("normal", "t", "percentile"), df = NULL) {
  type <- match.arg(type)
  ci_type <- match.arg(ci_type)
  if (inherits(wb, "weightflow_wave_jack"))
    return(.change_estimate_jack(wb, statistic, waves, level, type, by, ci_type, df))
  if (!inherits(wb, "weightflow_wave_boot"))
    stop("`wb` must come from wave_bootstrap() or wave_jackknife().", call. = FALSE)
  wv <- if (is.null(waves)) wb$waves[1:2] else as.character(waves)
  if (length(wv) != 2L || !all(wv %in% wb$waves))
    stop("`waves` must name two waves present in `wb`.", call. = FALSE)
  if (!is.null(by)) return(.change_by(wb, statistic, wv, level, type, by, ci_type, df))

  one <- function(wave) {
    W <- wb$reps[[wave]]; d <- wb$data[[wave]]
    hat <- statistic(wb$point[[wave]], d)
    b   <- vapply(seq_len(ncol(W)), function(j) {
      w <- W[, j]; if (anyNA(w)) NA_real_ else as.numeric(statistic(w, d))
    }, numeric(1))
    list(hat = as.numeric(hat), b = b)
  }
  t1 <- one(wv[1]); t2 <- one(wv[2])
  if (!is.finite(t1$hat) || !is.finite(t2$hat))
    stop("The statistic is NA on the full sample of a wave. A survey variable is often ",
         "structurally missing (e.g. `desocupado` is NA outside the labour force), and ",
         "weighted.mean() propagates it -- restrict the data to the estimand's domain, or ",
         "use the estimation grammar's mean()/total() (which drop NA).", call. = FALSE)
  good <- is.finite(t1$b) & is.finite(t2$b)
  if (sum(good) < 2L) stop("Too few valid replicates to estimate the change variance.",
                           call. = FALSE)
  # Dropped replicates are NOT missing at random -- the extreme (infeasible-calibration)
  # replicates are exactly the ones that fail -- so a material drop rate biases the variance
  # downward. Warn (audit C5); the object reports the effective R in `$R`.
  if (sum(!good) > 0.05 * length(good))
    warning(sprintf(paste0("change_estimate: %d of %d coordinated replicates (%.0f%%) were ",
                           "non-finite and dropped; the variance uses %d. Failures cluster on ",
                           "extreme replicates, so the SE may be underestimated."),
                    sum(!good), length(good), 100 * mean(!good), sum(good)), call. = FALSE)
  V1  <- mean((t1$b[good] - t1$hat)^2)
  V2  <- mean((t2$b[good] - t2$hat)^2)
  cov <- mean((t1$b[good] - t1$hat) * (t2$b[good] - t2$hat))   # level covariance
  rho <- if (V1 > 0 && V2 > 0) cov / sqrt(V1 * V2) else NA_real_
  if (type == "absolute") { d_hat <- t2$hat - t1$hat;      d_b <- t2$b - t1$b }
  else                    { d_hat <- t2$hat / t1$hat - 1;  d_b <- t2$b / t1$b - 1 }
  V   <- mean((d_b[good] - d_hat)^2)                          # exact replicate variance
  se  <- sqrt(V)
  ci  <- if (ci_type == "percentile")
    stats::quantile(d_b[good], c((1 - level) / 2, 1 - (1 - level) / 2), names = FALSE)
  else d_hat + c(-1, 1) * .wf_panel_cimult(level, ci_type, df %||% wb$df) * se
  structure(list(estimate = d_hat, se = se, V = V, V1 = V1, V2 = V2, Vind = V1 + V2,
                 cov = cov, rho = rho,
                 deff_change = if (type == "absolute" && V1 + V2 > 0) V / (V1 + V2) else NA_real_,
                 ci_lower = ci[1], ci_upper = ci[2], level = level, waves = wv,
                 # the two wave levels the change is built from: the change alone is not
                 # readable without them (+1.7 pp means little until you see 18.4 -> 20.1),
                 # and recomputing them outside would re-run the statistic on both waves.
                 point = stats::setNames(c(t1$hat, t2$hat), wv),
                 type = type, R = sum(good)),
            class = "weightflow_change")
}

# one change per domain -> a weightflow_change_by table (works for boot or jack)
.change_by <- function(wb, statistic, wv, level, type, by, ci_type = "normal", df = NULL) {
  vals <- unique(unlist(lapply(wv, function(w) {
    v <- wb$data[[w]][[by]]; v[!is.na(v)]
  }), use.names = FALSE))
  vals <- sort(vals)
  rows <- lapply(vals, function(dom) {
    stat_dom <- function(w, d) {
      idx <- !is.na(d[[by]]) & d[[by]] == dom
      if (!any(idx)) return(NA_real_)
      as.numeric(statistic(w[idx], d[idx, , drop = FALSE]))
    }
    ch <- tryCatch(change_estimate(wb, stat_dom, waves = wv, level = level, type = type,
                                   ci_type = ci_type, df = df),
                   error = function(e) NULL)
    if (is.null(ch)) return(NULL)
    data.frame(domain = dom, estimate = ch$estimate, se = ch$se,
               ci_lower = ch$ci_lower, ci_upper = ch$ci_upper, rho = ch$rho,
               stringsAsFactors = FALSE)
  })
  tab <- do.call(rbind, rows[!vapply(rows, is.null, logical(1))])
  structure(list(table = tab, by = by, waves = wv, type = type, level = level,
                 method = if (inherits(wb, "weightflow_wave_jack")) "jackknife" else "bootstrap"),
            class = "weightflow_change_by")
}

#' @export
print.weightflow_change_by <- function(x, ...) {
  cat(sprintf("<weightflow %s change by %s%s>\n", x$type, x$by,
              if (identical(x$method, "jackknife")) " [jackknife]" else ""))
  cat(sprintf("  %s -> %s\n", x$waves[1], x$waves[2]))
  tab <- x$table
  tab[] <- lapply(tab, function(c) if (is.numeric(c)) signif(c, 4) else c)
  print(tab, row.names = FALSE)
  invisible(x)
}

#' @rdname change_estimate
#' @param variable name of a numeric variable present in both waves.
#' @export
change_mean <- function(wb, variable, waves = NULL, level = 0.95,
                        type = c("absolute", "relative"), by = NULL) {
  change_estimate(wb, function(w, d) stats::weighted.mean(d[[variable]], w, na.rm = TRUE),
                  waves = waves, level = level, type = match.arg(type), by = by)
}

# ---------------------------------------------------------------------------
# Coordinated delete-one jackknife: the deterministic oracle for the change.
# Deletes the SAME PSU from every wave at once, so a shared PSU perturbs both
# theta1 and theta2 and the covariance of the change is captured with NO
# randomness. Self-contained (only prep()); does not touch R/variance.R.
#
# Exactness: uses the three-term decomposition V(change) = V1 + V2 - 2*Cov with
# PER-WAVE stratified factors (n_h - 1)/n_h. This is EXACT (reproduces the plain
# stratified delete-one jackknife of the per-PSU difference) when the two waves
# share the stratification and the shared PSUs match one-to-one -- in particular
# the FULL-OVERLAP regime, where coordination matters most -- and it is exact in
# the DISJOINT limit (Cov = 0, V = V1 + V2). For partial overlap the shared-PSU
# covariance uses the symmetric factor sqrt(c1_h*c2_h) (= c_h when the per-wave
# stratum sizes agree); there it is a close approximation cross-checked against
# the Monte-Carlo-validated coordinated bootstrap, not claimed bit-exact.
# ---------------------------------------------------------------------------

#' Coordinated delete-one jackknife across panel waves
#'
#' Deterministic counterpart of [wave_bootstrap()]: builds delete-one-PSU replicate
#' weights that are **coordinated** across waves (the same PSU is removed from every
#' wave simultaneously), so the sampling covariance the overlap induces is captured
#' without any randomness. Feed the result to [change_estimate()] for an honest,
#' reproducible variance of a net change. Meant as the cheap exact oracle to validate
#' [wave_bootstrap()]; it is also a valid variance estimator in its own right.
#'
#' Self-contained: each wave's recipe is re-run through [prep()] on base weights with
#' the deleted PSU zeroed and its stratum mates reweighted by \eqn{n_h/(n_h-1)}; it
#' does not modify [bootstrap_weights()] or touch `R/variance.R`.
#'
#' @inheritParams wave_bootstrap
#' @return an object of class `weightflow_wave_jack` accepted by [change_estimate()];
#'   replicate columns are aligned across waves by the union of PSU ids (a PSU absent
#'   from a wave, or alone in its stratum, yields that wave's point weights, i.e. a
#'   zero jackknife contribution).
#' @seealso [wave_bootstrap()], [change_estimate()]
#' @examples
#' \donttest{
#' t1 <- subset(panel_ine, ola == 1 & disp == "R")
#' t2 <- subset(panel_ine, ola == 2 & disp == "R")
#' wj <- wave_jackknife(
#'   list(T1 = weighting_spec(t1, base_weights = w_base),
#'        T2 = weighting_spec(t2, base_weights = w_base)),
#'   strata = "estrato", psu = "psu", progress = FALSE)
#' change_mean(wj, "desocupado")
#' }
#' @param refit_steps which recipe steps to re-run per replicate; see [wave_bootstrap()].
#'   `"all"` (default) re-preps the whole recipe; `"calibration"` freezes the prefix and
#'   re-runs only calibration (StatCan LFS convention).
#' @export
wave_jackknife <- function(specs, strata = NULL, psu = NULL, refit_steps = "all",
                           progress = TRUE) {
  if (!is.list(specs) || is.null(names(specs)) || any(!nzchar(names(specs))) ||
      length(specs) < 2L)
    stop("`specs` must be a NAMED list of at least 2 weighting_spec objects (one per wave).",
         call. = FALSE)
  if (!all(vapply(specs, inherits, logical(1), "weighting_spec")))
    stop("Every element of `specs` must be a weighting_spec.", call. = FALSE)
  for (s in specs)
    if (any(vapply(s$steps, inherits, logical(1), "step_subsample")))
      stop("wave_jackknife() does not support step_subsample() (two-phase) recipes.",
           call. = FALSE)
  if (is.null(psu))
    warning("wave_jackknife: `psu = NULL` makes each ROW its own PSU and coordinates waves ",
            "BY POSITION -- row i of one wave is treated as the same PSU as row i of another, ",
            "which is only correct if the waves are row-aligned to the same units. Pass a ",
            "`psu` column consistent across waves for the overlap covariance to be real.",
            call. = FALSE)

  # Nest the PSU id within its stratum (see wave_bootstrap): PSU ids restarted per stratum
  # would otherwise collapse across strata and understate the variance. (VAR-09)
  psu_of <- function(sp) {
    p <- if (is.null(psu)) paste0(".row", seq_len(nrow(sp$data))) else as.character(sp$data[[psu]])
    if (is.null(strata)) p else paste(as.character(sp$data[[strata]]), p, sep = "\r")
  }
  union_psu <- unique(unlist(lapply(specs, psu_of), use.names = FALSE))
  G <- length(union_psu)

  one_wave <- function(sp, label, prev_reps = NULL) {
    if (progress) message("wave_jackknife: '", label, "' (", G, " delete-one replicates)")
    if (!is.null(strata) && !strata %in% names(sp$data))
      stop(sprintf("`strata` column '%s' not in wave '%s'.", strata, label), call. = FALSE)
    if (!is.null(psu) && !psu %in% names(sp$data))
      stop(sprintf("`psu` column '%s' not in wave '%s'.", psu, label), call. = FALSE)
    n   <- nrow(sp$data)
    fr  <- .wf_freeze_split(sp, refit_steps)        # point weights + frozen-prefix split
    pw  <- fr$point
    w_pre <- fr$w_pre
    ps  <- psu_of(sp)
    st  <- if (is.null(strata)) rep("1", n) else as.character(sp$data[[strata]])
    upsu <- sort(unique(ps))                        # canonical order, invariant to row order (VAR-01)
    psu_str <- st[match(upsu, ps)]
    nh_of   <- table(psu_str)                       # PSUs per stratum, this wave
    # per union PSU: present? stratum? n_h? contributes (present & n_h >= 2)?
    present  <- union_psu %in% upsu
    stratum  <- rep(NA_character_, G); stratum[present]  <- psu_str[match(union_psu[present], upsu)]
    nh       <- rep(NA_integer_,   G); nh[present]       <- as.integer(nh_of[stratum[present]])
    contrib  <- present & !is.na(nh) & nh >= 2L
    inj <- if (is.null(prev_reps)) list(injected = 0L, skipped = 0L)
           else .wf_cre_inject_status(fr$spec, nrow(prev_reps))
    if (inj$skipped > 0L)
      warning(sprintf(paste0(
        "wave_jackknife: wave '%s' has %d step_cre whose `previous` did not align with the ",
        "preceding wave (row-count mismatch); its Zhat* is held FIXED, so the change variance ",
        "for it is anticonservative. Ensure each step_cre's `previous` is the immediately ",
        "preceding wave in `specs`."), label, inj$skipped), call. = FALSE)
    reps <- matrix(pw, nrow = n, ncol = G, dimnames = list(NULL, union_psu))
    for (g in which(contrib)) {
      h    <- stratum[g]; nhh <- nh[g]
      lam  <- rep(1, n)
      inh  <- ps %in% upsu[psu_str == h]            # rows whose PSU is in stratum h
      lam[inh]           <- nhh / (nhh - 1)          # reweight stratum mates
      lam[ps == union_psu[g]] <- 0                   # delete this PSU
      spb <- fr$spec; spb$data[[fr$base]] <- w_pre * lam   # perturb, re-prep suffix
      attr(spb$data, "wf_replicate")     <- TRUE   # step_assert -> no-op in replicates (VAR-06)
      attr(spb$data, "wf_replicate_idx") <- g      # pairs with a reference_sample() replicate (VAR-03)
      # coordinated Zhat*: delete-g weights of the previous wave feed step_cre.
      # jackknife columns are indexed by union_psu, so column g aligns across waves.
      spb <- .wf_cre_inject_prev(spb, if (is.null(prev_reps)) NULL else prev_reps[, g])
      reps[, g] <- tryCatch(prep(spb)$final_weight, error = function(e) rep(NA_real_, n))
    }
    list(point = pw, replicates = reps, data = sp$data,
         present = present, stratum = stratum, nh = nh, contrib = contrib)
  }

  # Sequential across waves so a wave's step_cre re-estimates Zhat* from the SAME
  # delete-one replicate of the previous wave (exact oracle for the recursion).
  out <- vector("list", length(specs)); names(out) <- names(specs)
  prev_reps <- NULL
  for (i in seq_along(specs)) {
    out[[i]]  <- one_wave(specs[[i]], names(specs)[i], prev_reps)
    prev_reps <- out[[i]]$replicates
  }
  n_strata <- if (is.null(strata)) 1L else
    length(unique(unlist(lapply(specs, function(sp) as.character(sp$data[[strata]])),
                         use.names = FALSE)))
  structure(list(
    waves     = names(specs),
    union_psu = union_psu,
    point     = lapply(out, `[[`, "point"),
    reps      = lapply(out, `[[`, "replicates"),
    data      = lapply(out, `[[`, "data"),
    meta      = lapply(out, function(o) o[c("present", "stratum", "nh", "contrib")]),
    df = max(length(union_psu) - n_strata, 1L),                # design df for a t interval (VAR-14)
    strata = strata, psu = psu),
    class = "weightflow_wave_jack")
}

#' @export
print.weightflow_wave_jack <- function(x, ...) {
  cat("<weightflow coordinated jackknife>\n")
  cat(sprintf("  waves       : %d (%s)\n", length(x$waves), paste(x$waves, collapse = ", ")))
  cat(sprintf("  union PSUs  : %d\n", length(x$union_psu)))
  cat(sprintf("  psu / strata: %s / %s\n",
              if (is.null(x$psu)) "(unit-level)" else x$psu,
              if (is.null(x$strata)) "(none)" else x$strata))
  invisible(x)
}

# jackknife variance of the change; shares the reporting object with the bootstrap.
# Relative change uses the delta method on the level pieces (V1, V2, cov); absolute is
# exact (gradient (-1, 1) -> V = V1 + V2 - 2*cov).
.change_estimate_jack <- function(wj, statistic, waves, level, type = "absolute", by = NULL,
                                  ci_type = "normal", df = NULL) {
  wv <- if (is.null(waves)) wj$waves[1:2] else as.character(waves)
  if (length(wv) != 2L || !all(wv %in% wj$waves))
    stop("`waves` must name two waves present in `wj`.", call. = FALSE)
  if (!is.null(by)) return(.change_by(wj, statistic, wv, level, type, by, ci_type, df))
  per <- lapply(wv, function(wave) {
    W <- wj$reps[[wave]]; d <- wj$data[[wave]]; mt <- wj$meta[[wave]]
    hat <- as.numeric(statistic(wj$point[[wave]], d))
    th  <- vapply(seq_len(ncol(W)), function(g) {
      w <- W[, g]; if (anyNA(w)) NA_real_ else as.numeric(statistic(w, d))
    }, numeric(1))                                   # theta_(g), aligned to union PSU
    # A failed delete-one replicate (prep error -> NA column) must not turn the whole
    # variance into NA / abort: drop it from its stratum and warn. (VAR-08)
    n_bad <- sum(mt$contrib & !is.finite(th))
    if (n_bad > 0L)
      warning(sprintf(paste0("change_estimate (jackknife): %d delete-one replicate(s) in wave ",
                            "'%s' were non-finite and were dropped from the variance."),
                     n_bad, wave), call. = FALSE)
    dev <- rep(0, length(th))
    cf  <- rep(0, length(th))                        # (n_h - 1)/n_h per contributing PSU
    for (h in unique(mt$stratum[mt$contrib])) {
      idx <- which(mt$contrib & mt$stratum == h & is.finite(th))
      if (!length(idx)) next
      dev[idx] <- th[idx] - mean(th[idx])            # centre on stratum mean of delete-one
      cf[idx]  <- (mt$nh[idx] - 1) / mt$nh[idx]
    }
    list(hat = hat, dev = dev, cf = cf, contrib = mt$contrib)
  })
  p1 <- per[[1]]; p2 <- per[[2]]
  V1  <- sum(p1$cf * p1$dev^2)
  V2  <- sum(p2$cf * p2$dev^2)
  sh  <- p1$contrib & p2$contrib                     # shared, non-singleton in both
  cov <- sum(sqrt(p1$cf[sh] * p2$cf[sh]) * p1$dev[sh] * p2$dev[sh])
  rho <- if (V1 > 0 && V2 > 0) cov / sqrt(V1 * V2) else NA_real_
  if (type == "absolute") {
    d_hat <- p2$hat - p1$hat
    V     <- V1 + V2 - 2 * cov                        # gradient (-1, 1), exact
    deff  <- if (V1 + V2 > 0) V / (V1 + V2) else NA_real_
  } else {                                            # delta method for theta2/theta1 - 1
    d_hat <- p2$hat / p1$hat - 1
    g1 <- -p2$hat / p1$hat^2; g2 <- 1 / p1$hat
    V  <- g1^2 * V1 + g2^2 * V2 + 2 * g1 * g2 * cov
    deff <- NA_real_
  }
  # V = V1 + V2 - 2*cov can go negative under high overlap with few PSUs; sqrt(max(V,0))
  # returns SE 0, which reads as "perfect precision" instead of "unstable estimate". Warn.
  if (V < 0)
    warning(sprintf(paste0("change_estimate (jackknife): V = V1 + V2 - 2*cov = %.3g < 0 ",
                           "(high overlap, few PSUs); SE set to 0. Treat this change's ",
                           "variance as unreliable -- add PSUs or use wave_bootstrap()."), V),
            call. = FALSE)
  se  <- sqrt(max(V, 0))
  z   <- .wf_panel_cimult(level, ci_type, df %||% wj$df)
  structure(list(estimate = d_hat, se = se, V = V, V1 = V1, V2 = V2, Vind = V1 + V2,
                 cov = cov, rho = rho, deff_change = deff,
                 ci_lower = d_hat - z * se, ci_upper = d_hat + z * se,
                 level = level, waves = wv, type = type, R = NA_integer_, method = "jackknife"),
            class = "weightflow_change")
}

#' Level estimate for a single panel wave, with its replicate variance
#'
#' Estimates a statistic in ONE wave of a [wave_bootstrap()] or [wave_jackknife()] object,
#' with the variance from that wave's replicates. Lets you report a level and a change from
#' the same coordinated object.
#'
#' @param wb a `weightflow_wave_boot` or `weightflow_wave_jack`.
#' @param statistic a function `function(w, data)` returning one number.
#' @param wave optional wave label (defaults to the first).
#' @param level confidence level for the normal interval.
#' @param ci_type `"normal"` (default, z) or `"t"` (Student t with `df` df).
#' @param df degrees of freedom for the `"t"` interval; `NULL` uses the object's design df.
#' @return an object of class `weightflow_level` with `estimate`, `se`, `V` and the interval.
#' @seealso [change_estimate()], [level_mean()], [level_total()]
#' @export
level_estimate <- function(wb, statistic, wave = NULL, level = 0.95,
                           ci_type = c("normal", "t"), df = NULL) {
  ci_type <- match.arg(ci_type)
  wave <- if (is.null(wave)) wb$waves[1] else as.character(wave)[1]
  if (!wave %in% wb$waves) stop("`wave` must be a wave present in the object.", call. = FALSE)
  d   <- wb$data[[wave]]
  hat <- as.numeric(statistic(wb$point[[wave]], d))
  if (inherits(wb, "weightflow_wave_boot")) {
    W <- wb$reps[[wave]]
    b <- vapply(seq_len(ncol(W)), function(j) {
      w <- W[, j]; if (anyNA(w)) NA_real_ else as.numeric(statistic(w, d))
    }, numeric(1))
    b <- b[is.finite(b)]
    if (length(b) < 2L) stop("Too few valid replicates.", call. = FALSE)
    V <- mean((b - hat)^2); method <- "bootstrap"
  } else if (inherits(wb, "weightflow_wave_jack")) {
    W <- wb$reps[[wave]]; mt <- wb$meta[[wave]]
    th <- vapply(seq_len(ncol(W)), function(g) {
      w <- W[, g]; if (anyNA(w)) NA_real_ else as.numeric(statistic(w, d))
    }, numeric(1))
    if (any(mt$contrib & !is.finite(th)))                # drop failed delete-one columns (VAR-08)
      warning(sprintf("level_estimate (jackknife): %d non-finite delete-one replicate(s) dropped.",
                     sum(mt$contrib & !is.finite(th))), call. = FALSE)
    V <- 0
    for (h in unique(mt$stratum[mt$contrib])) {
      idx <- which(mt$contrib & mt$stratum == h & is.finite(th))
      if (!length(idx)) next
      V <- V + (mt$nh[idx][1] - 1) / mt$nh[idx][1] * sum((th[idx] - mean(th[idx]))^2)
    }
    method <- "jackknife"
  } else stop("`wb` must come from wave_bootstrap() or wave_jackknife().", call. = FALSE)
  se <- sqrt(max(V, 0)); z <- .wf_panel_cimult(level, ci_type, df %||% wb$df)
  structure(list(estimate = hat, se = se, V = V, wave = wave, level = level,
                 ci_lower = hat - z * se, ci_upper = hat + z * se, method = method),
            class = "weightflow_level")
}

#' @rdname level_estimate
#' @param variable name of a numeric variable in the wave's data.
#' @export
level_mean <- function(wb, variable, wave = NULL, level = 0.95)
  level_estimate(wb, function(w, d) stats::weighted.mean(d[[variable]], w, na.rm = TRUE), wave, level)

#' @rdname level_estimate
#' @export
level_total <- function(wb, variable, wave = NULL, level = 0.95)
  level_estimate(wb, function(w, d) sum(w * d[[variable]], na.rm = TRUE), wave, level)

#' @export
print.weightflow_level <- function(x, ...) {
  cat(sprintf("<weightflow level [%s]>\n", x$method))
  cat(sprintf("  wave       : %s\n", x$wave))
  cat(sprintf("  estimate   : %.6g   SE %.6g\n", x$estimate, x$se))
  cat(sprintf("  %.0f%% CI    : [%.6g, %.6g]\n", 100 * x$level, x$ci_lower, x$ci_upper))
  invisible(x)
}

#' @rdname change_estimate
#' @export
change_total <- function(wb, variable, waves = NULL, level = 0.95,
                         type = c("absolute", "relative"), by = NULL) {
  change_estimate(wb, function(w, d) sum(w * d[[variable]], na.rm = TRUE),
                  waves = waves, level = level, type = match.arg(type), by = by)
}

#' @export
print.weightflow_change <- function(x, ...) {
  rel <- identical(x$type, "relative")
  cat(sprintf("<weightflow %s change%s>\n", if (rel) "relative" else "net",
              if (identical(x$method, "jackknife")) " [coordinated jackknife]" else ""))
  cat(sprintf("  %s -> %s\n", x$waves[1], x$waves[2]))
  cat(sprintf("  change     : %.6g   SE %.6g%s\n", x$estimate, x$se, if (rel) "  (ratio)" else ""))
  cat(sprintf("  %.0f%% CI    : [%.6g, %.6g]\n", 100 * x$level, x$ci_lower, x$ci_upper))
  cat(sprintf("  V1 %.4g | V2 %.4g | Cov %.4g | rho %.3f   (levels)\n",
              x$V1, x$V2, x$cov, x$rho))
  if (rel)
    cat(sprintf("  V(ratio) = %.4g  (overlap covariance via coordinated replicates)\n", x$V))
  else
    cat(sprintf("  V = %.4g  vs  V1+V2 = %.4g  (deff_change %.3f: overlap saved %.0f%%)\n",
                x$V, x$Vind, x$deff_change, 100 * (1 - x$deff_change)))
  invisible(x)
}

# ---------------------------------------------------------------------------
# Linear combinations of waves: panel_estimate(contrast = ...). The net change is
# the special case contrast = c(-1, 1); an annual average is rep(1/W, W); a
# semester-vs-semester contrast is c(-1/2, -1/2, 1/2, 1/2), etc. The variance of
# psi = a' theta is a' Sigma a, where Sigma is the W x W between-wave covariance
# the coordinated resampling captures. Works with either wave_bootstrap() (Sigma =
# mean of coordinated replicate deviation cross-products) or wave_jackknife()
# (Sigma = coordinated delete-one jackknife cov). Ignoring the covariance (treating
# waves as independent) mis-states the variance: it OVER-states a change and
# UNDER-states an average, because the overlap makes waves positively correlated.
# ---------------------------------------------------------------------------

# W x W between-wave covariance matrix + per-wave point estimates, from either engine
.wave_cov <- function(wb, statistic, waves) {
  W   <- length(waves)
  hat <- vapply(waves, function(wave) as.numeric(statistic(wb$point[[wave]], wb$data[[wave]])),
                numeric(1))
  if (inherits(wb, "weightflow_wave_boot")) {
    devs <- lapply(waves, function(wave) {
      Wt <- wb$reps[[wave]]; d <- wb$data[[wave]]
      b <- vapply(seq_len(ncol(Wt)), function(j) {
        w <- Wt[, j]; if (anyNA(w)) NA_real_ else as.numeric(statistic(w, d))
      }, numeric(1))
      b - as.numeric(statistic(wb$point[[wave]], d))
    })
    D    <- do.call(cbind, devs)                    # R x W replicate deviations
    good <- stats::complete.cases(D)
    if (sum(good) < 2L) stop("Too few valid replicates to estimate the variance.", call. = FALSE)
    D <- D[good, , drop = FALSE]
    Sigma <- crossprod(D) / nrow(D)                 # covariance emerges from coordination
    R <- nrow(D)
  } else if (inherits(wb, "weightflow_wave_jack")) {
    dv <- lapply(waves, function(wave) {
      Wt <- wb$reps[[wave]]; d <- wb$data[[wave]]; mt <- wb$meta[[wave]]
      th <- vapply(seq_len(ncol(Wt)), function(g) {
        w <- Wt[, g]; if (anyNA(w)) NA_real_ else as.numeric(statistic(w, d))
      }, numeric(1))
      dev <- rep(0, length(th)); cf <- rep(0, length(th))
      for (h in unique(mt$stratum[mt$contrib])) {
        idx <- which(mt$contrib & mt$stratum == h)
        dev[idx] <- th[idx] - mean(th[idx]); cf[idx] <- (mt$nh[idx] - 1) / mt$nh[idx]
      }
      list(dev = dev, cf = cf, contrib = mt$contrib)
    })
    Sigma <- matrix(0, W, W)
    for (i in seq_len(W)) for (j in i:W) {          # diag = V_w; off-diag over shared PSUs
      sh  <- dv[[i]]$contrib & dv[[j]]$contrib
      val <- sum(sqrt(dv[[i]]$cf[sh] * dv[[j]]$cf[sh]) * dv[[i]]$dev[sh] * dv[[j]]$dev[sh])
      Sigma[i, j] <- Sigma[j, i] <- val
    }
    R <- NA_integer_
  } else stop("`wb` must come from wave_bootstrap() or wave_jackknife().", call. = FALSE)
  dimnames(Sigma) <- list(waves, waves)
  list(hat = hat, Sigma = Sigma, R = R)
}

#' Linear combination of panel waves, with honest between-wave variance
#'
#' Estimates any linear combination `psi = sum(contrast * theta_wave)` of a statistic across
#' panel waves -- an annual average (`contrast = rep(1/W, W)`), a net change
#' (`contrast = c(-1, 1)`, i.e. what [change_estimate()] does), a semester contrast, etc. --
#' and its variance `a' Sigma a`, where `Sigma` is the between-wave covariance matrix that the
#' overlap of a rotating panel induces. That covariance is taken straight from the coordinated
#' replicates of [wave_bootstrap()] or [wave_jackknife()], so it is correct without any
#' analytic covariance formula. Treating the waves as independent (the diagonal of `Sigma`
#' only) understates the variance of an average and overstates that of a change.
#'
#' @param wb a `weightflow_wave_boot` from [wave_bootstrap()] or a `weightflow_wave_jack`
#'   from [wave_jackknife()].
#' @param statistic a function `function(w, data)` returning one number, evaluated per wave.
#' @param contrast numeric weights, one per wave, defining the combination; defaults to the
#'   equal-weight average `rep(1/W, W)`. May be named by wave label (matched to `waves`).
#' @param waves optional character vector of the waves to combine (defaults to all, in order).
#' @param level confidence level for the normal-approximation interval.
#' @param ci_type `"normal"` (default, z) or `"t"` (Student t with `df` df).
#' @param df degrees of freedom for the `"t"` interval; `NULL` uses the object's design df.
#' @return an object of class `weightflow_panel_estimate` with `estimate`, `se`, `V`, `Vind`
#'   (the independence-assuming variance), `deff = V / Vind`, the covariance matrix `Sigma`,
#'   the per-wave `point` estimates, the `contrast`, and the confidence interval.
#' @seealso [change_estimate()], [wave_bootstrap()], [wave_jackknife()]
#' @examples
#' \donttest{
#' waves <- lapply(1:3, function(t)
#'   weighting_spec(subset(panel_ine, ola == t & disp == "R"), base_weights = w_base))
#' names(waves) <- c("T1", "T2", "T3")
#' wb <- wave_bootstrap(waves, replicates = 100, strata = "estrato", psu = "psu",
#'                      seed = 1, progress = FALSE)
#' rate <- function(w, d) weighted.mean(d$desocupado, w, na.rm = TRUE)
#' panel_estimate(wb, rate)                       # average unemployment level over the waves
#' panel_estimate(wb, rate, contrast = c(-1, 0, 1))  # T3 - T1 change
#' }
#' @export
panel_estimate <- function(wb, statistic, contrast = NULL, waves = NULL, level = 0.95,
                           ci_type = c("normal", "t"), df = NULL) {
  ci_type <- match.arg(ci_type)
  if (!inherits(wb, c("weightflow_wave_boot", "weightflow_wave_jack")))
    stop("`wb` must come from wave_bootstrap() or wave_jackknife().", call. = FALSE)
  wv <- if (is.null(waves)) wb$waves else as.character(waves)
  if (!all(wv %in% wb$waves)) stop("`waves` must name waves present in `wb`.", call. = FALSE)
  W <- length(wv)
  a <- if (is.null(contrast)) rep(1 / W, W) else contrast
  if (!is.null(names(a))) {
    if (!all(wv %in% names(a))) stop("named `contrast` must cover all `waves`.", call. = FALSE)
    a <- a[wv]
  }
  a <- as.numeric(a)
  if (length(a) != W) stop(sprintf("`contrast` must have length %d (one per wave).", W),
                           call. = FALSE)

  mm   <- .wave_cov(wb, statistic, wv)
  est  <- sum(a * mm$hat)
  V    <- as.numeric(t(a) %*% mm$Sigma %*% a)
  Vind <- sum(a^2 * diag(mm$Sigma))                 # between-wave covariance set to 0
  se   <- sqrt(max(V, 0))
  z    <- .wf_panel_cimult(level, ci_type, df %||% wb$df)
  structure(list(estimate = est, se = se, V = V, Vind = Vind,
                 deff = if (Vind > 0) V / Vind else NA_real_,
                 Sigma = mm$Sigma, point = stats::setNames(mm$hat, wv),
                 contrast = stats::setNames(a, wv), waves = wv, level = level,
                 ci_lower = est - z * se, ci_upper = est + z * se, R = mm$R,
                 method = if (inherits(wb, "weightflow_wave_jack")) "jackknife" else "bootstrap"),
            class = "weightflow_panel_estimate")
}

#' @rdname panel_estimate
#' @param variable name of a numeric variable present in every wave.
#' @export
panel_mean <- function(wb, variable, contrast = NULL, waves = NULL, level = 0.95) {
  panel_estimate(wb, function(w, d) stats::weighted.mean(d[[variable]], w, na.rm = TRUE),
                 contrast = contrast, waves = waves, level = level)
}

#' @rdname panel_estimate
#' @export
panel_total <- function(wb, variable, contrast = NULL, waves = NULL, level = 0.95) {
  panel_estimate(wb, function(w, d) sum(w * d[[variable]], na.rm = TRUE),
                 contrast = contrast, waves = waves, level = level)
}

#' @export
print.weightflow_panel_estimate <- function(x, ...) {
  cat(sprintf("<weightflow panel estimate%s>\n",
              if (identical(x$method, "jackknife")) " [coordinated jackknife]" else ""))
  cat(sprintf("  contrast   : %s\n",
              paste(sprintf("%s=%g", x$waves, x$contrast), collapse = ", ")))
  cat(sprintf("  estimate   : %.6g   SE %.6g\n", x$estimate, x$se))
  cat(sprintf("  %.0f%% CI    : [%.6g, %.6g]\n", 100 * x$level, x$ci_lower, x$ci_upper))
  cat(sprintf("  V = %.4g  vs  V(independent) = %.4g  (ratio %.3f)\n",
              x$V, x$Vind, x$deff))
  if (x$deff < 1)
    cat("  between-wave covariance LOWERS the variance (a change-type contrast).\n")
  else if (x$deff > 1)
    cat("  between-wave covariance RAISES the variance (an average-type contrast).\n")
  invisible(x)
}
