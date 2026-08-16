# calibration internals: margin-N reconciliation; poststrata / raking / linear-GREG prep and solve.

.reconcile_margin_N <- function(Ns) {
  Ns <- Ns[!is.na(Ns)]
  if (is.null(names(Ns)))
    names(Ns) <- paste("margin", seq_along(Ns))
  target  <- max(Ns)
  factors <- target / Ns
  changed <- which(abs(Ns - target) > 1e-9 * target)
  note <- NULL
  if (length(changed) > 0L) {
    lead   <- names(Ns)[which.max(Ns)]
    detail <- paste(sprintf("'%s' %s -> %s (x%.4f)",
                            names(Ns)[changed],
                            format(round(Ns[changed]), big.mark = ","),
                            format(round(target),      big.mark = ","),
                            factors[changed]),
                    collapse = "; ")
    note <- sprintf(paste0(
      "The control totals did not all sum to the same population size. ",
      "Kept the largest, N = %s (from '%s'), and rescaled the others so the ",
      "calibration closes: %s. Each margin's internal distribution is preserved; ",
      "review the control totals if this difference was not expected."),
      format(round(target), big.mark = ","), lead, detail)
  }
  list(target = target, factors = factors, note = note)
}

.prep_poststrata <- function(totals, count, data, active) {

  totals <- as.data.frame(totals, stringsAsFactors = FALSE)

  if (!is.character(count) || length(count) != 1L)
    stop("`count` must be a single string naming the counts column in `totals`.")
  if (!count %in% names(totals))
    stop(sprintf(
      "The counts column '%s' is not in the totals data frame.\nColumns found: %s",
      count, paste(names(totals), collapse = ", ")))
  if (!is.numeric(totals[[count]]))
    stop(sprintf("The counts column '%s' must be numeric.", count))
  if (anyNA(totals[[count]]))
    stop(sprintf(paste0("The counts column '%s' has missing values (NA): every target ",
                        "cell needs a count. An NA target would leave that cell unadjusted."),
                 count), call. = FALSE)

  vars <- setdiff(names(totals), count)
  if (length(vars) == 0L)
    stop("The totals data frame has no category columns (only the counts column).")

  missing_cols <- setdiff(vars, names(data))
  if (length(missing_cols) > 0L)
    stop(sprintf(
      paste0("These post-stratification columns from `totals` are not present ",
             "in the data: %s.\nThe category columns of `totals` must match ",
             "variable names in the sample.\nSample columns available: %s"),
      paste(missing_cols, collapse = ", "),
      paste(names(data), collapse = ", ")))

  key_of <- function(df, vars) {
    parts <- lapply(vars, function(v) as.character(df[[v]]))
    do.call(paste, c(parts, sep = "\r"))
  }

  totals$.key  <- key_of(totals, vars)
  totals$.Freq <- as.numeric(totals[[count]])
  # collapse duplicate cells by summing their counts (robust to extra columns)
  agg   <- tapply(totals$.Freq, totals$.key, sum)
  # Order the cells by the NATURAL order of the (typed) category columns, so a
  # numeric category (e.g. age) sorts 2, 10, 20 -- not lexicographically as
  # "10", "2", "20", which makes the report table unreadable. We keep one
  # representative typed row per key and order by it; the string keys used for
  # matching are unchanged, so the calibration itself is unaffected.
  rep_rows <- totals[!duplicated(totals$.key), c(vars, ".key"), drop = FALSE]
  ord      <- do.call(order, rep_rows[vars])
  cells <- data.frame(.key  = rep_rows$.key[ord],
                      .Freq = as.numeric(agg[rep_rows$.key[ord]]),
                      stringsAsFactors = FALSE)

  sample_key <- rep(NA_character_, nrow(data))
  sample_key[active] <- key_of(data[active, , drop = FALSE], vars)

  s_cells <- unique(sample_key[active])
  u_cells <- cells$.key
  in_s_not_u <- setdiff(s_cells, u_cells)
  if (length(in_s_not_u) > 0L) {
    show <- utils::head(in_s_not_u, 10L)
    lbl  <- gsub("\r", " x ", show)
    stop(sprintf(
      paste0("Some post-strata are present in the sample but have no population ",
             "total in `totals`.\n",
             "Every unit in the sample must belong to the population, so each ",
             "cell that appears in the sample must have a known total.\n",
             "Post-strata without a total (showing up to 10): %s\n",
             "Variables crossed: %s"),
      paste(lbl, collapse = " | "),
      paste(vars, collapse = " x ")))
  }

  note <- NULL
  in_u_not_s <- setdiff(u_cells, s_cells)
  if (length(in_u_not_s) > 0L) {
    missing_N <- sum(cells$.Freq[cells$.key %in% in_u_not_s])
    total_N   <- sum(cells$.Freq)
    note <- sprintf(
      paste0("%d population post-strata have no units in the sample, so no ",
             "weight can be assigned to them. Calibration will proceed on the ",
             "post-strata that are present, and the calibrated weights will sum ",
             "to about %s rather than the full population size N = %s (a shortfall ",
             "of %s, ~%.1f%% of N)."),
      length(in_u_not_s),
      format(total_N - missing_N, big.mark = ","),
      format(total_N, big.mark = ","),
      format(missing_N, big.mark = ","),
      100 * missing_N / total_N)
    warning(note, call. = FALSE)
  }

  list(cells = cells, vars = vars, sample_key = sample_key, note = note)
}

