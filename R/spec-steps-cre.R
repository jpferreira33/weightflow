# Composite regression estimator (CRE / RCE): step_cre() + apply_step.step_cre().
# Statistics Canada LFS ch. 6 (composite calibration) == INE ECH sec. 8.4
# (calibracion compuesta). A calibration step whose auxiliary matrix is augmented
# with composite auxiliaries z (previous-wave labour status), whose control totals
# Zhat are ESTIMATED from the previous wave's CRE weights (hence recursive). The
# birth rotation group (no t-1 data) is imputed by MR1 (mean) / MR2 (carry-backward)
# and mixed with alpha = 2/3. Reuses the GREG solver (.solve_calibration) and the
# Lemaitre-Dufour integrative option; variance.R is untouched.

#' Composite regression estimator (CRE / regression composite estimation)
#'
#' Final-weight step for rotating panels that exploits the sample overlap **in the
#' estimation**, not only in the variance. It is the composite calibration of the
#' Canadian LFS (Gambino, Kennedy and Singh 2001; Fuller and Rao 2001) and the
#' composite calibration of the Uruguayan ECH (INE, methodology sec. 8.4): the same
#' estimator. On top of the ordinary calibration to known population totals `X`, it
#' adds a second set of constraints to control totals `Zhat` estimated from the
#' **previous wave** (the composite auxiliaries: previous-month labour status,
#' optionally crossed by domains). Because `Zhat` uses the previous wave's composite
#' weights, the estimator is recursive.
#'
#' The composite auxiliary `z` is known for the overlap sample (units present in
#' `t-1`) and imputed for the birth rotation group (units entering at `t`, with no
#' `t-1` value) by combining two imputations: MR1 (mean imputation, aimed at the
#' level) and MR2 (carry-backward, aimed at the change), mixed as
#' `z = (1 - alpha) z1 + alpha z2` with `alpha = 2/3`.
#'
#' The composite weights are `w_cre = w_nr * g`, with `g` the GREG factor of the
#' augmented calibration `[x | z]` to `[X | Zhat]`; the same solver as
#' [step_calibrate()]. With `equal_within_cluster = TRUE` the auxiliaries are
#' averaged to the household (integrated method of weighting, Lemaitre-Dufour 1987)
#' so every household member shares one final weight.
#'
#' @param spec a weighting_spec (its recipe up to here yields the nonresponse-adjusted
#'   weights `w_nr` that this step starts from).
#' @param previous the prepped previous-wave recipe (`prep()` output), which supplies
#'   the previous composite weights and the previous labour status for `Zhat` and the
#'   overlap imputation. `NULL` (default) is the **seed** wave: with no `t-1` there is
#'   no composite block and the step reduces to an ordinary linear calibration to `X`
#'   -- the start of the recursion.
#' @param status bare or quoted name of the categorical labour-status column
#'   (e.g. employed / unemployed / inactive) in the current wave; must exist with the
#'   same name in `previous`. Its indicators are the composite auxiliaries.
#' @param composite a **list of domain crossings**, each defining one block of
#'   composite control totals. `NULL` = country total; a string = status crossed by
#'   that domain (e.g. "sex"); a character vector = status crossed by the interaction
#'   (e.g. c("sex","age")). This mirrors the methodologies' composite-variable lists:
#'   the ECH's are `list(NULL, "sex", "department")`. Default `list(NULL)`.
#' @param id_unit character vector naming the unit key that links waves (e.g.
#'   c("household","person")). Used to look up each current unit's `t-1` status.
#' @param formula the demographic auxiliary formula for `x` (as in
#'   [step_calibrate()] method = "linear"), e.g. `~ age_sex + region`.
#' @param totals,count the population totals `X` for `x`, in the same forms accepted
#'   by [step_calibrate()] (a named vector aligned to the model.matrix, or the tidy
#'   named list with `count`).
#' @param birth expression (evaluated in the current data) that is TRUE for the birth
#'   rotation group (the units with no `t-1` value to carry). If `NULL`, birth units
#'   are those not found in `previous` by `id_unit` -- which means a key that fails to
#'   link is indistinguishable from a genuine entrant, and a broken `id_unit` then looks
#'   like an enormous rotation while the change correction quietly stops working. The
#'   step warns when the implied overlap falls below half (or below `overlap` minus ten
#'   points, when `overlap` is given as a number) and errors below 2%, but the only way
#'   to separate the two properly is to declare `birth` yourself, or to pass the design's
#'   nominal `overlap` so the check has something real to compare against.
#' @param alpha MR1/MR2 mixing constant between 0 and 1. `alpha = 0` targets the
#'   level only (MR1), `alpha = 1` the change only (MR2). Default 2/3 (Chen and Liu 2002).
#' @param overlap the overlap rate used by the MR2 carry-backward correction: "auto"
#'   (default) estimates it as the `w_nr`-weighted overlap fraction, or a number
#'   (e.g. 5/6, the nominal LFS/ECH rate).
#' @param rescale_previous put the composite block on the current wave's population
#'   scale: `Zhat <- Zhat * N_t / Nhat_{t-1}` (equivalently, calibrate the composite
#'   auxiliaries on proportions). `Zhat` is a total estimated with the previous wave's
#'   weights, so it lives on `Nhat_{t-1}` while `totals` fixes this wave's `N_t`; the
#'   identity that keeps the composite block a smoother rather than a level shift
#'   assumes the two agree. When they differ, the whole gap is discharged onto the
#'   status estimate with every constraint met and `converged = TRUE`. `FALSE`
#'   (default) keeps the totals as given and warns when the two scales differ by more
#'   than 1%; the better fix is to calibrate both waves to the same series of
#'   population projections.
#' @param on_missing_prev how to treat non-birth units without a valid `t-1` status
#'   (new household members, newly of working age): "carry_backward" (default; set
#'   `z_{t-1} = z_t`) or "zero" (`z_{t-1} = 0`).
#' @param cluster,equal_within_cluster integrated method of weighting: with
#'   `equal_within_cluster = TRUE` (needs `cluster`) the auxiliaries `x` and `z` are
#'   averaged to the cluster so members share one weight (Lemaitre-Dufour 1987).
#' @param calfun,bounds distance and g-bounds for the calibration, as in
#'   [step_calibrate()]. Use `bounds = c(L, U)` with a logit `calfun` to avoid final
#'   weights below 1.
#' @param rotation_group optional name of the rotation-group column. When given,
#'   the step adds the **equal-representation** constraints both surveys impose:
#'   each rotation group must weight to the same working-age total, `N / G` (ECH
#'   sec. 8.4.1, `sum_{i in s_g} w_i = N_PET / 6`; LFS sec. 6.3.1). `N` is read from
#'   the intercept target in `totals` and `G` is the number of groups; the last
#'   group is left implied (its total follows from the others and `N`), so `G - 1`
#'   constraints are added to the demographic block. `NULL` (default) omits them.
#' @param n_groups the number of rotation groups the **design** has, e.g. `6`. Only
#'   used with `rotation_group`, and worth giving: `G` is a property of the design, not
#'   of who answered this wave, and the target `N / G` is wrong the moment the two
#'   differ. If a group has no active units -- fully attrited, or a domain with no
#'   respondents in it -- and `G` is read off the sample, every remaining group is
#'   calibrated to `N / (G - 1)`, i.e. a whole group's population shared out among the
#'   others, while the intercept still targets `N`. The step refuses that rather than
#'   solving it, because the two constraints cannot both hold. When `n_groups` is not
#'   given, `G` comes from the column's factor levels (which survive a level going
#'   empty); a character column carries no such record, so the step warns that it had to
#'   read `G` off the wave.
#' @param status_ref the status level held as reference (dropped from each cell block
#'   to avoid the mechanical collinearity between the full status indicators and the
#'   demographic block, which pins the same cell totals). The dropped total is implied
#'   by the others plus `X`, so the estimator is unchanged; naming the level only sets
#'   which one is implicit (e.g. `"inact"` to keep employed/unemployed explicit).
#'   `NULL` (default) drops the last level in sorted order. One level is always dropped:
#'   keeping every level would make the block collinear with the intercept in `X`.
#' @param id optional stable identifier for this step.
#' @return the input `weighting_spec` with the CRE step appended (evaluated at
#'   [prep()]). Chain waves by passing each prepped wave as the `previous` of the next.
#' @references
#' Gambino J, Kennedy B, Singh MP (2001). Regression composite estimation for the
#'   Canadian Labour Force Survey. \emph{Survey Methodology} 27(1):65-74.
#' Fuller WA, Rao JNK (2001). A regression composite estimator with application to
#'   the Canadian Labour Force Survey. \emph{Survey Methodology} 27(1):45-51.
#' Instituto Nacional de Estadistica (Uruguay). Metodologia de la Encuesta Continua
#'   de Hogares, seccion 8.4 (calibracion compuesta).
#' @family weighting steps
#' @examples
#' # Composite (CRE) estimation on the 6-month rotating panel `panel_ine`.
#' # `lf_status` is the previous-wave labour status (emp / unemp / inact).
#' t1 <- subset(panel_ine, wave == 1 & disposition == "R")
#' t2 <- subset(panel_ine, wave == 2 & disposition == "R")
#' t1$sex <- factor(t1$sex); t2$sex <- factor(t2$sex)
#'
#' # ONE population vector for both waves, as a series of projections would be.
#' # `Zhat` is a total on the previous wave's scale, so calibrating each wave to its
#' # own design-weighted total puts two population scales in one system and the
#' # difference lands on the status estimate (see `rescale_previous`).
#' Xpop <- colSums(t1$pw * stats::model.matrix(~ sex, data = t1))
#'
#' # seed wave: no previous month, so step_cre() reduces to a linear calibration to X
#' seed <- weighting_spec(t1, base_weights = pw) |>
#'   step_cre(previous = NULL, status = lf_status, formula = ~ sex,
#'            totals = Xpop, status_ref = "inact") |>
#'   prep()
#'
#' # composite wave: augment X with the previous-wave status, country-level and by sex
#' fit2 <- weighting_spec(t2, base_weights = pw) |>
#'   step_cre(previous = seed, status = lf_status, composite = list(NULL, "sex"),
#'            id_unit = c("household_id", "person_no"), formula = ~ sex, totals = Xpop,
#'            alpha = 2/3, status_ref = "inact") |>
#'   prep()
#' fit2
#' @export
step_cre <- function(spec, previous = NULL, status, composite = list(NULL),
                     id_unit, formula, totals = NULL, count = NULL, birth = NULL,
                     alpha = 2/3, overlap = "auto", rescale_previous = FALSE,
                     on_missing_prev = c("carry_backward", "zero"),
                     cluster = NULL, equal_within_cluster = FALSE,
                     calfun = c("linear", "logit", "raking"), bounds = NULL,
                     rotation_group = NULL, n_groups = NULL, status_ref = NULL,
                     id = NULL) {
  calfun <- match.arg(calfun)
  on_missing_prev <- match.arg(on_missing_prev)
  equal_within_cluster <- .wf_flag(equal_within_cluster, "equal_within_cluster")
  id <- .wf_id(id)
  if (missing(status))
    stop("`status` (the labour-status column) is required.", call. = FALSE)
  status_q <- substitute(status)
  status   <- if (is.character(status_q)) status_q[1] else deparse(status_q)
  birth_q  <- substitute(birth)

  if (!inherits(formula, "formula"))
    stop("`formula` must be a formula naming the demographic auxiliaries x (e.g. ~ age_sex + region).",
         call. = FALSE)
  if (is.null(totals))
    stop("`totals` (the population totals X for the demographic auxiliaries) is required.",
         call. = FALSE)
  if (!is.list(composite) || !length(composite))
    stop("`composite` must be a non-empty list of domain crossings (NULL = country total, ",
         "a string, or a character vector for an interaction). E.g. list(NULL, \"sex\").",
         call. = FALSE)
  ok_cross <- vapply(composite, function(c) is.null(c) || is.character(c), logical(1))
  if (!all(ok_cross))
    stop("Each element of `composite` must be NULL or a character vector of domain columns.",
         call. = FALSE)
  if (!is.null(previous)) {
    if (!inherits(previous, "prepped_weighting_spec"))
      stop("`previous` must be a prepped recipe (the prep() output of the previous wave), or NULL for the seed wave.",
           call. = FALSE)
    if (missing(id_unit) || !is.character(id_unit) || !length(id_unit))
      stop("`id_unit` (the wave-linking key, e.g. c(\"household\",\"person\")) is required when `previous` is given.",
           call. = FALSE)
  }
  if (!is.numeric(alpha) || length(alpha) != 1L || !is.finite(alpha) || alpha < 0 || alpha > 1)
    stop("`alpha` must be a single number in [0, 1] (the MR1/MR2 mix; default 2/3).", call. = FALSE)
  if (!(identical(overlap, "auto") || (is.numeric(overlap) && length(overlap) == 1L &&
        is.finite(overlap) && overlap > 0 && overlap <= 1)))
    stop("`overlap` must be \"auto\" or a single number in (0, 1] (e.g. 5/6).", call. = FALSE)
  if (!is.null(bounds)) {
    if (!is.numeric(bounds) || length(bounds) != 2L || anyNA(bounds) || any(!is.finite(bounds)) ||
        bounds[1] >= 1 || bounds[2] <= 1)
      stop("`bounds` must be c(L, U) with L < 1 < U.", call. = FALSE)
  }
  if (calfun == "logit" && is.null(bounds))
    stop("calfun = \"logit\" requires `bounds` = c(L, U).", call. = FALSE)
  if (equal_within_cluster && is.null(cluster))
    stop("equal_within_cluster = TRUE requires `cluster`.", call. = FALSE)
  if (!is.null(rotation_group) && (!is.character(rotation_group) || length(rotation_group) != 1L))
    stop("`rotation_group` must be a single string naming the rotation-group column.", call. = FALSE)
  if (!is.null(n_groups)) {
    if (is.null(rotation_group))
      stop("`n_groups` only means anything with `rotation_group`; it declares how many ",
           "rotation groups the DESIGN has.", call. = FALSE)
    if (!is.numeric(n_groups) || length(n_groups) != 1L || !is.finite(n_groups) ||
        n_groups < 2 || n_groups != round(n_groups))
      stop("`n_groups` must be a single whole number >= 2 (e.g. 6 for a six-group ",
           "rotation).", call. = FALSE)
    n_groups <- as.integer(n_groups)
  }

  detail <- if (is.null(previous)) "seed: linear calibration" else
              sprintf("composite, alpha = %.2f", alpha)
  if (!is.null(rotation_group)) detail <- paste0(detail, ", equal groups")
  if (equal_within_cluster) detail <- paste0(detail, sprintf(", one weight per %s", cluster))
  step <- structure(
    list(
      label       = sprintf("composite regression estimator (%s)", detail),
      cre         = TRUE,
      previous    = previous,
      status      = status,
      composite   = composite,
      link_key    = if (missing(id_unit)) NULL else id_unit,  # NB: not `id_unit` -- `$id` partial-matches it
      formula     = formula,
      totals      = totals,
      count       = count,
      birth       = birth_q,
      env         = parent.frame(),   # so a `birth =` expression can see caller vars (CRE-03)
      alpha       = alpha,
      overlap     = overlap,
      rescale_previous = .wf_flag(rescale_previous, "rescale_previous"),
      on_missing_prev = on_missing_prev,
      cluster     = cluster,
      equal_within_cluster = equal_within_cluster,
      calfun      = calfun,
      bounds      = bounds,
      rotation_group = rotation_group,
      n_groups       = n_groups,
      status_ref  = status_ref
    ),
    class = c("step_cre", "weighting_step")
  )
  .add_step(spec, step, id = id)
}

