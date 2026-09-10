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
#'   are those not found in `previous` by `id_unit`.
#' @param alpha MR1/MR2 mixing constant between 0 and 1. `alpha = 0` targets the
#'   level only (MR1), `alpha = 1` the change only (MR2). Default 2/3 (Chen and Liu 2002).
#' @param overlap the overlap rate used by the MR2 carry-backward correction: "auto"
#'   (default) estimates it as the `w_nr`-weighted overlap fraction, or a number
#'   (e.g. 5/6, the nominal LFS/ECH rate).
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
#' # `condicion` is the previous-wave labour status (emp / unemp / inact).
#' t1 <- subset(panel_ine, ola == 1 & disp == "R")
#' t2 <- subset(panel_ine, ola == 2 & disp == "R")
#' t1$sexo <- factor(t1$sexo); t2$sexo <- factor(t2$sexo)
#' Xtot <- function(d) colSums(d$w_base * stats::model.matrix(~ sexo, data = d))
#'
#' # seed wave: no previous month, so step_cre() reduces to a linear calibration to X
#' seed <- weighting_spec(t1, base_weights = w_base) |>
#'   step_cre(previous = NULL, status = condicion, formula = ~ sexo,
#'            totals = Xtot(t1), status_ref = "inact") |>
#'   prep()
#'
#' # composite wave: augment X with the previous-wave status, country-level and by sex
#' fit2 <- weighting_spec(t2, base_weights = w_base) |>
#'   step_cre(previous = seed, status = condicion, composite = list(NULL, "sexo"),
#'            id_unit = c("id_hogar", "nper"), formula = ~ sexo, totals = Xtot(t2),
#'            alpha = 2/3, status_ref = "inact") |>
#'   prep()
#' fit2
#' @export
step_cre <- function(spec, previous = NULL, status, composite = list(NULL),
                     id_unit, formula, totals = NULL, count = NULL, birth = NULL,
                     alpha = 2/3, overlap = "auto",
                     on_missing_prev = c("carry_backward", "zero"),
                     cluster = NULL, equal_within_cluster = FALSE,
                     calfun = c("linear", "logit", "raking"), bounds = NULL,
                     rotation_group = NULL, status_ref = NULL, id = NULL) {
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
      on_missing_prev = on_missing_prev,
      cluster     = cluster,
      equal_within_cluster = equal_within_cluster,
      calfun      = calfun,
      bounds      = bounds,
      rotation_group = rotation_group,
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
    G     <- length(glev)
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

    # Link each current active unit to its previous-wave status.
    key_cur  <- do.call(paste, c(lapply(idu, function(v) as.character(dat_a[[v]])), sep = "\r"))
    key_prev <- do.call(paste, c(lapply(idu, function(v) as.character(pdat[[v]])), sep = "\r"))
    prev_status_by_key <- tapply(as.character(pdat[[st]]), key_prev, function(z) z[1])
    prev_status <- unname(prev_status_by_key[key_cur])       # NA if not in previous

    linked <- !is.na(prev_status)                            # found in previous by id_unit
    if (is.null(step$birth)) {
      # No birth expression: every unit without a t-1 link is treated as birth.
      is_birth     <- !linked
      missing_prev <- rep(FALSE, length(d))
    } else {
      bf <- eval(step$birth, envir = dat_a, enclos = step$env %||% baseenv())
      if (length(bf) == 1L) bf <- rep(bf, length(d))
      is_birth <- as.logical(bf); is_birth[is.na(is_birth)] <- FALSE
      # non-birth units without a t-1 link: new members / newly of working age.
      missing_prev <- !is_birth & !linked
      if (identical(step$on_missing_prev, "carry_backward"))
        prev_status[missing_prev] <- as.character(dat_a[[st]])[missing_prev]  # z_{t-1} = z_t
      # (else "zero": leave prev_status NA -> its z_{t-1} row is all zeros below)
    }

    # z at t (current status) and z at t-1 (linked previous status), same columns.
    z_t   <- .wf_cre_zmatrix(as.character(dat_a[[st]]), dat_a, step$composite,
                             status_levels, ref, cell_levels)
    ps    <- prev_status; ps[is.na(ps)] <- ref                # NA -> reference -> zero row
    z_tm1 <- .wf_cre_zmatrix(ps, dat_a, step$composite, status_levels, ref, cell_levels)

    # overlap rate delta (w_nr-weighted) for the MR2 carry-backward correction.
    delta <- if (identical(step$overlap, "auto")) {
      ov <- !is_birth
      s_all <- sum(d); if (s_all > 0) sum(d[ov]) / s_all else 5/6
    } else step$overlap
    delta <- min(max(delta, 1e-6), 1)

    # N (estimated PET total) for MR1's Zhat/N proportion imputation of births.
    N   <- sum(d); Zprop <- if (N > 0) Zhat / N else Zhat * 0

    # MR1 (level): overlap -> z_{t-1}; birth -> Zhat/N.
    z1 <- z_tm1
    if (any(is_birth)) z1[is_birth, ] <- matrix(Zprop, sum(is_birth), length(Zprop), byrow = TRUE)
    # MR2 (change): overlap -> z_{t-1} + (1/delta - 1)(z_{t-1} - z_t); birth -> z_t.
    z2 <- z_tm1 + (1/delta - 1) * (z_tm1 - z_t)
    if (any(is_birth)) z2[is_birth, ] <- z_t[is_birth, ]

    a  <- step$alpha
    Z  <- (1 - a) * z1 + a * z2
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
  attr(diag, "note") <- sprintf("CRE g-factor in [%.3f, %.3f]; %d composite aux (z), alpha = %.2f%s",
                                min(g_unit), max(g_unit), length(zcols),
                                if (is.null(step$previous)) 0 else step$alpha, note_clust)
  # Conditioning on the RANK-REDUCED system actually solved: the composite blocks are
  # deliberately redundant (country = sum over sex = sum over region), so kappa on the full
  # augmented matrix always looks ill-conditioned. Drop the dependent columns first (QR), so
  # the alert only fires for GENUINE near-collinearity among the independent auxiliaries.
  A_cond <- tryCatch({ qa <- qr(A)
    if (qa$rank < ncol(A)) A[, sort(qa$pivot[seq_len(qa$rank)]), drop = FALSE] else A },
    error = function(e) A)
  attr(diag, "calibrate") <- list(
    g = g_unit, d = as.numeric(d), calfun = step$calfun, bounds = step$bounds,
    cond = tryCatch(kappa(crossprod(A_cond), exact = FALSE), error = function(e) NA_real_),
    chi2 = sum(d * (g_unit - 1)^2),
    covars = dat_a[, all.vars(step$formula), drop = FALSE],
    formula = step$formula, active_idx = which(active))
  attr(diag, "cre") <- list(n_z = length(zcols), alpha = if (is.null(step$previous)) NA_real_ else step$alpha,
                            seed = is.null(step$previous))
  list(weights = new_w, diagnostics = diag)
}
