# Recursive month-to-month (period-to-period) chaining of the coordinated bootstrap.
#
# wave_bootstrap() takes every wave at once. That is fine for research and impossible in
# production: an office cannot re-run the whole history each month. wave_step() runs ONE
# wave and coordinates it against the carry artifacts of earlier periods, then emits the
# carry for the next run. The chain is recursive: period t needs only what period t-1 (and,
# for designs with gaps, earlier periods) left behind.
#
# What travels between periods is the MULTIPLICITY of each PSU, not the uniform that
# generated it. Statistics Canada's LFS (cat. 71-526-X, 7.2.2, after Roberts, Kovacevic,
# Mantel and Phillips 2001) coordinates by PAIRING the current period's PSUs with the
# previous period's and transferring the multiplicities. When the stratum's PSU count is
# unchanged the pairing is a bijection: the multiplicity vector is permuted, so the
# stratum total stays exactly m_h AND every shared PSU keeps exactly its multiplicity.
# Re-drawing from a stored uniform cannot do both, because the exact multinomial's
# conditionals depend on the stratum's PSU set, which rotation changes every period.
#
# Which earlier periods matter is a property of the rotation design, not of the calendar.
# A 6-consecutive design overlaps at lags 1..5 and nowhere else; a 4-(8)-4 design overlaps
# at 1..3 and again at 9..15; a 1-(3)-1-(3)-1-(3)-1 design has NO overlap at lag 1 and all
# of it at lags 4, 8, 12. So `previous` takes a LIST of carries and each PSU inherits from
# the most recent carry that holds it: gaps and returning cohorts are handled by that rule
# alone, with no window parameter to get wrong.

# ---- carry construction and inspection -------------------------------------

.wf_carry_seq <- function(previous) {
  if (is.null(previous)) return(0L)
  max(vapply(previous, function(p) as.integer(p$seq %||% 0L), integer(1)), 0L)
}

# Normalise `previous` to a list of carries ordered MOST RECENT FIRST.
.wf_norm_previous <- function(previous) {
  if (is.null(previous)) return(list())
  if (inherits(previous, "wf_wave_carry")) previous <- list(previous)
  if (!is.list(previous) || !all(vapply(previous, inherits, logical(1), "wf_wave_carry")))
    stop("`previous` must be a wf_wave_carry (or a list of them) from wave_carry().",
         call. = FALSE)
  previous[order(vapply(previous, function(p) as.integer(p$seq %||% 0L), integer(1)),
                 decreasing = TRUE)]
}

# ---- multiplicity registry --------------------------------------------------
# For each PSU, the multiplicity row of the MOST RECENT carry that holds it. The registry
# spans the UNION of this wave's PSUs and every PSU any carry knows about: a PSU that
# rotated OUT is not in this wave but its multiplicity is what a rotated-IN PSU inherits
# (LFS 7.2.2 ii), so dropping it would send every new PSU to the case-iv fallback and
# destroy the coordination. Returns the matrix (NA rows for PSUs seen in no carry), the
# stratum of every row, and which carry each row came from.
.wf_mult_registry <- function(prev_list, upsu, psu_str, R) {
  known <- unique(c(upsu, unlist(lapply(prev_list, function(p) rownames(p$mult)),
                                 use.names = FALSE)))
  known <- sort(known[!is.na(known)])
  M <- matrix(NA_integer_, nrow = length(known), ncol = R, dimnames = list(known, NULL))
  src <- stats::setNames(rep(NA_character_, length(known)), known)
  str <- stats::setNames(rep(NA_character_, length(known)), known)
  str[upsu] <- psu_str
  for (p in prev_list) {
    if (is.null(p$mult)) next
    if (ncol(p$mult) != R)
      stop(sprintf(paste0("carry '%s' has %d replicates and this run asks for %d. The ",
                          "number of replicates must be constant along the chain."),
                   p$period, ncol(p$mult), R), call. = FALSE)
    take <- intersect(known[is.na(src)], rownames(p$mult))
    if (length(take)) { M[take, ] <- p$mult[take, , drop = FALSE]; src[take] <- p$period }
    fill <- names(p$psu_stratum)[is.na(str[names(p$psu_stratum)])]
    if (length(fill)) str[fill] <- as.character(p$psu_stratum[fill])
  }
  list(mult = M, source = src, stratum = str)
}

