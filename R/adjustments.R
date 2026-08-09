# apply_step() S3 generic + cascade steps: unknown eligibility, within-household selection, nonresponse.

# Internal generic ----------------------------------------------------------
apply_step <- function(step, data, w) UseMethod("apply_step")

# Split fitted response propensities into `num_classes` quantile-based
# adjustment classes. When the propensities are (nearly) constant the quantile
# cut-points collapse to fewer than three distinct values, so no two classes can
# be formed. Passing the deduplicated breaks straight to cut() is a trap: with a
# single break, cut() reinterprets it as the *number* of intervals and fails
# with "invalid number of intervals". In that degenerate case everyone goes to a
# single adjustment class (the statistically sensible outcome -- if every unit
# has the same propensity there is nothing to differentiate) and a `collapsed`
# flag is attached so the caller can raise a quality alert.
.propensity_classes <- function(p, num_classes) {
  brks <- unique(stats::quantile(p, probs = seq(0, 1, length.out = num_classes + 1),
                                 names = FALSE, na.rm = TRUE))
  if (length(brks) < 3L) {
    cls <- factor(rep("all", length(p)))
    attr(cls, "collapsed") <- TRUE
    return(cls)
  }
  cut(p, breaks = brks, include.lowest = TRUE)
}

# Estimate the response propensity P(respond) with the chosen engine.
# Returns probabilities (bounded away from 0 for 1/p).
# The engine only changes HOW p is estimated; the class/unit logic is the same.
# `crossfit` (K) and `cluster_id`/`seed` enable K-fold out-of-sample prediction
# to avoid overfitting; when NULL, the model is fitted and predicted in-sample.
.estimate_propensity <- function(engine, formula, dd, weights,
                                 crossfit = NULL, cluster_id = NULL, seed = NULL) {
  f <- stats::update(formula, .y ~ .)
  dd$.wts <- weights

  # fit on rows `tr`, predict on rows `te`; returns P(respond) for `te`
  fit_pred <- function(tr, te) {
    dtr <- dd[tr, , drop = FALSE]; dte <- dd[te, , drop = FALSE]
    wtr <- weights[tr]
    if (engine == "logit") {
      # weighted binomial glm warns about non-integer successes; this is a
      # known, benign consequence of survey weights, so suppress just that one.
      fit <- withCallingHandlers(
        stats::glm(f, data = dtr, family = stats::binomial(), weights = .wts),
        warning = function(w) {
          if (grepl("non-integer", conditionMessage(w))) invokeRestart("muffleWarning")
        })
      as.numeric(stats::predict(fit, newdata = dte, type = "response"))
    } else if (engine == "tree") {
      if (!requireNamespace("rpart", quietly = TRUE))
        stop("engine = 'tree' requires the 'rpart' package (install.packages('rpart')).")
      dtr$.y <- factor(dtr$.y, levels = c(0, 1))
      fit <- rpart::rpart(f, data = dtr, method = "class", weights = .wts)
      as.numeric(stats::predict(fit, newdata = dte, type = "prob")[, "1"])
    } else if (engine == "forest") {
      if (!requireNamespace("ranger", quietly = TRUE))
        stop("engine = 'forest' requires the 'ranger' package (install.packages('ranger')).")
      dtr$.y <- factor(dtr$.y, levels = c(0, 1))
      fit <- ranger::ranger(f, data = dtr, probability = TRUE, case.weights = wtr,
                            num.threads = .wf_threads(), seed = 1L)
      as.numeric(stats::predict(fit, data = dte)$predictions[, "1"])
    } else if (engine == "boost") {
      y01 <- as.integer(as.character(dtr$.y) == "1" | dtr$.y == 1)
      .xgb_fit_predict(f, dtr, y01, wtr, list(dte), classification = TRUE)[[1]]
    } else {
      stop(sprintf("engine '%s' not recognized.", engine))
    }
  }

  n <- nrow(dd)
  if (is.null(crossfit)) {
    p <- fit_pred(seq_len(n), seq_len(n))
  } else {
    p <- .crossfit_predict(n, crossfit, cluster_id, seed,
                           fit_predict = function(tr, te_list)
                             lapply(te_list, function(te) fit_pred(tr, te)))
  }
  pmax(as.numeric(p), 1e-6)             # avoids division by zero in 1/p
}

