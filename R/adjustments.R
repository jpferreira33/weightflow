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
  Ffun(as.numeric(Xs %*% lambda))
}


# Returns E[y|x] (regression) or P(y = last level | x) (classification).
.model_predict <- function(m, train, w, newdatas) {
  f     <- m$formula
  yname <- as.character(f[[2]])
  yv    <- train[[yname]]
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
  stop(sprintf("engine '%s' not recognized.", m$engine))
}

# Internal generic ----------------------------------------------------------
apply_step <- function(step, data, w) UseMethod("apply_step")

# Estimate the response propensity P(respond) with the chosen engine.
# Returns probabilities (bounded away from 0 for 1/p).
# The engine only changes HOW p is estimated; the class/unit logic is the same.
.estimate_propensity <- function(engine, formula, dd, weights) {
  f <- stats::update(formula, .y ~ .)
  dd$.wts <- weights                    # weights as a column -> avoids glm/rpart scoping

  if (engine == "logit") {
    fit <- stats::glm(f, data = dd, family = stats::binomial(), weights = .wts)
    p   <- stats::predict(fit, type = "response")

  } else if (engine == "tree") {
    if (!requireNamespace("rpart", quietly = TRUE))
      stop("engine = 'tree' requires the 'rpart' package (install.packages('rpart')).")
    dd$.y <- factor(dd$.y, levels = c(0, 1))
    fit   <- rpart::rpart(f, data = dd, method = "class", weights = .wts)
    p     <- stats::predict(fit, type = "prob")[, "1"]

  } else if (engine == "forest") {
    if (!requireNamespace("ranger", quietly = TRUE))
      stop("engine = 'forest' requires the 'ranger' package (install.packages('ranger')).")
    dd$.y <- factor(dd$.y, levels = c(0, 1))
    fit   <- ranger::ranger(f, data = dd, probability = TRUE,
                            case.weights = weights)
    p     <- stats::predict(fit, data = dd)$predictions[, "1"]

  } else {
    stop(sprintf("engine '%s' not recognized.", engine))
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
    if (any(is.na(k[active])) || any(k[active] < 1))
      stop("`n_eligible` must be >= 1.")
    fac <- k
    lbl <- "n_eligible"
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
    p      <- .estimate_propensity(step$engine, step$formula, ddh, Wh)
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
  p       <- .estimate_propensity(step$engine, step$formula, dd, w[eligible])
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

# --- Calibration -----------------------------------------------------------
apply_step.step_calibrate <- function(step, data, w) {
  active <- w > 0
  new_w  <- w

  if (step$method == "poststratify") {
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
    if (!setequal(names(step$totals), cn))
      stop(sprintf(
        "`totals` names must match the model.matrix columns.\nExpected: %s",
        paste(cn, collapse = ", ")))
    Tvec     <- as.numeric(step$totals[cn])      # reorder to X columns
    bounded  <- !is.null(step$bounds) || step$calfun == "logit"

    if (!step$equal_within_cluster) {
      # --- unit-level ---
      if (!bounded) {
        A      <- t(X) %*% (d * X)
        lambda <- .solve_calib(A, Tvec - colSums(d * X))
        g      <- as.numeric(1 + X %*% lambda)
      } else {
        g <- .calib_ds(X, d, Tvec, step$calfun, step$bounds, step$maxit)
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
      hh <- unique(cl)
      Wh <- as.numeric(tapply(d, cl, mean)[hh])           # household weight
      Sh <- rowsum(X, group = cl)[hh, , drop = FALSE]     # household aux. sums
      if (!bounded) {
        A      <- t(Sh) %*% (Wh * Sh)
        lambda <- .solve_calib(A, Tvec - colSums(Wh * Sh))
        gh     <- as.numeric(1 + Sh %*% lambda)
      } else {
        gh <- .calib_ds(Sh, Wh, Tvec, step$calfun, step$bounds, step$maxit)
      }
      names(gh) <- hh
      new_w[active] <- as.numeric(Wh)[match(cl, hh)] * gh[cl]
      g          <- gh
      note_clust <- sprintf("; one weight per '%s' (integrative)", step$cluster)
    }

    # Achieved totals with the REAL X (must match the targets)
    achieved <- colSums(new_w[active] * X)
    diag <- data.frame(variable = cn, target = Tvec,
                       achieved = round(achieved, 2), stringsAsFactors = FALSE)
    bnote <- if (bounded)
      sprintf(" [calfun = %s%s]", step$calfun,
              if (!is.null(step$bounds)) sprintf(", bounds (%.2f, %.2f)",
                                                 step$bounds[1], step$bounds[2]) else "")
    else ""
    attr(diag, "note") <- sprintf(
      "g (calibration factor) in [%.3f, %.3f]%s%s",
      min(g), max(g), bnote, note_clust)
    return(list(weights = new_w, diagnostics = diag))
  }

  # method == "raking": iterative proportional fitting (IPF)
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
  X    <- stats::model.matrix(step$x_formula, data = sdata)
  Xpop <- stats::model.matrix(step$x_formula, data = pop)
  Tx   <- colSums(Xpop)[colnames(X)]
  if (anyNA(Tx))
    stop("Inconsistent factor levels between the sample and `population` in x_formula.")

  # Model-assisted block: one prediction column per model y
  mu_cols <- list(); Tmu <- numeric(0)
  for (k in names(step$models)) {
    preds        <- .model_predict(step$models[[k]], sdata, d, list(sdata, pop))
    mu_cols[[k]] <- preds[[1]]          # prediction on the sample
    Tmu[k]       <- sum(preds[[2]])     # population total of the prediction
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
    # Integrative calibration: one weight per cluster (sum Z by household)
    if (!step$cluster %in% names(data))
      stop(sprintf("Cluster column '%s' not found in the data.", step$cluster))
    cl <- as.character(data[[step$cluster]])[active]
    if (anyNA(cl))
      stop(sprintf("Cluster column '%s' has missing values (NA).", step$cluster))
    hh <- unique(cl)
    Wh <- tapply(d, cl, mean)[hh]                  # household weight (one per household)
    Sh <- rowsum(Z, group = cl)[hh, , drop = FALSE] # sum of Z by household
    A      <- t(Sh) %*% (as.numeric(Wh) * Sh)
    rhs    <- Tvec - colSums(as.numeric(Wh) * Sh)
    lambda <- .solve_calib(A, rhs)
    gh     <- as.numeric(1 + Sh %*% lambda)
    names(gh) <- hh
    new_w[active] <- as.numeric(Wh[cl]) * gh[cl]   # household_weight * household_factor
    g <- gh
    note_clust <- sprintf("; one weight per '%s' (integrative)", step$cluster)
  }

  achieved <- colSums(new_w[active] * Z)
  type <- c(rep("X (consistency)", ncol(X)),
            rep("y (model)", length(step$models)))
  diag <- data.frame(constraint = colnames(Z), type = type,
                     target = round(Tvec, 2), achieved = round(achieved, 2),
                     stringsAsFactors = FALSE)
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
apply_step.step_trim_weights <- function(step, data, w) {
  active <- w > 0
  new_w  <- w
  wv     <- new_w[active]

  upper <- step$upper
  if (is.null(upper)) {
    q  <- stats::quantile(wv, c(.25, .75))
    upper <- as.numeric(q[2] + 3 * (q[2] - q[1]))   # Tukey far-out fence
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
