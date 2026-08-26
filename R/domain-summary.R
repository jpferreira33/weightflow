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
#' @param by the name(s) of one or more domain columns in the data (e.g.
#'   `"region"`, or `c("region", "area")` to cross them). Domains are ordered by
#'   the factor levels of the column (or numerically for a numeric column); units
#'   with a missing domain value are shown as a `"(missing)"` domain rather than
#'   dropped silently.
#' @param min_n_eff optional publication threshold. When set to a positive number,
#'   the result gains a logical `publishable` column (whether the domain's
#'   final-stage effective sample size reaches the threshold) and a warning names
#'   the domains that fall below it, turning the implicit reliability read into an
#'   explicit gate. Domains below the threshold are candidates for small-area
#'   estimation (see [as_sae_input()]) rather than direct estimation.
#' @return A `data.frame` with one row per stage x domain and the columns
#'   `stage` (an ordered factor: base weights, then `1. <step>`, `2. <step>`,
#'   ...), `domain` (an ordered factor), `n_active` (active units in the domain at
#'   that stage), `sum_w` (sum of the active weights), `mean_w`, `deff` (the Kish
#'   design effect within the domain) and `n_eff`; and, when `min_n_eff` is given,
#'   `publishable`. Reading down a domain shows how its weight total and dispersion
#'   evolve step by step.
#' @seealso [design_effect()], [weight_factors()], [summary.prepped_weighting_spec()]
#' @examples
#' fit <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_calibrate(method = "raking", margins = list(region = c(table(population$region)))) |>
#'   prep()
#' domain_summary(fit, by = "region")
#' @export
#' @family cascade audit
domain_summary <- function(object, by, min_n_eff = NULL) {
  if (!inherits(object, "prepped_weighting_spec"))
    stop("`object` must be a prepped weighting_spec (the output of prep()).", call. = FALSE)
  if (!is.character(by) || length(by) < 1L)
    stop("`by` must name one or more domain columns in the data.", call. = FALSE)
  if (!is.null(min_n_eff) && (!is.numeric(min_n_eff) || length(min_n_eff) != 1L ||
                              !is.finite(min_n_eff) || min_n_eff <= 0))
    stop("`min_n_eff` must be NULL or a single positive number (the publication threshold).",
         call. = FALSE)
  miss <- setdiff(by, names(object$data))
  if (length(miss))
    stop(sprintf("Domain column(s) not found in the data: %s.", paste(miss, collapse = ", ")),
         call. = FALSE)

  # Domain vector + its natural order (factor levels, numeric order, or sorted).
  if (length(by) == 1L) {
    col <- object$data[[by]]
    dom <- as.character(col)
    dom_levels <- if (is.factor(col)) levels(col)
                  else if (is.numeric(col)) as.character(sort(unique(col[!is.na(col)])))
                  else sort(unique(dom[!is.na(dom)]))
  } else {
    f   <- interaction(object$data[by], drop = TRUE, sep = ":")   # cross the columns
    dom <- as.character(f)
    dom_levels <- levels(f)
  }
  # Missing domain values become an explicit "(missing)" domain (show, don't drop).
  # If a literal "(missing)" category already exists, use a distinct label so the
  # real category and the NAs stay separate and factor() does not get duplicate
  # levels (which would error).
  if (any(is.na(dom))) {
    lbl <- utils::tail(make.unique(c(dom_levels, "(missing)")), 1L)
    dom[is.na(dom)] <- lbl
    dom_levels <- c(dom_levels, lbl)
  }

  h   <- object$history
  stg <- names(h)

  # Readable, ordered stage labels: "base weights", then "1. <step class>", ...
  lab <- vapply(seq_along(stg), function(s) {
    if (identical(stg[s], "base")) "base weights"
    else sprintf("%d. %s", s - 1L, sub("^step_", "", class(object$steps[[s - 1L]])[1]))
  }, character(1))

  rows <- list()
  for (s in seq_along(stg)) {
    w <- h[[s]]
    for (d in dom_levels) {
      ws <- w[which(dom == d)]
      wa <- ws[.wf_active(ws)]
      if (length(ws)) { de <- design_effect(ws); deff <- de$deff; neff <- de$n_eff }
      else            { deff <- NA_real_;        neff <- NA_real_ }
      rows[[length(rows) + 1L]] <- data.frame(
        stage    = lab[s],
        domain   = d,
        n_active = length(wa),
        sum_w    = sum(wa),
        mean_w   = if (length(wa)) mean(wa) else NA_real_,
        deff     = deff,
        n_eff    = neff,
        stringsAsFactors = FALSE)
    }
  }
  out <- do.call(rbind, rows)
  out$stage  <- factor(out$stage, levels = unique(lab))   # keep cascade order
  out$domain <- factor(out$domain, levels = dom_levels)    # natural / factor order

  # Publication gate: turn the implicit reliability read into an explicit column
  # plus a warning, keyed to each domain's FINAL-stage effective sample size.
  if (!is.null(min_n_eff)) {
    final_lab <- utils::tail(levels(out$stage), 1L)
    fin       <- out[out$stage == final_lab, c("domain", "n_eff")]
    neff_by   <- stats::setNames(fin$n_eff, as.character(fin$domain))
    dom_neff  <- neff_by[as.character(out$domain)]
    out$publishable <- is.finite(dom_neff) & dom_neff >= min_n_eff
    below <- names(neff_by)[!(is.finite(neff_by) & neff_by >= min_n_eff)]
    if (length(below))
      warning(sprintf(paste0("%d domain(s) below the publication threshold (final n_eff < %s): %s. ",
                             "Direct estimates for these domains are unreliable; consider small-area ",
                             "estimation (see as_sae_input())."),
                      length(below), format(min_n_eff), paste(below, collapse = ", ")),
              call. = FALSE)
  }
  rownames(out) <- NULL
  out
}
