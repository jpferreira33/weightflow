# post-calibration steps: rounding, trimming, model-assisted calibration, assert, rescale.

# --- Weight rounding -------------------------------------------------------
apply_step.step_round <- function(step, data, w) {
  active <- w > 0
  new_w  <- w
  f      <- 10^step$digits
  sum_before <- sum(w[active])

  if (step$method == "nearest") {
    new_w[active] <- round(w[active], step$digits)
  } else {
    # largest-remainder method: preserves the sum (on the `digits` scale)
    x      <- w[active] * f
    fl     <- floor(x)
    target <- round(sum(x))
    k      <- as.integer(round(target - sum(fl)))   # how many to round up
    if (k > 0) {
      ord <- order(x - fl, decreasing = TRUE)
      fl[ord[seq_len(min(k, length(fl)))]] <- fl[ord[seq_len(min(k, length(fl)))]] + 1
    }
    new_w[active] <- fl / f
  }

  diag <- data.frame(
    method     = step$method,
    decimals   = step$digits,
    sum_before = round(sum_before, 2),
    sum_after  = round(sum(new_w[active]), 2),
    n_modified = sum(abs(new_w[active] - w[active]) > 1e-9),
    stringsAsFactors = FALSE
  )
  list(weights = new_w, diagnostics = diag)
}

# --- Trimming (capping extreme weights) ------------------------------------
apply_step.step_trim <- function(step, data, w) {
  n      <- length(w)
  active <- w > 0
  new_w  <- w

  # Cells first: with reference = "median" the threshold is computed WITHIN each
  # `by` group, so a differentiated trim uses each subgroup's own median (not a
  # single global median). With by = NULL there is one group (the whole sample).
  cells  <- .make_cells(data, step$by, n)

  # Define the cap and floor per unit according to the reference
  base_w <- attr(data, "weightflow_base_w")
  cap   <- numeric(n); floor_v <- rep(0, n)
  if (step$reference == "base") {
    if (is.null(base_w)) stop("reference = 'base' requires the base weights (provided by prep()).")
    cap[]     <- step$max_ratio * base_w
    if (!is.null(step$min_ratio)) floor_v[] <- step$min_ratio * base_w
  } else if (step$reference == "median") {
    for (g in levels(cells)) {               # per-group median threshold
      gi <- which(cells == g & active)
      if (!length(gi)) next
      med <- stats::median(new_w[gi])
      cap[gi] <- step$max_ratio * med
      if (!is.null(step$min_ratio)) floor_v[gi] <- step$min_ratio * med
    }
  } else {                                   # "value": absolute
    cap[]     <- step$max_ratio
    if (!is.null(step$min_ratio)) floor_v[] <- step$min_ratio
  }

  deff_before <- design_effect(new_w)$deff

  # Iterative cap + redistribution (Potter/NAEP style), group by group
  total_trimmed <- 0L
  it_global     <- 0L
  for (g in levels(cells)) {
    gi <- which(cells == g & active)
    if (!length(gi)) next
    it <- 0L
    repeat {
      it <- it + 1L
      over        <- gi[new_w[gi] > cap[gi]]
      under_floor <- gi[new_w[gi] < floor_v[gi]]
      if (!length(over) && !length(under_floor)) break
      if (it > step$maxit) break

      excess <- 0
      if (length(over)) {
        excess <- excess + sum(new_w[over] - cap[over])
        new_w[over] <- cap[over]
      }
      if (length(under_floor)) {                # raise weights below the floor
        excess <- excess - sum(floor_v[under_floor] - new_w[under_floor])
        new_w[under_floor] <- floor_v[under_floor]
      }
      total_trimmed <- total_trimmed + length(over)

      if (!step$redistribute || abs(excess) < 1e-12) {
        if (!step$redistribute) break
        next
      }
      # spread the excess proportionally among those within band
      free <- gi[new_w[gi] < cap[gi] & new_w[gi] > floor_v[gi]]
      if (!length(free)) break                  # nowhere to redistribute
      new_w[free] <- new_w[free] + excess * new_w[free] / sum(new_w[free])
    }
    it_global <- max(it_global, it)
  }

  deff_after <- design_effect(new_w)$deff
  diag <- data.frame(
    reference   = step$reference,
    cap         = step$max_ratio,
    floor       = ifelse(is.null(step$min_ratio), NA, step$min_ratio),
    trimmed     = total_trimmed,
    redistributed = step$redistribute,
    deff_before = round(deff_before, 3),
    deff_after  = round(deff_after, 3),
    stringsAsFactors = FALSE
  )
  attr(diag, "iterations") <- it_global
  list(weights = new_w, diagnostics = diag)
}