# Apply the post-stratification adjustment from a .prep_poststrata() result:
# within each cell, rescale weights so they sum to the known population total.
.poststratify_calc <- function(prep, w, active) {

  new_w <- w
  cells <- prep$cells
  skey  <- prep$sample_key

  idx_by <- split(which(active), skey[active])      # active rows per cell key, once
  diag <- vector("list", nrow(cells))
  for (i in seq_len(nrow(cells))) {
    key    <- cells$.key[i]
    target <- cells$.Freq[i]
    idx <- idx_by[[key]]; if (is.null(idx)) idx <- integer(0)
    cur <- sum(new_w[idx])
    fac <- if (cur > 0) target / cur else NA_real_
    if (!is.na(fac)) new_w[idx] <- new_w[idx] * fac
    diag[[i]] <- data.frame(
      variable   = paste(prep$vars, collapse = " x "),
      category   = gsub("\r", " x ", key),
      target     = target,
      prev_total = cur,
      factor     = fac,
      stringsAsFactors = FALSE
    )
  }
  list(weights = new_w, diagnostics = do.call(rbind, diag))
}


# =========================================================================
# Helpers for the tidy `totals` input to raking (step_calibrate)
# =========================================================================

# Prepare a LIST of margin data frames for raking. Each margin is validated
# with the same cell logic as post-stratification (structure, Rule 1, Rule 2).
# Returns a list of margins, each: list(cells, vars, sample_key).
.prep_raking_margins <- function(totals_list, count, data, active) {

  if (!is.list(totals_list) || is.data.frame(totals_list))
    stop(paste0("For raking with the tidy format, `totals` must be a LIST of ",
                "data frames (one per margin). For a single margin, use ",
                "post-stratification instead."))
  if (length(totals_list) == 0L)
    stop("`totals` is an empty list; provide at least one margin data frame.")

  lapply(totals_list, function(df) {
    prep <- .prep_poststrata(df, count, data, active)
    list(cells = prep$cells, vars = prep$vars, sample_key = prep$sample_key)
  })
}

