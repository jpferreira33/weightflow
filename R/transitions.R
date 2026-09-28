# Gross flows / transition matrices between two panel waves (CEPAL ch. XVII). Computed on the
# LONGITUDINAL weight (the wide file, one weight per unit) -- case (c): a single file, a single
# weight, ordinary bootstrap. transition_matrix() is the point estimate; boot_transition() adds
# a per-cell standard error from the bootstrap replicate weights. Self-contained base R; no
# dependency. bootstrap_estimate() already handles a vector-valued statistic (one entry per
# from x to cell), so the per-cell SE comes for free.

# --- input guards (TR-01) ---------------------------------------------------
# A flow table is read as "who moved where", so both ways of getting it silently
# wrong are expensive: a mistyped column name used to give a matrix of ZEROS with no
# error (data[["typo"]] is NULL, every cell empty), and rows whose state is NA -- or
# outside an explicit `states =` -- were dropped without being counted, so `joint`
# renormalized over the survivors and the loss was invisible. In a panel the NA share
# IS the attrition, i.e. exactly the number a reader needs to see.

.wf_flow_cols <- function(d, from, to) {
  for (nm in c(from = from, to = to)) {
    if (!is.character(nm) || length(nm) != 1L || is.na(nm))
      stop("`from` and `to` must each be a single column name.", call. = FALSE)
  }
  miss <- setdiff(c(from, to), names(d))
  if (length(miss))
    stop(sprintf("Column(s) %s are not in the data. Available: %s.",
                 paste(sprintf("'%s'", miss), collapse = ", "),
                 paste(utils::head(names(d), 25L), collapse = ", ")), call. = FALSE)
  invisible(TRUE)
}

# How much weight the table does NOT cover, and why. Called once at the user-facing
# entry points, never per replicate.
.wf_flow_coverage <- function(fr, to_, w, lev) {
  w <- as.numeric(w); w[!is.finite(w)] <- 0
  tot <- sum(abs(w))
  if (!isTRUE(tot > 0)) return(invisible(NULL))
  na_state  <- is.na(fr) | is.na(to_)
  off_lev   <- !na_state & (!as.character(fr) %in% lev | !as.character(to_) %in% lev)
  lost      <- sum(abs(w[na_state | off_lev]))
  if (lost <= 0) return(invisible(NULL))
  parts <- c(if (any(na_state)) sprintf("%.1f%% with a missing state",
                                        100 * sum(abs(w[na_state])) / tot),
             if (any(off_lev))  sprintf("%.1f%% in a state outside `states`",
                                        100 * sum(abs(w[off_lev])) / tot))
  warning(sprintf(paste0("The flow table covers %.1f%% of the weight: %s. Those units are not ",
                         "in any cell, so the conditional and joint formats renormalize over ",
                         "the rest. In a panel that share is usually the attrition -- decide ",
                         "it explicitly (an 'out of scope' state, or step_drop_ineligible())."),
                  100 * (1 - lost / tot), paste(parts, collapse = " and ")), call. = FALSE)
  invisible(NULL)
}

# weighted from x to table, in the requested format, over fixed state levels `lev`.
.wf_xtab <- function(from, to, w, lev, format) {
  f  <- factor(as.character(from), levels = lev)
  t  <- factor(as.character(to),   levels = lev)
  ok <- !is.na(f) & !is.na(t) & is.finite(w) & w != 0
  m  <- matrix(0, length(lev), length(lev), dimnames = list(from = lev, to = lev))
  if (any(ok)) {
    agg <- tapply(w[ok], list(f[ok], t[ok]), sum)
    agg[is.na(agg)] <- 0
    m[rownames(agg), colnames(agg)] <- agg
  }
  # A margin that is zero or negative (calibration can produce negative weights) has
  # no conditional distribution: pmax(., eps) turned a -0.02 row total into a ratio of
  # 1e16 presented as a probability. Return NA for that row/column instead.
  safe <- function(x) ifelse(x > 0, x, NA_real_)
  switch(format,
    counts = m,
    row    = m / safe(rowSums(m)),                       # P(to | from)  (row-conditional)
    col    = t(t(m) / safe(colSums(m))),                 # P(from | to)
    joint  = m / safe(sum(m)))                           # P(from, to)
}