# --- Model calibration (Wu & Sitter 2001) ----------------------------------
# Calibrates simultaneously to the X totals (consistency) and to the population
# totals of each model y prediction (model-assisted efficiency).
apply_step.step_model_calibration <- function(step, data, w) {
  active <- w > 0
  new_w  <- w
  d      <- w[active]
  sdata  <- data[active, , drop = FALSE]
  pop    <- step$population

  # Consistency block: X auxiliaries
  X  <- stats::model.matrix(step$x_formula, data = sdata)
  if (nrow(X) != length(d) || anyNA(X))
    stop("Auxiliaries in `x_formula` have missing values (NA) in the active ",
         "sample; model calibration needs a value for every unit. Impute them ",
         "first, or use a complete auxiliary.")
  cn <- colnames(X)
  # X totals may come from the frame (default) or from an external source.
  if (is.null(step$x_totals)) {
    # from the population frame, as before
    Xpop <- stats::model.matrix(step$x_formula, data = pop)
    Tx   <- colSums(Xpop)[cn]
    if (anyNA(Tx))
      stop("Inconsistent factor levels between the sample and `population` in x_formula.")
  } else {
    # external totals, same two shapes as step_calibrate(method = "linear"):
    #   - tidy: a NAMED LIST (data frame per factor, number per continuous)
    #   - classic: a named numeric vector aligned with the model.matrix columns
    # `x_formula` columns are only required in the sample, not in `population`.
    if (is.list(step$x_totals) && !is.data.frame(step$x_totals)) {
      totvec <- .prep_linear_totals(step$x_formula, step$x_totals, step$count,
                                    data, active)
    } else {
      totvec <- step$x_totals
    }
    if (!setequal(names(totvec), cn))
      stop(sprintf(
        paste0("`x_totals` names must match the model.matrix columns of ",
               "`x_formula`.\nExpected: %s"), paste(cn, collapse = ", ")))
    Tx <- as.numeric(totvec[cn]); names(Tx) <- cn
  }

  # Model-assisted block: one prediction column per model y
  mu_cols <- list(); Tmu <- numeric(0)
  for (k in names(step$models)) {
    m <- step$models[[k]]
    if (is.null(step$crossfit)) {
      preds        <- .model_predict(m, sdata, d, list(sdata, pop))
      mu_cols[[k]] <- preds[[1]]          # prediction on the sample
      Tmu[k]       <- sum(preds[[2]])     # population total of the prediction
    } else {
      cl_cf <- if (!is.null(step$cluster)) as.character(sdata[[step$cluster]]) else NULL
      mu_cols[[k]] <- .crossfit_predict(   # out-of-fold predictions on the sample
        nrow(sdata), step$crossfit, cl_cf, step$crossfit_seed,
        fit_predict = function(tr, te_list)
          .model_predict(m, sdata[tr, , drop = FALSE], d[tr],
                         lapply(te_list, function(te) sdata[te, , drop = FALSE])))
      Tmu[k] <- sum(.model_predict(m, sdata, d, list(pop))[[1]])  # full model -> pop total
    }
  }

  Z  <- cbind(X, do.call(cbind, mu_cols))
  colnames(Z) <- c(colnames(X), names(step$models))
  Tvec <- c(Tx, Tmu)

  if (!step$equal_within_cluster) {
    # Unit-level linear calibration
    A      <- t(Z) %*% (d * Z)
    rhs    <- Tvec - colSums(d * Z)
    lambda <- .solve_calib(A, rhs)
    g      <- as.numeric(1 + Z %*% lambda)
    new_w[active] <- d * g
    note_clust <- ""
  } else {
    # Integrative calibration (Lemaitre-Dufour 1987): household-MEAN replacement,
    # person-level calibration -> one weight per household (matches survey's
    # aggregate.stage / Vanderhoeft 2001; ReGenesees uses a different variant).
    if (!step$cluster %in% names(data))
      stop(sprintf("Cluster column '%s' not found in the data.", step$cluster))
    cl <- as.character(data[[step$cluster]])[active]
    if (anyNA(cl))
      stop(sprintf("Cluster column '%s' has missing values (NA).", step$cluster))
    hh   <- unique(cl)
    n_h  <- as.numeric(tapply(d, cl, length)[hh])   # persons per household
    Wsum <- as.numeric(tapply(d, cl, sum)[hh])      # total base weight in household
    Xbar <- rowsum(Z, group = cl)[hh, , drop = FALSE] / n_h  # household MEANS of Z
    A      <- t(Xbar) %*% (Wsum * Xbar)
    rhs    <- Tvec - colSums(Wsum * Xbar)
    lambda <- .solve_calib(A, rhs)
    gh     <- as.numeric(1 + Xbar %*% lambda)
    names(gh) <- hh
    new_w[active] <- d * gh[cl]                     # own base weight x household g-factor
    g <- gh
    note_clust <- sprintf("; one weight per '%s' (integrative)", step$cluster)
  }

  achieved <- colSums(new_w[active] * Z)
  # Check that the calibration constraints (X and model blocks) are satisfied.
  # Model calibration is unbounded linear, so deviations only arise from
  # collinear auxiliaries or an ill-conditioned system.
  rel_dev <- abs(achieved - Tvec) / (abs(Tvec) + 1)
  off     <- which(rel_dev > 1e-6)
  if (length(off) > 0L)
    warning(sprintf(
      paste0("Model calibration did not fully satisfy the constraints for: %s. ",
             "The achieved totals differ from the targets (max relative ",
             "deviation = %.2e); this can happen with collinear auxiliaries or ",
             "an ill-conditioned system; check the auxiliary variables."),
      paste(utils::head(colnames(Z)[off], 10L), collapse = ", "), max(rel_dev)),
      call. = FALSE)
  type <- c(rep("X (consistency)", ncol(X)),
            rep("y (model)", length(step$models)))
  diag <- data.frame(constraint = colnames(Z), type = type,
                     target = round(Tvec, 2), achieved = round(achieved, 2),
                     stringsAsFactors = FALSE)
  attr(diag, "converged") <- (length(off) == 0L)
  attr(diag, "note") <- sprintf("g (calibration factor) in [%.3f, %.3f]%s",
                                min(g), max(g), note_clust)
  list(weights = new_w, diagnostics = diag)
}