# Iterative proportional fitting (raking) over prepared tidy margins.
# Warns if margins are inconsistent (different Ns) or if it fails to converge.
.raking_calc <- function(margins_prep, w, active, maxit, tol) {

  new_w <- w

  Ns <- vapply(margins_prep, function(m) sum(m$cells$.Freq), numeric(1))
  names(Ns) <- vapply(margins_prep, function(m) paste(m$vars, collapse = " x "),
                      character(1))
  rec <- .reconcile_margin_N(Ns)
  if (!is.null(rec$note)) message(rec$note)     # informative, never fatal (warn=2)
  for (i in seq_along(margins_prep))          # rescale each margin to the common N
    margins_prep[[i]]$cells$.Freq <- margins_prep[[i]]$cells$.Freq * rec$factors[i]

  # precompute the active row indices per cell key, once, for each margin
  for (j in seq_along(margins_prep))
    margins_prep[[j]]$idx <- split(which(active), margins_prep[[j]]$sample_key[active])

  it <- 0L; maxdiff <- Inf
  while (it < maxit && maxdiff >= tol) {
    it <- it + 1L; maxdiff <- 0
    for (m in margins_prep) {
      for (i in seq_len(nrow(m$cells))) {
        key    <- m$cells$.key[i]
        target <- m$cells$.Freq[i]
        idx <- m$idx[[key]]
        if (is.null(idx)) next
        cur <- sum(new_w[idx])
        if (cur > 0) {
          adj        <- target / cur
          new_w[idx] <- new_w[idx] * adj
          maxdiff    <- max(maxdiff, abs(adj - 1))
        }
      }
    }
  }

  if (maxdiff >= tol) {
    warning(sprintf(
      paste0("Raking did not converge after %d iterations (max relative change ",
             "= %.2e, tolerance = %.2e). The returned weights do not fully ",
             "satisfy all margins. Consider increasing `maxit`, or check that ",
             "the margin totals are mutually consistent."),
      it, maxdiff, tol), call. = FALSE)
  }

  diag <- list()
  for (m in margins_prep) {
    skey <- m$sample_key
    vlab <- paste(m$vars, collapse = " x ")
    for (i in seq_len(nrow(m$cells))) {
      key <- m$cells$.key[i]
      idx <- which(skey == key & active)
      diag[[length(diag) + 1]] <- data.frame(
        variable = vlab,
        category = gsub("\r", " x ", key),
        target   = m$cells$.Freq[i],
        achieved = sum(new_w[idx]),
        stringsAsFactors = FALSE
      )
    }
  }
  diag <- do.call(rbind, diag)
  attr(diag, "iterations") <- it
  attr(diag, "converged")  <- (maxdiff < tol)
  if (!is.null(rec$note)) attr(diag, "reconcile") <- rec$note
  list(weights = new_w, diagnostics = diag)
}


# =========================================================================
# Helper for the tidy `totals` input to linear/GREG calibration
# =========================================================================

