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
  w_in <- object$history[[k]]                  # design weights entering the NR step
  elig <- which(w_in > 0)                       # eligible sample (resolved cases)
  if (length(elig) < 10L) return(NULL)

  resp <- tryCatch(
    as.integer(as.logical(eval(step$respondent, envir = data, enclos = baseenv()))),
    error = function(e) NULL)
  if (is.null(resp) || length(resp) != nrow(data)) return(NULL)

  aux <- if (identical(step$method, "propensity") && !is.null(step$formula))
           all.vars(step$formula) else step$by
  aux <- intersect(aux, names(data))
  if (!length(aux)) return(NULL)

  df <- data[elig, aux, drop = FALSE]
  df$.resp <- resp[elig]
  df$.d    <- w_in[elig]
  df <- df[stats::complete.cases(df[, c(aux, ".resp"), drop = FALSE]), , drop = FALSE]
  if (nrow(df) < 10L || length(unique(df$.resp)) < 2L) return(NULL)

  fml <- stats::reformulate(aux, response = ".resp")
  fit <- tryCatch(
    suppressWarnings(stats::glm(fml, data = df, family = stats::binomial(),
                                weights = df$.d)),
    error = function(e) NULL)
  if (is.null(fit)) return(NULL)

  rho  <- as.numeric(stats::fitted(fit))
  d    <- df$.d
  Nhat <- sum(d)
  rbar <- sum(d * rho) / Nhat
  S    <- sqrt(sum(d * (rho - rbar)^2) / (Nhat - 1))
  R    <- 1 - 2 * S

  # unconditional partial R-indicators, for the categorical auxiliaries
  cat_aux <- aux[vapply(aux, function(v) !is.numeric(df[[v]]), logical(1))]
  partials <- if (length(cat_aux))
    do.call(rbind, lapply(cat_aux, function(v) {
      z   <- as.character(df[[v]])
      Nz  <- tapply(d, z, sum)
      rbz <- tapply(d * rho, z, sum) / Nz
      data.frame(variable = v,
                 partial_R = sqrt(sum((Nz / Nhat) * (rbz - rbar)^2)),
                 stringsAsFactors = FALSE)
    })) else NULL

  list(R = R, S = S, n_eligible = nrow(df), aux = aux, partials = partials)
}