# --- Assert / checkpoint ---------------------------------------------------
apply_step.step_assert <- function(step, data, w) {
  de     <- design_effect(w)
  base_w <- attr(data, "weightflow_base_w")
  active <- w > 0
  checks <- list()
  add <- function(name, value, thr, pass)
    checks[[length(checks) + 1]] <<- data.frame(
      check = name, value = round(value, 3), threshold = thr, pass = pass,
      stringsAsFactors = FALSE)

  if (!is.null(step$max_deff))
    add("deff <= max", de$deff, step$max_deff, de$deff <= step$max_deff)
  if (!is.null(step$min_n_eff))
    add("n_eff >= min", de$n_eff, step$min_n_eff, de$n_eff >= step$min_n_eff)
  if (!is.null(step$max_weight_ratio)) {
    if (is.null(base_w)) stop("max_weight_ratio needs the base weights (provided by prep()).")
    mr <- max(w[active] / base_w[active])
    add("max(w/base) <= max", mr, step$max_weight_ratio, mr <= step$max_weight_ratio)
  }
  diag <- do.call(rbind, checks)
  if (!is.null(diag) && any(!diag$pass)) {
    failed <- diag$check[!diag$pass]
    msg <- sprintf("Assertion(s) not met: %s", paste(failed, collapse = "; "))
    if (step$on_fail == "error") stop(msg, call. = FALSE) else warning(msg, call. = FALSE)
  }
  list(weights = w, diagnostics = diag)         # weights unchanged
}

# --- Automatic weight trimming (survey-style) ------------------------------
# Potter (1990) MSE-optimal trimming threshold. Over a grid of candidate upper
# cutoffs, approximate the mean squared error of the (weight) total as
#   bias(t)^2 + variance(t),
# where bias(t) is the total weight trimmed above t (the amount the estimator
# shifts before redistribution) and variance(t) is proportional to the sum of
# squared weights that remain after capping at t. The cutoff with the smallest
# estimated MSE is returned. The grid runs over the upper tail of the weights.
.potter_threshold <- function(wv, ngrid = 100L) {
  qs   <- stats::quantile(wv, c(0.50, 0.999))
  grid <- seq(as.numeric(qs[1]), as.numeric(qs[2]), length.out = ngrid)
  mse  <- vapply(grid, function(t) {
    capped <- pmin(wv, t)
    bias   <- sum(wv[wv > t] - t)            # weight removed above the cutoff
    varc   <- sum(capped^2)                  # dispersion remaining after capping
    bias^2 + varc
  }, numeric(1))
  grid[which.min(mse)]
}

