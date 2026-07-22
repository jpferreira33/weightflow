# ---------------------------------------------------------------------------
# Computation of each adjustment. Internal helpers + the apply_step() generic.
# Each apply_step() receives the step, the data and the current weight vector,
# and returns list(weights = <new weights>, diagnostics = <data.frame>).
# Convention: a 0 weight marks a "dropped" case (ineligible / nonresponse).
# ---------------------------------------------------------------------------

# Evaluate a captured condition against the data ----------------------------
# Accepts a logical expression OR a 0/1 dummy column (coerced to logical).
.eval_cond <- function(expr, data) {
  if (is.null(expr)) return(NULL)
  out <- eval(expr, envir = data, enclos = baseenv())
  if (is.numeric(out)) {
    if (!all(out %in% c(0, 1, NA)))
      stop("A 0/1 dummy was expected, but other values were found.")
    out <- out == 1
  }
  if (!is.logical(out)) stop("The condition did not evaluate to TRUE/FALSE or a 0/1 dummy.")
  out[is.na(out)] <- FALSE
  out
}

# Build a grouping factor from the `by` columns -----------------------------
.make_cells <- function(data, by, n) {
  if (is.null(by)) return(factor(rep("(all)", n)))
  parts <- lapply(by, function(v) {
    if (!v %in% names(data)) stop(sprintf("Cell variable '%s' not found.", v))
    as.character(data[[v]])
  })
  factor(do.call(paste, c(parts, sep = " | ")))
}

# Solve the calibration system; if singular, use the pseudo-inverse ---------
# Ridge-calibration penalty diagonal (Bardsley-Chambers / Chambers). Each
# constraint j gets a cost c_j; the calibration system A becomes A + diag(s/c_j),
# where s = mean(diag(A)) makes the penalty SCALE-FREE: `penalty` is a unitless
# number that means the same regardless of sample size or weight scale. A large
# cost keeps the constraint (near) exact, a small cost relaxes it. `penalty` is a
# positive scalar (same cost for all constraints) or a named vector (cost per
# constraint, matched to the model.matrix columns `cn`).
.ridge_diag <- function(penalty, cn, A) {
  s <- mean(diag(A))                          # scale of the calibration system
  if (length(penalty) == 1L) {
    costs <- rep(as.numeric(penalty), length(cn))
  } else {
    if (is.null(names(penalty)))
      stop("A vector `penalty` must be named by calibration constraint.")
    costs <- penalty[cn]
    if (anyNA(costs))
      stop(sprintf("`penalty` is missing costs for: %s",
                   paste(cn[is.na(costs)], collapse = ", ")))
    costs <- as.numeric(costs)
  }
  diag(s / costs, nrow = length(cn))
}

.solve_calib <- function(A, rhs) {
  out <- tryCatch(solve(A, rhs), error = function(e) NULL)
  if (!is.null(out)) return(out)
  # Moore-Penrose pseudo-inverse via SVD (collinear/redundant auxiliaries)
  sv   <- svd(A)
  tol  <- max(dim(A)) * .Machine$double.eps * max(sv$d)
  dinv <- ifelse(sv$d > tol, 1 / sv$d, 0)
  warning("Singular calibration system (collinear auxiliaries); using pseudo-inverse.",
          call. = FALSE)
  as.numeric(sv$v %*% (dinv * crossprod(sv$u, rhs)))
}