#' Gross-flow transition matrix between two panel waves
#'
#' Weighted cross-tabulation of a categorical state at an earlier wave (`from`) against a later
#' wave (`to`) -- e.g. the labour-force status of the same people across two periods -- computed
#' on the **longitudinal** weight. This is the gross flow (CEPAL ch. XVII): who moved between
#' which states. [boot_transition()] adds a per-cell standard error from the ordinary bootstrap.
#'
#' @param data a `data.frame` (wide longitudinal file) or a prepped `weighting_spec`.
#' @param from,to names of the earlier- and later-wave state columns.
#' @param weights a weight column name or a numeric vector; defaults to 1 (or the prepped
#'   weight when `data` is a prepped spec).
#' @param states optional character vector fixing the state levels and their order.
#' @param format `"row"` (default, P(to|from)), `"col"` (P(from|to)), `"joint"` (P(from,to)) or
#'   `"counts"` (weighted counts).
#' @section Why there is a single weight, and not two:
#'
#' Feinberg and Stasny (1983) describe a gross-change table built from the **two cross-sectional
#' weights**: when \eqn{w_{k,t-1} \neq w_{k,t}}, the smaller weight goes to the (i, j) cell and
#' the difference goes to an "out of population" cell -- (Outside, j) or (i, Outside) depending
#' on the sign -- on the assumption that the weights differ only because of natural entries to
#' and exits from the target population. ECLAC cites it (ch. XVI, sec. B) as the state of things
#' *before* a longitudinal weight is built.
#'
#' This function takes **one** weight because the package builds that longitudinal weight
#' instead, by the sequence the same chapter prescribes: panel base weight, adjustment for
#' nonresponse in the first period, an explicit definition of the longitudinal population, the
#' attrition adjustment and the final calibration. Once that weight exists the discrepancy
#' Feinberg-Stasny reconstructs no longer arises -- who left the population was decided
#' explicitly at [step_drop_ineligible()] rather than inferred from a difference between two
#' weights. The two-weight construction is the alternative to the longitudinal weight, not a
#' complement to it.
#'
#' @return a `weightflow_transition` object holding the matrix.
#' @seealso [boot_transition()]
#' @export
transition_matrix <- function(data, from, to, weights = NULL, states = NULL,
                              format = c("row", "col", "joint", "counts")) {
  format <- match.arg(format)
  if (inherits(data, "prepped_weighting_spec")) { w <- data$final_weight; data <- data$data }
  else if (!is.data.frame(data))
    stop("`data` must be a data.frame or a prepped weighting_spec.", call. = FALSE)
  else w <- if (is.null(weights)) rep(1, nrow(data))
            else if (is.character(weights) && length(weights) == 1L) {
              if (!weights %in% names(data))
                stop(sprintf("Weight column '%s' is not in the data.", weights), call. = FALSE)
              data[[weights]]
            } else weights
  .wf_flow_cols(data, from, to)
  if (!is.numeric(w) || length(w) != nrow(data))
    stop(sprintf(paste0("`weights` must be one weight per row (%d), or the name of such a ",
                        "column; got %d value(s). A shorter vector would be recycled and the ",
                        "flows would be silently wrong."), nrow(data), length(w)), call. = FALSE)
  fr <- data[[from]]; to_ <- data[[to]]
  lev <- states %||% sort(unique(c(as.character(fr), as.character(to_))))
  lev <- lev[!is.na(lev)]
  .wf_flow_coverage(fr, to_, w, lev)
  structure(list(matrix = .wf_xtab(fr, to_, w, lev, format),
                 counts = .wf_xtab(fr, to_, w, lev, "counts"),   # absolute flows (for the Sankey)
                 states = lev, from = from, to = to, format = format),
            class = "weightflow_transition")
}

#' Transition matrix with per-cell bootstrap standard errors
#'
#' Like [transition_matrix()], but every cell also gets a standard error and confidence interval
#' from the bootstrap replicate weights of a longitudinal-weight [bootstrap_weights()] object, by
#' re-tabulating the flow within each replicate. The recipe is re-run per replicate, so the
#' uncertainty of the longitudinal weighting propagates into the flow SEs.
#'
#' @param boot a `weightflow_boot` from [bootstrap_weights()] on the longitudinal recipe.
#' @param from,to,states,format as in [transition_matrix()].
#' @return a `weightflow_transition_boot` with `estimate`, `se`, `ci_lower`, `ci_upper` matrices.
#' @seealso [transition_matrix()], [bootstrap_weights()]
#' @export
boot_transition <- function(boot, from, to, states = NULL,
                            format = c("row", "col", "joint", "counts")) {
  format <- match.arg(format)
  if (!inherits(boot, "weightflow_boot"))
    stop("`boot` must come from bootstrap_weights() on the longitudinal recipe.", call. = FALSE)
  d   <- boot$data
  .wf_flow_cols(d, from, to)
  lev <- states %||% { v <- sort(unique(c(as.character(d[[from]]), as.character(d[[to]]))))
                       v[!is.na(v)] }
  .wf_flow_coverage(d[[from]], d[[to]], boot$weights, lev)
  stat <- function(w, dd) {
    m <- .wf_xtab(dd[[from]], dd[[to]], w, lev, format)
    v <- as.numeric(m)
    names(v) <- as.vector(outer(rownames(m), colnames(m), paste, sep = "->"))
    v
  }
  est <- bootstrap_estimate(boot, stat)                 # per-cell estimate + se + CI
  k   <- length(lev)
  toM <- function(x) matrix(x, k, k, dimnames = list(from = lev, to = lev))
  structure(list(estimate = toM(est$estimate), se = toM(est$se),
                 ci_lower = toM(est$ci_lower), ci_upper = toM(est$ci_upper),
                 counts = .wf_xtab(d[[from]], d[[to]], boot$weights, lev, "counts"),
                 states = lev, from = from, to = to, format = format),
            class = c("weightflow_transition_boot", "weightflow_transition"))
}