# --- composite auxiliary matrix ---------------------------------------------
# Cell factor for one crossing (NULL -> a single "all" cell; else the interaction
# of the domain columns), returned as a character vector.
.wf_cre_cellfac <- function(data, cross) {
  if (is.null(cross)) return(rep_len("all", nrow(data)))
  miss <- setdiff(cross, names(data))
  if (length(miss))
    stop(sprintf("composite crossing column(s) not found: %s.", paste(miss, collapse = ", ")),
         call. = FALSE)
  # Join multi-column crossings with "|", NOT ".": the composite column name is
  # sprintf("z%d.%s.%s", ci, cell, status), so a "." inside a cell label would make two
  # distinct cells collide on the same name and one composite constraint would overwrite the
  # other. "|" does not occur in the "z.<cell>.<status>" delimiters. (CRE-04)
  do.call(paste, c(lapply(cross, function(v) as.character(data[[v]])), sep = "|"))
}

# Build the composite indicator matrix z for a status vector and the `composite`
# list, with columns fixed by the shared `levels` (status) and per-crossing cell
# levels so the previous-wave Zhat and the current-wave z align exactly. The
# reference status level is dropped per cell (collinear with the demographic block).
.wf_cre_zmatrix <- function(status_chr, data, composite, status_levels, ref,
                            cell_levels) {
  keep_status <- setdiff(status_levels, ref)
  blocks <- list()
  for (ci in seq_along(composite)) {
    cross <- composite[[ci]]
    cellf <- .wf_cre_cellfac(data, cross)
    clev  <- cell_levels[[ci]]
    for (cl in clev) for (st in keep_status) {
      col <- as.numeric(status_chr == st & cellf == cl)
      nm  <- sprintf("z%d.%s.%s", ci, cl, st)
      blocks[[nm]] <- col
    }
  }
  m <- matrix(unlist(blocks, use.names = FALSE), nrow = nrow(data),
              dimnames = list(NULL, names(blocks)))
  m
}

