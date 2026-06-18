#' weightflow: declarative survey weighting
#'
#' Build survey weights from design base weights by chaining hierarchical
#' adjustments (unknown eligibility, nonresponse, trimming, calibration,
#' rounding, rescaling, assertions) through a declarative, pipeable,
#' tidymodels-style API. Computes weights only; for variance/inference, export
#' the weights and use them with the 'survey' package.
#'
#' Start with `weighting_spec()`, add `step_*()` adjustments, estimate the
#' cascade with `prep()`, and extract the weights with `collect_weights()`.
#' Inspect with `summary()`, `plot()` and `report_weighting()`.
#'
#' @keywords internal
"_PACKAGE"
