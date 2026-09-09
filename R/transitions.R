# Gross flows / transition matrices between two panel waves (CEPAL ch. XVII). Computed on the
# LONGITUDINAL weight (the wide file, one weight per unit) -- case (c): a single file, a single
# weight, ordinary bootstrap. transition_matrix() is the point estimate; boot_transition() adds
# a per-cell standard error from the bootstrap replicate weights. Self-contained base R; no
# dependency. bootstrap_estimate() already handles a vector-valued statistic (one entry per
# from x to cell), so the per-cell SE comes for free.

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
  eps <- .Machine$double.eps
  switch(format,
    counts = m,
    row    = m / pmax(rowSums(m), eps),                 # P(to | from)  (row-conditional)
    col    = t(t(m) / pmax(colSums(m), eps)),           # P(from | to)
    joint  = m / max(sum(m), eps))                       # P(from, to)
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
#' @return a `weightflow_transition` object holding the matrix.
#' @seealso [boot_transition()]
#' @export
transition_matrix <- function(data, from, to, weights = NULL, states = NULL,
                              format = c("row", "col", "joint", "counts")) {
  format <- match.arg(format)
  if (inherits(data, "prepped_weighting_spec")) { w <- data$final_weight; data <- data$data }
  else w <- if (is.null(weights)) rep(1, nrow(data))
            else if (is.character(weights) && length(weights) == 1L) data[[weights]]
            else weights
  fr <- data[[from]]; to_ <- data[[to]]
  lev <- states %||% sort(unique(c(as.character(fr), as.character(to_))))
  lev <- lev[!is.na(lev)]
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
  lev <- states %||% { v <- sort(unique(c(as.character(d[[from]]), as.character(d[[to]]))))
                       v[!is.na(v)] }
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
  lev <- states %||% { v <- sort(unique(c(as.character(d[[from]]), as.character(d[[to]]))))
                       v[!is.na(v)] }
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