# --- Unknown eligibility ---------------------------------------------------
apply_step.step_unknown_eligibility <- function(step, data, w) {
  n       <- length(w)
  unknown <- .eval_cond(step$unknown, data, step$env, active = w > 0)
  cells   <- .make_cells(data, step$by, n)
  active  <- w > 0                       # only still-active cases
  new_w   <- w
  diag    <- list()

  if (is.null(step$cluster)) {
    # ---- person/row level ----
    for (g in levels(cells)) {
      idx     <- which(cells == g & active)
      if (!length(idx)) next
      w_tot   <- sum(w[idx])
      idx_unk <- idx[unknown[idx]]
      idx_kn  <- idx[!unknown[idx]]
      w_known <- sum(w[idx_kn])
      factor  <- if (w_known > 0) w_tot / w_known else NA_real_
      new_w[idx_unk] <- 0                       # unknowns are always redistributed away
      if (!is.na(factor)) new_w[idx_kn] <- w[idx_kn] * factor
      diag[[length(diag) + 1]] <- data.frame(
        cell = g, level = "person", n_known = length(idx_kn),
        n_unknown = length(idx_unk), factor = factor, stringsAsFactors = FALSE
      )
    }
  } else {
    # ---- cluster (household) level ----
    if (!step$cluster %in% names(data))
      stop(sprintf("Cluster column '%s' not found in the data.", step$cluster))
    cl <- as.character(data[[step$cluster]])
    for (g in levels(cells)) {
      idx <- which(cells == g & active)
      if (!length(idx)) next
      clg   <- cl[idx]
      Wh    <- tapply(w[idx], clg, mean)            # one weight per cluster (uniform assumed)
      unk_h <- tapply(unknown[idx], clg, any)       # cluster unknown if any member is
      hh    <- names(Wh)
      unk_h <- as.logical(unk_h[hh])
      W_tot   <- sum(Wh)
      W_known <- sum(Wh[!unk_h])
      factor  <- if (W_known > 0) W_tot / W_known else NA_real_
      member_unknown <- clg %in% hh[unk_h]
      new_w[idx[member_unknown]]  <- 0          # unknown households always redistributed away
      if (!is.na(factor)) new_w[idx[!member_unknown]] <- w[idx[!member_unknown]] * factor
      diag[[length(diag) + 1]] <- data.frame(
        cell = g, level = "household", n_known = sum(!unk_h),
        n_unknown = sum(unk_h), factor = factor, stringsAsFactors = FALSE
      )
    }
  }
  list(weights = new_w, diagnostics = do.call(rbind, diag))
}

# --- Within-household (sub)selection ---------------------------------------
apply_step.step_select_within <- function(step, data, w) {
  ecenv  <- if (is.null(step$env)) baseenv() else step$env
  active <- w > 0
  new_w  <- w
  if (!is.null(step$prob)) {
    p <- as.numeric(eval(step$prob, envir = data, enclos = ecenv))
    if (any(is.na(p[active])) || any(p[active] <= 0 | p[active] > 1))
      stop("`prob` must be a within-household selection probability in (0, 1].")
    fac <- 1 / p
    lbl <- "1/prob"
  } else {
    k <- as.numeric(eval(step$n_eligible, envir = data, enclos = ecenv))
    m <- if (is.null(step$n_selected)) rep(1, length(k))
         else as.numeric(eval(step$n_selected, envir = data, enclos = ecenv))
    if (length(m) == 1L) m <- rep(m, length(k))
    if (any(is.na(k[active])) || any(k[active] < 1))
      stop("`n_eligible` must be >= 1.")
    if (any(is.na(m[active])) || any(m[active] < 1) || any(m[active] > k[active]))
      stop("`n_selected` must be >= 1 and <= `n_eligible`.")
    fac <- k / m
    lbl <- if (is.null(step$n_selected)) "n_eligible" else "n_eligible/n_selected"
  }
  new_w[active] <- w[active] * fac[active]
  diag <- data.frame(
    using       = lbl,
    mean_factor = round(mean(fac[active]), 3),
    min_factor  = round(min(fac[active]), 3),
    max_factor  = round(max(fac[active]), 3),
    stringsAsFactors = FALSE
  )
  list(weights = new_w, diagnostics = diag)
}