apply_step.step_trim_weights <- function(step, data, w) {
  active <- w != 0          # trim every non-zero weight (incl. negatives from
  new_w  <- w               # unbounded calibration); leave dropped units (w == 0)
  wv     <- new_w[active]

  upper <- step$upper
  if (is.null(upper)) {
    if (identical(step$method, "potter")) {
      upper <- .potter_threshold(wv)                 # MSE-optimal cutoff (Potter)
    } else {
      q  <- stats::quantile(wv, c(.25, .75))
      upper <- as.numeric(q[2] + 3 * (q[2] - q[1]))  # Tukey far-out fence
    }
  }
  lower <- step$lower

  it <- 0L
  if (identical(step$redistribute, "uniform")) {
    # survey::trimWeights scheme: share the trimmed mass EQUALLY among the
    # untrimmed units, and never reuse a unit that has already been trimmed.
    has_trimmed <- rep(FALSE, length(wv))
    repeat {
      it      <- it + 1L
      outside <- wv < lower | wv > upper
      if (!any(outside) || it > step$maxit) break
      wvnew     <- pmin(pmax(wv, lower), upper)
      trimmings <- wv - wvnew
      can_trim  <- !outside & !has_trimmed
      if (any(can_trim))
        wvnew[can_trim] <- wvnew[can_trim] + sum(trimmings) / sum(can_trim)
      has_trimmed <- outside | has_trimmed
      wv <- wvnew
      if (!step$strict) break
    }
  } else {
    # proportional (default): share the trimmed mass in proportion to weights.
    repeat {
      it    <- it + 1L
      over  <- wv > upper
      under <- wv < lower
      if (!any(over) && !any(under)) break
      if (it > step$maxit) break
      # net weight removed by clamping (high trimmed minus low raised)
      net <- sum(wv[over] - upper) - sum(lower - wv[under])
      wv[over]  <- upper
      wv[under] <- lower
      free <- wv < upper & wv > lower
      if (abs(net) > 1e-12 && any(free))          # redistribute to preserve total
        wv[free] <- wv[free] + net * wv[free] / sum(wv[free])
      if (!step$strict) break
    }
  }
  new_w[active] <- wv

  diag <- data.frame(
    method = if (is.null(step$method)) "tukey" else step$method,
    lower = lower, upper = round(upper, 3), strict = step$strict,
    n_capped = sum(w[active] > upper), n_raised = sum(w[active] < lower),
    sum_before = round(sum(w[active]), 2), sum_after = round(sum(new_w[active]), 2),
    stringsAsFactors = FALSE
  )
  attr(diag, "iterations") <- it
  list(weights = new_w, diagnostics = diag)
}

# --- Trimmed (range-restricted) calibration --------------------------------
# Trim the incoming (calibration) weights to an absolute interval [lower, upper]
# WHILE PRESERVING the calibration totals of `formula`. This is not a clip: it is
# a bounded re-calibration (Folsom & Singh 2000, GEM). The targets to preserve
# are the totals the incoming weights already achieve
# (T = sum_k w_k x_k), and the absolute-weight bound w_k in [lower, upper] is
# imposed as a per-unit factor bound f_k = w_k^new / w_k in [lower/w_k, upper/w_k]
# on top of the incoming weights, using the range-restricted Euclidean distance
# (calfun = "linear", the default) or the multiplicative one ("raking").
# Units within range and not needed to restore the totals stay put (f_k ~ 1);
# out-of-range units saturate at their bound and the rest move minimally.
# Expand an absolute-weight bound to one value per active unit. `b` is NULL
# (use `default`), a single number (same bound for all), or a named vector of
# bounds per `by` group (names = the group levels); `grp` gives each active
# unit's group. Used by trimmed calibration for subgroup-specific bounds.
.expand_bound <- function(b, grp, n, default, nm) {
  if (is.null(b))        return(rep(default, n))
  if (length(b) == 1L)   return(rep(as.numeric(b), n))
  if (is.null(grp))
    stop(sprintf(paste0("`%s` has length > 1 but no `by` was given. Supply `by` ",
                        "and a named vector of %s bounds per group, or a single number."),
                 nm, nm))
  if (is.null(names(b)))
    stop(sprintf(paste0("`%s` must be a NAMED vector (names = the `by` group ",
                        "levels) when it varies by group."), nm))
  miss <- setdiff(unique(grp), names(b))
  if (length(miss))
    stop(sprintf("`%s` has no value for these `by` group(s): %s.",
                 nm, paste(miss, collapse = ", ")))
  as.numeric(b[grp])
}

