# ---------------------------------------------------------------------------
# print/summary methods: make the cascade visible (tidymodels style).
# ---------------------------------------------------------------------------

print.weighting_spec <- function(x, ...) {
  cat("\n== Weighting specification (weightflow) ==\n")
  cat(sprintf("Data    : %d cases\n", nrow(x$data)))
  cat(sprintf("Base wts: %s\n", x$base_weights))
  if (!length(x$steps)) {
    cat("Steps   : (none yet)\n")
  } else {
    cat("Steps   :\n")
    for (i in seq_along(x$steps))
      cat(sprintf("  %d. %s\n", i, x$steps[[i]]$label))
  }
  prepped <- inherits(x, "prepped_weighting_spec")
  cat(sprintf("Status  : %s\n\n", if (prepped) "estimated (prep)" else "not estimated"))
  invisible(x)
}

print.prepped_weighting_spec <- function(x, ...) {
  NextMethod()                          # prints the common header
  h <- x$history
  cat("Stage summary:\n")
  tab <- data.frame(
    stage     = names(h),
    n_active  = vapply(h, function(w) sum(w > 0), integer(1)),
    sum_wts   = vapply(h, function(w) round(sum(w)), numeric(1)),
    cv_wts    = vapply(h, function(w) round(design_effect(w)$cv, 3), numeric(1)),
    deff_kish = vapply(h, function(w) round(design_effect(w)$deff, 3), numeric(1)),
    n_eff     = vapply(h, function(w) round(design_effect(w)$n_eff), numeric(1)),
    row.names = NULL
  )
  print(tab, row.names = FALSE)
  cat("\ndeff_kish = 1 + CV^2 (Kish design effect from unequal weighting);\n")
  cat("n_eff = n_active / deff_kish. Both worsen with each adjustment and\n")
  cat("improve with trimming.\n\n")
  invisible(x)
}

#' Detailed per-step diagnostics
#'
#' @param object a prepped object (output of prep()).
#' @param ... ignored.
#' @return (invisibly) the prepped object.
summary.prepped_weighting_spec <- function(object, ...) {
  print(object)
  h <- object$history                   # base, stage_1, stage_2, ...
  for (i in seq_along(object$steps)) {
    s <- object$steps[[i]]
    cat(sprintf("--- Step %d: %s ---\n", i, s$label))
    print(s$diagnostics, row.names = FALSE)
    it <- attr(s$diagnostics, "iterations")
    if (!is.null(it)) cat(sprintf("(converged/iterated in %d iterations)\n", it))
    note <- attr(s$diagnostics, "note")
    if (!is.null(note)) cat(note, "\n")

    # Kish design effect: before and after THIS step
    de_before <- design_effect(h[[i]])        # weight entering the step
    de_after  <- design_effect(h[[i + 1L]])   # weight leaving the step
    cat(sprintf(
      "Kish deff: %.3f -> %.3f   |   n_eff: %.0f -> %.0f\n\n",
      de_before$deff, de_after$deff, de_before$n_eff, de_after$n_eff
    ))
  }
  invisible(object)
}