# Household-level nonresponse (whole-household response) --------------------
.nonresponse_cluster <- function(step, data, w, respondent, eligible) {
  if (!step$cluster %in% names(data))
    stop(sprintf("Cluster column '%s' not found in the data.", step$cluster))
  n      <- length(w)
  new_w  <- w
  idx_el <- which(eligible)
  cl     <- as.character(data[[step$cluster]])[idx_el]
  Wh     <- tapply(w[idx_el], cl, mean)            # one weight per household
  resp_h <- tapply(respondent[idx_el], cl, all)    # household responded (whole roster)
  hhn    <- names(Wh)
  # partial-response households (some responded, not all) are treated as household
  # nonresponse; record how many responding members that discards, to flag it.
  resp_any_h  <- tapply(respondent[idx_el], cl, any)
  n_partial   <- sum(as.logical(resp_any_h[hhn]) & !as.logical(resp_h[hhn]))
  n_discarded <- sum(respondent[idx_el] & !as.logical(resp_h[cl]))
  Wh     <- as.numeric(Wh[hhn]); resp_h <- as.logical(resp_h[hhn])
  factor_h <- rep(NA_real_, length(hhn)); names(factor_h) <- hhn

  if (step$method == "weighting_class") {
    cells_all <- .make_cells(data, step$by, n)
    cellh <- tapply(as.character(cells_all[idx_el]), cl, function(z) z[1])[hhn]
    diag  <- list()
    for (g in unique(cellh)) {
      sel    <- which(cellh == g)
      w_tot  <- sum(Wh[sel]); w_resp <- sum(Wh[sel][resp_h[sel]])
      f      <- if (w_resp > 0) w_tot / w_resp else NA_real_
      factor_h[sel] <- ifelse(resp_h[sel], f, 0)
      diag[[length(diag) + 1]] <- data.frame(
        cell = g, n_resp_hh = sum(resp_h[sel]), n_nr_hh = sum(!resp_h[sel]),
        factor = f, stringsAsFactors = FALSE)
    }
    diag <- do.call(rbind, diag)

  } else {                                          # propensity, household level
    if (is.null(step$formula)) stop("method = 'propensity' requires `formula`.")
    ddh    <- data[idx_el[match(hhn, cl)], , drop = FALSE]   # one row per household
    ddh$.y <- as.integer(resp_h)
    mw     <- if (is.null(step$weight_model) || isTRUE(step$weight_model)) Wh
              else rep(1, length(Wh))
    p      <- .estimate_propensity(step$engine, step$formula, ddh, mw,
                                   crossfit = step$crossfit, seed = step$crossfit_seed)
    if (is.null(step$num_classes)) {
      factor_h <- ifelse(resp_h, 1 / p, 0)
      diag <- data.frame(engine = step$engine, level = "household",
                         method = "1/p per household",
                         p_min = min(p), p_max = max(p), stringsAsFactors = FALSE)
    } else {
      classh <- .propensity_classes(p, step$num_classes)
      diag   <- list()
      for (cls in levels(classh)) {
        sel    <- which(classh == cls)
        w_tot  <- sum(Wh[sel]); w_resp <- sum(Wh[sel][resp_h[sel]])
        f      <- if (w_resp > 0) w_tot / w_resp else NA_real_
        factor_h[sel] <- ifelse(resp_h[sel], f, 0)
        diag[[length(diag) + 1]] <- data.frame(
          propensity_class = cls, n_hh = length(sel),
          mean_prop = mean(p[sel]), factor = f, stringsAsFactors = FALSE)
      }
      diag <- do.call(rbind, diag)
      if (isTRUE(attr(classh, "collapsed"))) attr(diag, "classes_collapsed") <- TRUE
    }
    names(factor_h) <- hhn
  }

  new_w[idx_el] <- w[idx_el] * factor_h[cl]         # assign household factor to members
  attr(diag, "partial_hh")     <- n_partial
  attr(diag, "discarded_resp") <- n_discarded
  list(weights = new_w, diagnostics = diag)
}

