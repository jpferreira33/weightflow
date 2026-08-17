# collect_propensities(): recover the per-unit response propensities fitted by a
# step_nonresponse(method = "propensity") step from a prepped recipe.

#' Recover the fitted response propensities of a nonresponse step
#'
#' A `step_nonresponse(method = "propensity")` step fits a response-propensity
#' model and adjusts the weights by \eqn{1/\hat p}{1/phat}. `prep()` keeps the
#' full per-unit propensity vector \eqn{\hat p}{phat} (out-of-fold when
#' cross-fitting is used) on the step, but it is not returned by
#' [collect_weights()]. This accessor extracts it aligned to the sample, so you
#' can inspect its distribution and confirm the nonresponse model is well fitted
#' before trusting the adjusted weights. It works the same way whether the
#' adjustment was made at the unit level or, through `cluster`, at the household
#' level (there the household propensity is broadcast to its members).
#'
#' @param object a prepped `weighting_spec` (the output of [prep()]).
#' @param step optional integer, which step to read when the recipe has more than
#'   one propensity step. If `NULL` (default) and there is a single propensity
#'   step it is used; with several, the last one is used with a message.
#' @return The sample `data.frame` with four columns appended: `.propensity`
#'   (the fitted response propensity \eqn{\hat p}{phat}, `NA` for units outside
#'   the model, i.e. ineligible / already dropped), `.responded` (the response
#'   indicator the model used), `.weight_in` (the weight reaching the step, see
#'   below), and `.status`, a factor that labels each unit as `"eligible respondent"`,
#'   `"eligible nonrespondent"` or `"not in propensity model"`. Units not in the
#'   propensity model carry `NA` in the first three columns. `.weight_in` is the
#'   weight *reaching* the nonresponse step -- it already carries any earlier
#'   adjustment (unknown-eligibility redistribution, within-cluster selection),
#'   not the raw base weight -- and is the weight the propensity model is fitted
#'   with (unless `weight_model = FALSE`). The stage-by-stage weights are
#'   available through [weight_factors()] and [domain_summary()].
#' @seealso [step_nonresponse()], [collect_weights()]
#' @examples
#' fit <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "propensity",
#'                    formula = ~ sex + region, engine = "logit") |>
#'   prep()
#' p <- collect_propensities(fit)
#' summary(p$.propensity)
#' @export
collect_propensities <- function(object, step = NULL) {
  if (!inherits(object, "prepped_weighting_spec"))
    stop("`object` must be a prepped weighting_spec (the output of prep()).", call. = FALSE)
  n <- nrow(object$data)

  # Collect every step that stored a propensity vector (unit- or household-level).
  props <- Filter(Negate(is.null), lapply(seq_along(object$steps), function(i) {
    pr <- attr(object$steps[[i]]$diagnostics, "propensity")
    if (is.null(pr) || is.null(pr$p) || is.null(pr$idx)) NULL else list(i = i, pr = pr)
  }))
  if (!length(props))
    stop("No response-propensity step found. collect_propensities() needs a ",
         "step_nonresponse(method = \"propensity\") in the recipe.", call. = FALSE)

  avail <- vapply(props, function(x) x$i, integer(1))
  if (!is.null(step)) {
    props <- Filter(function(x) x$i == step, props)
    if (!length(props))
      stop(sprintf("Step %s has no fitted propensities. Steps with a propensity model: %s.",
                   step, paste(avail, collapse = ", ")), call. = FALSE)
  } else if (length(props) > 1L) {
    message(sprintf("The recipe has several propensity steps (%s); returning step %d. ",
                    paste(avail, collapse = ", "), avail[length(avail)]),
            "Pass `step =` to choose another.")
    props <- props[length(props)]
  }

  pr <- props[[1L]]$pr
  p_full <- rep(NA_real_, n); p_full[pr$idx] <- as.numeric(pr$p)
  r_full <- rep(NA,        n); r_full[pr$idx] <- as.logical(pr$resp)
  w_full <- rep(NA_real_,  n); w_full[pr$idx] <- as.numeric(pr$dw)
  # One categorical so a unit's role is obvious at a glance (grouping/teaching):
  # every unit in the propensity model is an eligible respondent or eligible
  # nonrespondent; everything else was not modelled (ineligible / already dropped).
  status <- rep("not in propensity model", n)
  status[pr$idx] <- ifelse(as.logical(pr$resp), "eligible respondent", "eligible nonrespondent")
  status <- factor(status,
                   levels = c("eligible respondent", "eligible nonrespondent",
                              "not in propensity model"))

  out <- object$data
  for (nm in c(".propensity", ".responded", ".weight_in", ".status"))
    if (nm %in% names(out))
      warning(sprintf("Column `%s` already exists in the data and will be overwritten.", nm),
              call. = FALSE)
  out$.propensity <- p_full
  out$.responded  <- r_full
  out$.weight_in  <- w_full     # weight reaching the step (carries prior adjustments), not the base weight
  out$.status     <- status
  out
}
