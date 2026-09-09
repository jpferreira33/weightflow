# apply_step for the panel weighting steps.

# step_panel_overlap: new_w = w / Pr(panel selection). `prob` is a per-unit
# probability column or a single constant (recycled). See step_panel_overlap().
#' @export
apply_step.step_panel_overlap <- function(step, data, w) {
  ecenv  <- if (is.null(step$env)) baseenv() else step$env
  active <- .wf_active(w)
  new_w  <- w
  p <- .eval_num(step$prob, "prob", data, ecenv)
  if (length(p) == 1L) p <- rep(p, length(w))
  if (length(p) != length(w))
    stop("`prob` must have one value per row, or be a single constant.", call. = FALSE)
  if (any(is.na(p[active])) || any(p[active] <= 0 | p[active] > 1))
    stop("`prob` (panel-selection probability) must be in (0, 1].", call. = FALSE)
  fac <- 1 / p
  new_w[active] <- w[active] * fac[active]
  diag <- data.frame(
    pr_panel = round(mean(p[active]), 4),
    factor   = round(mean(fac[active]), 4),
    n_units  = sum(active),
    stringsAsFactors = FALSE)
  attr(diag, "note") <- "base weight divided by Pr(panel selection) (CEPAL ch. XVI)"
  list(weights = new_w, diagnostics = diag)
}

# Scope declarations: identity on the weights, they only record the intent.
#' @export
apply_step.step_cross_sectional <- function(step, data, w) {
  list(weights = w,
       diagnostics = data.frame(scope = "cross-sectional", stringsAsFactors = FALSE))
}

#' @export
apply_step.step_longitudinal <- function(step, data, w) {
  p <- attr(data, "wf_panel")
  list(weights = w, diagnostics = data.frame(
    scope          = "longitudinal",
    reference_wave = if (is.null(p)) NA_character_ else p$reference_wave,
    waves          = if (is.null(p)) NA_character_ else paste(p$waves, collapse = ", "),
    stringsAsFactors = FALSE))
}