# --- Drop ineligible (out-of-scope) units ----------------------------------
apply_step.step_drop_ineligible <- function(step, data, w) {
  active <- w > 0
  inelig <- .eval_cond(step$ineligible, data, step$env, active = w > 0)
  new_w  <- w
  drop   <- active & inelig
  new_w[drop] <- 0                       # discarded, NOT redistributed
  diag <- data.frame(
    n_dropped      = sum(drop),
    weight_dropped = round(sum(w[drop]), 2),
    n_remaining    = sum(new_w > 0),
    stringsAsFactors = FALSE
  )
  list(weights = new_w, diagnostics = diag)
}

# --- Nonresponse -----------------------------------------------------------
# Calibration approach to nonresponse (two-phase; Lundstrom & Sarndal 1999,
# Sarndal & Lundstrom 2005; Estevao & Sarndal 2002 for the two-phase case).
# Calibrate the respondents' weights so the weighted auxiliaries reproduce either
# the R+NR design-weighted totals at this stage (totals = NULL: the sample-level /
# two-phase target, which by construction coincides with the pre-nonresponse
# cascade estimate) or supplied population totals. Nonrespondents get weight 0.
# The sample-level target is computed INSIDE the step from the incoming weights,
# so the recipe-aware bootstrap/jackknife recomputes it on each replicate and the
# two-phase variance is captured automatically.
.nonresponse_calibrate <- function(step, data, w, respondent, eligible) {
  new_w    <- w
  elig_idx <- which(eligible)
  dd       <- data[eligible, , drop = FALSE]
  Xall     <- stats::model.matrix(step$formula, data = dd)
  if (nrow(Xall) != length(elig_idx) || anyNA(Xall))
    stop("Auxiliaries in `formula` have missing values in the eligible sample. ",
         "Sample-level nonresponse calibration requires them observed for both ",
         "respondents and nonrespondents.")
  cn     <- colnames(Xall)
  resp_e <- as.logical(respondent[eligible])
  if (!any(resp_e)) stop("No eligible respondents to calibrate.")

  # --- target: sample-level (R+NR) or population ---
  if (is.null(step$totals)) {
    Tvec <- colSums(w[eligible] * Xall)          # R + NR with incoming weights
    tlab <- "sample-level"
  } else {
    totvec <- if (is.list(step$totals) && !is.data.frame(step$totals))
                .prep_linear_totals(step$formula, step$totals, step$count, data, eligible)
              else step$totals
    if (!setequal(names(totvec), cn))
      stop("`totals` names must match the model.matrix columns: ",
           paste(cn, collapse = ", "))
    Tvec <- as.numeric(totvec[cn]); tlab <- "population"
  }

  # --- solve on respondents only, drop nonrespondents ---
  Xr  <- Xall[resp_e, , drop = FALSE]
  dr  <- w[eligible][resp_e]
  if (!step$equal_within_cluster) {
    # unit-level: one calibration factor per responding unit
    sol <- .solve_calibration(Xr, dr, Tvec, step$calfun, step$bounds,
                              step$penalty, step$maxit, step$tol)
    g   <- sol$g
    new_w[elig_idx[resp_e]] <- dr * g
    note_clust <- ""
  } else {
    # integrative (Lemaitre-Dufour): one weight per cluster among the
    # respondents. Replace each responding unit's auxiliaries by the mean over
    # its responding household members and calibrate at unit level, so all
    # responding members of a household share one calibration factor.
    if (!step$cluster %in% names(data))
      stop(sprintf("Cluster column '%s' not found in the data.", step$cluster))
    clr <- as.character(data[[step$cluster]])[eligible][resp_e]
    if (anyNA(clr))
      stop(sprintf("Cluster column '%s' has missing values (NA).", step$cluster))
    hh   <- unique(clr)
    n_h  <- as.numeric(tapply(dr, clr, length)[hh])          # responding members
    Wsum <- as.numeric(tapply(dr, clr, sum)[hh])             # base weight in household
    Xbar <- rowsum(Xr, group = clr)[hh, , drop = FALSE] / n_h  # household MEANS
    sol  <- .solve_calibration(Xbar, Wsum, Tvec, step$calfun, step$bounds,
                               step$penalty, step$maxit, step$tol)
    gh   <- sol$g; names(gh) <- hh
    g    <- gh
    new_w[elig_idx[resp_e]] <- dr * gh[clr]                  # own weight x household factor
    note_clust <- sprintf("; one weight per '%s' (integrative)", step$cluster)
  }
  new_w[elig_idx[!resp_e]] <- 0

  # --- diagnostics (same conventions as step_calibrate) ---
  achieved  <- colSums(new_w[elig_idx[resp_e]] * Xr)
  truncated <- !is.null(step$bounds) || step$calfun == "logit"
  conv_ok   <- sol$converged
  if (is.null(step$penalty) && !truncated) {
    rel_dev <- abs(achieved - Tvec) / (abs(Tvec) + 1)
    if (any(rel_dev > 1e-6)) {
      conv_ok <- FALSE
      warning(sprintf(paste0("Nonresponse calibration did not fully satisfy the ",
                             "constraints (max relative deviation = %.2e)."),
                      max(rel_dev)), call. = FALSE)
    }
  }
  diag <- data.frame(variable = cn, target = Tvec, achieved = round(achieved, 2),
                     stringsAsFactors = FALSE)
  if (!is.null(step$penalty)) diag$deviation <- round(achieved - Tvec, 2)
  attr(diag, "converged") <- conv_ok
  bnote <- if (step$calfun != "linear" || !is.null(step$bounds))
    sprintf(" [calfun = %s%s]", step$calfun,
            if (!is.null(step$bounds)) sprintf(", bounds (%.2f, %.2f)",
                                               step$bounds[1], step$bounds[2]) else "")
  else ""
  rnote <- if (!is.null(step$penalty)) " [ridge: constraints relaxed, not exact]" else ""
  attr(diag, "note") <- sprintf(
    "nonresponse calibration to %s totals; g in [%.3f, %.3f]%s%s%s",
    tlab, min(g), max(g), bnote, rnote, note_clust)
  # Per-respondent calibration g and info level, for the report's unified NR
  # diagnostics: implicit response propensity phi-hat = 1/g (Sarndal-Lundstrom).
  attr(diag, "calib_nr") <- list(
    g = as.numeric(new_w[elig_idx[resp_e]] / dr), dw = as.numeric(dr), info = tlab,
    aux = dd[, all.vars(step$formula), drop = FALSE], resp = as.logical(resp_e),
    dw_all = as.numeric(w[eligible]), elig_idx = elig_idx)
  list(weights = new_w, diagnostics = diag)
}

