# Panel weighting steps. step_panel_overlap() applies the CEPAL panel base-weight
# adjustment: divide the incoming weight by Pr(panel selection), so the combined
# rotation panels represent the population of the reference wave.

#' Adjust base weights by the panel-selection probability (CEPAL ch. XVI)
#'
#' Divides each incoming weight by `Pr(panel selection)` -- the probability that a
#' rotation panel belongs to the combined-wave sample -- turning the design weight
#' of the reference wave into the panel base weight of the longitudinal sample
#' (`d_base = d1 / Pr`). This is the first step of the Verma-Betti-Ghellini
#' longitudinal-weight sequence: combining `k` waves in a design that keeps `g` of
#' its `G` rotation groups in all of them gives `Pr = g / G`, so the factor is its
#' reciprocal (e.g. 4/3 when 3 of 4 groups persist, 4 when only 1 does).
#'
#' `prob` is a probability in `(0, 1]`: either a per-unit column (or expression) or
#' a single constant applied to every active unit. When the data has a
#' `rotation_group`, get the constant from [panel_pr()]:
#' `prob = panel_pr(pd, c("T1", "T2"))`. When it does not (e.g. the Chilean ENE),
#' derive the probability yourself (from the design fraction or the cluster) and
#' pass it here. Run this on the longitudinal sample (the intersection of the
#' combined waves), before the attrition and calibration steps.
#'
#' @param spec a weighting_spec.
#' @param prob a panel-selection probability in `(0, 1]`: an unquoted per-unit
#'   column/expression, or a single constant (e.g. `panel_pr(pd, c("T1","T2"))`).
#' @param id optional string identifier for the step, shown in the recipe print-out
#'   and usable in [collect_step_detail()].
#' @return The input `weighting_spec` with this step appended to its recipe.
#' @seealso [panel_pr()], [panel_design()], [step_nonresponse()], [step_calibrate()]
#' @examples
#' # wide longitudinal file of the units in sample in both waves
#' wide <- panel_merge(
#'   list(T1 = subset(panel_ine, ola == 1), T2 = subset(panel_ine, ola == 2)),
#'   by = c("id_hogar", "nper"), require = "all")
#'
#' # rotation group known -> derive Pr(panel selection) from the panel design
#' pd <- panel_design(panel_ine, unit = c("id_hogar", "nper"), wave = "ola",
#'                    rotation_group = "grupo_rotacion")
#' weighting_spec(wide, base_weights = w_base_T1) |>
#'   step_panel_overlap(prob = panel_pr(pd, c("1", "2"))) |> prep()
#'
#' # no rotation group (e.g. Chile ENE) -> pass the probability directly
#' weighting_spec(wide, base_weights = w_base_T1) |>
#'   step_panel_overlap(prob = 5 / 6) |> prep()
#' @export
step_panel_overlap <- function(spec, prob, id = NULL) {
  p <- substitute(prob)
  if (is.null(p) || missing(prob))
    stop("`prob` is required: a panel-selection probability in (0, 1] ",
         "(a per-unit column, or a constant from panel_pr()).", call. = FALSE)
  if (!is.null(attr(spec$data, "wf_panel")) && !identical(.wf_purpose(spec), "longitudinal"))
    warning("step_panel_overlap() builds a longitudinal panel base weight; declare ",
            "step_longitudinal() first if that is the intent.", call. = FALSE)
  step <- structure(
    list(label = "panel overlap", prob = p, env = parent.frame()),
    class = c("step_panel_overlap", "weighting_step"))
  .add_step(spec, step, id = id)
}

# --- Scope: declare what the recipe computes (cross-sectional vs longitudinal) --

# The purpose declared by the last step_scope in the recipe (default cross-sectional).
.wf_purpose <- function(spec) {
  for (s in rev(spec$steps))
    if (inherits(s, "step_scope")) return(s$purpose)
  "cross_sectional"
}

