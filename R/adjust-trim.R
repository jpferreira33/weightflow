# post-calibration steps: rounding, trimming, model-assisted calibration, assert, rescale.

# --- Weight rounding -------------------------------------------------------
apply_step.step_round <- function(step, data, w) {
  active <- .wf_active(w)
  new_w  <- w
  f      <- 10^step$digits
  sum_before <- sum(w[active])

  bal_dev <- NA_real_
  if (step$method == "nearest") {
    new_w[active] <- round(w[active], step$digits)
  } else if (step$method == "preserve_total") {
    # largest-remainder method: preserves the sum (on the `digits` scale)
    x      <- w[active] * f
    fl     <- floor(x)
    target <- round(sum(x))
    k      <- as.integer(round(target - sum(fl)))   # how many to round up
    if (k > 0) {
      # ROUND-01. Ties in the fractional part are the RULE, not the exception: a
      # self-weighting design, weights landing on .5, calibrated weights on a grid.
      # order() is stable, so a plain order(x - fl) gave the extra unit to the first
      # rows OF THE FILE every time, and a file sorted by region -- the usual layout
      # -- then moved mass from the last domains to the first. Measured on 100 units
      # at 12.5: North 650 / South 600 where both should be ~625, i.e. 4% off, in the
      # method chosen PRECISELY to preserve totals, and with nothing in the
      # diagnostics to show it (sum_before == sum_after, as promised). Break ties at
      # random, which makes the allocation unbiased per unit. Weights with distinct
      # fractional parts are unaffected: the ordering is the same as before.
      ord <- order(x - fl, stats::runif(length(fl)), decreasing = TRUE)
      fl[ord[seq_len(min(k, length(fl)))]] <- fl[ord[seq_len(min(k, length(fl)))]] + 1
    }
    new_w[active] <- fl / f
  } else {
    # balanced (cube) rounding. Two ways to build the balancing matrix, and they are
    # not the same problem.
    #
    # With `formula` the matrix IS the calibration design, model.matrix(~ x1 + x2).
    # Preserving X'w preserves exactly the totals the calibration imposed -- no more --
    # and its columns OVERLAP: a unit loads on several of them at once, so no unit-level
    # allocation can satisfy them independently. That overlap is the whole reason the
    # cube method exists.
    #
    # With `by` the matrix is one indicator per crossed cell. Every row then has a single
    # 1, so the problem SEPARATES into one independent "keep this cell total" per cell,
    # which a per-cell largest remainder already solves; the cube machinery buys nothing
    # and the landing phase pays for every cell. It is also strictly stronger than the
    # calibration asked for -- preserving each cell implies preserving the margins -- so
    # on a design with many sparse cells it spends accuracy on constraints rounding
    # cannot meet. Kept because it is the right thing after a post-stratification, and
    # because it is what earlier versions did.
    if (!is.null(step$formula)) {
      dd <- data[active, , drop = FALSE]
      # model.matrix() fails opaquely on a term that is constant among the active units
      # -- "contrasts can be applied only to factors with 2 or more levels" names neither
      # the step nor the variable. A domain filtered down to one level is an ordinary way
      # to get there, so say what happened.
      Z <- tryCatch(stats::model.matrix(step$formula, data = dd),
        error = function(e)
          stop(sprintf(paste0("`formula` could not be turned into a balancing matrix over ",
                              "the %d active units: %s. A term that is constant among them ",
                              "carries no constraint -- drop it from `formula`."),
                       sum(active), conditionMessage(e)), call. = FALSE))
      if (nrow(Z) != sum(active))
        stop(sprintf(paste0("`formula` dropped %d of the %d active units: a variable in it ",
                            "is NA there. Balanced rounding has to place every active unit, ",
                            "so fill or drop those units before rounding."),
                     sum(active) - nrow(Z), sum(active)), call. = FALSE)
    } else {
      cells <- .make_cells(data, step$by, length(w), active = active)[active]
      cells <- droplevels(cells)
      Z     <- stats::model.matrix(~ cells - 1)        # one indicator column per cell
    }
    new_w[active] <- .wf_balanced_round(w[active], Z, step$digits)
    # honest quality number: worst preserved cell-total deviation (weight scale)
    tot_before <- colSums(w[active] * Z)
    tot_after  <- colSums(new_w[active] * Z)
    bal_dev    <- max(abs(tot_after - tot_before) / pmax(abs(tot_before), 1))
  }

  diag <- data.frame(
    method     = step$method,
    decimals   = step$digits,
    sum_before = round(sum_before, 2),
    sum_after  = round(sum(new_w[active]), 2),
    n_modified = sum(abs(new_w[active] - w[active]) > 1e-9),
    stringsAsFactors = FALSE
  )
  if (identical(step$method, "balanced"))
    diag$max_total_reldev <- signif(bal_dev, 3)
  list(weights = new_w, diagnostics = diag)
}

# --- Trimming (capping extreme weights) ------------------------------------
# TRIM-01. A trim loop ends for one of two reasons: every weight is inside the band,
# or `maxit` ran out. Only the first was ever reported. The second leaves weights
# outside the band the step was asked to impose, and said nothing: the diagnostics
# table prints the cap that was REQUESTED, the weights sit above it, and the report
# certifies the step as applied. The iteration genuinely need not converge -- each
# redistribution hands the trimmed mass to the units still inside, which can push one
# of them back over the cap -- so exhausting `maxit` is an ordinary outcome that has to
# be reported rather than silently accepted. A deliberate non-strict single pass is a
# different thing and does not come through here.
.wf_warn_trim_maxit <- function(wv, lo, hi, maxit, fn) {
  lo <- rep_len(lo, length(wv)); hi <- rep_len(hi, length(wv))
  over  <- which(is.finite(hi) & wv > hi + 1e-9)
  under <- which(is.finite(lo) & wv < lo - 1e-9)
  if (!length(over) && !length(under)) return(invisible(FALSE))
  ex <- c(if (length(over))  (wv[over]  - hi[over])  / pmax(abs(hi[over]),  1e-12),
          if (length(under)) (lo[under] - wv[under]) / pmax(abs(lo[under]), 1e-12))
  warning(sprintf(paste0(
    "%s stopped at maxit = %d with %d weight(s) still outside the band: %d above the ",
    "cap, %d below the floor, the worst by %.3g%% of its own bound. Those weights are ",
    "NOT trimmed, even though the step reports the cap it was asked for. Each pass ",
    "hands the trimmed mass to the units still inside the band, which can push one of ",
    "them back out, so the iteration is not guaranteed to converge. Raise `maxit`, ",
    "widen the band, or trim within `by` groups so the mass has somewhere to go."),
    fn, maxit, length(over) + length(under), length(over), length(under),
    100 * max(ex)), call. = FALSE)
  invisible(TRUE)
}