apply_step.step_nonresponse <- function(step, data, w) {
  n          <- length(w)
  eligible   <- w > 0                    # reach this stage alive
  respondent <- .eval_cond(step$respondent, data, step$env, active = eligible)

  if (step$method == "calibration")      # calibration approach (two-phase)
    return(.nonresponse_calibrate(step, data, w, respondent, eligible))

  if (!is.null(step$cluster))
    return(.nonresponse_cluster(step, data, w, respondent, eligible))

  new_w      <- w

  if (step$method == "weighting_class") {
    cells <- .make_cells(data, step$by, n)
    diag  <- list()
    for (g in levels(cells)) {
      idx      <- which(cells == g & eligible)
      if (!length(idx)) next
      idx_resp <- idx[respondent[idx]]
      idx_nr   <- idx[!respondent[idx]]
      w_resp   <- sum(w[idx_resp])
      w_tot    <- sum(w[idx])
      factor   <- if (w_resp > 0) w_tot / w_resp else NA_real_
      new_w[idx_nr] <- 0                        # nonrespondents dropped even if the cell has no respondents
      if (!is.na(factor)) new_w[idx_resp] <- w[idx_resp] * factor
      diag[[length(diag) + 1]] <- data.frame(
        cell = g, n_respondents = length(idx_resp),
        n_nonresponse = length(idx_nr), factor = factor,
        stringsAsFactors = FALSE
      )
    }
    return(list(weights = new_w, diagnostics = do.call(rbind, diag)))
  }

  # method == "propensity"
  if (is.null(step$formula)) stop("method = 'propensity' requires `formula`.")
  dd      <- data[eligible, , drop = FALSE]
  dd$.y   <- as.integer(respondent[eligible])
  cl_cf   <- if (!is.null(step$cluster)) as.character(data[[step$cluster]][eligible]) else NULL
  mw      <- if (is.null(step$weight_model) || isTRUE(step$weight_model)) w[eligible]
             else rep(1, sum(eligible))
  p       <- .estimate_propensity(step$engine, step$formula, dd, mw,
                                  crossfit = step$crossfit, cluster_id = cl_cf,
                                  seed = step$crossfit_seed)
  idx_el  <- which(eligible)
  resp_el <- respondent[eligible]

  if (is.null(step$num_classes)) {
    # direct factor 1/p for respondents
    fac <- 1 / p
    new_w[idx_el[resp_el]]  <- w[idx_el[resp_el]] * fac[resp_el]
    new_w[idx_el[!resp_el]] <- 0
    diag <- data.frame(engine = step$engine, method = "1/p per unit",
                       p_min = min(p), p_max = max(p),
                       stringsAsFactors = FALSE)
  } else {
    class <- .propensity_classes(p, step$num_classes)
    diag  <- list()
    for (cl in levels(class)) {
      sel       <- which(class == cl)
      idx_cl    <- idx_el[sel]
      resp_cl   <- resp_el[sel]
      w_resp    <- sum(w[idx_cl[resp_cl]])
      w_tot     <- sum(w[idx_cl])
      factor    <- if (w_resp > 0) w_tot / w_resp else NA_real_
      new_w[idx_cl[!resp_cl]] <- 0
      if (!is.na(factor)) new_w[idx_cl[resp_cl]] <- w[idx_cl[resp_cl]] * factor
      diag[[length(diag) + 1]] <- data.frame(
        propensity_class = cl, n = length(idx_cl),
        mean_prop = mean(p[sel]), factor = factor,
        stringsAsFactors = FALSE
      )
    }
    diag <- do.call(rbind, diag)
    if (isTRUE(attr(class, "collapsed"))) attr(diag, "classes_collapsed") <- TRUE
  }
  attr(diag, "p_min") <- min(p[resp_el], na.rm = TRUE)   # smallest propensity among respondents (drives 1/p)
  # Keep what the report needs to diagnose the ML propensities (calibration,
  # floor/overlap, covariate balance). Out-of-fold p when crossfit is used.
  attr(diag, "propensity") <- list(
    p = as.numeric(p), resp = as.logical(resp_el), dw = w[eligible],
    covars = dd[, all.vars(step$formula), drop = FALSE], engine = step$engine,
    formula = step$formula,
    crossfit = step$crossfit, weight_model = step$weight_model,
    num_classes = step$num_classes,
    cal_slope = tryCatch(unname(stats::coef(suppressWarnings(stats::glm(
      as.integer(resp_el) ~ stats::qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6)),
      family = stats::binomial(), weights = w[eligible])))[2]), error = function(e) NA_real_))
  list(weights = new_w, diagnostics = diag)
}