# Deville-Sarndal calibration solver: returns the g factors so that
# sum_i d_i * g_i * x_i = T, using the chosen distance (calfun) and bounds.
# calfun: "linear" (g = 1 + u), "raking" (g = exp(u)), "logit" (bounded by
# construction). With bounds, linear/raking are clamped (truncated distance).
.calib_ds <- function(X, d, Tvec, calfun = "linear", bounds = NULL,
                      maxit = 100L, tol = 1e-7) {
  L <- if (is.null(bounds)) -Inf else bounds[1]
  U <- if (is.null(bounds)) Inf  else bounds[2]
  CLZ <- 500                                # clamp for exp() to avoid overflow

  if (calfun == "logit") {
    if (is.null(bounds)) stop("calfun = 'logit' requires `bounds`.")
    A_   <- (U - L) / ((1 - L) * (U - 1))
    Ffun <- function(u) { e <- exp(pmin(pmax(A_ * u, -CLZ), CLZ))
      (L * (U - 1) + U * (1 - L) * e) / ((U - 1) + (1 - L) * e) }
    Fp   <- function(u) { g <- Ffun(u); A_ * (g - L) * (U - g) / (U - L) }
  } else if (calfun == "raking") {
    Ffun <- function(u) pmin(pmax(exp(pmin(pmax(u, -CLZ), CLZ)), L), U)
    Fp   <- function(u) { g <- exp(pmin(pmax(u, -CLZ), CLZ)); ifelse(g > L & g < U, g, 0) }
  } else {                                  # linear (truncated if bounded)
    Ffun <- function(u) pmin(pmax(1 + u, L), U)
    Fp   <- function(u) { g <- 1 + u; ifelse(g > L & g < U, 1, 0) }
  }

  # Column scaling for conditioning (leaves the g-weights unchanged)
  s   <- apply(X, 2, function(col) { v <- sqrt(mean(col^2)); if (v == 0) 1 else v })
  Xs  <- sweep(X, 2, s, "/")
  Ts  <- Tvec / s

  lambda <- rep(0, ncol(Xs)); ok <- FALSE
  resid_norm <- function(lam) {                       # max relative residual
    ach <- colSums(d * Ffun(as.numeric(Xs %*% lam)) * Xs)
    max(abs(ach - Ts) / (abs(Ts) + 1))
  }
  cur <- resid_norm(lambda)
  for (it in seq_len(maxit)) {
    if (cur < tol) { ok <- TRUE; break }
    u    <- as.numeric(Xs %*% lambda)
    J    <- t(Xs) %*% (d * Fp(u) * Xs)
    rhs  <- Ts - colSums(d * Ffun(u) * Xs)
    # Levenberg-Marquardt ridge: keeps J invertible when many units saturate
    # at the bounds (Fp -> 0), avoiding singular-system fallbacks each step.
    ridge <- 1e-7 * (mean(diag(J)) + .Machine$double.eps)
    dl    <- tryCatch(solve(J + diag(ridge, ncol(J)), rhs),
                      error = function(e) .solve_calib(J, rhs))
    # damped step: shrink until the residual does not blow up
    stepf <- 1; improved <- FALSE
    for (h in 1:20) {
      nr <- resid_norm(lambda + stepf * dl)
      if (is.finite(nr) && nr <= cur) { lambda <- lambda + stepf * dl; cur <- nr; improved <- TRUE; break }
      stepf <- stepf / 2
    }
    if (!improved) break
  }
  if (!ok)
    warning("Bounded calibration did not fully converge (bounds may be infeasible).",
            call. = FALSE)
  out <- Ffun(as.numeric(Xs %*% lambda))
  attr(out, "converged") <- ok
  out
}


# Fit an xgboost model and return predictions on a list of newdata frames.
# Handles both regression (objective "reg:squarederror") and binary
# classification (objective "binary:logistic", returns P(class = 1)).
# xgboost works on numeric matrices, so the design matrix is built with
# model.matrix from the same formula, dropping the intercept column.
.xgb_fit_predict <- function(formula, train, y, w, newdatas, classification,
                             nrounds = 150L, max_depth = 4L, eta = 0.1) {
  if (!requireNamespace("xgboost", quietly = TRUE))
    stop("engine = 'boost' requires the 'xgboost' package (install.packages('xgboost')).")
  rhs <- stats::reformulate(attr(stats::terms(formula), "term.labels"))
  mm  <- function(df) {
    M <- stats::model.matrix(rhs, data = df)
    M[, colnames(M) != "(Intercept)", drop = FALSE]
  }
  Xtr <- mm(train)
  obj <- if (classification) "binary:logistic" else "reg:squarederror"
  dtr <- xgboost::xgb.DMatrix(data = Xtr, label = as.numeric(y), weight = w)
  fit <- xgboost::xgb.train(params = list(objective = obj, max_depth = max_depth,
                                          eta = eta), data = dtr,
                            nrounds = nrounds, verbose = 0)
  cols <- colnames(Xtr)
  lapply(newdatas, function(nd) {
    Mn <- mm(nd)
    miss <- setdiff(cols, colnames(Mn))           # align columns to training
    for (cc in miss) Mn <- cbind(Mn, stats::setNames(data.frame(0), cc))
    Mn <- as.matrix(Mn[, cols, drop = FALSE])
    as.numeric(stats::predict(fit, Mn))
  })
}