# Per-crossing cell levels, unioned across the previous and current waves so the
# column set is stable regardless of which cells each wave happens to observe.
.wf_cre_celllevels <- function(composite, cur_data, prev_data) {
  lapply(composite, function(cross) {
    if (is.null(cross)) return("all")
    a <- unique(.wf_cre_cellfac(cur_data, cross))
    b <- if (is.null(prev_data)) character(0) else unique(.wf_cre_cellfac(prev_data, cross))
    sort(unique(c(a, b)))
  })
}

# Solve a calibration dropping columns that are linearly dependent on the others
# (via QR pivoting). The composite blocks are deliberately redundant -- the nested
# crossings share the same status totals (country = sum over sex = sum over dept),
# exactly as the ECH/LFS list them -- so the full system is singular by design. A
# dropped constraint is implied by the kept ones and by construction consistent
# (all Zhat come from the same previous weights), so the fitted weights are
# identical; this just avoids the (uninformative) pseudo-inverse warning. A GENUINE
# problem (an empty cell, an inconsistent target) is NOT hidden: the caller still
# checks the achieved totals against the FULL target set afterwards.
.wf_cre_solve <- function(M, v, Tvec, calfun, bounds) {
  qrM <- qr(M)
  if (qrM$rank < ncol(M)) {
    keep <- sort(qrM$pivot[seq_len(qrM$rank)])
    return(.solve_calibration(M[, keep, drop = FALSE], v, Tvec[keep], calfun, bounds,
                              NULL, 100L, 1e-7))
  }
  .solve_calibration(M, v, Tvec, calfun, bounds, NULL, 100L, 1e-7)
}

