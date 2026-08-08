# calibration steps: domain-partitioned calibration and apply_step.step_calibrate().

# --- Domain (partitioned) calibration --------------------------------------
# Split one tidy totals table to a single domain `d`: keep the rows of that
# domain, drop the domain column. A table with the `count` column stays a
# (categorical) data frame; a 2-column table without `count` (a continuous
# total given as `domain, value`) collapses to the single number for `d`.
.split_totals_by_domain <- function(totals, byvar, count, d) {
  split_one <- function(t) {
    if (!is.data.frame(t)) return(t)
    if (!byvar %in% names(t))
      stop(sprintf("The calibration totals are missing the domain column '%s'.", byvar))
    sub <- t[as.character(t[[byvar]]) == d, , drop = FALSE]
    sub[[byvar]] <- NULL
    rownames(sub) <- NULL
    if (!is.null(count) && !(count %in% names(sub)) && ncol(sub) == 1L)
      return(as.numeric(sub[[1L]][1L]))           # continuous total -> single number
    sub
  }
  if (is.data.frame(totals)) split_one(totals)
  else if (is.list(totals)) { out <- lapply(totals, split_one); names(out) <- names(totals); out }
  else totals
}

# Calibrate independently within each domain and stitch the weights back.
.calibrate_by_domain <- function(step, data, w) {
  byvar <- step$by
  if (!byvar %in% names(data))
    stop(sprintf("Domain column '%s' not found in the data.", byvar))
  dom    <- as.character(data[[byvar]])
  active <- w > 0
  if (any(is.na(dom[active])))
    stop(sprintf("Domain column '%s' has missing values (NA) among active units.", byvar))

  new_w <- w
  diags <- list()
  doms  <- unique(dom[active])
  for (d in doms) {
    idx_d  <- which(dom == d)
    step_d <- step
    step_d$by     <- NULL                          # avoid recursion; calibrate this domain
    step_d$totals <- .split_totals_by_domain(step$totals, byvar, step$count, d)
    res_d <- apply_step(step_d, data[idx_d, , drop = FALSE], w[idx_d])
    new_w[idx_d] <- res_d$weights
    dg <- res_d$diagnostics
    if (!is.null(dg) && nrow(dg) > 0L)
      diags[[length(diags) + 1L]] <- cbind(domain = d, dg)
  }
  diag <- if (length(diags)) do.call(rbind, diags) else NULL
  if (!is.null(diag))
    attr(diag, "note") <- sprintf("calibrated independently within '%s' (%d domains)",
                                  byvar, length(doms))
  list(weights = new_w, diagnostics = diag)
}