# Cross-fitting (K-fold out-of-sample prediction) to avoid overfitting when a
# flexible learner is used to estimate a propensity or an outcome model. For
# each fold k, the model is trained on the other K-1 folds and used to predict
# the held-out fold, so each unit's prediction comes from a model that did not
# see it. Folds are formed by cluster when `cluster_id` is given (so correlated
# units, e.g. a household, stay together and there is no information leakage).
# `fit_predict(train_idx, newdata_idx_list)` must fit on rows `train_idx` and
# return a list of prediction vectors, one per element of `newdata_idx_list`.
.crossfit_predict <- function(n, K, cluster_id = NULL, seed = NULL, fit_predict) {
  if (!is.null(seed)) { old <- .Random.seed; on.exit({.Random.seed <<- old});
                        set.seed(seed) }
  if (is.null(cluster_id)) {
    fold <- sample(rep_len(seq_len(K), n))
  } else {                                   # assign whole clusters to folds
    uc       <- unique(cluster_id)
    cf       <- sample(rep_len(seq_len(K), length(uc)))
    names(cf) <- as.character(uc)
    fold     <- cf[as.character(cluster_id)]
  }
  K <- length(unique(fold))                  # may shrink if few clusters
  out <- numeric(n)
  for (k in sort(unique(fold))) {
    test_idx  <- which(fold == k)
    train_idx <- which(fold != k)
    if (!length(train_idx)) next
    out[test_idx] <- fit_predict(train_idx, list(test_idx))[[1]]
  }
  out
}

# Returns E[y|x] (regression) or P(y = last level | x) (classification).
.model_predict <- function(m, train, w, newdatas) {
  f     <- m$formula
  yname <- as.character(f[[2]])
  yv    <- train[[yname]]
  if (anyNA(yv))
    stop(sprintf(paste0("Model-calibration outcome '%s' has missing values in the ",
      "training sample. This usually means a nonresponse step is missing before ",
      "step_model_calibration(): the outcome is only observed for respondents, so ",
      "adjust for nonresponse first so that nonrespondents are dropped."), yname),
      call. = FALSE)
  is_class <- isTRUE(m$family == "binomial") || is.factor(yv) || is.character(yv) ||
              (is.numeric(yv) && length(unique(yv[!is.na(yv)])) == 2L)
  train <- as.data.frame(train)
  train$.wts <- w                       # weights as a column -> avoids glm/rpart scoping

  if (m$engine == "glm") {
    fam <- if (!is.null(m$family))
             switch(m$family, gaussian = stats::gaussian(),
                    binomial = stats::binomial(), poisson = stats::poisson(),
                    stop("`family` not recognized (use gaussian/binomial/poisson).") )
           else stats::gaussian()
    fit <- stats::glm(f, data = train, family = fam, weights = .wts)
    return(lapply(newdatas, function(nd)
      as.numeric(stats::predict(fit, newdata = nd, type = "response"))))
  }

  if (m$engine == "tree") {
    if (!requireNamespace("rpart", quietly = TRUE))
      stop("engine = 'tree' requires the 'rpart' package.")
    if (is_class) {
      train[[yname]] <- factor(train[[yname]]); lev <- levels(train[[yname]])
      fit <- rpart::rpart(f, data = train, method = "class", weights = .wts)
      return(lapply(newdatas, function(nd)
        as.numeric(stats::predict(fit, newdata = nd, type = "prob")[, lev[length(lev)]])))
    }
    fit <- rpart::rpart(f, data = train, method = "anova", weights = .wts)
    return(lapply(newdatas, function(nd) as.numeric(stats::predict(fit, newdata = nd))))
  }

  if (m$engine == "forest") {
    if (!requireNamespace("ranger", quietly = TRUE))
      stop("engine = 'forest' requires the 'ranger' package.")
    if (is_class) {
      train[[yname]] <- factor(train[[yname]]); lev <- levels(train[[yname]])
      fit <- ranger::ranger(f, data = train, probability = TRUE, case.weights = w)
      return(lapply(newdatas, function(nd)
        as.numeric(stats::predict(fit, data = nd)$predictions[, lev[length(lev)]])))
    }
    fit <- ranger::ranger(f, data = train, case.weights = w)
    return(lapply(newdatas, function(nd) as.numeric(stats::predict(fit, data = nd)$predictions)))
  }

  if (m$engine == "boost") {
    if (is_class) {
      ylev <- factor(train[[yname]])
      y01  <- as.integer(ylev) - 1L            # last level coded as 1
      return(.xgb_fit_predict(f, train, y01, w, newdatas, classification = TRUE))
    }
    return(.xgb_fit_predict(f, train, train[[yname]], w, newdatas, classification = FALSE))
  }
  stop(sprintf("engine '%s' not recognized.", m$engine))
}