# Close every column of an integer multiplicity matrix on `target` by adding or dropping
# draws at random (LFS 7.2.2 iii/iv). Returns the matrix and the share of columns that
# already closed (a coordination-quality diagnostic: 1 = untouched = exact coordination).
.wf_close_mult <- function(M, target) {
  n <- nrow(M); if (n == 0L) return(list(mult = M, untouched = 1))
  s <- colSums(M); untouched <- mean(s == target)
  for (b in which(s != target)) {
    sb <- s[b]
    while (sb < target) { j <- sample.int(n, 1L); M[j, b] <- M[j, b] + 1L; sb <- sb + 1L }
    while (sb > target) {
      pos <- which(M[, b] > 0L); if (!length(pos)) break
      j <- pos[sample.int(length(pos), 1L)]; M[j, b] <- M[j, b] - 1L; sb <- sb - 1L
    }
  }
  list(mult = M, untouched = untouched)
}

# Transfer multiplicities into one stratum's current PSU set (LFS 7.2.2 i-iv).
# `retired` are PSUs of the SAME stratum that an earlier period had and this one does not:
# their multiplicities are the ones the rotated-in PSUs inherit.
.wf_transfer_stratum <- function(Mreg, ph, retired, mh, nh, R, rotation_map = NULL) {
  have  <- ph[!is.na(Mreg[ph, 1L])]                       # inherited from some carry
  fresh <- setdiff(ph, have)                              # never seen before
  M <- matrix(0L, nrow = length(ph), ncol = R, dimnames = list(ph, NULL))
  if (length(have)) M[have, ] <- Mreg[have, , drop = FALSE]
  # Pair by the declared replacement map, else in sorted order (a deterministic bijection:
  # reproducible, unlike LFS's random pairing).
  retired <- sort(retired[!is.na(retired)])
  if (length(fresh)) {
    fresh_s <- sort(fresh)
    mapped <- character(0)
    if (!is.null(rotation_map)) {
      hit <- fresh_s[fresh_s %in% names(rotation_map)]
      for (f in hit) {
        r <- rotation_map[[f]]
        if (!is.na(r) && r %in% retired) {
          M[f, ] <- Mreg[r, ]; retired <- setdiff(retired, r); mapped <- c(mapped, f)
        }
      }
    }
    rest <- setdiff(fresh_s, mapped)
    k <- min(length(rest), length(retired))
    if (k > 0L) { M[rest[seq_len(k)], ] <- Mreg[retired[seq_len(k)], , drop = FALSE]
                  retired <- retired[-seq_len(k)] }
    if (length(rest) > k) {                              # case iv: new PSUs with no partner
      ex <- rest[(k + 1L):length(rest)]
      np <- max(2L, length(have) + k)                     # previous-period PSU count
      M[ex, ] <- matrix(as.integer(stats::rbinom(length(ex) * R, np - 1L, 1 / np)),
                        nrow = length(ex))
    }
  }
  cl <- .wf_close_mult(M, mh)
  list(mult = cl$mult, untouched = cl$untouched,
       n_inherited = length(have), n_fresh = length(fresh))
}

