#' weightflow: declarative survey weighting
#'
#' Builds analysis weights from design base weights by declaring the
#' weighting process as an ordered recipe of explicit adjustments — unknown
#' eligibility, within-cluster selection (e.g. within household), nonresponse,
#' calibration, trimming, rounding, rescaling, assertions — and then estimating
#' that recipe in one call. The package also produces replicate weights and
#' design-based standard errors that carry the variability of the whole cascade,
#' so a weighting project no longer has to end at the weights.
#'
#' Start with `weighting_spec()`, add `step_*()` adjustments, estimate the
#' cascade with `prep()`, and extract the weights with `collect_weights()`.
#' Inspect with `summary()`, `plot()` and `report_weighting()`.
#'
#' @keywords internal
"_PACKAGE"