#' Declare the recipe's scope: cross-sectional or longitudinal weights
#'
#' Two argument-free declarative steps that say what the recipe is building. They
#' do not touch the weights (like [step_assert()]); they record the intent so the
#' rest of the recipe, the report and the estimators behave accordingly, and so a
#' wrong-purpose estimate can be flagged. All the panel detail -- waves, rotation
#' group, reference wave -- already lives in [panel_design()], so these steps need
#' no arguments.
#'
#' Put the scope step first. `step_cross_sectional()` is the default (a plain recipe
#' with no scope step behaves as cross-sectional). `step_longitudinal()` requires the
#' data to be tagged by [panel_design()] and marks the recipe as building the panel
#' (longitudinal) weight, so steps like [step_panel_overlap()] apply and the
#' calibration targets the reference wave.
#'
#' @section ECLAC conventions for the longitudinal weight:
#'
#' The three points below are conventions of ECLAC's household-survey manual (ch. XVI). The
#' package cannot enforce them -- a vector of control totals carries no label saying which
#' period it belongs to -- so they are the reader's to apply.
#'
#' **Who is in the longitudinal population.** It is made up of the units that were in the target
#' population at the *first* period **and remained in it** through the last. Units that left
#' (death, migration, institutionalization) are out, and so are units that *entered* after the
#' first period: a panel adds no elements over time. Drop the first group with
#' [step_drop_ineligible()] before the attrition step -- leaving the target population is not
#' nonresponse and must not be compensated by redistributing weight.
#'
#' **Calibrate to the FIRST period's totals.** ECLAC is explicit that the auxiliary totals used
#' in the calibration must represent the population of the *first* period of interest, because a
#' panel that adds no elements over the measurement periods is representative only of the period
#' in which it was selected (ch. XVI, sec. B.2.c). In the original:
#' \preformatted{
#' "los totales auxiliares utilizados en la calibracion deben representar la
#'  poblacion del primer periodo de interes, puesto que, al conformar un panel
#'  que no suma elementos a lo largo de los periodos de medicion, la muestra
#'  sera representativa unicamente del periodo en el que fue seleccionada"
#' }
#' Passing the *later* period's projections is a silent error: the
#' recipe converges, the totals close, and the weights represent a population the sample never
#' had a chance to cover.
#'
#' **Cross-sectional estimates from a longitudinal file are reference only.** They will not
#' match the published cross-sectional figures **and should not**: the target population of the
#' panel combination is not the target population of the cross-section (ch. XVI, sec. C). Use
#' the longitudinal weight for gross flows, transitions and durations -- what it exists for --
#' and the cross-sectional weight for levels.
#'
#' @param spec a weighting_spec.
#' @param id optional string identifier for the step.
#' @return The input `weighting_spec` with the scope declared.
#' @seealso [panel_design()], [step_panel_overlap()]
#' @examples
#' wide <- panel_merge(
#'   list(T1 = subset(panel_ine, ola == 1), T2 = subset(panel_ine, ola == 2)),
#'   by = c("id_hogar", "nper"), require = "all")
#' weighting_spec(wide, base_weights = w_base_T1) |>
#'   step_longitudinal() |>
#'   step_panel_overlap(prob = 5 / 6) |> prep()
#' @export
step_cross_sectional <- function(spec, id = NULL) {
  if (!inherits(spec, "weighting_spec"))
    stop("The first argument must be a weighting_spec (piped with |>).", call. = FALSE)
  step <- structure(list(label = "scope: cross-sectional", purpose = "cross_sectional"),
                    class = c("step_cross_sectional", "step_scope", "weighting_step"))
  .add_step(spec, step, id = id)
}

#' @rdname step_cross_sectional
#' @export
step_longitudinal <- function(spec, id = NULL) {
  if (!inherits(spec, "weighting_spec"))
    stop("The first argument must be a weighting_spec (piped with |>).", call. = FALSE)
  if (is.null(attr(spec$data, "wf_panel")))
    warning("step_longitudinal() without a panel_design() on the data: the reference wave ",
            "and rotation structure are unknown. Tag the recipe data with panel_design() ",
            "for the reference wave, Pr(panel selection) and the panel report.", call. = FALSE)
  step <- structure(list(label = "scope: longitudinal", purpose = "longitudinal"),
                    class = c("step_longitudinal", "step_scope", "weighting_step"))
  .add_step(spec, step, id = id)
}