#' One period of a coordinated panel bootstrap, chained from the previous ones
#'
#' Runs the whole weighting recipe of a single period, coordinates its bootstrap with the
#' periods that share sample with it, and returns the cross-sectional weights, the level
#' and net-change estimates, and a compact **carry** artifact for the next run. It is the
#' production counterpart of [wave_bootstrap()]: that one needs every wave in memory at
#' once, this one needs only what the earlier runs left behind.
#'
#' Coordination transfers the **multiplicity** of each primary sampling unit, following the
#' Statistics Canada LFS (cat. 71-526-X, section 7.2.2, after Roberts, Kovacevic, Mantel and
#' Phillips 2001): current-period PSUs are paired with earlier ones, common PSUs with
#' themselves, and each inherits its partner's multiplicity. When a stratum's PSU count is
#' unchanged this is a permutation, so the stratum total is preserved exactly and every
#' shared PSU keeps exactly its resampling; the coordination is then exact. When the count
#' changes, multiplicity is added or dropped at random until the stratum total closes, and
#' the coordination is approximate -- `$strata` reports, per stratum, the share of
#' replicates that needed no adjustment.
#'
#' `previous` is a **list** of carries, not a single one, because which earlier periods
#' share sample is a property of the rotation design: a 6-consecutive design overlaps at
#' lags 1 to 5 and nowhere else, a 4-(8)-4 design overlaps at lags 1-3 and again at 9-15,
#' and a 1-(3)-1-(3)-1-(3)-1 design has no overlap at lag 1 at all. Each PSU inherits from
#' the most recent carry that holds it, so gaps and returning cohorts need no window
#' parameter. Supply every carry whose period shares sample with this one.
#'
#' The cross-sectional weights are **not** touched by any of this: `$weights` is exactly
#' `prep(spec)$final_weight`.
#'
#' @param spec a [weighting_spec()] for this period, with its full recipe.
#' @param previous a `wf_wave_carry` from a previous run, or a list of them; `NULL` for the
#'   first period of a chain.
#' @param estimands a named list of functions `function(w, data)` each returning one number
#'   (e.g. `list(unemp = function(w, d) weighted.mean(d$unemployed, w, na.rm = TRUE))`).
#'   Their replicate values are what the carry stores, and what the next period needs to
#'   compute a net change. Required to estimate change.
#' @param by optional character vector of domain columns: every estimand is also evaluated
#'   within each level, and the change is reported per domain.
#' @param replicates number of bootstrap replicates. Must be constant along the chain.
#' @param strata,psu column names identifying the stratum and the primary sampling unit.
#'   The PSU identity is nested within the stratum, so ids restarting at 1 in each stratum
#'   are handled.
#' @param period a label for this period (defaults to `"t<seq>"`). Used in the carry and in
#'   the change table.
#' @param rotation_map optional named character vector mapping a new PSU id to the id of
#'   the PSU it replaces, in the same nested `stratum` + `psu` form. Improves the pairing;
#'   without it partners are matched in sorted order.
#' @param m PSUs drawn per stratum (default `n_h - 1`).
#' @param seed integer seed. The caller's RNG state is restored on exit.
#' @param refit_steps which steps to re-run per replicate; `"all"` (default) re-runs the
#'   entire cascade, which is what makes the variance recipe-aware.
#' @param resample `"multinom"` (default, exact Rao-Wu) or `"binom"` (legacy).
#' @param carry `"auto"` (default) stores the replicate weights only when the recipe needs
#'   them, i.e. when it contains a [step_cre()]; `"thin"` forces the compact form (only the
#'   replicate values of the estimands); `"fat"` always stores the replicate weight matrix,
#'   which lets a later run estimate an estimand that was not declared here.
#' @param progress print progress messages.
#' @return an object of class `wf_wave_step` with `$weights` (the publishable
#'   cross-sectional weights), `$level`, `$change`, `$strata` (the per-stratum coordination
#'   report), and `$carry` -- the artifact to save for the next period.
#' @seealso [wave_carry()], [wave_bootstrap()], [change_estimate()]
#' @export
wave_step <- function(spec, previous = NULL, estimands = NULL, by = NULL,
                      replicates = 500L, strata = NULL, psu = NULL, period = NULL,
                      rotation_map = NULL, m = NULL, seed = NULL, refit_steps = "all",
                      resample = c("multinom", "binom"),
                      carry = c("auto", "thin", "fat"), progress = TRUE) {
  resample <- match.arg(resample); carry <- match.arg(carry)
  if (!inherits(spec, "weighting_spec"))
    stop("`spec` must be a weighting_spec.", call. = FALSE)
  if (any(vapply(spec$steps, inherits, logical(1), "step_subsample")))
    stop("wave_step() does not support step_subsample() (two-phase) recipes: the two-phase ",
         "factor replaces the Rao-Wu draw and does not compose with the coordination.",
         call. = FALSE)
  R <- as.integer(replicates)
  if (is.na(R) || R < 2L) stop("`replicates` must be >= 2.", call. = FALSE)
  # `estimands` accepts either an estimation plan built with the package DSL --
  # spec |> step_filter() |> step_domain() |> step_estimate(mean(y)) -- or a plain named
  # list of function(w, data). The plan carries its own domains, so it also sets `by`.
  if (inherits(estimands, "weightflow_estimation")) {
    plan <- .wf_plan_to_estimands(estimands)
    estimands <- plan$fns
    if (is.null(by)) by <- plan$by
  } else if (!is.null(estimands) &&
             (!is.list(estimands) || is.null(names(estimands)) ||
              any(!nzchar(names(estimands))) ||
              !all(vapply(estimands, is.function, logical(1)))))
    stop("`estimands` must be an estimation plan (spec |> step_estimate(...)) or a NAMED ",
         "list of functions function(w, data).", call. = FALSE)
  prev <- .wf_norm_previous(previous)
  seq_i <- .wf_carry_seq(prev) + 1L
  period <- period %||% sprintf("t%d", seq_i)
  has_cre <- any(vapply(spec$steps, inherits, logical(1), "step_cre"))
  fat <- switch(carry, auto = has_cre, thin = FALSE, fat = TRUE)
  if (has_cre && !fat)
    stop("carry = \"thin\" cannot serve a step_cre() recipe: the composite control totals ",
         "are re-estimated per replicate from the previous period's replicate WEIGHTS, so ",
         "the carry must be \"fat\". Use carry = \"auto\".", call. = FALSE)

  if (!is.null(seed)) {
    if (exists(".Random.seed", envir = .GlobalEnv)) {
      old <- get(".Random.seed", envir = .GlobalEnv)
      on.exit(assign(".Random.seed", old, envir = .GlobalEnv), add = TRUE)
    } else {
      on.exit(if (exists(".Random.seed", envir = .GlobalEnv))
                rm(".Random.seed", envir = .GlobalEnv), add = TRUE)
    }
    set.seed(as.integer(seed))
  }

  dat <- spec$data; n <- nrow(dat)
  if (!is.null(strata) && !strata %in% names(dat))
    stop(sprintf("`strata` column '%s' not in the data.", strata), call. = FALSE)
  if (!is.null(psu) && !psu %in% names(dat))
    stop(sprintf("`psu` column '%s' not in the data.", psu), call. = FALSE)
  if (is.null(psu))
    warning("wave_step: `psu = NULL` makes each ROW its own PSU; pass a `psu` column ",
            "consistent across periods for the overlap covariance to be real.", call. = FALSE)
  st <- if (is.null(strata)) rep("1", n) else as.character(dat[[strata]])
  ps <- if (is.null(psu)) paste0(".row", seq_len(n)) else as.character(dat[[psu]])
  ps <- if (is.null(strata)) ps else paste(st, ps, sep = "\r")
  upsu <- sort(unique(ps))
  psu_str <- st[match(upsu, ps)]

  reg <- .wf_mult_registry(prev, upsu, psu_str, R)
  Mreg <- reg$mult; reg_str <- reg$stratum
  seen <- rownames(Mreg)[!is.na(Mreg[, 1L])]

  # --- multiplicities and lambda, stratum by stratum ---
  Lam <- matrix(1, nrow = length(upsu), ncol = R, dimnames = list(upsu, NULL))
  rep_rows <- vector("list", length(unique(psu_str))); k <- 0L
  for (h in unique(psu_str)) {
    ph <- upsu[psu_str == h]; nh <- length(ph)
    k <- k + 1L
    if (nh < 2L) {
      rep_rows[[k]] <- data.frame(stratum = h, n_psu = nh, inherited = 0L, fresh = nh,
                                  case = "singleton", coordinated = NA_real_,
                                  stringsAsFactors = FALSE)
      next
    }
    mh <- if (is.null(m)) nh - 1L else min(max(1L, as.integer(m)), nh - 1L)
    inh <- sum(!is.na(Mreg[ph, 1L]))
    # Reference period FOR THIS STRATUM: the most recent carry that holds any PSU this
    # stratum still has. Its PSU set is what "the previous period" means here, so the
    # retired PSUs -- the partners the rotated-in ones inherit from -- come from it alone.
    # Taking them from every carry ever seen would treat a long-gone cohort as retired and
    # misread a plain rotation as a change in n_h.
    retired <- character(0); nh_prev <- inh
    for (p in prev) {
      if (is.null(p$mult) || !any(ph %in% rownames(p$mult))) next
      prev_ph <- names(p$psu_stratum)[!is.na(p$psu_stratum) & p$psu_stratum == h]
      retired <- setdiff(intersect(prev_ph, rownames(Mreg)), ph)
      nh_prev <- length(prev_ph)
      break
    }
    if (inh == 0L) {                                   # nothing to coordinate with: draw fresh
      U <- matrix(stats::runif(nh * R), nrow = nh, dimnames = list(ph, NULL))
      cnt <- .wf_rao_wu_counts(U, mh, nh, resample); rownames(cnt) <- ph
      unt <- 1; cs <- "fresh"
    } else {
      tr <- .wf_transfer_stratum(Mreg, ph, retired, mh, nh, R, rotation_map)
      cnt <- tr$mult; unt <- tr$untouched
      cs <- if (tr$n_fresh == 0L && length(retired) == 0L) "i" else
            if (nh_prev == nh) "ii" else if (nh_prev > nh) "iii" else "iv"
    }
    a <- sqrt(mh / (nh - 1))
    Lam[ph, ] <- 1 - a + a * (nh / mh) * cnt
    Mreg[ph, ] <- cnt                                   # what this period will carry forward
    rep_rows[[k]] <- data.frame(stratum = h, n_psu = nh, inherited = inh, fresh = nh - inh,
                                case = cs, coordinated = unt, stringsAsFactors = FALSE)
  }
  strata_rep <- do.call(rbind, rep_rows)

  # --- point weights and the replicate cascade ---
  fr <- .wf_freeze_split(spec, refit_steps)
  pw <- fr$point; w_pre <- fr$w_pre
  ridx <- match(ps, upsu)
  prev_reps <- if (length(prev)) prev[[1L]]$reps else NULL
  inj <- if (is.null(prev_reps)) list(injected = 0L, skipped = 0L)
         else .wf_cre_inject_status(fr$spec, nrow(prev_reps))
  # A seed wave declares step_cre(previous = NULL) on purpose: there is no Zhat to vary, so
  # only warn when a step_cre actually points at an earlier wave and we could not reach it.
  needs_prev <- sum(vapply(spec$steps, function(s)
    inherits(s, "step_cre") && !is.null(s$previous), logical(1)))
  if (needs_prev > 0L && inj$injected == 0L)
    warning(sprintf(paste0(
      "wave_step: period '%s' has a step_cre() but no aligned previous replicate weights, ",
      "so Zhat is held FIXED and the variance is anticonservative. Pass the carry of the ",
      "period the step_cre's `previous` refers to."), period), call. = FALSE)
  if (progress) message("wave_step: '", period, "' (", R, " replicates, ",
                        nrow(strata_rep), " strata)")
  reps <- vapply(seq_len(R), function(b) {
    spb <- fr$spec; spb$data[[fr$base]] <- w_pre * Lam[ridx, b]
    attr(spb$data, "wf_replicate") <- TRUE
    attr(spb$data, "wf_replicate_idx") <- b
    spb <- .wf_cre_inject_prev(spb, if (is.null(prev_reps)) NULL else prev_reps[, b])
    tryCatch(prep(spb)$final_weight, error = function(e) rep(NA_real_, n))
  }, numeric(n))
  n_failed <- sum(apply(reps, 2L, anyNA))
  if (n_failed > 0L)
    warning(sprintf("wave_step: %d of %d replicates failed and are dropped.", n_failed, R),
            call. = FALSE)

  # --- estimands, point and replicate ---
  ev <- .wf_expand_estimands(estimands, by, dat)
  th <- lapply(ev, function(f) vapply(seq_len(R), function(b) {
    v <- tryCatch(f(reps[, b], dat), error = function(e) NA_real_)
    if (length(v) == 1L && is.numeric(v)) as.numeric(v) else NA_real_ }, numeric(1)))
  pt <- vapply(ev, function(f) tryCatch(as.numeric(f(pw, dat)), error = function(e) NA_real_),
               numeric(1))
  level <- .wf_level_table(pt, th, period)
  change <- .wf_change_table(pt, th, prev, period)

  cy <- structure(list(
    period = period, seq = seq_i,
    # Only THIS wave's PSUs: a carry describes its own period. A cohort that returns after a
    # gap is recovered by passing the older carry that holds it, which is what the
    # lag-indexed store is for -- letting each carry accumulate every PSU ever seen would
    # make a recent carry claim PSUs it never had and misread the rotation.
    mult = Mreg[upsu, , drop = FALSE],
    nh = table(psu_str), psu_stratum = stats::setNames(psu_str, upsu),
    theta = th, point = pt,
    reps = if (fat) reps else NULL, data = if (fat) dat else NULL, weights = if (fat) pw else NULL,
    meta = list(R = R, resample = resample, refit_steps = refit_steps, m = m,
                strata = strata, psu = psu, by = by, fat = fat,
                estimands = names(ev), rngkind = RNGkind(),
                version = as.character(utils::packageVersion("weightflow")))
  ), class = "wf_wave_carry")

  structure(list(period = period, weights = pw, reps = reps, theta = th, point = pt,
                 level = level, change = change, strata = strata_rep, carry = cy,
                 n_failed = n_failed, n_cre_injected = inj$injected,
                 n_cre_skipped = inj$skipped, previous = vapply(prev, `[[`, "", "period")),
            class = "wf_wave_step")
}

