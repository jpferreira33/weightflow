# disclosure_risk(): flag units whose final weight is an outlier within its
# publication cell. A single unit carrying a weight far above the rest of its cell
# is a re-identification risk in a public-use file: it stands out and can pin down
# a rare combination of characteristics. This is the detector side of the
# confidentiality tools; the remedy already exists (step_trim_weights() /
# step_trim_calibrated()).

#' Flag re-identification risk from outlier weights within a publication cell
#'
#' A unit whose final weight is far larger than the rest of its publication cell is
#' a disclosure risk in a public-use file: an extreme weight makes a rare unit
#' stand out. `disclosure_risk()` flags, within each cell defined by `by`, the units
#' whose final weight exceeds `ratio` times the cell's median weight, and reports
#' the unit's share of the cell's total weight. Trimming (`step_trim_weights()` or
#' the totals-preserving `step_trim_calibrated()`) is the usual remedy.
#'
#' @param object a prepped `weighting_spec` (the output of [prep()]).
#' @param by the name(s) of the publication cell column(s) (e.g. `"region"`, or
#'   `c("region", "sex")`). The risk is judged within each cell.
#' @param ratio the multiple of the cell median weight above which a unit is
#'   flagged. Default 10.
#' @return A `data.frame`, one row per flagged unit, with the row index (`.row`),
#'   the `cell`, the unit `weight`, the `cell_median`, the `cell_n` (active units in
#'   the cell) and `cell_share` (the unit's fraction of the cell's total weight),
#'   ordered from the largest weight down. Zero rows when nothing is flagged.
#' @seealso [step_trim_weights()], [step_trim_calibrated()],
#'   [collect_replicate_weights()]
#' @examples
#' fit <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   prep()
#' disclosure_risk(fit, by = "region")
#' @export
#' @family confidentiality tools
disclosure_risk <- function(object, by, ratio = 10) {
  if (!inherits(object, "prepped_weighting_spec"))
    stop("`object` must be a prepped weighting_spec (the output of prep()).", call. = FALSE)
  if (!is.character(by) || length(by) < 1L)
    stop("`by` must name one or more publication-cell columns in the data.", call. = FALSE)
  miss <- setdiff(by, names(object$data))
  if (length(miss))
    stop(sprintf("Cell column(s) not found in the data: %s.", paste(miss, collapse = ", ")),
         call. = FALSE)
  if (!is.numeric(ratio) || length(ratio) != 1L || !is.finite(ratio) || ratio <= 1)
    stop("`ratio` must be a single number greater than 1.", call. = FALSE)

  w    <- object$final_weight
  act  <- .wf_active(w)
  cell <- if (length(by) == 1L) as.character(object$data[[by]])
          else as.character(interaction(object$data[by], drop = FALSE, sep = ":"))

  flagged <- list()
  for (g in unique(cell[act])) {
    idx <- which(act & cell == g)
    ws  <- w[idx]
    med <- stats::median(ws)
    tot <- sum(ws)
    if (!is.finite(med) || med <= 0) next
    hit <- which(ws > ratio * med)
    for (h in hit)
      flagged[[length(flagged) + 1L]] <- data.frame(
        .row = idx[h], cell = g, weight = ws[h],
        cell_median = med, cell_n = length(idx),
        cell_share = ws[h] / tot, stringsAsFactors = FALSE)
  }
  out <- if (length(flagged)) do.call(rbind, flagged) else
    data.frame(.row = integer(0), cell = character(0), weight = numeric(0),
               cell_median = numeric(0), cell_n = integer(0),
               cell_share = numeric(0), stringsAsFactors = FALSE)
  out <- out[order(-out$weight), , drop = FALSE]
  rownames(out) <- NULL
  out
}
