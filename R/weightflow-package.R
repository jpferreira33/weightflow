#' weightflow: declarative survey weighting
#'
#' Build survey weights from design base weights by chaining hierarchical
#' adjustments (unknown eligibility, nonresponse, trimming, calibration,
#' rounding, rescaling, assertions) through a declarative, pipeable,
#' tidymodels-style API. For inference it provides recipe-aware bootstrap and
#' delete-a-PSU jackknife replicate weights (`bootstrap_weights()`,
#' `jackknife_weights()`), which re-run the whole cascade on each replicate so the
#' variance of the adjustments is captured; the weights and replicates also export
#' to the 'survey' / 'srvyr' packages (`as_svydesign()`, `as_svrepdesign()`,
#' `collect_replicate_weights()`).
#'
#' Start with `weighting_spec()`, add `step_*()` adjustments, estimate the
#' cascade with `prep()`, and extract the weights with `collect_weights()`.
#' Inspect with `summary()`, `plot()` and `report_weighting()`.
#'
#' @keywords internal
"_PACKAGE"