# Translate an estimation pipeline -- spec |> step_filter() |> step_domain() |>
# step_estimate() -- into the named list of function(w, data) that the chain stores.
# Filters MASK rows rather than dropping them, so the coordinated replicate structure
# and the overlap covariance survive; domains expand each estimand over the observed
# levels. `over`/`contrast` do not apply here: a chained period always reports its own
# level and the change against every carry supplied.
.wf_plan_to_estimands <- function(est) {
  if (!length(est$estimands))
    stop("The estimation plan declares no estimand. Add step_estimate(...).", call. = FALSE)
  keep_fn <- if (length(est$filters)) function(d) {
    k <- rep(TRUE, nrow(d))
    for (f in est$filters) {
      v <- eval(f$expr, d, f$env)
      k <- k & !is.na(v) & v
    }
    k
  } else NULL
  out <- list()
  for (e in est$estimands) {
    f0 <- e$fn
    fun <- if (is.null(keep_fn)) f0 else local({ ff <- f0
      function(w, d) { k <- which(keep_fn(d))
        if (!length(k)) return(NA_real_); ff(w[k], d[k, , drop = FALSE]) } })
    nm <- e$label
    if (nm %in% names(out)) nm <- paste0(nm, "_", length(out) + 1L)
    out[[nm]] <- fun
  }
  list(fns = out, by = if (length(est$domains)) est$domains else NULL)
}