# Internal generic ----------------------------------------------------------
apply_step <- function(step, data, w) UseMethod("apply_step")

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
      fit <- ranger::ranger(f, data = dtr, probability = TRUE, case.weights = wtr)
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
  unknown <- .eval_cond(step$unknown, data)
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
      if (!is.na(factor)) {
        new_w[idx_kn]  <- w[idx_kn] * factor
        new_w[idx_unk] <- 0
      }
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
      if (!is.na(factor)) {
        member_unknown <- clg %in% hh[unk_h]
        new_w[idx[!member_unknown]] <- w[idx[!member_unknown]] * factor
        new_w[idx[member_unknown]]  <- 0
      }
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
  active <- w > 0
  new_w  <- w
  if (!is.null(step$prob)) {
    p <- as.numeric(eval(step$prob, envir = data, enclos = baseenv()))
    if (any(is.na(p[active])) || any(p[active] <= 0 | p[active] > 1))
      stop("`prob` must be a within-household selection probability in (0, 1].")
    fac <- 1 / p
    lbl <- "1/prob"
  } else {
    k <- as.numeric(eval(step$n_eligible, envir = data, enclos = baseenv()))
    m <- if (is.null(step$n_selected)) rep(1, length(k))
         else as.numeric(eval(step$n_selected, envir = data, enclos = baseenv()))
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
    p      <- .estimate_propensity(step$engine, step$formula, ddh, Wh,
                                   crossfit = step$crossfit, seed = step$crossfit_seed)
    if (is.null(step$num_classes)) {
      factor_h <- ifelse(resp_h, 1 / p, 0)
      diag <- data.frame(engine = step$engine, level = "household",
                         method = "1/p per household",
                         p_min = min(p), p_max = max(p), stringsAsFactors = FALSE)
    } else {
      brks   <- stats::quantile(p, probs = seq(0, 1, length.out = step$num_classes + 1))
      classh <- cut(p, breaks = unique(brks), include.lowest = TRUE)
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
    }
    names(factor_h) <- hhn
  }

  new_w[idx_el] <- w[idx_el] * factor_h[cl]         # assign household factor to members
  list(weights = new_w, diagnostics = diag)
}

