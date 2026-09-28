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
  # A flag/condition must have exactly one value per unit. A global vector of the
  # wrong length (typically passed after the data was filtered) would otherwise be
  # recycled or truncated silently, quietly misassigning dispositions.
  if (length(out) != nrow(data))
    stop(sprintf(paste0("The disposition flag/condition evaluated to length %d, but the data ",
                        "has %d row(s); it must have one value per unit. This usually means a ",
                        "global vector was passed after the data was filtered -- pass a column ",
                        "of the data, or a condition evaluated on it."),
                 length(out), nrow(data)), call. = FALSE)
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

# Active units: everything with a non-zero FINITE weight. 0 is the "dropped"
# marker; a negative weight (a valid, if unusual, output of unbounded linear
# calibration) is still active -- it must take part in later steps, be counted,
# and appear in collect_weights(), so the reported totals/deff match reality.
.wf_active <- function(w) is.finite(w) & w != 0

# Small argument validators (fail early, with a message that names the fix) ---
.wf_flag <- function(x, arg) {
  if (!is.logical(x) || length(x) != 1L || is.na(x))
    stop(sprintf(paste0("`%s` must be a single TRUE or FALSE; got %s. Values such as 1, 0, ",
                        "NA or \"yes\" are not accepted -- they would be silently treated as ",
                        "FALSE and change the result."), arg, deparse(x)[1]), call. = FALSE)
  x
}
.wf_count <- function(x, arg, min = 1L) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x < min || x != round(x))
    stop(sprintf("`%s` must be a single integer >= %d; got %s.", arg, min, deparse(x)[1]),
         call. = FALSE)
  as.integer(x)
}
.wf_num <- function(x, arg, min = -Inf, max = Inf) {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) || x < min || x > max)
    stop(sprintf("`%s` must be a single finite number%s; got %s.", arg,
                 if (is.finite(min) || is.finite(max))
                   sprintf(" in [%s, %s]", format(min), format(max)) else "",
                 deparse(x)[1]), call. = FALSE)
  as.numeric(x)
}
.wf_id <- function(x, arg = "id") {
  if (is.null(x)) return(NULL)
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(x)))
    stop(sprintf("`%s` must be a single non-empty string (not NA or \"\"); got %s.",
                 arg, deparse(x)[1]), call. = FALSE)
  x
}
.wf_level <- function(level) {
  if (!is.numeric(level) || length(level) != 1L || is.na(level) || level <= 0 || level >= 1)
    stop("`level` must be a single number strictly between 0 and 1 (e.g. 0.95, not 95).",
         call. = FALSE)
  level
}
.wf_var <- function(variable, obj) {
  if (!is.character(variable) || length(variable) != 1L || !variable %in% names(obj$data))
    stop(sprintf("`variable` must be a single column name present in the data; got %s.",
                 deparse(variable)[1]), call. = FALSE)
  variable
}
.wf_outname <- function(x, arg) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x))
    stop(sprintf("`%s` must be a single non-empty column name (a string), not %s.",
                 arg, deparse(x)[1]), call. = FALSE)
  x
}
# Evaluate a numeric expression in the data, rejecting factors (as.numeric() on a
# factor returns its integer codes, not the values -- a silent, wrong result).
.eval_num <- function(expr, arg, data, env) {
  v <- eval(expr, envir = data, enclos = env)
  if (is.factor(v))
    stop(sprintf(paste0("`%s` evaluated to a factor; it must be numeric. as.numeric() on a ",
                        "factor returns its integer codes, not the values -- convert with ",
                        "as.numeric(as.character(x)) if it holds numbers."), arg), call. = FALSE)
  as.numeric(v)
}

# Build a grouping factor from the `by` columns -----------------------------
# CELL-01. The adjustment cell is the `by` values pasted with " | ", and that string is
# also its identity: units are grouped by it, and it is what every diagnostics table and
# report shows. Pasting the raw values is NOT injective. Two different combinations whose
# values contain the separator -- ("a | b", "c") and ("a", "b | c") -- produce the same
# string and are merged into ONE cell. The damage is double: the adjustment factor is
# computed over the union, so both halves come out wrong (measured: weights x2), and the
# "adjustment cell with no respondents" alert never fires, because the empty half is
# absorbed by the full one and there is nothing left to be empty. The diagnostics then
# display a cell ("a | b | c") that does not exist in the data. A genuine value equal to
# the "(missing)" sentinel collides with NA the same way.
#
# Escaping inside the values makes the paste injective while keeping the label readable:
# an unescaped "|" can then only be a separator. Values that contain no "|" and no
# backslash -- every ordinary survey variable -- are untouched, so no existing cell label
# changes.
.wf_cell_escape <- function(x) {
  hit <- !is.na(x) & grepl("[\\|]", x)
  if (any(hit)) {
    x[hit] <- gsub("\\", "\\\\", x[hit], fixed = TRUE)   # the escape character first
    x[hit] <- gsub("|",  "\\|",  x[hit], fixed = TRUE)
  }
  sen <- !is.na(x) & x == "(missing)"                    # a real value, not an NA
  if (any(sen)) x[sen] <- "\\(missing)"
  x
}