apply_step.step_trim_calibrated <- function(step, data, w) {
  active <- w > 0                      # only positive calibration weights
  if (!any(active)) return(list(weights = w, diagnostics = NULL))
  new_w <- w
  d     <- w[active]                   # incoming weights = base for this step

  dd <- data[active, , drop = FALSE]
  X  <- stats::model.matrix(step$formula, data = dd)
  if (nrow(X) != length(d) || anyNA(X))
    stop("Auxiliaries in `formula` have missing values in the active sample; ",
         "trimmed calibration needs them observed for every unit being trimmed.")
  cn <- colnames(X)

  # Totals to PRESERVE: the ones the incoming weights already reproduce.
  Tvec <- colSums(d * X)

  # Per-unit absolute bounds. With `by`, each subgroup can have its own bounds
  # (Option A: the preserved totals stay global; only the bounds differ).
  if (!is.null(step$by) && !step$by %in% names(dd))
    stop(sprintf("`by` column '%s' not found in the data.", step$by))
  grp   <- if (is.null(step$by)) NULL else as.character(dd[[step$by]])
  lower <- .expand_bound(step$lower, grp, length(d), -Inf, "lower")
  upper <- .expand_bound(step$upper, grp, length(d),  Inf, "upper")
  if (any(lower >= upper))
    stop("`lower` must be strictly below `upper` (for every subgroup).")
  n_below <- sum(d < lower)
  n_above <- sum(d > upper)

  # Absolute-weight bound -> factor bound. Always bounded, so go straight to the
  # Deville-Sarndal iterative solver (honouring this step's own maxit/tol).
  if (!step$equal_within_cluster) {
    # unit level: per-unit factor bound f_k in [lower/w_k, upper/w_k]
    bnd  <- cbind(lower / d, upper / d)
    gsol <- .calib_ds(X, d, Tvec, calfun = step$calfun, bounds = bnd,
                      maxit = step$maxit, tol = step$tol)
    f    <- as.numeric(gsol)
    note_clust <- ""
  } else {
    # integrative: one factor per cluster (Lemaitre-Dufour household means). The
    # incoming weights are constant within household, so the person-weight bound
    # w = d*f in [lower, upper] becomes a per-household factor bound on the common
    # household weight d_h = Wsum_h / n_h.
    if (!step$cluster %in% names(data))
      stop(sprintf("Cluster column '%s' not found in the data.", step$cluster))
    cl <- as.character(data[[step$cluster]])[active]
    if (anyNA(cl))
      stop(sprintf("Cluster column '%s' has missing values (NA).", step$cluster))
    hh    <- unique(cl)
    n_h   <- as.numeric(tapply(d, cl, length)[hh])
    Wsum  <- as.numeric(tapply(d, cl, sum)[hh])
    Xbar  <- rowsum(X, group = cl)[hh, , drop = FALSE] / n_h
    d_h   <- Wsum / n_h                                  # common household weight
    lo_h  <- as.numeric(tapply(lower, cl, function(x) x[1])[hh])  # bound per household
    up_h  <- as.numeric(tapply(upper, cl, function(x) x[1])[hh])
    bnd_h <- cbind(lo_h / d_h, up_h / d_h)
    gsol  <- .calib_ds(Xbar, Wsum, Tvec, calfun = step$calfun, bounds = bnd_h,
                       maxit = step$maxit, tol = step$tol)
    fh    <- as.numeric(gsol); names(fh) <- hh
    f     <- fh[cl]
    note_clust <- sprintf("; one factor per '%s' (integrative)", step$cluster)
  }
  new_w[active] <- d * f

  # --- diagnostics ---
  wa       <- new_w[active]
  achieved <- colSums(wa * X)
  rel_dev  <- abs(achieved - Tvec) / (abs(Tvec) + 1)
  conv_ok  <- isTRUE(attr(gsol, "converged")) && max(rel_dev) <= 1e-6
  # bounds may be per-unit (subgroup `by`); label them as a single value when
  # constant, else "by group", and count units at their OWN bound.
  lo_lab <- if (length(unique(lower)) == 1L) format(lower[1]) else "by group"
  up_lab <- if (length(unique(upper)) == 1L) format(upper[1]) else "by group"
  if (!conv_ok)
    warning(sprintf(paste0("Trimmed calibration could not both stay within ",
      "[%s, %s] and preserve every total (max relative deviation = %.2e). ",
      "The range may be infeasible; widen the bounds or relax the constraints."),
      lo_lab, up_lab, max(rel_dev)), call. = FALSE)
  fin         <- c(lower, upper); fin <- fin[is.finite(fin)]
  tolb        <- 1e-6 * max(abs(fin), 1)          # scale from the finite bound(s)
  n_at_lower  <- sum(is.finite(lower) & abs(wa - lower) <= tolb)
  n_at_upper  <- sum(is.finite(upper) & abs(wa - upper) <= tolb)
  diag <- data.frame(variable = cn, target = round(Tvec, 2),
                     achieved = round(achieved, 2), stringsAsFactors = FALSE)
  attr(diag, "converged") <- conv_ok
  attr(diag, "note") <- sprintf(
    paste0("trimmed calibration to [%s, %s] (calfun = %s); %d weights raised to ",
           "lower, %d capped at upper; f (adjustment) in [%.3f, %.3f]%s"),
    lo_lab, up_lab, step$calfun, n_at_lower, n_at_upper,
    min(f), max(f), note_clust)
  attr(diag, "trim") <- data.frame(
    lower = if (length(unique(lower)) == 1L) lower[1] else NA_real_,
    upper = if (length(unique(upper)) == 1L) upper[1] else NA_real_,
    calfun = step$calfun,
    n_below_before = n_below, n_above_before = n_above,
    n_at_lower = n_at_lower, n_at_upper = n_at_upper,
    sum_before = round(sum(d), 2), sum_after = round(sum(wa), 2),
    stringsAsFactors = FALSE)
  list(weights = new_w, diagnostics = diag)
}

