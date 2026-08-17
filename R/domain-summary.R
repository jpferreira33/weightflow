# domain_summary(): how the weights move, stage by stage, within each study
# domain (e.g. a DAM / department) -- a per-domain quality-control view.

#' Per-domain weight summary at every stage of the cascade
#'
#' For quality control by study domain (for example a department / DAM), this
#' summarises how the weights move within each domain at every stage of the
#' recipe: the base weights, then the weights after each step. It reads the
#' stage-by-stage weights that [prep()] already stores, so it adds no computation
#' to the cascade and never changes a weight.
#'
#' @param object a prepped `weighting_spec` (the output of [prep()]).
#' @param by the name (string) of a domain column in the data (e.g. `"region"`).
#' @return A `data.frame` with one row per stage x domain and the columns
#'   `stage` (an ordered factor: base weights, then `1. <step>`, `2. <step>`,
#'   ...), `domain`, `n_active` (active units in the domain at that stage),
#'   `sum_w` (sum of the active weights), `mean_w`, `deff` (the Kish design
#'   effect within the domain) and `n_eff`. Reading down a domain shows how its
#'   weight total and dispersion evolve step by step.
#' @seealso [design_effect()], [weight_factors()], [summary.prepped_weighting_spec()]
#' @examples
#' fit <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_calibrate(method = "raking", margins = list(region = c(table(population$region)))) |>
#'   prep()
#' domain_summary(fit, by = "region")
#' @export
domain_summary <- function(object, by) {
  if (!inherits(object, "prepped_weighting_spec"))
    stop("`object` must be a prepped weighting_spec (the output of prep()).", call. = FALSE)
  if (!is.character(by) || length(by) != 1L)
    stop("`by` must be a single string naming a domain column in the data.", call. = FALSE)
  if (!by %in% names(object$data))
    stop(sprintf("Domain column '%s' not found in the data.", by), call. = FALSE)

  h    <- object$history
  dom  <- as.character(object$data[[by]])
  doms <- sort(unique(dom[!is.na(dom)]))
  stg  <- names(h)

  # Readable, ordered stage labels: "base weights", then "1. <step class>", ...
  lab <- vapply(seq_along(stg), function(s) {
    if (identical(stg[s], "base")) "base weights"
    else sprintf("%d. %s", s - 1L, sub("^step_", "", class(object$steps[[s - 1L]])[1]))
  }, character(1))

  rows <- list()
  for (s in seq_along(stg)) {
    w <- h[[s]]
    for (d in doms) {
      ws <- w[which(dom == d)]
      wa <- ws[.wf_active(ws)]
      de <- design_effect(ws)
      rows[[length(rows) + 1L]] <- data.frame(
        stage    = lab[s],
        domain   = d,
        n_active = length(wa),
        sum_w    = sum(wa),
        mean_w   = if (length(wa)) mean(wa) else NA_real_,
        deff     = de$deff,
        n_eff    = de$n_eff,
        stringsAsFactors = FALSE)
    }
  }
  out <- do.call(rbind, rows)
  out$stage <- factor(out$stage, levels = unique(lab))   # keep cascade order
  rownames(out) <- NULL
  out
}
