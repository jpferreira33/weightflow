# ---------------------------------------------------------------------------
# R-indicators (representativity indicators, Schouten, Cobben & Bethlehem).
# Internal diagnostic surfaced automatically by summary() and report_weighting()
# when the recipe includes a nonresponse adjustment. NOT exported: no new API.
# ---------------------------------------------------------------------------

# Compute the R-indicator (and unconditional partial R-indicators) from a
# prepped recipe. Returns NULL when the recipe has no nonresponse step or the
# quantities cannot be estimated.
#
# The response propensities are re-estimated with a design-weighted logistic
# regression of the response indicator on the auxiliaries used in the LAST
# nonresponse step, over the eligible sample (units active entering that step).
# R = 1 - 2 * S(rho), with S the design-weighted standard deviation of the
# propensities. Higher R -> more representative response (less nonresponse-bias
# risk). Partials measure how much each categorical auxiliary drives the
# variation (between-category standard deviation of the propensities).
.r_indicator <- function(object) {
  steps <- object$steps
  is_nr <- vapply(steps, function(s) inherits(s, "step_nonresponse"), logical(1))
  if (!any(is_nr)) return(NULL)
  k    <- max(which(is_nr))
  step <- steps[[k]]
  data <- object$data
  w_in <- object$history[[k]]                  # weights entering the NR step
  elig <- which(.wf_active(w_in))               # eligible sample (resolved cases)
  if (length(elig) < 10L) return(NULL)

  # Evaluate `respondent` in the step's captured environment (as the cascade does),
  # not baseenv(): otherwise an expression that references a user-environment object
  # (e.g. `id %in% ids_resp`) fails here, the tryCatch returns NULL, and the whole
  # R-indicator silently disappears from summary() and the report.
  # NB: use an explicit NULL check, not the package `%||%` -- that helper calls
  # is.na() on its LHS, which errors/warns when the LHS is an environment.
  enc  <- if (is.null(step$env)) baseenv() else step$env
  resp <- tryCatch(
    as.integer(as.logical(eval(step$respondent, envir = data, enclos = enc))),
    error = function(e) NULL)
  if (is.null(resp) || length(resp) != nrow(data)) return(NULL)

  aux <- if (step$method %in% c("propensity", "calibration") &&
             !is.null(step$formula))
           all.vars(step$formula) else step$by
  aux <- intersect(aux, names(data))
  if (!length(aux)) return(NULL)

  df <- data[elig, aux, drop = FALSE]
  df$.resp <- resp[elig]
  df$.d    <- w_in[elig]
  df <- df[stats::complete.cases(df[, c(aux, ".resp"), drop = FALSE]), , drop = FALSE]
  if (nrow(df) < 10L || length(unique(df$.resp)) < 2L) return(NULL)

  # REP-05: back-quote the names, or a column such as "region code" parses as two
  # symbols and the whole report aborts.
  fml <- stats::reformulate(sprintf("`%s`", aux), response = ".resp")
  fit <- tryCatch(
    suppressWarnings(stats::glm(fml, data = df, family = stats::binomial(),
                                weights = .wf_model_wts(df$.d))),   # mean 1 (NR-PROP-01)
    error = function(e) NULL)
  if (is.null(fit)) return(NULL)

  # RIND-01. S is the standard deviation of the FITTED propensities, so the plug-in
  # S^2 absorbs the estimation error of the model on top of the real dispersion:
  # E[S-hat^2] = S^2 + (1/N) sum_i Var(rho-hat_i). Under MCAR, where the truth is
  # R = 1, the plug-in returned 0.976 with two auxiliary categories, 0.907 with ten,
  # 0.808 with forty and 0.703 at n = 200 -- so the headline representativity number
  # fell as the model grew, and two surveys with identical real representativity
  # scored differently according to how many dummies their propensity model had. The
  # partials inherited it and named "drivers" of nonresponse in data with none.
  # Schouten, Shlomo and Skinner (2011) give the bias-adjusted estimator. Subtract an
  # estimate of (1/N) sum_i Var(rho-hat_i), with Var(rho-hat_i) = v_i^2 x_i' V(beta)
  # x_i by the delta method. V(beta) must be the SANDWICH A^-1 B A^-1 (A = X'WVX,
  # B = X'W^2VX): the inverse-information form -- which is what stats::hatvalues()
  # reports -- understates the variance whenever the weights are unequal, and the
  # correction then under-corrects exactly where survey weights vary most. With equal
  # weights B = A and the sandwich collapses to the hat diagonal, so nothing changes
  # in the self-weighting case.
  rho  <- as.numeric(stats::fitted(fit))
  d    <- df$.d
  Nhat <- sum(d)
  rbar <- sum(d * rho) / Nhat
  S2   <- sum(d * (rho - rbar)^2) / (Nhat - 1)

  # V(beta) and the machinery both the overall S and the partials correct with. Any
  # weighted mean of the fitted propensities, a'rho-hat, has (delta method)
  # Var = u' V(beta) u with u = X'(a * v); that covers rho-bar and each group mean.
  vx <- NULL; M <- NULL
  try({
    X  <- stats::model.matrix(fit)
    wm <- .wf_model_wts(d)                      # the weights the fit actually used
    v  <- rho * (1 - rho)
    A  <- crossprod(X, X * (wm * v))
    B  <- crossprod(X, X * (wm^2 * v))
    Mx <- solve(A, B) %*% solve(A)
    if (all(is.finite(Mx))) { M <- Mx; vx <- X * v }
  }, silent = TRUE)
  .var_of <- function(a) {                      # Var(sum_i a_i rho-hat_i)
    if (is.null(M)) return(0)
    u <- as.numeric(crossprod(vx, a))
    max(0, as.numeric(t(u) %*% M %*% u))
  }
  var_rbar <- .var_of(d / Nhat)
  bias <- if (is.null(M)) 0 else {
    q <- rowSums((vx %*% M) * vx)               # v_i^2 x_i' V(beta) x_i
    b <- sum(d * q) / Nhat - var_rbar
    if (is.finite(b) && b > 0) b else 0
  }
  S    <- sqrt(max(0, S2 - bias))
  R    <- 1 - 2 * S

  # unconditional partial R-indicators. Categorical auxiliaries are used as is;
  # numeric auxiliaries are binned into quantile groups (quintiles), so an
  # informative continuous driver still gets a partial. `omitted` collects any
  # that cannot be binned (too few distinct values).
  #
  # RIND-01: the partials are between-group variances of the SAME fitted values, so
  # they carry the same upward bias -- on MCAR data the uncorrected ones named a
  # "driver" of nonresponse where there is none. Correct each with the same delta
  # method, then keep the invariant the whole decomposition rests on: a between-group
  # component cannot exceed the total dispersion, so a partial is capped at S. After
  # correction the cap rarely binds; without it, two separately corrected quantities
  # can cross by sampling noise alone.
  omitted  <- character(0)
  part_one <- function(z, vlab) {
    Nz  <- tapply(d, z, sum); rbz <- tapply(d * rho, z, sum) / Nz
    p2  <- sum((Nz / Nhat) * (rbz - rbar)^2)
    lv  <- names(Nz)
    bz  <- sum(vapply(lv, function(L) {
             a <- ifelse(z == L, d / Nz[[L]], 0)
             (Nz[[L]] / Nhat) * .var_of(a)
           }, numeric(1))) - var_rbar
    if (!is.finite(bz) || bz < 0) bz <- 0
    data.frame(variable = vlab,
               partial_R = min(sqrt(max(0, p2 - bz)), S),
               stringsAsFactors = FALSE)
  }
  plist <- lapply(aux, function(v) {
    xv <- df[[v]]
    if (!is.numeric(xv)) return(part_one(as.character(xv), v))
    br <- unique(stats::quantile(xv, seq(0, 1, 0.2), na.rm = TRUE))
    if (length(br) < 3L) { omitted <<- c(omitted, v); return(NULL) }
    part_one(as.character(cut(xv, breaks = br, include.lowest = TRUE)),
             sprintf("%s (quintiles)", v))
  })
  partials <- do.call(rbind, plist)

  list(R = R, S = S, n_eligible = nrow(df), aux = aux, partials = partials,
       num_aux = omitted)
}
