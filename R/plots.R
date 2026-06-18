# ---------------------------------------------------------------------------
# Diagnostic plots for the weighting cascade (base graphics, no dependencies).
# plot() method kept separate from summary() per R convention.
# ---------------------------------------------------------------------------

#' Diagnostic plots for the weights
#'
#' @param x a prepped object (output of prep()).
#' @param type "all" (default): per-step adjustment-factor histograms PLUS the
#'   summary panel (final weights, cumulative factor, base vs final, deff by
#'   stage), all in one grid. "factors": only the per-step factor histograms.
#'   "summary": only the summary panel.
#' @param ... ignored.
plot.prepped_weighting_spec <- function(x, type = c("all", "factors", "summary"), ...) {
  type   <- match.arg(type)
  h      <- x$history
  ns     <- length(x$steps)
  base_w <- h[["base"]]; fin_w <- x$final_weight; act <- fin_w > 0

  # Per-step factor histogram (weight after / before, among survivors)
  draw_factor <- function(i) {
    prev <- h[[i]]; cur <- h[[i + 1L]]; keep <- cur > 0 & prev > 0
    graphics::hist(cur[keep] / prev[keep], breaks = 30, col = "grey80",
                   border = "white", main = x$steps[[i]]$label,
                   xlab = "weight after / before", cex.main = 0.9)
    graphics::abline(v = 1, col = "red", lty = 2)
  }

  # Summary panels
  draw_summary <- list(
    function() graphics::hist(fin_w[act], breaks = 30, col = "grey80",
                              border = "white", main = "Final weights", xlab = "weight"),
    function() { graphics::hist(fin_w[act] / base_w[act], breaks = 30, col = "grey80",
                                border = "white", main = "Cumulative adjustment factor",
                                xlab = "final / base"); graphics::abline(v = 1, col = "red", lty = 2) },
    function() { plot(base_w[act], fin_w[act], pch = 16, col = "#3366aa55",
                      main = "Base vs final weight", xlab = "base weight",
                      ylab = "final weight"); graphics::abline(0, 1, col = "red", lty = 2) },
    function() { deff <- vapply(h, function(w) design_effect(w)$deff, numeric(1))
                 graphics::barplot(deff, names.arg = seq_along(deff) - 1L, col = "grey70",
                                   border = NA, main = "Kish design effect by stage",
                                   xlab = "stage (0 = base)", ylab = "deff")
                 graphics::abline(h = 1, col = "red", lty = 2) }
  )

  panels <- list()
  if (type %in% c("all", "factors") && ns > 0)
    panels <- c(panels, lapply(seq_len(ns), function(i) function() draw_factor(i)))
  if (type %in% c("all", "summary"))
    panels <- c(panels, draw_summary)
  if (!length(panels)) { message("Nothing to plot."); return(invisible(x)) }

  np <- length(panels); nc <- min(3L, np); nr <- ceiling(np / nc)
  op <- graphics::par(mfrow = c(nr, nc), mar = c(4, 4, 3, 1))
  on.exit(graphics::par(op), add = TRUE)
  for (p in panels) p()
  invisible(x)
}

#' Per-unit adjustment factors table
#'
#' Returns a data.frame with the weight at each stage and the factor of each
#' step (stage weight / previous-stage weight), handy for custom plots.
#'
#' @param object a prepped object (output of prep()).
#' @return data.frame with one weight column per stage and one factor per step.
weight_factors <- function(object) {
  if (!inherits(object, "prepped_weighting_spec"))
    stop("Call prep() first.")
  h   <- object$history
  out <- as.data.frame(h, check.names = FALSE)
  nm  <- names(h)
  for (i in 2:length(h)) {
    prev <- h[[i - 1]]
    out[[paste0("factor_", nm[i])]] <- ifelse(prev > 0, h[[i]] / prev, NA_real_)
  }
  out
}