#' @export
apply_step.step_cre <- function(step, data, w) {
  active <- .wf_active(w)
  new_w  <- w
  d      <- new_w[active]
  dat_a  <- data[active, , drop = FALSE]

  # Demographic design matrix X and its targets (as in the linear calibrate step).
  X  <- stats::model.matrix(step$formula, data = dat_a)
  if (nrow(X) != length(d) || anyNA(X))
    stop("Demographic auxiliaries in `formula` have NA in the active sample; impute first.",
         call. = FALSE)
  cn <- colnames(X)
  if (is.list(step$totals) && !is.data.frame(step$totals))
    Xtot <- .prep_linear_totals(step$formula, step$totals, step$count, data, active)
  else
    Xtot <- step$totals
  if (!setequal(names(Xtot), cn))
    stop(sprintf("`totals` names must match the model.matrix columns.\nExpected: %s",
                 paste(cn, collapse = ", ")), call. = FALSE)
  Xtot <- as.numeric(Xtot[cn]); names(Xtot) <- cn

  # --- equal representation of rotation groups (ECH 8.4.1 / LFS 6.3.1) --------
  # Each rotation group must weight to N / G. Read N from the intercept target,
  # add G-1 group indicators (the last is implied by the others plus N), and fold
  # them into the demographic block X so they hold per bootstrap replicate too.
  if (!is.null(step$rotation_group)) {
    rg <- step$rotation_group
    if (!rg %in% names(data))
      stop(sprintf("`rotation_group` column '%s' not found in the data.", rg), call. = FALSE)
    if (!"(Intercept)" %in% names(Xtot))
      stop("Equal-representation of rotation groups needs the working-age total N: ",
           "include an intercept in `formula` (its target is N), or drop `rotation_group`.",
           call. = FALSE)
    N_tot <- unname(Xtot[["(Intercept)"]])
    grp   <- as.character(dat_a[[rg]])
    glev  <- sort(unique(grp))

    # CRE-07. G is a property of the DESIGN, not of whoever answered this wave. Taking
    # it from the active sample makes the target N/G move with the sample: lose one of
    # six rotation groups -- a wave where a group has fully attrited, or a small domain
    # where one has no respondents -- and every remaining group is calibrated to N/5
    # instead of N/6, i.e. 20% too high, with the intercept still at N so the missing
    # group's population is silently shared out among the others. It converges, the
    # constraints hold to 1e-6, and nothing is reported.
    #
    # There is no safe automatic answer, because the system as posed is contradictory:
    # with the intercept pinned at N you cannot also ask N/G_design of only G_present
    # groups. N/G_present is the one feasible reading, which is exactly why it happened
    # in silence. So establish the design's G -- the factor's levels if the column is a
    # factor (they survive a level going empty), otherwise the declared `n_groups` --
    # and refuse when it does not match what is present.
    G_design <- if (!is.null(step$n_groups)) step$n_groups
                else if (is.factor(dat_a[[rg]])) nlevels(dat_a[[rg]])
                else length(glev)
    # A character column carries no record of a group that answered nobody, so there is
    # nothing to compare against and the inference below is vacuous. Say so once: this is
    # the only configuration where the silent N/G_present can still happen.
    if (is.null(step$n_groups) && !is.factor(dat_a[[rg]]))
      warning(sprintf(paste0(
        "Equal representation of rotation groups: `%s` is not a factor and `n_groups` was ",
        "not given, so the design's number of groups was taken from the wave itself (%d ",
        "found). If a group has no active units here, that goes unnoticed and every ",
        "remaining group is calibrated to N/%d instead of its real share. Make the column ",
        "a factor with all the design's levels, or pass `n_groups = %d` if that is the ",
        "design."), rg, G_design, G_design, G_design), call. = FALSE)
    G <- length(glev)
    if (G_design != G) {
      miss <- if (is.factor(dat_a[[rg]])) setdiff(levels(dat_a[[rg]]), glev) else character(0)
      stop(sprintf(paste0(
        "Equal representation of rotation groups: the design has %d group(s) but only %d ",
        "are present in this wave%s. Calibrating the %d present groups to N/%d each would ",
        "give every one of them %.1f%% more than its share and hand out the missing ",
        "group(s)' population among them, while the intercept still targets the whole N ",
        "-- the two constraints cannot both hold. Decide which you mean: drop ",
        "`rotation_group` for this wave, restrict `totals` to the population the present ",
        "groups represent, or pass `n_groups = %d` together with a `totals` intercept that ",
        "matches it."),
        G_design, G,
        if (length(miss)) sprintf(" (missing: %s)", paste(miss, collapse = ", ")) else "",
        G, G, 100 * (G_design / G - 1), G), call. = FALSE)
    }
    if (G >= 2L) {
      keep_g <- glev[-G]                                   # drop last group (implied)
      Xg <- vapply(keep_g, function(g) as.numeric(grp == g), numeric(length(grp)))
      colnames(Xg) <- paste0(".GR.", keep_g)
      X    <- cbind(X, Xg)
      Xtot <- c(Xtot, stats::setNames(rep(N_tot / G, length(keep_g)), colnames(Xg)))
      cn   <- colnames(X)
    }
  }

  # --- seed wave: no previous -> ordinary linear calibration to X -------------
  if (is.null(step$previous)) {
    A <- X; Tvec <- Xtot; zcols <- character(0); Zhat <- numeric(0)
  } else {
    # --- composite block --------------------------------------------------------
    prev  <- step$previous
    pw    <- prev$final_weight
    pactv <- .wf_active(pw)
    pdat  <- prev$data
    st    <- step$status
    if (!st %in% names(data))    stop(sprintf("`status` column '%s' not in the current data.", st), call. = FALSE)
    if (!st %in% names(pdat))    stop(sprintf("`status` column '%s' not in `previous`.", st), call. = FALSE)
    idu <- step$link_key
    miss_id <- setdiff(idu, intersect(names(data), names(pdat)))
    if (length(miss_id))
      stop(sprintf("`id_unit` column(s) not in both waves: %s.", paste(miss_id, collapse = ", ")),
           call. = FALSE)

    status_levels <- sort(unique(c(as.character(data[[st]]), as.character(pdat[[st]]))))
    status_levels <- status_levels[!is.na(status_levels)]
    ref <- if (is.null(step$status_ref)) status_levels[length(status_levels)] else step$status_ref
    if (!ref %in% status_levels)
      stop(sprintf("`status_ref` = '%s' is not a level of `status`.", ref), call. = FALSE)
    cell_levels <- .wf_cre_celllevels(step$composite, dat_a, pdat[pactv, , drop = FALSE])

    # Zhat: previous-wave composite totals, estimated with the previous CRE weights.
    Zprev <- .wf_cre_zmatrix(as.character(pdat[[st]]), pdat, step$composite,
                             status_levels, ref, cell_levels)
    Zhat  <- colSums(pw[pactv] * Zprev[pactv, , drop = FALSE])
    zcols <- names(Zhat)

    # Link each current active unit to its previous-wave status -- against the ACTIVE
    # previous rows only (CRE-05). Zhat is built from `pactv`, so a unit linked to a
    # previous row with weight 0 (a nonrespondent: weightflow zeroes the weight, it does
    # not delete the row) was counted as overlap while contributing nothing to the target
    # it is supposed to reproduce. In a wave with ordinary nonresponse that is the normal
    # case, not the corner one: it inflated the linked set from 201 to 400 in a 480-row
    # wave, and delta with it.
    key_cur  <- do.call(paste, c(lapply(idu, function(v) as.character(dat_a[[v]])), sep = "\r"))
    key_prev <- do.call(paste, c(lapply(idu, function(v) as.character(pdat[[v]])), sep = "\r"))
    prev_status_by_key <- tapply(as.character(pdat[[st]])[pactv], key_prev[pactv],
                                 function(z) z[1])
    prev_status <- unname(prev_status_by_key[key_cur])       # NA if not in previous

    linked <- !is.na(prev_status)                            # found in previous by id_unit
    if (is.null(step$birth)) {
      # No birth expression: every unit without a t-1 link is treated as birth.
      is_birth     <- !linked
      missing_prev <- rep(FALSE, length(d))
      # CRE-10. This is the DEFAULT branch, and it makes the CRE-06 guard below dead
      # code: that guard fires on n_missing_prev, which is 0 here by construction. So a
      # broken `id_unit` key is indistinguishable from an enormous rotation -- every
      # unlinked unit is reclassified as the incoming rotation group, the one category
      # that does NOT take part in the change correction. Measured on `panel_ine` with
      # the key broken: delta 1e-6, 0 linked, 1,774 births out of 1,774, n_missing_prev
      # 0, converged TRUE, not one warning. The only control left is to compare the
      # implied link rate against what the design says it should be; flag it so the
      # check further down can do exactly that.
      birth_inferred <- TRUE
    } else {
      bf <- eval(step$birth, envir = dat_a, enclos = step$env %||% baseenv())
      # Length 1 is recycled on purpose; ANY other wrong length used to be recycled too,
      # silently, by the indexing below -- a `birth` of length 3 on a 1,774-row wave moved
      # employment by +24% with neither error nor warning. .eval_cond() guards exactly
      # against this everywhere else in the package. (CRE-07)
      if (length(bf) == 1L) bf <- rep(bf, length(d))
      if (length(bf) != length(d))
        stop(sprintf(paste0("`birth` gave %d value(s) for %d active unit(s). It must be a ",
                            "single TRUE/FALSE or one value per unit."),
                     length(bf), length(d)), call. = FALSE)
      if (!is.logical(bf) && !is.numeric(bf))
        stop("`birth` must evaluate to a logical (or 0/1) vector.", call. = FALSE)
      is_birth <- as.logical(bf); is_birth[is.na(is_birth)] <- FALSE
      # non-birth units without a t-1 link: new members / newly of working age.
      missing_prev <- !is_birth & !linked
      if (identical(step$on_missing_prev, "carry_backward"))
        prev_status[missing_prev] <- as.character(dat_a[[st]])[missing_prev]  # z_{t-1} = z_t
      # (else "zero": leave prev_status NA -> its z_{t-1} row is all zeros below)
      birth_inferred <- FALSE
    }

    # z at t (current status) and z at t-1 (linked previous status), same columns.
    z_t   <- .wf_cre_zmatrix(as.character(dat_a[[st]]), dat_a, step$composite,
                             status_levels, ref, cell_levels)
    ps    <- prev_status; ps[is.na(ps)] <- ref                # NA -> reference -> zero row
    z_tm1 <- .wf_cre_zmatrix(ps, dat_a, step$composite, status_levels, ref, cell_levels)

    # Overlap rate delta (w_nr-weighted) for the MR2 carry-backward correction.
    # It must count the units that actually CARRY a t-1 value, i.e. !is_birth AND linked.
    # A non-birth unit whose link failed lands in `missing_prev`: with the default
    # carry_backward it gets z_{t-1} = z_t, so it contributes exactly zero to
    # (z_{t-1} - z_t) -- and counting it in delta made the 1/delta - 1 multiplier too
    # small, attenuating the estimated change in proportion to the link-failure rate.
    # Measured: with 30% of the overlap links broken the month-on-month change came out
    # at 77% of the truth, with 60% broken at 47%, converged = TRUE and not a word said.
    # That is the most expensive silent failure in an LFS-type survey. (CRE-06)
    # The MEASURED link rate, always -- with a numeric `overlap` the user's value REPLACES
    # it below, and then comparing `delta` against that same value would be vacuous.
    ov_meas <- {
      ov <- !is_birth & linked
      s_all <- sum(d); if (s_all > 0) sum(d[ov]) / s_all else NA_real_
    }
    delta <- if (identical(step$overlap, "auto")) {
      if (is.na(ov_meas)) 5/6 else ov_meas
    } else step$overlap
    # A floor of 1e-6 turned a broken link into a 1/delta - 1 multiplier of 10^6 and
    # carried on. No rotating design has an overlap anywhere near that: below a few per
    # cent the composite block is not smoothing anything, it is amplifying noise by two
    # orders of magnitude. Refuse, and say which of the two causes it is. (CRE-11)
    if (is.finite(delta) && delta < 0.02) {
      stop(sprintf(paste0("step_cre(): the overlap rate is %.4g (%s), so the MR2 carry-backward ",
                          "multiplier 1/delta - 1 would be %.4g. No rotating design overlaps that ",
                          "little: either `id_unit` (%s) does not link the two waves, or `overlap` ",
                          "was set by hand to an impossible value. Check the key on a few units ",
                          "of both waves, or declare `birth =` so an unlinked unit is not counted ",
                          "as the incoming rotation group."),
                  delta,
                  if (identical(step$overlap, "auto")) "estimated from the data" else "as supplied",
                  1 / max(delta, 1e-12) - 1, paste(idu, collapse = ", ")), call. = FALSE)
    }
    delta <- min(max(delta, 1e-6), 1)

    # Link quality, recorded so it can be read back and asserted on. Without it, E9/E10
    # -- a failing link silently attenuating the change -- are invisible from outside:
    # the step converges, the totals are met, and nothing says what share of the wave
    # actually carried a t-1 value. (CRE-09)
    link_diag <- list(
      delta        = delta,
      n_active     = length(d),
      n_birth      = sum(is_birth),
      n_linked     = sum(!is_birth & linked),
      n_missing_prev = sum(missing_prev),
      w_linked     = if (sum(d) > 0) sum(d[!is_birth & linked]) / sum(d) else NA_real_,
      linked_rate  = ov_meas,            # measured, even when `overlap` was supplied
      birth_inferred = isTRUE(birth_inferred),
      on_missing_prev = step$on_missing_prev %||% "carry_backward")

    # N for MR1's Zhat/N proportion imputation of births. Zhat is the PREVIOUS wave's
    # composite total, so the denominator has to be the previous wave's estimated
    # population -- sum(d) is the CURRENT wave's incoming weight, which only coincides
    # when the recipe already arrives calibrated to N. Every test in the suite builds the
    # totals so that sum(d) == N by construction, which is why this stayed invisible;
    # at sum(d) = 0.85 N the measured level bias was +18%. (CRE-08)
    N   <- sum(pw[pactv]); Zprop <- if (N > 0) Zhat / N else Zhat * 0

    # MR1 (level): overlap -> z_{t-1}; birth -> Zhat/N.
    z1 <- z_tm1
    if (any(is_birth)) z1[is_birth, ] <- matrix(Zprop, sum(is_birth), length(Zprop), byrow = TRUE)
    # MR2 (change): overlap -> z_{t-1} + (1/delta - 1)(z_{t-1} - z_t); birth -> z_t.
    z2 <- z_tm1 + (1/delta - 1) * (z_tm1 - z_t)
    if (any(is_birth)) z2[is_birth, ] <- z_t[is_birth, ]

    a  <- step$alpha
    Z  <- (1 - a) * z1 + a * z2

    # Two population scales in one system (CRE-09). `Zhat` is a TOTAL estimated with the
    # PREVIOUS wave's weights, so it lives on Nhat_{t-1}; `Xtot` fixes this wave's N_t.
    # The identity that makes the composite block weakly binding -- and so a smoother
    # rather than a level shift -- assumes the two agree: with N_t = N_{t-1} the whole
    # expression collapses to Z_{t-1} for every alpha. When they differ, the MR1 term is
    # scaled by N_t/N_{t-1} and the entire gap is discharged onto the labour-status
    # estimate, with every constraint satisfied to 1e-6 and converged = TRUE.
    # Measured on `panel_ine` with the totals of this function's own @examples
    # (design-weighted per wave, Nhat_1 = 286,880 against N_2 = 254,211, 11.4% apart):
    # the employment rate moves +7.0 points against +0.1 with the scales aligned.
    N_cur <- if ("(Intercept)" %in% names(Xtot)) unname(Xtot[["(Intercept)"]]) else sum(d)
    drift <- if (is.finite(N_cur) && N_cur > 0) abs(N / N_cur - 1) else 0
    if (isTRUE(step$rescale_previous)) {
      if (N > 0 && is.finite(N_cur)) {
        Zhat  <- Zhat * (N_cur / N)
        Zprop <- Zhat / N_cur
        z1    <- z_tm1
        if (any(is_birth))
          z1[is_birth, ] <- matrix(Zprop, sum(is_birth), length(Zprop), byrow = TRUE)
        Z <- (1 - a) * z1 + a * z2
      }
    } else if (drift > 0.01) {
      warning(sprintf(paste0(
        "step_cre(): the population estimated from `previous` (%s) differs by %.1f%% from the ",
        "population `totals` fixes for this wave (%s). `Zhat` is a TOTAL on the previous ",
        "wave's scale while the demographic block fixes this wave's, and the whole difference ",
        "is discharged onto the status estimate -- with every constraint met and ",
        "converged = TRUE. Calibrate both waves to the SAME series of projections, or pass ",
        "rescale_previous = TRUE to put the composite block on proportions."),
        format(round(N), big.mark = ","), 100 * drift,
        format(round(N_cur), big.mark = ",")), call. = FALSE)
    }

    A    <- cbind(X, Z)
    Tvec <- c(Xtot, Zhat)
  }

  # --- solve the (augmented) calibration -------------------------------------
  ds_converged <- TRUE
  if (!step$equal_within_cluster) {
    sol <- .wf_cre_solve(A, d, Tvec, step$calfun, step$bounds)
    g <- sol$g; ds_converged <- sol$converged
    new_w[active] <- d * g
    note_clust <- ""
  } else {
    if (!step$cluster %in% names(data))
      stop(sprintf("Cluster column '%s' not found in the data.", step$cluster), call. = FALSE)
    cl <- as.character(dat_a[[step$cluster]])
    if (anyNA(cl)) stop(sprintf("Cluster column '%s' has missing values (NA).", step$cluster), call. = FALSE)
    hh   <- unique(cl)
    n_h  <- as.numeric(tapply(d, cl, length)[hh])
    Wsum <- as.numeric(tapply(d, cl, sum)[hh])
    .wf_assert_uniform_within_cluster(d, cl, step$cluster)
    Abar <- rowsum(A, group = cl)[hh, , drop = FALSE] / n_h
    sol  <- .wf_cre_solve(Abar, Wsum, Tvec, step$calfun, step$bounds)
    gh <- sol$g; ds_converged <- sol$converged; names(gh) <- hh
    new_w[active] <- d * gh[cl]; g <- gh
    note_clust <- sprintf("; one weight per '%s' (integrative)", step$cluster)
  }

  achieved <- colSums(new_w[active] * A)
  conv_ok  <- ds_converged
  rel_dev  <- abs(achieved - Tvec) / (abs(Tvec) + 1)
  tol_dev  <- if (!is.null(step$bounds) || step$calfun == "logit") 1e-3 else 1e-6
  off <- which(rel_dev > tol_dev)
  if (length(off)) {
    conv_ok <- FALSE
    warning(sprintf(paste0("Composite calibration did not satisfy the constraints for: %s ",
                           "(max relative deviation = %.2e)."),
                    paste(utils::head(colnames(A)[off], 10L), collapse = ", "), max(rel_dev)),
            call. = FALSE)
  }
  diag <- data.frame(variable = colnames(A), target = Tvec,
                     achieved = round(achieved, 2),
                     block = c(rep("x", ncol(X)), rep("z", length(Tvec) - ncol(X))),
                     stringsAsFactors = FALSE)
  attr(diag, "converged") <- conv_ok
  g_unit <- as.numeric(new_w[active] / d)
  attr(diag, "cre_link") <- if (exists("link_diag", inherits = FALSE)) link_diag else NULL
  link_txt <- if (exists("link_diag", inherits = FALSE))
    sprintf("; delta = %.3f (%d linked, %d births, %d unlinked non-births)",
            link_diag$delta, link_diag$n_linked, link_diag$n_birth,
            link_diag$n_missing_prev) else ""
  attr(diag, "note") <- sprintf("CRE g-factor in [%.3f, %.3f]; %d composite aux (z), alpha = %.2f%s%s",
                                min(g_unit), max(g_unit), length(zcols),
                                if (is.null(step$previous)) 0 else step$alpha, link_txt, note_clust)
  # A non-birth unit that does not link carries no t-1 value: with carry_backward it
  # contributes nothing to the change correction, so a large share of them means the
  # composite is doing much less than delta suggests. Say so rather than let the change
  # quietly shrink. (CRE-06)
  # Only outside a replicate: prep() re-runs the recipe once per bootstrap replicate, so
  # a step-level warning would be repeated R times for one recipe (the same reason
  # step_assert() is a no-op there). And the threshold is set where a rate stops looking
  # like ordinary design churn -- a rotating panel legitimately has a few per cent of
  # non-birth units absent from the previous wave; a broken key gives tens of per cent.
  if (!isTRUE(attr(data, "wf_replicate")) &&
      exists("link_diag", inherits = FALSE) && link_diag$n_active > 0 &&
      link_diag$n_missing_prev / link_diag$n_active > 0.20)
    warning(sprintf(paste0("step_cre(): %d of %d non-birth unit(s) (%.1f%%) have no t-1 link, so ",
                           "they carry no previous status and contribute nothing to the composite ",
                           "change correction. Check `id_unit` and the linkage key; a broken link ",
                           "attenuates the estimated change."),
                    link_diag$n_missing_prev, link_diag$n_active,
                    100 * link_diag$n_missing_prev / link_diag$n_active), call. = FALSE)
  # CRE-10. The guard above cannot fire in the DEFAULT branch: with `birth = NULL` every
  # unlinked unit is classified as a birth, so n_missing_prev is 0 by construction and the
  # one warning written to catch a broken key is dead code. The only signal left is the
  # implied overlap: compare it against what the design says. A rotating panel overlaps
  # 5/6, 3/4, 1/2; anything under half, with the births merely inferred, is far more
  # likely a key that does not link than a real rotation. Measured on `panel_ine`: a
  # fully broken `person_no` gave delta 1e-6 and 100% births in a design whose nominal
  # incoming group is 1/6, converged TRUE, silent.
  if (!isTRUE(attr(data, "wf_replicate")) && exists("link_diag", inherits = FALSE) &&
      isTRUE(link_diag$birth_inferred) && link_diag$n_active > 0) {
    nominal <- if (identical(step$overlap, "auto")) NA_real_ else as.numeric(step$overlap)
    rate    <- link_diag$linked_rate
    too_low <- is.finite(rate) &&
      (if (is.na(nominal)) rate < 0.5 else rate < nominal - 0.10)
    if (isTRUE(too_low))
      warning(sprintf(paste0("step_cre(): only %.1f%% of the weight links to `previous`, and %d of ",
                             "%d unit(s) were classified as the incoming rotation group. With no ",
                             "`birth =` declared, an unlinked unit is INDISTINGUISHABLE from a ",
                             "genuine entrant, so a broken key looks like an enormous rotation and ",
                             "the change correction quietly stops working. Check `id_unit` (%s) on ",
                             "a few units of both waves, or declare `birth =` to separate the two."),
                      100 * rate, link_diag$n_birth, link_diag$n_active,
                      paste(idu, collapse = ", ")), call. = FALSE)
  }
  # Conditioning on the RANK-REDUCED system actually solved: the composite blocks are
  # deliberately redundant (country = sum over sex = sum over region), so kappa on the full
  # augmented matrix always looks ill-conditioned. Drop the dependent columns first (QR), so
  # the alert only fires for GENUINE near-collinearity among the independent auxiliaries.
  A_cond <- tryCatch({ qa <- qr(A)
    if (qa$rank < ncol(A)) A[, sort(qa$pivot[seq_len(qa$rank)]), drop = FALSE] else A },
    error = function(e) A)
  attr(diag, "calibrate") <- list(
    g = g_unit, d = as.numeric(d), calfun = step$calfun, bounds = step$bounds,
    cond = .wf_calib_cond(A_cond, d),   # scaled and weighted, as in step_calibrate()
    chi2 = sum(d * (g_unit - 1)^2),
    covars = dat_a[, all.vars(step$formula), drop = FALSE],
    formula = step$formula, active_idx = which(active))
  attr(diag, "cre") <- list(n_z = length(zcols), alpha = if (is.null(step$previous)) NA_real_ else step$alpha,
                            seed = is.null(step$previous))
  list(weights = new_w, diagnostics = diag)
}