# --- Drop ineligible (out-of-scope) units ----------------------------------
apply_step.step_drop_ineligible <- function(step, data, w) {
  active <- w > 0
  inelig <- .eval_cond(step$ineligible, data)
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
apply_step.step_nonresponse <- function(step, data, w) {
  n          <- length(w)
  respondent <- .eval_cond(step$respondent, data)
  eligible   <- w > 0                    # reach this stage alive

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
      if (!is.na(factor)) {
        new_w[idx_resp] <- w[idx_resp] * factor
        new_w[idx_nr]   <- 0
      }
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
  p       <- .estimate_propensity(step$engine, step$formula, dd, w[eligible],
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
    brks  <- stats::quantile(p, probs = seq(0, 1, length.out = step$num_classes + 1))
    class <- cut(p, breaks = unique(brks), include.lowest = TRUE)
    diag  <- list()
    for (cl in levels(class)) {
      sel       <- which(class == cl)
      idx_cl    <- idx_el[sel]
      resp_cl   <- resp_el[sel]
      w_resp    <- sum(w[idx_cl[resp_cl]])
      w_tot     <- sum(w[idx_cl])
      factor    <- if (w_resp > 0) w_tot / w_resp else NA_real_
      if (!is.na(factor)) {
        new_w[idx_cl[resp_cl]]  <- w[idx_cl[resp_cl]] * factor
        new_w[idx_cl[!resp_cl]] <- 0
      }
      diag[[length(diag) + 1]] <- data.frame(
        propensity_class = cl, n = length(idx_cl),
        mean_prop = mean(p[sel]), factor = factor,
        stringsAsFactors = FALSE
      )
    }
    diag <- do.call(rbind, diag)
  }
  list(weights = new_w, diagnostics = diag)
}

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
      if (!use_ds) {
        A <- t(X) %*% (d * X)
        if (!is.null(step$penalty)) A <- A + .ridge_diag(step$penalty, cn, A)
        lambda <- .solve_calib(A, Tvec - colSums(d * X))
        g      <- as.numeric(1 + X %*% lambda)
      } else {
        g <- .calib_ds(X, d, Tvec, step$calfun, step$bounds, step$maxit)
        ds_converged <- isTRUE(attr(g, "converged"))
      }
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
      # aggregate.stage (Vanderhoeft 2001), ReGenesees and Statistics Canada's GES.
      hh   <- unique(cl)
      n_h  <- as.numeric(tapply(d, cl, length)[hh])       # persons per household
      Wsum <- as.numeric(tapply(d, cl, sum)[hh])          # total base weight in household
      Xbar <- rowsum(X, group = cl)[hh, , drop = FALSE] / n_h   # household MEANS
      if (!use_ds) {
        A <- t(Xbar) %*% (Wsum * Xbar)
        if (!is.null(step$penalty)) A <- A + .ridge_diag(step$penalty, cn, A)
        lambda <- .solve_calib(A, Tvec - colSums(Wsum * Xbar))
        gh     <- as.numeric(1 + Xbar %*% lambda)
      } else {
        gh <- .calib_ds(Xbar, Wsum, Tvec, step$calfun, step$bounds, step$maxit)
        ds_converged <- isTRUE(attr(gh, "converged"))
      }
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

  # Define the cap and floor per unit according to the reference
  base_w <- attr(data, "weightflow_base_w")
  cap   <- numeric(n); floor_v <- rep(0, n)
  if (step$reference == "base") {
    if (is.null(base_w)) stop("reference = 'base' requires the base weights (provided by prep()).")
    cap[]     <- step$max_ratio * base_w
    if (!is.null(step$min_ratio)) floor_v[] <- step$min_ratio * base_w
  } else if (step$reference == "median") {
    med       <- stats::median(new_w[active])
    cap[]     <- step$max_ratio * med
    if (!is.null(step$min_ratio)) floor_v[] <- step$min_ratio * med
  } else {                                   # "value": absolute
    cap[]     <- step$max_ratio
    if (!is.null(step$min_ratio)) floor_v[] <- step$min_ratio
  }

  deff_before <- design_effect(new_w)$deff
  cells       <- .make_cells(data, step$by, n)

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
    # aggregate.stage / Vanderhoeft 2001, ReGenesees and Statistics Canada's GES).
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
  active <- w > 0
  new_w  <- w
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
    if (abs(net) > 1e-12 && any(free))            # redistribute to preserve total
      wv[free] <- wv[free] + net * wv[free] / sum(wv[free])
    if (!step$strict) break
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
  cells <- data.frame(.key = names(agg), .Freq = as.numeric(agg),
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

  diag <- vector("list", nrow(cells))
  for (i in seq_len(nrow(cells))) {
    key    <- cells$.key[i]
    target <- cells$.Freq[i]
    idx <- which(skey == key & active)
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
  if (length(Ns) > 1L && diff(range(Ns)) > tol * max(Ns)) {
    warning(sprintf(
      paste0("The margin totals do not all sum to the same population size ",
             "(margin Ns: %s). Raking may not converge; each margin should sum ",
             "to the same N."),
      paste(format(round(Ns), big.mark = ","), collapse = ", ")),
      call. = FALSE)
  }

  it <- 0L; maxdiff <- Inf
  while (it < maxit && maxdiff >= tol) {
    it <- it + 1L; maxdiff <- 0
    for (m in margins_prep) {
      skey <- m$sample_key
      for (i in seq_len(nrow(m$cells))) {
        key    <- m$cells$.key[i]
        target <- m$cells$.Freq[i]
        idx <- which(skey == key & active)
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

  # population size N from any categorical margin (they must agree)
  Ns <- vapply(totals, function(t) {
    if (is.data.frame(t)) sum(as.numeric(t[[count]])) else NA_real_
  }, numeric(1))
  Ns <- Ns[!is.na(Ns)]
  if (length(Ns) == 0L)
    stop(paste0("At least one categorical target (a data frame) is required to ",
                "determine the population size N for the intercept."))
  if (diff(range(Ns)) > 1e-6 * max(Ns))
    warning(sprintf(
      "Categorical margins do not all sum to the same N (%s). Using the first.",
      paste(format(round(Ns), big.mark = ","), collapse = ", ")),
      call. = FALSE)
  N <- Ns[1]

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
      counts_v <- as.numeric(t[[count]])
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

  Tvec
}