.make_cells <- function(data, by, n, active = NULL) {
  if (is.null(by)) return(factor(rep("(all)", n)))
  if (!length(by))
    stop(paste0("`by` has length 0. Use `by = NULL` for no grouping; a zero-length `by` ",
                "(e.g. from names(x)[grepl(...)] matching nothing) would silently skip the ",
                "whole step."), call. = FALSE)
  na_unit <- logical(n)                       # which units have an NA in any cell variable
  parts <- lapply(by, function(v) {
    if (!v %in% names(data)) stop(sprintf("Cell variable '%s' not found.", v))
    x  <- as.character(data[[v]])
    na <- is.na(x)
    if (any(na)) na_unit <<- na_unit | na
    x <- .wf_cell_escape(x)                   # CELL-01, see below
    x[na] <- "(missing)"                      # explicit, not the ambiguous "NA"
    x
  })
  # Only warn about NA cells among the units this step actually acts on. Units
  # already dropped earlier in the cascade (weight 0: ineligible, unknown, whole-
  # household nonresponse) commonly lack later-collected variables (sex, age), and
  # flagging their NAs is a false alarm -- they take no part in this adjustment.
  flag <- if (is.null(active)) na_unit else (na_unit & as.logical(active))
  if (any(flag))
    warning(paste0("Missing values in the cell variable(s) `by` were grouped into a ",
                   "'(missing)' cell. Those units are adjusted within their own cell; ",
                   "recode the NAs if that is not intended."), call. = FALSE)
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

# Column scale used everywhere a calibration system is built or measured: the RMS of
# each column, so a column of zeros (an empty dummy) keeps scale 1 instead of dividing
# by zero. Shared by the solver and by the conditioning diagnostic, so the number the
# user is shown is the number the solver worked with.
.wf_col_scale <- function(Z) {
  apply(Z, 2L, function(cc) { v <- sqrt(mean(cc^2)); if (!is.finite(v) || v == 0) 1 else v })
}

# Condition number of the system actually solved: A = X' diag(d) X on the SCALED
# columns. The diagnostic used to report kappa(crossprod(X)) -- unweighted, unscaled
# and squared -- which measures the disparity of units rather than collinearity, so
# it fired on every calibration carrying a continuous auxiliary in natural units and
# advised dropping an auxiliary that was not redundant.
.wf_calib_cond <- function(X, d) {
  tryCatch({
    Xs <- sweep(X, 2L, .wf_col_scale(X), "/")
    kappa(t(Xs) %*% (d * Xs), exact = TRUE)
  }, error = function(e) NA_real_)
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
  # M6: the convergence test runs at the TOP of the loop, so an update made on the
  # last allowed iteration (it == maxit) is never re-checked. Re-test once here so
  # a run that actually reached `tol` on its final step is reported as converged.
  if (!ok && cur < tol) ok <- TRUE
  # Name the distance actually in use and only blame `bounds` when there are any:
  # with calfun = "raking" and no bounds the old text sent the user to an argument
  # they had not supplied. Report the size of the miss, not just that there was one.
  if (!ok)
    warning(sprintf(paste0("The %s calibration did not fully converge in %d iteration(s): largest ",
                           "relative deviation from the targets = %.3e. The weights returned do ",
                           "NOT satisfy the constraints.%s"),
                    calfun, maxit, cur,
                    if (is.null(bounds) && calfun != "logit")
                      " Raise `maxit`, loosen `tol`, or check the auxiliaries for collinearity."
                    else " Widen `bounds`, raise `maxit`, or check that the range is feasible."),
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
    # Column scaling, as .calib_ds() already does for the iterative path. The closed
    # form is the DEFAULT route (linear, no bounds) and was the only one solving the
    # raw system: any auxiliary in natural units (income, sales, area) drives the
    # condition number to 1e12-1e14 purely through the disparity of units, with no
    # collinearity at all. solve() only errors past ~4e15, so it returned an answer
    # with no warning. Scaling is an exact reparametrisation (lambda_s = s * lambda),
    # so the weights are unchanged up to floating point.
    s  <- .wf_col_scale(Z)
    Zs <- sweep(Z, 2L, s, "/")
    As <- t(Zs) %*% (v * Zs)
    if (!is.null(penalty)) {
      # The ridge diagonal is defined on the UNSCALED system, so map it into the
      # scaled coordinates (R_s = D^-1 R D^-1) rather than recomputing it here:
      # recomputing would silently make `penalty` per-column, which is a separate
      # behaviour change and not this fix.
      R  <- .ridge_diag(penalty, cn, t(Z) %*% (v * Z))
      As <- As + diag(diag(R) / s^2, nrow = length(cn))
    }
    lambda <- .solve_calib(As, Tvec / s - colSums(v * Zs))
    return(list(g = as.numeric(1 + Zs %*% lambda), converged = TRUE))
  }
  g <- .calib_ds(Z, v, Tvec, calfun, bounds, maxit, tol)
  list(g = as.numeric(g), converged = isTRUE(attr(g, "converged")))
}


# Fit an xgboost model and return predictions on a list of newdata frames.
# Handles both regression (objective "reg:squarederror") and binary
# classification (objective "binary:logistic", returns P(class = 1)).