# --- Rescale / normalize ---------------------------------------------------
apply_step.step_rescale <- function(step, data, w) {
  n      <- length(w)
  active <- w > 0
  new_w  <- w

  if (step$to == "total") {                       # scale overall to `total`
    cur <- sum(new_w[active])
    fac <- if (cur > 0) step$total / cur else NA_real_
    if (!is.na(fac)) new_w[active] <- new_w[active] * fac
    diag <- data.frame(cell = "(all)", target = round(step$total, 2),
                       prev_sum = round(cur, 2), factor = round(fac, 4),
                       stringsAsFactors = FALSE)
    return(list(weights = new_w, diagnostics = diag))
  }

  # to == "n": each (by-)group sums to its active count (mean weight 1)
  cells <- .make_cells(data, step$by, n)
  diag  <- list()
  for (g in levels(cells)) {
    idx <- which(cells == g & active)
    if (!length(idx)) next
    cur <- sum(new_w[idx]); target <- length(idx)
    fac <- if (cur > 0) target / cur else NA_real_
    if (!is.na(fac)) new_w[idx] <- new_w[idx] * fac
    diag[[length(diag) + 1]] <- data.frame(
      cell = g, target = target, prev_sum = round(cur, 2),
      factor = round(fac, 4), stringsAsFactors = FALSE)
  }
  list(weights = new_w, diagnostics = do.call(rbind, diag))
}


# =========================================================================
# Helpers for the tidy `totals` input to post-stratification (step_calibrate)
# =========================================================================

# Normalise and validate a data.frame/tibble of population counts for
# post-stratification. Infers the post-stratification variables (every column
# except `count`), builds cell keys (all coerced to character for matching),
# and runs the validation cascade:
#   - structure: `count` present & numeric; category columns present in `data`
#   - Rule 1: cells in the sample but not in `totals` -> error (conceptual)
#   - Rule 2: cells in `totals` but not in the sample -> warning, calibrate anyway
# Returns list(cells, vars, sample_key, note).
# =========================================================================
# Reconcile tidy control totals that do not all sum to the same N
# =========================================================================
# When the tidy margins/totals do not sum to a common population size N, keep
# the LARGEST as the reference and rescale the others proportionally. Only the
# internal distribution of each margin matters to raking/GREG, so proportional
# rescaling lets the tidy interface always CLOSE (instead of erroring or, for
# raking, failing to converge). The adjustment is reported so the user can
# review the control totals. `Ns` is a named numeric vector (one N per margin).
# Returns list(target, factors, note); note is NULL when the Ns already agree.