# --- Calibration -----------------------------------------------------------
apply_step.step_calibrate <- function(step, data, w) {
  active <- w > 0
  new_w  <- w

  if (!is.null(step$by)) return(.calibrate_by_domain(step, data, w))

  if (step$method == "poststratify") {
    # --- tidy `totals` data frame (one or more category columns + counts) ---
    if (is.data.frame(step$totals)) {
      prep <- .prep_poststrata(step$totals, step$count, data, active)
      out  <- .poststratify_calc(prep, new_w, active)
      return(list(weights = out$weights, diagnostics = out$diagnostics))
    }
    # --- classic `margins` named list (unchanged) ---
    if (length(step$margins) != 1L)
      stop("poststratify uses exactly one variable in `margins`.")
    v      <- names(step$margins)[1]
    target <- step$margins[[1]]
    f      <- as.character(data[[v]])
    diag   <- list()
    for (lev in names(target)) {
      idx <- which(f == lev & active)
      cur <- sum(new_w[idx])
      fac <- if (cur > 0) target[[lev]] / cur else NA_real_
      if (!is.na(fac)) new_w[idx] <- new_w[idx] * fac
      diag[[length(diag) + 1]] <- data.frame(
        variable = v, category = lev, target = target[[lev]],
        prev_total = cur, factor = fac, stringsAsFactors = FALSE
      )
    }
    return(list(weights = new_w, diagnostics = do.call(rbind, diag)))
  }

  if (step$method == "linear") {
    # Linear / GREG calibration. Handles continuous and categorical auxiliaries.
    # Closed form for unbounded linear; Deville-Sarndal solver for bounded or
    # logit (calfun), which keeps g within `bounds`.
    d  <- new_w[active]
    X  <- stats::model.matrix(step$formula, data = data[active, , drop = FALSE])
    if (nrow(X) != length(d) || anyNA(X))
      stop("Auxiliaries in `formula` have missing values (NA) in the active ",
           "sample; calibration needs a value for every unit. Impute them first, ",
           "or calibrate on a complete auxiliary.")
    cn <- colnames(X)
    # `totals` may be given two ways:
    #   - tidy: a NAMED LIST (data frame per categorical, number per continuous)
    #     -> translate to the model.matrix totals vector
    #   - classic: a named numeric vector aligned with the model.matrix columns
    if (is.list(step$totals) && !is.data.frame(step$totals)) {
      totvec <- .prep_linear_totals(step$formula, step$totals, step$count,
                                    data, active)
    } else {
      totvec <- step$totals
    }
    if (!setequal(names(totvec), cn))
      stop(sprintf(
        "`totals` names must match the model.matrix columns.\nExpected: %s",
        paste(cn, collapse = ", ")))
    Tvec     <- as.numeric(totvec[cn])      # reorder to X columns
    # Closed form only for plain linear (calfun = "linear", no bounds). The
    # exponential ("raking") distance, logit, or explicit bounds use the
    # iterative Deville-Sarndal solver. Only bounds/logit may relax the
    # constraints; the exponential distance is exact when it converges.
    use_ds    <- step$calfun != "linear" || !is.null(step$bounds)
    truncated <- !is.null(step$bounds) || step$calfun == "logit"
    if (!is.null(step$penalty) && use_ds)
      stop("`penalty` (ridge) is only available for unbounded linear ",
           "calibration (calfun = \"linear\" without bounds).")

    ds_converged <- TRUE
    if (!step$equal_within_cluster) {
      # --- unit-level ---
      sol <- .solve_calibration(X, d, Tvec, step$calfun, step$bounds,
                                step$penalty, step$maxit, step$tol)
      g            <- sol$g
      ds_converged <- sol$converged
      new_w[active] <- d * g
      note_clust <- ""

    } else {
      # --- integrative calibration (Lemaitre-Dufour 1987): one weight/household ---
      if (!step$cluster %in% names(data))
        stop(sprintf("Cluster column '%s' not found in the data.", step$cluster))
      cl <- as.character(data[[step$cluster]])[active]
      if (anyNA(cl))
        stop(sprintf("Cluster column '%s' has missing values (NA).", step$cluster))
      # Lemaitre-Dufour: replace each person's auxiliaries by the HOUSEHOLD MEAN
      # and calibrate at the person level, so all members share one weight. The
      # per-household mass is the household's total base weight (sum over persons),
      # i.e. the penalty scales with household size. This matches survey's
      # aggregate.stage (Vanderhoeft 2001), to machine precision. (ReGenesees
      # implements a different integrative variant, so it need not agree.)
      hh   <- unique(cl)
      n_h  <- as.numeric(tapply(d, cl, length)[hh])       # persons per household
      Wsum <- as.numeric(tapply(d, cl, sum)[hh])          # total base weight in household
      Xbar <- rowsum(X, group = cl)[hh, , drop = FALSE] / n_h   # household MEANS
      sol  <- .solve_calibration(Xbar, Wsum, Tvec, step$calfun, step$bounds,
                                 step$penalty, step$maxit, step$tol)
      gh           <- sol$g
      ds_converged <- sol$converged
      names(gh) <- hh
      new_w[active] <- d * gh[cl]          # each person: own base weight x household g-factor
      g          <- gh
      note_clust <- sprintf("; one weight per '%s' (integrative)", step$cluster)
    }

    # Achieved totals with the REAL X (must match the targets, except under ridge)
    achieved <- colSums(new_w[active] * X)
    # Check that the calibration constraints are satisfied (unless ridge, where
    # relaxation is intentional, or bounded, which has its own convergence warn).
    conv_ok <- TRUE
    if (is.null(step$penalty) && !truncated) {
      rel_dev <- abs(achieved - Tvec) / (abs(Tvec) + 1)
      off <- which(rel_dev > 1e-6)
      if (length(off) > 0L) {
        conv_ok <- FALSE
        warning(sprintf(
          paste0("Linear calibration did not fully satisfy the constraints for: ",
                 "%s. The achieved totals differ from the targets (max relative ",
                 "deviation = %.2e). This can happen with collinear auxiliaries ",
                 "or an ill-conditioned system; check the auxiliary variables."),
          paste(utils::head(cn[off], 10L), collapse = ", "), max(rel_dev)),
          call. = FALSE)
      }
    } else if (truncated) {
      conv_ok <- ds_converged
    }
    diag <- data.frame(variable = cn, target = Tvec,
                       achieved = round(achieved, 2), stringsAsFactors = FALSE)
    if (!is.null(step$penalty))
      diag$deviation <- round(achieved - Tvec, 2)
    attr(diag, "converged") <- conv_ok
    attr(diag, "reconcile") <- attr(totvec, "reconcile")
    bnote <- if (use_ds)
      sprintf(" [calfun = %s%s]", step$calfun,
              if (!is.null(step$bounds)) sprintf(", bounds (%.2f, %.2f)",
                                                 step$bounds[1], step$bounds[2]) else "")
    else ""
    rnote <- if (!is.null(step$penalty))
      sprintf(" [ridge: constraints relaxed, not exact]") else ""
    attr(diag, "note") <- sprintf(
      "g (calibration factor) in [%.3f, %.3f]%s%s%s",
      min(g), max(g), bnote, rnote, note_clust)
    return(list(weights = new_w, diagnostics = diag))
  }

  # method == "raking": iterative proportional fitting (IPF)

  # --- tidy `totals`: a LIST of data frames (one per margin) ---
  if (is.list(step$totals) && !is.data.frame(step$totals) &&
      length(step$totals) > 0L && is.data.frame(step$totals[[1]])) {
    mprep <- .prep_raking_margins(step$totals, step$count, data, active)
    out   <- .raking_calc(mprep, new_w, active, step$maxit, step$tol)
    return(list(weights = out$weights, diagnostics = out$diagnostics))
  }

  # --- classic `margins` named list (unchanged behaviour + convergence warn) ---
  it <- 0L; maxdiff <- Inf
  while (it < step$maxit && maxdiff >= step$tol) {
    it <- it + 1L; maxdiff <- 0
    for (v in names(step$margins)) {
      target <- step$margins[[v]]
      f      <- as.character(data[[v]])
      for (lev in names(target)) {
        idx <- which(f == lev & active)
        cur <- sum(new_w[idx])
        if (cur > 0) {
          adj        <- target[[lev]] / cur
          new_w[idx] <- new_w[idx] * adj
          maxdiff    <- max(maxdiff, abs(adj - 1))
        }
      }
    }
  }
  if (maxdiff >= step$tol) {
    warning(sprintf(
      paste0("Raking did not converge after %d iterations (max relative change ",
             "= %.2e, tolerance = %.2e). The returned weights do not fully ",
             "satisfy all margins. Consider increasing `maxit`, or check that ",
             "the margin totals are mutually consistent."),
      it, maxdiff, step$tol), call. = FALSE)
  }
  # diagnostics: final target vs achieved
  diag <- list()
  for (v in names(step$margins)) {
    target <- step$margins[[v]]
    f      <- as.character(data[[v]])
    for (lev in names(target)) {
      idx <- which(f == lev & active)
      diag[[length(diag) + 1]] <- data.frame(
        variable = v, category = lev, target = target[[lev]],
        achieved = sum(new_w[idx]), stringsAsFactors = FALSE
      )
    }
  }
  diag <- do.call(rbind, diag)
  attr(diag, "iterations") <- it
  attr(diag, "converged")  <- (maxdiff < step$tol)
  list(weights = new_w, diagnostics = diag)
}