#' Attrition adjustment for panel waves
#'
#' The panel-facing nonresponse step: it adjusts for **attrition** (nonresponse between
#' waves) when building a longitudinal weight, reweighting the units that stayed in to also
#' represent those that dropped out, among the units that remain **eligible**. It is a thin
#' wrapper over [step_nonresponse()] -- so the theory stays visible in the recipe -- that
#' uses the same estimators but under a name that reads correctly in a panel cascade and with
#' the panel conventions: the covariates should come from a wave where the unit was observed
#' (e.g. the first period), and it does NOT absorb eligibility (out-of-scope and
#' unknown-eligibility go in [step_drop_ineligible()] / [step_unknown_eligibility()]).
#'
#' The attrition adjustment prescribed by ECLAC's household-survey manual (ch. XVI) and used by
#' Statistics Canada's SLID (Naud 2002; LaRoche 2003) is **response-propensity weighting**
#' (`method = "propensity"`, i.e. inverse of the estimated response probability; Little 1986;
#' Rosenbaum 1987) -- not an ECLAC invention. `method = "rhg"` is the response-homogeneity-group
#' variant (propensity stratified into `num_classes` groups, then the class-mean rate), which
#' stabilises the weights.
#'
#' Two ECLAC prescriptions are **not** implemented, and the difference matters when they apply.
#' The manual (ch. XVI, sec. B.1.b) allows two fallback imputations for units with no auxiliary
#' information at all: a nonrespondent whose rotation panel does not overlap (impute the overall
#' effective response rate as its `phi`), and a newly incorporated nonrespondent (impute the
#' adjusted expansion factor of its household). Here a covariate that is `NA` for an eligible
#' unit is an **error**, not an imputation -- an `NA` propensity would let that nonrespondent
#' survive the adjustment silently, which is the failure the error exists to prevent, and the
#' package will not silently substitute a value of its own for a missing input.
#'
#' So when the error fires, the fix belongs in the data, and either ECLAC route is available to
#' you there: impute the missing covariates before the step (the manual's own fallback is the
#' overall effective response rate, i.e. a constant, which is what a model with no covariates
#' for those units amounts to), give a newly incorporated nonrespondent its household's adjusted
#' factor, or restrict `formula` to a covariate set observed for every eligible unit. What the
#' package will not do is choose one of those for you and leave no trace in the recipe.
#' Multi-wave retention chaining (decomposing Pr(in at T3) into Pr(reach T2) x Pr(T2 to T3)) is
#' likewise absent: this step adjusts one transition at a time, which is what ch. XVI specifies
#' for two consecutive periods.
#'
#' @param spec a weighting_spec.
#' @param respondent an unquoted 0/1 column or logical condition, TRUE for the units that
#'   responded in the wave being adjusted (e.g. `disp_T2 == "R"`).
#' @param method attrition estimator: `"propensity"` (individual `1/phi`, the SLID/ECLAC
#'   response-propensity weighting; default), `"rhg"` (response homogeneity groups: propensity
#'   stratified into `num_classes` classes), `"weighting_class"` (design-variable cells), or
#'   `"calibration"` (Sarndal-Lundstrom).
#' @param formula model formula for `"propensity"`/`"rhg"`, in covariates observed for
#'   responders and nonrespondents (from a wave where the unit was seen).
#' @param by adjustment cells for `"weighting_class"`.
#' @param engine propensity engine (`"logit"`/`"tree"`/`"forest"`/`"boost"`).
#' @param num_classes number of propensity classes for `"rhg"`.
#' @param id optional stable step id.
#' @return the `weighting_spec` with the attrition step appended.
#' @seealso [step_nonresponse()], [step_panel_overlap()], [step_drop_ineligible()]
#' @examples
#' wide <- panel_merge(
#'   list(T1 = subset(panel_ine, ola == 1), T2 = subset(panel_ine, ola == 2)),
#'   by = c("id_hogar", "nper"), require = "all")
#' weighting_spec(wide, base_weights = w_base_T1) |>
#'   step_panel_overlap(prob = 5 / 6) |>
#'   step_drop_ineligible(disp_T2 == "OS", reason = "left the target population") |>
#'   step_attrition(respondent = disp_T2 == "R", method = "propensity",
#'                  formula = ~ edad_T1 + sexo_T1 + region_T1) |>
#'   prep()
#' @export
step_attrition <- function(spec, respondent,
                           method = c("propensity", "rhg", "weighting_class", "calibration"),
                           formula = NULL, by = NULL,
                           engine = c("logit", "tree", "forest", "boost"),
                           num_classes = 5L, id = NULL) {
  method <- match.arg(method)
  if (!inherits(spec, "weighting_spec"))
    stop("The first argument must be a weighting_spec (piped with |>).", call. = FALSE)
  # Delegate to step_nonresponse via the call, preserving the NSE `respondent` expression and
  # the caller's environment. Naming: "propensity" = individual 1/phi (num_classes NULL),
  # "rhg" = binned propensity classes (num_classes).
  mc <- match.call()
  mc[[1L]]  <- quote(step_nonresponse)
  mc$spec   <- spec                                  # embed the evaluated spec (no double eval)
  mc$method <- if (method == "rhg") "propensity" else method
  if (method == "propensity")      mc["num_classes"] <- list(NULL)
  else if (method == "rhg")        mc$num_classes <- num_classes
  else                              mc$num_classes <- NULL
  out <- eval(mc, parent.frame())
  k <- length(out$steps)                             # tag the appended step as attrition
  out$steps[[k]]$label <- paste0("attrition (", method, ")")
  out$steps[[k]]$attrition_method <- method
  # Own subclass so `inherits(s, "step_attrition")` is TRUE (e.g. refit_steps = "step_attrition")
  # while apply_step still dispatches to apply_step.step_nonresponse (no method for step_attrition).
  class(out$steps[[k]]) <- unique(c("step_attrition", class(out$steps[[k]])))
  out
}