# Translate friendly calibration targets into the model.matrix totals vector
# expected by the linear engine. Categorical variables are given as data frames
# (all categories + a counts column named by `count`); continuous variables as
# a single number. The user never deals with the intercept or with treatment
# contrasts.
.prep_linear_totals <- function(formula, totals, count, data, active) {

  if (!is.list(totals) || is.data.frame(totals) || is.null(names(totals)))
    stop(paste0("For the tidy linear format, `totals` must be a NAMED list ",
                "(one entry per auxiliary variable), each entry a data frame ",
                "(categorical) or a single number (continuous)."))

  # calibration requires complete auxiliaries: NA breaks the calibration
  # equations (a unit with a missing value cannot enter that constraint).
  aux_vars <- all.vars(formula)
  present  <- intersect(aux_vars, names(data))
  for (v in present) {
    if (anyNA(data[[v]][active]))
      stop(sprintf(
        paste0("The calibration variable '%s' has missing values (NA) in the ",
               "sample. Calibration requires every unit to have a value for ",
               "each auxiliary variable, so a variable with NAs cannot be used ",
               "as a calibration target. Impute the missing values first, or ",
               "calibrate on a frame variable that is complete for all units."),
        v))
  }

  X  <- stats::model.matrix(formula, data = data[active, , drop = FALSE])
  cn <- colnames(X)

  # population size N: if the categorical margins disagree, reconcile them to
  # the LARGEST (the intercept is that N; each margin is rescaled below).
  Ns <- vapply(totals, function(t) {
    if (is.data.frame(t)) sum(as.numeric(t[[count]])) else NA_real_
  }, numeric(1))
  if (all(is.na(Ns)))
    stop(paste0("At least one categorical target (a data frame) is required to ",
                "determine the population size N for the intercept."))
  rec <- .reconcile_margin_N(Ns[!is.na(Ns)])
  if (!is.null(rec$note)) message(rec$note)     # informative, never fatal (warn=2)
  N <- rec$target

  Tvec <- stats::setNames(rep(NA_real_, length(cn)), cn)
  if ("(Intercept)" %in% cn) Tvec["(Intercept)"] <- N

  for (v in names(totals)) {
    t <- totals[[v]]
    if (is.data.frame(t)) {
      if (!count %in% names(t))
        stop(sprintf("`count = \"%s\"` is not a column of the totals for '%s'.",
                     count, v))
      lev_col <- setdiff(names(t), count)
      if (length(lev_col) != 1L)
        stop(sprintf(paste0("The totals data frame for '%s' must have exactly ",
                            "one category column plus the counts column."), v))
      levels_v <- as.character(t[[lev_col]])
      sc       <- if (!is.null(rec$factors[[v]])) rec$factors[[v]] else 1
      counts_v <- as.numeric(t[[count]]) * sc
      # Sum duplicate categories (e.g. a census table disaggregated by extra
      # variables, collapsed onto this margin) instead of letting the last row
      # silently overwrite the earlier ones -- the missing mass would otherwise
      # leak into the reference category. Matches the post-stratification path,
      # with an informative message (never fatal, safe under options(warn = 2)).
      if (anyDuplicated(levels_v)) {
        message(sprintf(
          "The totals for '%s' had %d duplicate category value(s); their counts were summed.",
          v, sum(duplicated(levels_v))))
        agg      <- tapply(counts_v, levels_v, sum)
        levels_v <- names(agg)
        counts_v <- as.numeric(agg)
      }
      # A population level present in `totals` but with NO units in the sample
      # cannot be calibrated: linear/GREG builds no model.matrix column for it, so
      # its total would silently leak into the reference category and inflate it.
      # Unlike post-stratification (which can simply fall short of N), GREG also
      # carries continuous and interaction terms, so absorbing an uncovered level
      # into the reference is wrong -- error and let the user decide.
      sample_levels <- unique(as.character(data[[v]][active]))
      absent <- setdiff(levels_v, sample_levels)
      if (length(absent))
        stop(sprintf(paste0(
          "The totals for '%s' include level(s) with no units in the sample: %s. ",
          "Linear/GREG calibration cannot assign weight to a category that has no ",
          "sample units (there is no model term for it), so its total would ",
          "silently inflate the reference category. Drop those level(s) from ",
          "`totals` if they are genuinely out of the sample's scope, or fix the ",
          "sample coverage before calibrating."),
          v, paste(utils::head(absent, 15L), collapse = ", ")), call. = FALSE)
      for (j in seq_along(levels_v)) {
        col <- paste0(v, levels_v[j])
        if (col %in% cn) Tvec[col] <- counts_v[j]
      }
    } else if (is.numeric(t) && length(t) == 1L) {
      if (v %in% cn) {
        Tvec[v] <- t
      } else {
        stop(sprintf(paste0("Continuous target '%s' is not a column of the ",
                            "model.matrix. Check the formula and the name."), v))
      }
    } else {
      stop(sprintf(paste0("Target for '%s' must be a data frame (categorical) ",
                          "or a single number (continuous)."), v))
    }
  }

  missing <- cn[is.na(Tvec)]
  if (length(missing) > 0L)
    stop(sprintf(
      paste0("No population total was provided for these model terms: %s.\n",
             "Make sure `totals` covers every variable in the formula ",
             "(all categories for factors, a number for continuous)."),
      paste(missing, collapse = ", ")))

  if (!is.null(rec$note)) attr(Tvec, "reconcile") <- rec$note
  Tvec
}