#' Gross-flow TOTALS with standard errors, plus net flows and margins
#'
#' The gross change is about the **number of people** who move between states, i.e. totals. From a
#' longitudinal-weight [bootstrap_weights()] object this returns, all with a bootstrap standard
#' error computed within each replicate: the from x to count matrix (the gross flows, in
#' population totals), the **net** flow matrix `i->j minus j->i`, and the margins -- the origin
#' totals (how many started in each state), the destination totals (how many ended in each), the
#' stayers (the diagonal) and the movers (off-diagonal).
#'
#' @param boot a `weightflow_boot` from [bootstrap_weights()] on the longitudinal recipe.
#' @param from,to,states as in [transition_matrix()].
#' @return a `weightflow_flows` object with `counts`/`counts_se`, `net`/`net_se`, `origin`/`origin_se`,
#'   `dest`/`dest_se`, and `stayers`/`movers` (each with its SE).
#' @seealso [boot_transition()], [transition_matrix()]
#' @export
boot_flows <- function(boot, from, to, states = NULL) {
  if (!inherits(boot, "weightflow_boot"))
    stop("`boot` must come from bootstrap_weights() on the longitudinal recipe.", call. = FALSE)
  d   <- boot$data
  .wf_flow_cols(d, from, to)
  lev <- states %||% { v <- sort(unique(c(as.character(d[[from]]), as.character(d[[to]]))))
                       v[!is.na(v)] }
  .wf_flow_coverage(d[[from]], d[[to]], boot$weights, lev)
  k <- length(lev); k2 <- k * k
  stat <- function(w, dd) {
    m   <- .wf_xtab(dd[[from]], dd[[to]], w, lev, "counts")
    net <- m - t(m)
    v <- c(as.numeric(m), as.numeric(net), rowSums(m), colSums(m),
           sum(diag(m)), sum(m) - sum(diag(m)))
    names(v) <- c(paste0("c", seq_len(k2)), paste0("n", seq_len(k2)),
                  paste0("o", seq_len(k)), paste0("d", seq_len(k)), "stayers", "movers")
    v
  }
  e <- bootstrap_estimate(boot, stat)                # per-quantity estimate + se (order preserved)
  M <- function(x, a, b) matrix(x[a:b], k, k, dimnames = list(from = lev, to = lev))
  V <- function(x, a, b) stats::setNames(x[a:b], lev)
  structure(list(
    counts    = M(e$estimate, 1, k2),          counts_se = M(e$se, 1, k2),
    net       = M(e$estimate, k2 + 1, 2 * k2), net_se    = M(e$se, k2 + 1, 2 * k2),
    origin    = V(e$estimate, 2 * k2 + 1, 2 * k2 + k),     origin_se = V(e$se, 2 * k2 + 1, 2 * k2 + k),
    dest      = V(e$estimate, 2 * k2 + k + 1, 2 * k2 + 2 * k), dest_se = V(e$se, 2 * k2 + k + 1, 2 * k2 + 2 * k),
    stayers   = e$estimate[2 * k2 + 2 * k + 1], stayers_se = e$se[2 * k2 + 2 * k + 1],
    movers    = e$estimate[2 * k2 + 2 * k + 2], movers_se  = e$se[2 * k2 + 2 * k + 2],
    states = lev, from = from, to = to),
    class = "weightflow_flows")
}

#' @export
print.weightflow_flows <- function(x, ...) {
  cat(sprintf("<weightflow gross flows (population totals): %s -> %s  with bootstrap SE>\n",
              x$from, x$to))
  cat("counts (gross flow):\n");        print(round(x$counts, 1))
  cat("SE:\n");                          print(round(x$counts_se, 1))
  cat("net flow (i->j minus j->i):\n");  print(round(x$net, 1))
  mg <- data.frame(state = x$states,
                   origin = round(x$origin, 1), origin_se = round(x$origin_se, 1),
                   dest = round(x$dest, 1), dest_se = round(x$dest_se, 1))
  cat("margins (origin = started in state, dest = ended in state):\n")
  print(mg, row.names = FALSE)
  cat(sprintf("stayers %.0f (SE %.0f)  |  movers %.0f (SE %.0f)\n",
              x$stayers, x$stayers_se, x$movers, x$movers_se))
  invisible(x)
}

#' @export
print.weightflow_transition <- function(x, ...) {
  cat(sprintf("<weightflow transition: %s -> %s  [%s]>\n", x$from, x$to, x$format))
  print(round(x$matrix, 4))
  invisible(x)
}

#' @export
print.weightflow_transition_boot <- function(x, ...) {
  cat(sprintf("<weightflow transition: %s -> %s  [%s]  with bootstrap SE>\n",
              x$from, x$to, x$format))
  cat("estimate:\n"); print(round(x$estimate, 4))
  cat("SE:\n");       print(round(x$se, 4))
  invisible(x)
}