# Expand estimands over domain levels: "name" and "name|col=level".
.wf_expand_estimands <- function(estimands, by, dat) {
  if (is.null(estimands)) return(list())
  out <- estimands
  if (!is.null(by)) {
    for (cl in by) {
      if (!cl %in% names(dat))
        stop(sprintf("`by` column '%s' not in the data.", cl), call. = FALSE)
      lv <- sort(unique(as.character(dat[[cl]])))
      lv <- lv[!is.na(lv)]
      for (nm in names(estimands)) for (g in lv) {
        local({
          f <- estimands[[nm]]; cc <- cl; gg <- g
          out[[sprintf("%s|%s=%s", nm, cc, gg)]] <<- function(w, d) {
            k <- which(!is.na(d[[cc]]) & as.character(d[[cc]]) == gg)
            if (!length(k)) return(NA_real_)
            f(w[k], d[k, , drop = FALSE])
          }
        })
      }
    }
  }
  out
}

.wf_level_table <- function(pt, th, period) {
  if (!length(th)) return(NULL)
  do.call(rbind, lapply(names(th), function(k) {
    b <- th[[k]]; b <- b[is.finite(b)]
    se <- if (length(b) >= 2L) sqrt(mean((b - pt[[k]])^2)) else NA_real_
    data.frame(period = period, estimand = k, estimate = unname(pt[[k]]), se = se,
               R_used = length(b), stringsAsFactors = FALSE)
  }))
}

