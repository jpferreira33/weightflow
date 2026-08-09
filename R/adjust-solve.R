# adjustment internals: NSE condition eval, cell grouping, calibration solver (Deville-Sarndal).

# ---------------------------------------------------------------------------
# Computation of each adjustment. Internal helpers + the apply_step() generic.
# Each apply_step() receives the step, the data and the current weight vector,
# and returns list(weights = <new weights>, diagnostics = <data.frame>).
# Convention: a 0 weight marks a "dropped" case (ineligible / nonresponse).
# ---------------------------------------------------------------------------

# Evaluate a captured condition against the data ----------------------------
# Accepts a logical expression OR a 0/1 dummy column (coerced to logical).
.eval_cond <- function(expr, data, env = baseenv(), active = NULL) {
  if (is.null(expr)) return(NULL)
  if (is.null(env)) env <- baseenv()
  out <- eval(expr, envir = data, enclos = env)
  if (is.numeric(out)) {
    if (!all(out %in% c(0, 1, NA)))
      stop("A 0/1 dummy was expected, but other values were found.")
    out <- out == 1
  }
  if (!is.logical(out)) stop("The condition did not evaluate to TRUE/FALSE or a 0/1 dummy.")
  # A missing disposition among the units this step still acts on is an error:
  # weightflow will not guess a disposition from NA. NA among units already out
  # of scope (weight 0: dropped as ineligible / unknown) is fine -- their
  # disposition is genuinely undefined -- and is left to fall through as FALSE.
  chk <- if (is.null(active)) rep(TRUE, length(out)) else as.logical(active)
  if (anyNA(out[chk])) {
    lbl <- tryCatch(paste(deparse(expr), collapse = " "), error = function(e) "the flag")
    stop(sprintf(paste0("The disposition flag (%s) has %d missing value(s) among the ",
                        "units still in scope at this step. weightflow does not guess a ",
                        "disposition from NA: recode them (e.g. to respondent/nonrespondent, ",
                        "eligible/ineligible, or known/unknown eligibility) before weighting."),
                 lbl, sum(is.na(out[chk]))), call. = FALSE)
  }
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
  # `bounds` may be a length-2 vector c(L, U) (global, the usual case) or an
  # n x 2 matrix of per-unit bounds cbind(L_k, U_k) (used by trimmed
  # calibration, where the absolute-weight bound w in [w_l, w_u] becomes a
  # per-unit factor bound). L and U then broadcast element-wise below.
  if (is.matrix(bounds)) {
    L <- bounds[, 1]; U <- bounds[, 2]
  } else {
    L <- if (is.null(bounds)) -Inf else bounds[1]
    U <- if (is.null(bounds)) Inf  else bounds[2]
  }
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

# Shared linear/GREG calibration solver core. Given a design matrix `Z`, weights
# `v` and targets `Tvec`, return the g factors so that
#   sum_i v_i * g_i * Z_i = Tvec.
# Closed form for plain linear (calfun = "linear", no bounds, optional ridge
# `penalty`); the Deville-Sarndal iterative solver for the "raking"/"logit"
# distances or explicit `bounds`. Used by both step_calibrate (Z = X or the
# household means Xbar) and the calibration flavours of step_nonresponse
# (Z = respondents' auxiliaries). Returns list(g, converged).
.solve_calibration <- function(Z, v, Tvec, calfun = "linear", bounds = NULL,
                               penalty = NULL, maxit = 100L, tol = 1e-7) {
  use_ds <- calfun != "linear" || !is.null(bounds)
  if (!use_ds) {
    cn <- colnames(Z)
    A  <- t(Z) %*% (v * Z)
    if (!is.null(penalty)) A <- A + .ridge_diag(penalty, cn, A)
    lambda <- .solve_calib(A, Tvec - colSums(v * Z))
    return(list(g = as.numeric(1 + Z %*% lambda), converged = TRUE))
  }
  g <- .calib_ds(Z, v, Tvec, calfun, bounds, maxit, tol)
  list(g = as.numeric(g), converged = isTRUE(attr(g, "converged")))
}


# Fit an xgboost model and return predictions on a list of newdata frames.
# Handles both regression (objective "reg:squarederror") and binary
# classification (objective "binary:logistic", returns P(class = 1)).