apply_step.step_trim <- function(step, data, w) {
  n      <- length(w)
  active <- .wf_active(w)
  new_w  <- w
  step$maxit <- .wf_count(step$maxit, "maxit")   # 0/NA/"a" would silently skip trimming

  if (!is.null(step$min_ratio) && step$min_ratio >= step$max_ratio)
    stop(sprintf(paste0("`min_ratio` (%s) must be strictly below `max_ratio` (%s) in ",
                        "step_trim(); with min_ratio >= max_ratio the floor sits above the cap ",
                        "and the 'trim' would clamp every weight and distort the total."),
                 format(step$min_ratio), format(step$max_ratio)), call. = FALSE)

  # Cells first: with reference = "median" the threshold is computed WITHIN each
  # `by` group, so a differentiated trim uses each subgroup's own median (not a
  # single global median). With by = NULL there is one group (the whole sample).
  cells  <- .make_cells(data, step$by, n, active = active)

  # Define the cap and floor per unit according to the reference
  base_w <- attr(data, "weightflow_base_w")
  # #8: no `min_ratio` means "no floor" (-Inf), not a floor of 0. A floor of 0
  # would clamp a legitimate active negative weight (a valid GREG output) up to 0,
  # the "dropped" marker, so the unit silently leaves the cascade while the total
  # is preserved (no alert fires). Only a supplied `min_ratio` sets a real floor.
  cap   <- numeric(n); floor_v <- rep(-Inf, n)
  if (step$reference == "base") {
    if (is.null(base_w)) stop("reference = 'base' requires the base weights (provided by prep()).")
    cap[]     <- step$max_ratio * base_w
    if (!is.null(step$min_ratio)) floor_v[] <- step$min_ratio * base_w
  } else if (step$reference == "median") {
    for (g in levels(cells)) {               # per-group median threshold
      gi <- which(cells == g & active)
      if (!length(gi)) next
      med <- stats::median(new_w[gi])
      # N4-2: a ratio to a non-positive reference is meaningless -- with a negative
      # median (a group dominated by negative calibration weights) the cap falls
      # below the implicit floor and the whole group would collapse to weight 0,
      # inflating the total. Fail loudly instead.
      if (!is.finite(med) || med <= 0)
        stop(sprintf(paste0("step_trim(reference = \"median\") needs a positive reference, ",
                            "but group '%s' has a non-positive median weight (%s), which ",
                            "happens when the group is dominated by negative calibration ",
                            "weights. Trim before that calibration, use reference = \"value\" ",
                            "with an absolute cap, or set `bounds` to keep the weights positive."),
                     g, format(round(med, 4))), call. = FALSE)
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
  maxed         <- FALSE            # a cell ran out of iterations (TRIM-01)
  unredist      <- 0                 # mass that could not be handed back (TRIM-02)
  sum_before    <- sum(new_w[active])
  for (g in levels(cells)) {
    gi <- which(cells == g & active)
    if (!length(gi)) next
    it <- 0L
    repeat {
      it <- it + 1L
      over        <- gi[new_w[gi] > cap[gi]]
      under_floor <- gi[new_w[gi] < floor_v[gi]]
      if (!length(over) && !length(under_floor)) break
      if (it > step$maxit) { maxed <- TRUE; break }

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
      if (!length(free)) { unredist <- unredist + excess; break }  # nowhere to redistribute
      # Proportional-to-weight redistribution assumes positive weights. If the
      # free set's weight sum is not clearly positive (negative weights from an
      # earlier GREG), the proportional factor explodes or flips sign -- fall back
      # to an EQUAL split, which still preserves the total.
      sf <- sum(new_w[free])
      if (sf > 1e-9) new_w[free] <- new_w[free] + excess * new_w[free] / sf
      else           new_w[free] <- new_w[free] + excess / length(free)
    }
    it_global <- max(it_global, it)
  }

  if (maxed)
    .wf_warn_trim_maxit(new_w[active], floor_v[active], cap[active], step$maxit,
                        "step_trim()")

  deff_after <- design_effect(new_w)$deff
  sum_after  <- sum(new_w[active])
  # Warn (not just a deferred alert) when mass could not be handed back, like the other
  # two trim steps -- prep(warn = FALSE) is the default, so a silent total change is easy
  # to miss. (TRIM-02)
  if (abs(unredist) > 1e-9)
    warning(sprintf(paste0("step_trim(): %.4g of weight could not be redistributed (no units ",
                          "left within the band to receive it), so the weighted total changed ",
                          "by that amount."), unredist), call. = FALSE)
  diag <- data.frame(
    reference   = step$reference,
    cap         = step$max_ratio,
    floor       = ifelse(is.null(step$min_ratio), NA, step$min_ratio),
    trimmed     = total_trimmed,
    redistributed = step$redistribute,
    sum_before  = round(sum_before, 2), sum_after = round(sum_after, 2),
    deff_before = round(deff_before, 3),
    deff_after  = round(deff_after, 3),
    stringsAsFactors = FALSE
  )
  attr(diag, "iterations") <- it_global
  ai <- which(active)
  attr(diag, "trim_rec") <- list(
    wb = w[ai], wa = new_w[ai], cap = cap[ai], floor = floor_v[ai], idx = ai,
    by = if (!is.null(step$by)) as.character(cells)[ai] else NULL,
    redistribute = if (isTRUE(step$redistribute)) "proportional" else "none",
    method = step$reference, kind = "ratio", f = new_w[ai] / w[ai],
    unredist = unredist, deff_before = deff_before, deff_after = deff_after)
  list(weights = new_w, diagnostics = diag)
}

# Weighted total of a per-reference-unit prediction, with an alignment guard so a
# reference survey with NA predictors (which drops rows) fails loudly, not silently.
.wf_ref_total <- function(pred, w_ref) {
  if (length(pred) != length(w_ref))
    stop("The reference sample (reference_sample()) has missing values (NA) in the ",
         "model predictors; every reference unit needs complete predictors for the ",
         "projection. Impute or drop them first.", call. = FALSE)
  sum(w_ref * pred)
}

# --- Model calibration (Wu & Sitter 2001) ----------------------------------
# Calibrates simultaneously to the X totals (consistency) and to the population
# totals of each model y prediction (model-assisted efficiency). `population` may
# be a full frame (unweighted sums) or a weighted reference survey wrapped with
# reference_sample() (weighted sums = estimated totals).
# --- Model calibration partitioned by domain (MCAL-BY) ---------------------
# `by` has the same meaning it has in step_calibrate(): the sample is PARTITIONED
# and each domain is solved on its own. For model calibration that carries two
# consequences at once, which is usually why it is wanted: every working model is
# fitted on the units of its own domain and never sees the other domains, and the X totals
# are reproduced exactly WITHIN each domain rather than only nationally.
#
# The rank ceiling then binds per domain, and harder: domain g must carry its
# qA + K constraints on its own n_g units, and with cross-fitting each of its
# folds must leave q usable rows behind. A domain too small for that gives a
# singular system whose symptom is wild weights rather than an error, so it is
# checked up front, by name, with the arithmetic shown.
.wf_ref_subset <- function(pop, i) {
  wr <- attr(pop, "wf_ref_weights"); rr <- attr(pop, "wf_ref_replicates")
  cl <- class(pop)
  out <- as.data.frame(pop)[i, , drop = FALSE]
  rownames(out) <- NULL
  if (!is.null(wr)) attr(out, "wf_ref_weights") <- wr[i]
  if (!is.null(rr)) attr(out, "wf_ref_replicates") <- rr[i, , drop = FALSE]
  class(out) <- cl
  out
}

.mcal_domain_sizes <- function(step, dom, active, qA_hint = NULL) {
  K <- length(step$models)
  F <- if (is.null(step$crossfit)) 1L else as.integer(step$crossfit)
  tab <- table(dom[active])
  list(K = K, F = F, tab = tab)
}

# Is [X | mu_1 ... mu_K] full rank? Column-scale first, so the test measures
# collinearity and not the disparity of units between an intercept, a dummy and a
# continuous auxiliary. `where` names the domain when called from the `by` path.
# A warning, not an error: a rank-deficient system still returns usable GREG
# weights, and the user may knowingly have passed a linear working model.
.wf_check_mcal_rank <- function(Z, q_A, model_names, where = NULL) {
  if (is.null(dim(Z)) || nrow(Z) < 2L) return(invisible(TRUE))
  s  <- apply(Z, 2L, function(cc) { v <- sqrt(mean(cc^2)); if (!is.finite(v) || v == 0) 1 else v })
  Zs <- sweep(Z, 2L, s, "/")
  r  <- tryCatch(qr(Zs)$rank, error = function(e) NA_integer_)
  if (is.na(r) || r >= ncol(Zs)) return(invisible(TRUE))
  # Which model columns are the redundant ones: regress each on the X block and
  # report those whose residual is numerically zero.
  Xs  <- Zs[, seq_len(q_A), drop = FALSE]
  bad <- character(0)
  for (k in seq_along(model_names)) {
    y  <- Zs[, q_A + k]
    fv <- tryCatch(stats::lm.fit(Xs, y)$residuals, error = function(e) NULL)
    if (!is.null(fv) && max(abs(fv)) <= 1e-8 * max(1, max(abs(y)))) bad <- c(bad, model_names[k])
  }
  warning(sprintf(paste0("The model-calibration system [X | model predictions]%s has rank %d on %d ",
                         "column(s)%s. A prediction that lies in the span of `x_formula` adds no ",
                         "constraint: the system is solved by pseudo-inverse, the achieved totals ",
                         "still match the targets exactly and `converged` is TRUE, but the step has ",
                         "degraded to a plain GREG on `x_formula`. Use model predictors outside ",
                         "`x_formula`, a non-linear engine, or `crossfit` to move the predictions ",
                         "out of that span."),
                 if (is.null(where)) "" else sprintf(" in domain '%s'", where),
                 r, ncol(Zs),
                 if (length(bad)) sprintf(" -- redundant model constraint(s): %s",
                                          paste(bad, collapse = ", ")) else ""),
          call. = FALSE)
  invisible(FALSE)
}

.model_calibrate_by_domain <- function(step, data, w) {
  byvar <- step$by
  if (!is.character(byvar) || length(byvar) != 1L)
    stop("`by` in step_model_calibration() must be a single column name.", call. = FALSE)
  if (!byvar %in% names(data))
    stop(sprintf("Domain column '%s' not found in the data.", byvar), call. = FALSE)
  pop <- step$population
  if (!byvar %in% names(pop))
    stop(sprintf(paste0("Domain column '%s' not found in `population`. With `by`, the ",
                        "calibration frame (or reference_sample) must carry the same domain ",
                        "column as the sample, because each domain is calibrated to its own ",
                        "totals."), byvar), call. = FALSE)
  active <- .wf_active(w)
  dom    <- as.character(data[[byvar]])
  if (any(is.na(dom[active])))
    stop(sprintf(paste0("Domain column '%s' has missing values (NA) in %d active unit(s). ",
                        "Every unit must belong to a domain to be calibrated within one."),
                 byvar, sum(is.na(dom[active]))), call. = FALSE)
  pdom <- as.character(pop[[byvar]])
  if (anyNA(pdom))
    stop(sprintf("Domain column '%s' has missing values (NA) in `population`.", byvar),
         call. = FALSE)
  # Same split-cluster hazard as step_calibrate(by=): one solve per domain gives a
  # straddling cluster two g factors. See .wf_assert_cluster_within_domain().
  if (isTRUE(step$equal_within_cluster) && !is.null(step$cluster))
    .wf_assert_cluster_within_domain(dom[active],
                                     as.character(data[[step$cluster]])[active],
                                     step$cluster, byvar)
  # Per-domain totals: a national named vector would be applied to EVERY domain and
  # the population would be counted once per domain. Same guard as step_calibrate().
  if (!is.null(step$x_totals) && !is.list(step$x_totals) && !is.data.frame(step$x_totals))
    stop(sprintf(paste0("`x_totals` given as a national named vector cannot be used with ",
                        "`by = \"%s\"`: the same totals would be applied to every domain, so the ",
                        "population would be counted once per domain. Give the per-domain form ",
                        "(a data frame carrying the '%s' column), or leave `x_totals = NULL` so ",
                        "the totals are taken from each domain's slice of `population`."),
                 byvar, byvar), call. = FALSE)

  doms <- unique(dom[active])
  miss_pop <- setdiff(doms, unique(pdom))
  if (length(miss_pop))
    stop(sprintf(paste0("Domain(s) of '%s' present in the sample but absent from `population`: ",
                        "%s. They have no totals to calibrate to."),
                 byvar, paste(utils::head(miss_pop, 10L), collapse = ", ")), call. = FALSE)
  miss_smp <- setdiff(unique(pdom), doms)
  if (length(miss_smp))
    warning(sprintf(paste0("`population` covers domain(s) of '%s' with no active unit in the ",
                           "sample: %s. Their totals are dropped, so the calibrated weights do ",
                           "not reach the intended population size."),
                    byvar, paste(utils::head(miss_smp, 10L), collapse = ", ")), call. = FALSE)

  # Rank feasibility, per domain, before anything is solved.
  q  <- ncol(stats::model.matrix(step$x_formula, data = data[active, , drop = FALSE]))
  mv <- unique(unlist(lapply(step$models, function(m) all.vars(m$formula[[3L]]))))
  qm <- length(mv) + 1L                       # model-block predictors + intercept
  K  <- length(step$models)
  Fd <- if (is.null(step$crossfit)) 1L else as.integer(step$crossfit)
  n_d <- table(dom[active])
  need <- max(q + K, if (Fd > 1L) ceiling(Fd * qm / (Fd - 1)) else qm)
  bad <- names(n_d)[n_d < need]
  if (length(bad))
    stop(sprintf(paste0("With `by = \"%s\"` each domain is calibrated on its own units, so it ",
                        "must support the whole system by itself: %d constraint(s) (%d margin ",
                        "column(s) + %d model(s))%s, i.e. at least %d active unit(s). ",
                        "Domain(s) below that: %s. Collapse the small domains, drop a model, or ",
                        "calibrate without `by`."),
                 byvar, q + K, q, K,
                 if (Fd > 1L) sprintf(", and with crossfit = %d each fold must leave %d rows to fit %d model coefficient(s)",
                                      Fd, qm, qm) else "",
                 need,
                 paste(sprintf("%s (n = %d)", bad, as.integer(n_d[bad])), collapse = ", ")),
         call. = FALSE)

  new_w <- w
  diags <- list(); conv <- logical(0); mu_rows <- list(); mu_idx <- integer(0)
  for (d in doms) {
    idx_d  <- which(dom == d)
    step_d <- step
    step_d$by         <- NULL                       # avoid recursion
    step_d$.wf_domain <- d                          # so the rank warning names it
    step_d$population <- .wf_ref_subset(pop, which(pdom == d))
    if (!is.null(step$x_totals))
      step_d$x_totals <- .split_totals_by_domain(step$x_totals, byvar, step$count, d)
    res_d <- apply_step(step_d, data[idx_d, , drop = FALSE], w[idx_d])
    new_w[idx_d] <- res_d$weights
    dg <- res_d$diagnostics
    conv <- c(conv, attr(dg, "converged"))
    if (!is.null(dg) && nrow(dg) > 0L)
      diags[[length(diags) + 1L]] <- cbind(domain = d, dg, stringsAsFactors = FALSE)
    mc <- attr(res_d$weights, "wf_modelcal")
    if (!is.null(mc)) { mu_rows[[length(mu_rows) + 1L]] <- mc$mu
                        mu_idx <- c(mu_idx, idx_d[mc$active]) }
  }
  diag <- if (length(diags)) do.call(rbind, diags) else NULL
  if (!is.null(diag)) {
    rownames(diag) <- NULL
    attr(diag, "note") <- sprintf(paste0("model-calibrated independently within '%s' (%d domains): ",
                                         "each working model is fitted on its own domain and the X ",
                                         "totals hold within it"), byvar, length(doms))
    if (length(conv)) attr(diag, "converged") <- all(conv)
  }
  # The mu block a following step_trim_calibrated() reads, stitched back in row order.
  if (length(mu_rows)) {
    mu <- do.call(rbind, mu_rows)
    o  <- order(mu_idx)
    attr(new_w, "wf_modelcal") <- list(mu = mu[o, , drop = FALSE], active = sort(mu_idx))
  }
  list(weights = new_w, diagnostics = diag)
}

apply_step.step_model_calibration <- function(step, data, w) {
  if (!is.null(step$by)) return(.model_calibrate_by_domain(step, data, w))
  active <- .wf_active(w)
  new_w  <- w
  d      <- w[active]
  sdata  <- data[active, , drop = FALSE]
  pop    <- step$population
  w_ref  <- attr(pop, "wf_ref_weights")   # non-NULL only for reference_sample()
  # In a bootstrap replicate, re-estimate the reference totals from the paired
  # replicate column of the reference survey (Opsomer & Erciulescu 2021), so the
  # reference's sampling variance propagates. Point prep, or no replicate weights
  # supplied, falls back to the point reference weights (totals treated as fixed).
  if (!is.null(w_ref)) {
    rep_mat <- attr(pop, "wf_ref_replicates")
    ridx    <- attr(data, "wf_replicate_idx")
    if (!is.null(rep_mat) && !is.null(ridx))
      w_ref <- rep_mat[, ((ridx - 1L) %% ncol(rep_mat)) + 1L]
  }

  # Cluster validation up front: it depends only on the incoming weights, so an
  # integrative recipe that cannot work should say so before K working models are
  # fitted -- and before the rank check below, so a run with both problems reports
  # the fatal one rather than a warning about a solve that is not going to happen.
  cl <- NULL
  if (isTRUE(step$equal_within_cluster)) {
    if (!step$cluster %in% names(data))
      stop(sprintf("Cluster column '%s' not found in the data.", step$cluster))
    cl <- as.character(data[[step$cluster]])[active]
    if (anyNA(cl))
      stop(sprintf("Cluster column '%s' has missing values (NA).", step$cluster))
    .wf_assert_uniform_within_cluster(d, cl, step$cluster)
  }

  # Consistency block: X auxiliaries
  X  <- stats::model.matrix(step$x_formula, data = sdata)
  if (nrow(X) != length(d) || anyNA(X))
    stop("Auxiliaries in `x_formula` have missing values (NA) in the active ",
         "sample; model calibration needs a value for every unit. Impute them ",
         "first, or use a complete auxiliary.")
  cn <- colnames(X)
  # X totals may come from the frame (default) or from an external source.
  if (is.null(step$x_totals)) {
    # from the population frame, as before. Guard NA first: model.matrix() would
    # silently drop rows with missing auxiliaries (default na.omit), so colSums()
    # below would undercount and the calibration totals would be understated.
    pv <- intersect(all.vars(step$x_formula), names(pop))
    if (length(pv) && anyNA(pop[, pv, drop = FALSE]))
      stop("`population` (the calibration frame or reference_sample) has missing ",
           "values (NA) in the x_formula variables; those rows would be dropped ",
           "silently and the calibration totals understated. Impute or drop them first.",
           call. = FALSE)
    Xpop <- stats::model.matrix(step$x_formula, data = pop)
    if (!is.null(w_ref) && nrow(Xpop) != length(w_ref))
      stop("The reference sample (reference_sample()) has missing values (NA) in ",
           "`x_formula`; every reference unit needs complete auxiliaries. Impute or ",
           "drop them first.", call. = FALSE)
    Tx   <- if (is.null(w_ref)) colSums(Xpop)[cn] else colSums(Xpop * w_ref)[cn]
    if (anyNA(Tx))
      stop("Inconsistent factor levels between the sample and `population` in x_formula.")
    # #7: the reverse gap -- a level present in `population` but ABSENT from the
    # sample. Its column is dropped here, so its population mass is absorbed into
    # the reference category via the intercept and the calibration totals are
    # misassigned silently. Error, naming the offending level(s).
    extra <- setdiff(colnames(Xpop), cn)
    if (length(extra))
      stop(sprintf(paste0("`population` has factor level(s) absent from the sample in x_formula: ",
                          "%s. Their population mass would be absorbed into the reference ",
                          "category, misassigning the calibration totals. Align the sample and ",
                          "population factor levels, or drop the extra level(s)."),
                   paste(utils::head(extra, 10L), collapse = ", ")), call. = FALSE)
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

  # The models predict on `pop`; NA in a model predictor there would reach the
  # engine (glm errors; rpart imputes silently via surrogates), so the projected
  # totals would be wrong. Guard the predictors on the frame, as we do for x_formula.
  mvars <- unique(unlist(lapply(step$models, function(m) all.vars(m$formula[[3L]]))))
  mvars <- intersect(mvars, names(pop))
  if (length(mvars) && anyNA(pop[, mvars, drop = FALSE]))
    stop("`population` has missing values (NA) in a y_model predictor; those rows would ",
         "reach the model engine (an error, or silent surrogate imputation). Impute or drop ",
         "them first.", call. = FALSE)

  # Model-assisted block: one prediction column per model y.
  # ML-01: fix regression-vs-classification here, ONCE, on the whole sample, so that
  # every cross-fitting fold predicts on the same scale. Deciding it inside the fold
  # let a y value missing from one fold's training set flip that fold alone.
  step$models <- lapply(step$models, function(m) {
    yv <- sdata[[as.character(m$formula[[2L]])]]
    m$classify <- .wf_is_class(yv, m$family)
    m
  })
  mu_cols <- list(); Tmu <- numeric(0)
  for (k in names(step$models)) {
    m <- step$models[[k]]
    if (is.null(step$crossfit)) {
      preds        <- .model_predict(m, sdata, d, list(sdata, pop))
      mu_cols[[k]] <- preds[[1]]          # prediction on the sample
      Tmu[k]       <- if (is.null(w_ref)) sum(preds[[2]]) else .wf_ref_total(preds[[2]], w_ref)
    } else {
      cl_cf <- if (!is.null(step$cluster)) as.character(sdata[[step$cluster]]) else NULL
      mu_cols[[k]] <- .crossfit_predict(   # out-of-fold predictions on the sample
        nrow(sdata), step$crossfit, cl_cf, step$crossfit_seed,
        fit_predict = function(tr, te_list)
          .model_predict(m, sdata[tr, , drop = FALSE], d[tr],
                         lapply(te_list, function(te) sdata[te, , drop = FALSE])))
      p_pop  <- .model_predict(m, sdata, d, list(pop))[[1]]       # full model on the reference/frame
      Tmu[k] <- if (is.null(w_ref)) sum(p_pop) else .wf_ref_total(p_pop, w_ref)
    }
  }

  Z  <- cbind(X, do.call(cbind, mu_cols))
  colnames(Z) <- c(colnames(X), names(step$models))
  Tvec <- c(Tx, Tmu)

  # Rank of [X | mu] BEFORE the solve. Model calibration is the one system built to
  # be near-singular: a working model linear in a subset of `x_formula` puts mu in
  # col(X), the model constraint then adds nothing, and .solve_calib() quietly falls
  # back to the pseudo-inverse. Because the pseudo-inverse still solves the
  # consistent system exactly, the diagnostics show target == achieved, the weights
  # look ordinary and `converged` is TRUE -- the calibration silently degrades to a
  # plain GREG. The only signal today is .solve_calib()'s generic warning, which
  # blames collinear auxiliaries. Say what actually happened, and which constraint.
  .wf_check_mcal_rank(Z, ncol(X), names(step$models), step$.wf_domain)

  # Calibration solver: closed-form linear GREG when unbounded (the default),
  # bounded Deville-Sarndal iteration when `bounds`/`calfun` are set. Shared with
  # step_calibrate() through .solve_calibration(). The defaults guard specs built
  # before `bounds` existed (an older step list has no calfun/bounds/maxit/tol).
  cf_fun <- if (is.null(step$calfun)) "linear" else step$calfun
  cf_bnd <- step$bounds
  cf_mx  <- if (is.null(step$maxit)) 100L else step$maxit
  cf_tl  <- if (is.null(step$tol))   1e-7 else step$tol
  solver_ok <- TRUE

  if (!step$equal_within_cluster) {
    # Unit-level calibration
    sol    <- .solve_calibration(Z, d, Tvec, cf_fun, cf_bnd, maxit = cf_mx, tol = cf_tl)
    g      <- sol$g
    solver_ok <- isTRUE(sol$converged)
    new_w[active] <- d * g
    note_clust <- ""
  } else {
    # Integrative calibration (Lemaitre-Dufour 1987): household-MEAN replacement,
    # person-level calibration -> one weight per household (matches survey's
    # aggregate.stage / Vanderhoeft 2001; ReGenesees uses a different variant).
    # cluster column, NA and within-cluster uniformity were validated up front
    hh   <- unique(cl)
    n_h  <- as.numeric(tapply(d, cl, length)[hh])   # persons per household
    Wsum <- as.numeric(tapply(d, cl, sum)[hh])      # total base weight in household
    Xbar <- rowsum(Z, group = cl)[hh, , drop = FALSE] / n_h  # household MEANS of Z
    sol    <- .solve_calibration(Xbar, Wsum, Tvec, cf_fun, cf_bnd, maxit = cf_mx, tol = cf_tl)
    gh     <- sol$g
    solver_ok <- isTRUE(sol$converged)
    names(gh) <- hh
    new_w[active] <- d * gh[cl]                     # own base weight x household g-factor
    g <- gh
    note_clust <- sprintf("; one weight per '%s' (integrative)", step$cluster)
  }

  achieved <- colSums(new_w[active] * Z)
  # Check that the calibration constraints (X and model blocks) are satisfied.
  # Unbounded model calibration is exact up to numerical precision, so a deviation
  # points to collinear auxiliaries or an ill-conditioned system; with `bounds`,
  # a deviation can also mean the requested range is infeasible for these totals.
  rel_dev <- abs(achieved - Tvec) / (abs(Tvec) + 1)
  off     <- which(rel_dev > 1e-6)
  if (length(off) > 0L) {
    cause <- if (is.null(cf_bnd))
      "collinear auxiliaries or an ill-conditioned system; check the auxiliary variables."
    else
      "collinear auxiliaries, an ill-conditioned system, or an infeasible `bounds` range; widen the bounds or check the auxiliaries."
    warning(sprintf(
      paste0("Model calibration did not fully satisfy the constraints for: %s. ",
             "The achieved totals differ from the targets (max relative ",
             "deviation = %.2e); this can happen with %s"),
      paste(utils::head(colnames(Z)[off], 10L), collapse = ", "), max(rel_dev), cause),
      call. = FALSE)
  }
  type <- c(rep("X (consistency)", ncol(X)),
            rep("y (model)", length(step$models)))
  diag <- data.frame(constraint = colnames(Z), type = type,
                     target = round(Tvec, 2), achieved = round(achieved, 2),
                     stringsAsFactors = FALSE)
  attr(diag, "converged") <- (length(off) == 0L) && isTRUE(solver_ok)
  bnd_note <- if (is.null(cf_bnd)) "" else sprintf(", bounds [%.3f, %.3f]", cf_bnd[1], cf_bnd[2])
  attr(diag, "note") <- sprintf("g (calibration factor) in [%.3f, %.3f]%s%s",
                                min(g), max(g), bnd_note, note_clust)
  # Save the model-prediction columns (the mu block of Z) on the weights so a
  # FOLLOWING step_trim_calibrated() can preserve the model totals T_mu, not only
  # the X margins. prep() passes `w` forward to the next step, which reads this
  # attribute; it is consumed and stripped there (and by prep() at the end).
  mu_mat <- do.call(cbind, mu_cols)
  colnames(mu_mat) <- names(step$models)
  attr(new_w, "wf_modelcal") <- list(mu = mu_mat, active = which(active))
  list(weights = new_w, diagnostics = diag)
}

# --- Assert / checkpoint ---------------------------------------------------
apply_step.step_assert <- function(step, data, w) {
  # During recipe-aware replication the replicate weights carry the Rao-Wu
  # multiplier, so their design effect is structurally larger than the point
  # weights'. A quality checkpoint is meant for the FINAL weights, not each
  # replicate: evaluating it here would fail every replicate (SE = NaN), or worse,
  # let only the low-deff replicates survive and bias the SE downward. Skip it.
  if (isTRUE(attr(data, "wf_replicate")))
    return(list(weights = w, diagnostics = NULL))
  de     <- design_effect(w)
  base_w <- attr(data, "weightflow_base_w")
  active <- .wf_active(w)
  checks <- list()
  add <- function(name, value, thr, pass)
    checks[[length(checks) + 1]] <<- data.frame(
      check = name, value = round(value, 3), threshold = thr, pass = pass,
      stringsAsFactors = FALSE)

  # M8: a non-finite deff / n_eff (e.g. all-zero weights) made `de$deff <= max`
  # return NA, which then blew up `any(!diag$pass)` with "missing value where
  # TRUE/FALSE needed". isTRUE() turns an unverifiable check into a clean failure.
  if (!is.null(step$max_deff))
    add("deff <= max", de$deff, step$max_deff, isTRUE(de$deff <= step$max_deff))
  if (!is.null(step$min_n_eff))
    add("n_eff >= min", de$n_eff, step$min_n_eff, isTRUE(de$n_eff >= step$min_n_eff))
  if (!is.null(step$max_weight_ratio)) {
    if (is.null(base_w)) stop("max_weight_ratio needs the base weights (provided by prep()).")
    # N4-6: with no active units max(numeric(0)) is -Inf and the check would pass
    # on no data (and warn under warn = 2); NA makes it a clean failure instead.
    mr <- if (any(active)) max(w[active] / base_w[active]) else NA_real_
    add("max(w/base) <= max", mr, step$max_weight_ratio, isTRUE(mr <= step$max_weight_ratio))
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
# TRIM-01 documents what this criterion assumes; see the Details section of
# step_trim_weights(). In short: the two terms sit on different orders of n on
# purpose (it is the MSE of a TOTAL, so the cutoff rises with the sample size for
# the same weight distribution), and the bias charged is the bias of capping
# WITHOUT redistribution while the step always redistributes -- so the criterion
# overstates the bias and caps less than its own name promises. `kappa` prices bias
# against variance; 1 is Potter's own weighting and leaves the cutoff unchanged.
.potter_threshold <- function(wv, ngrid = 100L, kappa = 1) {
  qs    <- stats::quantile(wv, c(0.50, 0.999))
  grid  <- seq(as.numeric(qs[1]), as.numeric(qs[2]), length.out = ngrid)
  bias2 <- vapply(grid, function(t) sum(wv[wv > t] - t)^2, numeric(1))  # bias(t)^2
  varc  <- vapply(grid, function(t) sum(pmin(wv, t)^2),     numeric(1))  # dispersion remaining
  mse   <- kappa * bias2 + varc
  best  <- grid[which.min(mse)]
  attr(best, "grid")  <- grid;  attr(best, "bias2") <- bias2
  attr(best, "varc")  <- varc;  attr(best, "mse")   <- mse
  best
}

apply_step.step_trim_weights <- function(step, data, w) {
  active <- .wf_active(w)   # trim every active weight (non-zero and finite, incl.
  new_w  <- w               # negatives from unbounded calibration); leave dropped units
  wv     <- new_w[active]
  step$maxit <- .wf_count(step$maxit, "maxit")   # 0/NA/"a" would silently skip trimming

  pot_obj <- NULL; unredist <- 0        # init BEFORE the potter branch, so the
                                        # Potter grid/MSE set below is not clobbered
  upper <- step$upper
  if (is.null(upper)) {
    if (identical(step$method, "potter")) {
      upper   <- .potter_threshold(wv, kappa = step$kappa %||% 1)   # MSE-optimal cutoff (Potter)
      pot_obj <- upper                               # keep grid/mse for the report
      upper   <- as.numeric(upper)
    } else {
      q   <- stats::quantile(wv, c(.25, .75))
      iqr <- as.numeric(q[2] - q[1])
      if (iqr > 0) {
        upper <- as.numeric(q[2] + 3 * iqr)          # Tukey far-out fence
      } else {
        # IQR == 0: a dominant modal weight or a (near) self-weighting design. The
        # Tukey fence then degenerates to Q3 (the mode), so every unit above the mode
        # is capped and the receiving set (units strictly below the cap) is EMPTY --
        # the capped mass would be lost silently. Fall back to a high quantile, which
        # keeps the modal units as a non-empty receiving set.
        upper <- as.numeric(stats::quantile(wv, 0.99))
        if (upper <= q[2]) upper <- max(wv)          # still degenerate -> nothing to trim
      }
    }
  }
  # `lower = NULL` means "no floor" -> -Inf. (Leaving it NULL makes `wv < lower`
  # collapse to logical(0), which breaks the redistribution and errors on the
  # diagnostics data.frame.)
  lower <- if (is.null(step$lower)) -Inf else as.numeric(step$lower)
  # Validate AFTER the automatic `upper` (Potter / Tukey) is resolved, not just in
  # the constructor: `lower >= upper` has no valid interval and would otherwise
  # clamp every weight to a single value and silently inflate/deflate the total.
  if (lower >= upper)
    stop(sprintf(paste0("`lower` (%s) must be strictly below `upper` (%s) in ",
                        "step_trim_weights(); with lower >= upper the trim has no valid ",
                        "interval."), format(lower), format(upper)), call. = FALSE)

  it    <- 0L
  maxed <- FALSE                    # the loop ran out of iterations (TRIM-01)
  if (identical(step$redistribute, "uniform")) {
    # survey::trimWeights scheme: share the trimmed mass EQUALLY among the
    # untrimmed units, and never reuse a unit that has already been trimmed.
    has_trimmed <- rep(FALSE, length(wv))
    repeat {
      it      <- it + 1L
      outside <- wv < lower | wv > upper
      if (!any(outside)) break
      if (it > step$maxit) { maxed <- TRUE; break }
      wvnew     <- pmin(pmax(wv, lower), upper)
      trimmings <- wv - wvnew
      can_trim  <- !outside & !has_trimmed
      if (any(can_trim))
        wvnew[can_trim] <- wvnew[can_trim] + sum(trimmings) / sum(can_trim)
      else
        unredist <- unredist + sum(trimmings)         # nobody left to receive it
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
      if (it > step$maxit) { maxed <- TRUE; break }
      # net weight removed by clamping (high trimmed minus low raised)
      net <- sum(wv[over] - upper) - sum(lower - wv[under])
      wv[over]  <- upper
      wv[under] <- lower
      free <- wv < upper & wv > lower
      sf   <- sum(wv[free])
      if (abs(net) > 1e-12 && any(free)) {        # redistribute to preserve total
        # equal split when the free weights are not clearly positive (see step_trim)
        if (sf > 1e-9) wv[free] <- wv[free] + net * wv[free] / sf
        else           wv[free] <- wv[free] + net / sum(free)
      } else if (abs(net) > 1e-12)
        unredist <- unredist + net                # nowhere to redistribute: mass lost
      if (!step$strict) break
    }
  }
  new_w[active] <- wv

  if (maxed) .wf_warn_trim_maxit(wv, lower, upper, step$maxit, "step_trim_weights()")

  # Mass that could not be handed back (no eligible receiving units) changes the weighted
  # total. The report emits a deferred alert, but prep(warn = FALSE) is the default, so warn
  # from the step itself -- silent mass loss is the failure this preserves-the-total step
  # exists to avoid.
  if (abs(unredist) > 1e-9)
    warning(sprintf(paste0("step_trim_weights(): %.4g of weight could not be redistributed ",
                          "(no units left to receive the trimmed mass), so the weighted total ",
                          "changed by that amount. Set `upper`/`lower` explicitly, or check for ",
                          "a dominant modal weight."), unredist), call. = FALSE)

  diag <- data.frame(
    method = if (is.null(step$method)) "tukey" else step$method,
    lower = lower, upper = round(upper, 3), strict = step$strict,
    n_capped = sum(w[active] > upper), n_raised = sum(w[active] < lower),
    sum_before = round(sum(w[active]), 2), sum_after = round(sum(new_w[active]), 2),
    stringsAsFactors = FALSE
  )
  attr(diag, "iterations") <- it
  ai <- which(active); lo_u <- if (is.null(lower)) -Inf else as.numeric(lower)
  attr(diag, "trim_rec") <- list(
    wb = w[ai], wa = new_w[ai], cap = rep(as.numeric(upper), length(ai)),
    floor = rep(lo_u, length(ai)), idx = ai, by = NULL,
    redistribute = if (identical(step$redistribute, "uniform")) "uniform" else "proportional",
    method = if (is.null(step$method)) "tukey" else step$method, kind = "weights",
    f = new_w[ai] / w[ai], unredist = unredist,
    deff_before = design_effect(w)$deff, deff_after = design_effect(new_w)$deff)
  if (!is.null(pot_obj))
    attr(diag, "potter") <- list(grid = attr(pot_obj, "grid"), bias2 = attr(pot_obj, "bias2"),
                                 varc = attr(pot_obj, "varc"), mse = attr(pot_obj, "mse"),
                                 chosen = as.numeric(pot_obj))
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
  # M3: only an UNNAMED single number is a global bound. A named length-1 vector
  # (e.g. c(North = 16)) is a per-group bound for one group -- fall through so it
  # requires `by` and is checked for coverage, instead of being applied to all.
  if (length(b) == 1L && is.null(names(b))) return(rep(as.numeric(b), n))
  if (is.null(grp))
    stop(sprintf(paste0("`%s` is a named / length > 1 vector but no `by` was given. ",
                        "Supply `by` and a named vector of %s bounds per group, or pass a ",
                        "single unnamed number for a global bound."),
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
  active <- .wf_active(w)                      # active weights (may include negatives)
  if (!any(active)) return(list(weights = w, diagnostics = NULL))
  new_w <- w
  d     <- w[active]                   # incoming weights = base for this step

  dd <- data[active, , drop = FALSE]
  X  <- stats::model.matrix(step$formula, data = dd)
  if (nrow(X) != length(d) || anyNA(X))
    stop("Auxiliaries in `formula` have missing values in the active sample; ",
         "trimmed calibration needs them observed for every unit being trimmed.")
  cn <- colnames(X)

  # If the previous step was a step_model_calibration(), it saved its prediction
  # columns (the mu block of Z) on the incoming weights. Append them so we preserve
  # the MODEL totals T_mu too, not only the X margins in `formula`. Absent (the usual
  # case, after step_calibrate) -> unchanged behaviour.
  mc <- attr(w, "wf_modelcal")
  if (!is.null(mc)) {
    if (identical(mc$active, which(active)) && nrow(mc$mu) == length(d)) {
      X  <- cbind(X, mc$mu)
      cn <- colnames(X)
    } else {
      warning(paste0("A preceding step_model_calibration()'s predictions are not aligned ",
                     "with the active sample here (an intermediate step changed it); trimming ",
                     "preserves only the X margins in `formula`."), call. = FALSE)
    }
  }

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
    # unit level: per-unit factor bound so that w_k = d_k * f_k stays in
    # [lower, upper]. Dividing by a NEGATIVE incoming weight flips the inequality,
    # so take the min/max per row instead of assuming lower/d <= upper/d (which
    # would invert the interval and pin negative-weight units at `upper`).
    bnd  <- cbind(pmin(lower / d, upper / d), pmax(lower / d, upper / d))
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
    # The integrative solve assigns ONE weight per cluster, so the incoming weight
    # must already be uniform within the cluster; otherwise the per-unit bound
    # w = d*f in [lower, upper] cannot be honoured with a single household factor
    # and the bounds would be violated silently. Same guard as the other three
    # integrative engines.
    .wf_assert_uniform_within_cluster(d, cl, step$cluster)
    # With `by` the bounds are per subgroup; a cluster that spans two subgroups has
    # an ambiguous household bound. Require the bounds to be constant within cluster
    # instead of silently taking the first member's (order-dependent).
    .chk_bound_const <- function(v, nm) {
      if (any(tapply(v, cl, function(x) length(unique(x)) > 1L)))
        stop(sprintf(paste0("Trimming bound `%s` is not constant within cluster '%s': a cluster ",
                            "spans `by` subgroups with different bounds, so the one-weight-per-cluster ",
                            "bound is ambiguous. Keep each cluster within a single `by` subgroup."),
                     nm, step$cluster), call. = FALSE)
    }
    .chk_bound_const(lower, "lower"); .chk_bound_const(upper, "upper")
    hh    <- unique(cl)
    n_h   <- as.numeric(tapply(d, cl, length)[hh])
    Wsum  <- as.numeric(tapply(d, cl, sum)[hh])
    Xbar  <- rowsum(X, group = cl)[hh, , drop = FALSE] / n_h
    d_h   <- Wsum / n_h                                  # common household weight
    lo_h  <- as.numeric(tapply(lower, cl, function(x) x[1])[hh])  # bound per household
    up_h  <- as.numeric(tapply(upper, cl, function(x) x[1])[hh])
    bnd_h <- cbind(pmin(lo_h / d_h, up_h / d_h), pmax(lo_h / d_h, up_h / d_h))
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
  # Both endpoints go through ONE formatter. format() uses 7 *significant* digits,
  # so a pair like (0.00083516172, 109.806432) printed as
  # "[0.0008351617, 109.8064]" -- ten decimals on one side, four on the other.
  .b <- function(z) formatC(z, format = "fg", digits = 4, big.mark = ",", drop0trailing = TRUE)
  lo_lab <- if (length(unique(lower)) == 1L) .b(lower[1]) else "by group"
  up_lab <- if (length(unique(upper)) == 1L) .b(upper[1]) else "by group"
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
           "lower, %d capped at upper; f (adjustment) in [%s, %s]%s"),
    lo_lab, up_lab, step$calfun, n_at_lower, n_at_upper,
    .b(min(f)), .b(max(f)), note_clust)
  attr(diag, "trim") <- data.frame(
    lower = if (length(unique(lower)) == 1L) lower[1] else NA_real_,
    upper = if (length(unique(upper)) == 1L) upper[1] else NA_real_,
    calfun = step$calfun,
    n_below_before = n_below, n_above_before = n_above,
    n_at_lower = n_at_lower, n_at_upper = n_at_upper,
    sum_before = round(sum(d), 2), sum_after = round(sum(wa), 2),
    stringsAsFactors = FALSE)
  attr(diag, "trim_rec") <- list(
    wb = d, wa = wa, cap = upper, floor = lower, idx = which(active), by = grp,
    redistribute = "calibration", method = step$calfun, kind = "calibrated",
    f = f, unredist = NA_real_,
    deff_before = design_effect(w)$deff, deff_after = design_effect(new_w)$deff)
  attr(new_w, "wf_modelcal") <- NULL   # consumed; do not carry it further
  list(weights = new_w, diagnostics = diag)
}

# --- Rescale / normalize ---------------------------------------------------
apply_step.step_rescale <- function(step, data, w) {
  n      <- length(w)
  active <- .wf_active(w)
  new_w  <- w

  if (step$to == "total") {                       # scale overall to `total`
    if (!is.numeric(step$total) || length(step$total) != 1L || !is.finite(step$total) ||
        step$total <= 0)
      stop(sprintf(paste0("step_rescale(to = \"total\") needs `total` to be a single positive ",
                          "finite number; got %s. (0 zeroes every weight, a negative flips their ",
                          "sign, Inf/NA corrupt them.)"), deparse(step$total)[1]), call. = FALSE)
    cur <- sum(new_w[active])
    fac <- if (cur > 0) step$total / cur else NA_real_
    if (!is.na(fac)) new_w[active] <- new_w[active] * fac
    diag <- data.frame(cell = "(all)", target = round(step$total, 2),
                       prev_sum = round(cur, 2), factor = round(fac, 4),
                       stringsAsFactors = FALSE)
    return(list(weights = new_w, diagnostics = diag))
  }

  # to == "n": each (by-)group sums to its active count (mean weight 1)
  cells <- .make_cells(data, step$by, n, active = active)
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