.wf_change_table <- function(pt, th, prev, period) {
  if (!length(th) || !length(prev)) return(NULL)
  rows <- list()
  for (p in prev) {
    common <- intersect(names(th), names(p$theta))
    # An estimand declared now but absent from the carry cannot yield a change: the carry
    # stores the replicate values of the estimands DECLARED WHEN IT WAS WRITTEN. Adding an
    # estimand or a domain mid-chain silently drops it from the change table, so say so.
    miss <- setdiff(names(th), names(p$theta))
    if (length(miss))
      warning(sprintf(paste0("carry '%s' has no replicate values for %d estimand(s) (%s%s), ",
                             "so no change is reported for them. Declare the same ",
                             "`estimands`/`by` in every period of the chain, or re-run that ",
                             "period."), p$period, length(miss),
                      paste(utils::head(miss, 3), collapse = ", "),
                      if (length(miss) > 3L) ", ..." else ""), call. = FALSE)
    for (k in common) {
      b2 <- th[[k]]; b1 <- p$theta[[k]]
      ok <- is.finite(b1) & is.finite(b2)
      if (sum(ok) < 2L) next
      d2 <- b2[ok] - pt[[k]]; d1 <- b1[ok] - p$point[[k]]
      V2 <- mean(d2^2); V1 <- mean(d1^2); cv <- mean(d1 * d2)
      V  <- V1 + V2 - 2 * cv
      est <- unname(pt[[k]] - p$point[[k]])
      se  <- sqrt(max(V, 0))
      rows[[length(rows) + 1L]] <- data.frame(
        estimand = k, from = p$period, to = period, lag = NA_integer_,
        estimate = est, se = se, V = V, V1 = V1, V2 = V2, cov = cv,
        rho = if (V1 > 0 && V2 > 0) cv / sqrt(V1 * V2) else NA_real_,
        deff_change = if (V1 + V2 > 0) V / (V1 + V2) else NA_real_,
        lo = est - stats::qnorm(0.975) * se, hi = est + stats::qnorm(0.975) * se,
        R_used = sum(ok), stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) return(NULL)
  out <- do.call(rbind, rows)
  out$lag <- NULL
  out
}

#' Extract the carry artifact of a period
#'
#' The object [wave_step()] leaves for the next run: the PSU multiplicities that coordinate
#' the next period's bootstrap, the replicate values of the declared estimands, and -- only
#' when the recipe needs them -- the replicate weights.
#'
#' @param x a `wf_wave_step` from [wave_step()].
#' @return a `wf_wave_carry`, to be saved (`saveRDS()`) and passed as `previous` next period.
#' @seealso [wave_step()]
#' @export
wave_carry <- function(x) {
  if (!inherits(x, "wf_wave_step"))
    stop("`x` must be a wf_wave_step from wave_step().", call. = FALSE)
  x$carry
}

#' @export
print.wf_wave_carry <- function(x, ...) {
  sz <- format(utils::object.size(x), units = "auto")
  cat(sprintf("<weightflow carry> period '%s' (seq %d)\n", x$period, x$seq))
  cat(sprintf("  %d PSUs x %d replicates%s\n", nrow(x$mult), ncol(x$mult),
              if (isTRUE(x$meta$fat)) ", + replicate weights (fat)" else " (thin)"))
  cat(sprintf("  estimands   : %s\n",
              if (length(x$meta$estimands)) paste(utils::head(x$meta$estimands, 4),
                collapse = ", ") else "(none)"))
  if (length(x$meta$estimands) > 4L) cat(sprintf("                ... %d in total\n",
                                                 length(x$meta$estimands)))
  cat(sprintf("  size        : %s\n", sz))
  invisible(x)
}

#' @export
print.wf_wave_step <- function(x, ...) {
  cat(sprintf("<weightflow wave step> period '%s'\n", x$period))
  cat(sprintf("  coordinated with: %s\n",
              if (length(x$previous)) paste(x$previous, collapse = ", ") else "(none, first period)"))
  s <- x$strata
  if (!is.null(s) && nrow(s)) {
    tb <- table(s$case)
    cat(sprintf("  strata          : %d  (%s)\n", nrow(s),
                paste(sprintf("%s: %d", names(tb), as.integer(tb)), collapse = "; ")))
    co <- s$coordinated[is.finite(s$coordinated)]
    if (length(co))
      cat(sprintf("  coordination    : %.1f%% of replicates needed no adjustment%s\n",
                  100 * mean(co),
                  if (any(co < 1)) sprintf(" (%d stratum/a approximate)", sum(co < 1)) else ""))
  }
  if (x$n_failed > 0L) cat(sprintf("  failed reps     : %d\n", x$n_failed))
  if ((x$n_cre_injected + x$n_cre_skipped) > 0L)
    cat(sprintf("  CRE Zhat*       : %d injected%s\n", x$n_cre_injected,
                if (x$n_cre_skipped > 0L) sprintf(", %d SKIPPED", x$n_cre_skipped) else ""))
  if (!is.null(x$change) && nrow(x$change)) {
    cat("\n  net change\n")
    d <- x$change[, c("estimand", "from", "estimate", "se", "rho", "deff_change")]
    d$estimate <- signif(d$estimate, 4); d$se <- signif(d$se, 3)
    d$rho <- round(d$rho, 3); d$deff_change <- round(d$deff_change, 3)
    print(utils::head(d, 12), row.names = FALSE)
    if (nrow(d) > 12L) cat(sprintf("  ... %d rows in total\n", nrow(d)))
  } else if (!is.null(x$level) && nrow(x$level)) {
    cat("\n  level\n"); print(utils::head(x$level, 12), row.names = FALSE)
  }
  invisible(x)
}

# Linear combinations over a chain of carries -------------------------------

#' Linear combination of an estimand across a chain of periods
#'
#' [wave_step()] reports the level of its own period and the net change against each carry it
#' was given -- that is, **pairwise** contrasts. Many published series are not pairwise: a
#' rolling quarter is the average of three consecutive months, a semester-on-semester contrast
#' is `c(-1/2, -1/2, 1/2, 1/2)`, an annual average is `rep(1/W, W)`. `wave_contrast()` estimates
#' any such combination \eqn{\psi = a'\theta} directly from the carries the chain already wrote
#' to disk, with \eqn{V(\psi) = a' \Sigma a}.
#'
#' The carries make this possible without keeping the waves in memory: each one stores the `R`
#' replicate values of every declared estimand, and those replicates are **paired across
#' periods** because the coordination transferred the PSU multiplicities. Stacking them into an
#' `R x W` matrix and taking its (uncentred-at-`R`) covariance recovers the full between-period
#' covariance matrix, from which any linear combination follows. With `contrast = c(-1, 1)` the
#' result reproduces the `$change` row of [wave_step()] exactly.
#'
#' @param carries a list of `wf_wave_carry` objects, one per period entering the combination.
#'   Order defines the order of `contrast`; they are used as given (not sorted).
#' @param estimand name of the estimand to combine, as it appears in `carry$point` (a domain
#'   estimand is named e.g. `"rate|sex=F"`).
#' @param contrast numeric weights, one per carry. Defaults to the average `rep(1/W, W)`.
#' @param level confidence level for the interval.
#' @return a one-row `data.frame` with `estimate`, `se`, `V`, `lo`, `hi`, `R_used`, the periods
#'   and the contrast used, plus the covariance matrix `Sigma` as an attribute.
#' @seealso [wave_step()], [wave_carry()]; [panel_estimate()] does the same on a
#'   [wave_bootstrap()] object, when all waves are held together.
#' @export
wave_contrast <- function(carries, estimand, contrast = NULL, level = 0.95) {
  if (inherits(carries, "wf_wave_carry")) carries <- list(carries)
  if (!is.list(carries) || !length(carries) ||
      !all(vapply(carries, inherits, logical(1), "wf_wave_carry")))
    stop("`carries` must be a list of wave_carry() objects.", call. = FALSE)
  W <- length(carries)
  a <- if (is.null(contrast)) rep(1 / W, W) else as.numeric(contrast)
  if (length(a) != W)
    stop(sprintf("`contrast` has length %d but %d carries were given.", length(a), W),
         call. = FALSE)
  if (!is.character(estimand) || length(estimand) != 1L)
    stop("`estimand` must be a single name.", call. = FALSE)

  miss <- vapply(carries, function(cy) is.null(cy$theta[[estimand]]), logical(1))
  if (any(miss))
    stop(sprintf(paste0("Estimand '%s' is missing from carr%s %s. A linear combination needs ",
                        "the same estimand declared in every period; available here: %s."),
                 estimand, if (sum(miss) > 1L) "ies" else "y",
                 paste(which(miss), collapse = ", "),
                 paste(names(carries[[1]]$theta), collapse = ", ")), call. = FALSE)

  R <- vapply(carries, function(cy) length(cy$theta[[estimand]]), integer(1))
  if (length(unique(R)) != 1L)
    stop(sprintf(paste0("The replicate count must be constant along the chain, but the carries ",
                        "carry %s. A combination pairs replicate b across periods, so they ",
                        "have to line up."), paste(R, collapse = ", ")), call. = FALSE)
  R <- R[1L]

  Th <- vapply(carries, function(cy) as.numeric(cy$theta[[estimand]]), numeric(R))
  if (!is.matrix(Th)) Th <- matrix(Th, nrow = R)
  ok <- stats::complete.cases(Th) & apply(is.finite(Th), 1L, all)
  if (sum(ok) < 2L)
    stop("Fewer than two replicates are finite in every period; cannot form a covariance.",
         call. = FALSE)
  if (sum(ok) < R)
    warning(R - sum(ok), " replicate(s) dropped (non-finite in at least one period).",
            call. = FALSE)
  Th <- Th[ok, , drop = FALSE]
  theta <- vapply(carries, function(cy) as.numeric(cy$point[[estimand]]), 0)
  # Centre on the POINT estimate, not on the replicate mean, and divide by R rather than R - 1.
  # This is what wave_step() itself does (V = mean((theta_b - theta_hat)^2)), so a contrast of
  # c(-1, 1) reproduces its $change bit for bit. stats::cov() would centre on colMeans(Th) and
  # use R - 1, which differs from the reported change in the fourth significant digit -- small,
  # but it would mean the two paths disagree about the same quantity.
  D <- sweep(Th, 2L, theta, "-")
  S <- crossprod(D) / nrow(D)
  dimnames(S) <- list(vapply(carries, function(cy) as.character(cy$period), ""),
                      vapply(carries, function(cy) as.character(cy$period), ""))

  psi   <- sum(a * theta)
  V     <- drop(t(a) %*% S %*% a)
  se    <- sqrt(max(V, 0))
  crit  <- stats::qnorm(1 - (1 - level) / 2)
  out <- data.frame(
    estimand = estimand,
    periods  = paste(rownames(S), collapse = " + "),
    contrast = paste(format(a, trim = TRUE), collapse = ", "),
    estimate = psi, se = se, V = V,
    lo = psi - crit * se, hi = psi + crit * se,
    R_used = nrow(Th), stringsAsFactors = FALSE)
  attr(out, "Sigma") <- S
  attr(out, "theta") <- stats::setNames(theta, rownames(S))
  out
}
