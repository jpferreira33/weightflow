# Panel / longitudinal support: inert descriptors of a rotating-panel structure.
# panel_design() tags stacked per-wave data with its rotation structure (overlap,
# panel-selection probability, linkage quality) the way reference_sample() tags a
# reference survey -- it computes and validates, but does not touch the weights.
# panel_merge() reshapes per-wave frames into the wide, one-row-per-unit
# longitudinal file that the longitudinal recipe consumes. Nothing here changes
# weighting_spec(): the descriptor travels in attributes and the panel steps read
# it from attr(data, "wf_panel").

# Derive the theoretical adjacent-wave overlap and group count implied by a
# rotation pattern string, for verification only. Accepts CEPAL's "k(0)1", the
# CPS "in-out-in" form "4-8-4", and a plain integer "6" (k months in sample).
# Returns NULL when the string cannot be parsed (then no theoretical check runs).
# Rotation calendar from a pattern in the EU-LFS notation `n1-(m1)-n2-(m2)-...`: n_i periods
# in sample, m_i periods out, until the cycle closes. It subsumes everything else as a special
# case -- "6" is a contiguous block (Canada LFS, INE Uruguay ECH), "4-(8)-4" is the US CPS,
# "1-(2)-1-(2)-1-(2)-1-(2)-1" is PNAD Continua's 1-2(5). Returns the 0-indexed periods a cohort
# is in sample and the length of the full cycle.
.wf_pattern_calendar <- function(pattern) {
  if (is.null(pattern) || !is.character(pattern) || length(pattern) != 1L || is.na(pattern))
    return(NULL)
  # TWO notations, told apart by the hyphens:
  #   EU-LFS  "n1-(m1)-n2-(m2)-..."  a list of blocks; a parenthesised block is time OUT.
  #   CEPAL   "n(m)k"                n in, m out, REPEATED k times (k is a repeat count, not
  #                                  another in-block). "4(0)1" is four consecutive periods,
  #                                  not five -- reading the trailing 1 as a block would add a
  #                                  period that does not exist.
  # They are the same family: "1(2)5" is "1-(2)-1-(2)-1-(2)-1-(2)-1".
  tk <- regmatches(pattern, gregexpr("\\(?[0-9]+\\)?", pattern))[[1L]]
  if (!length(tk)) return(NULL)
  num <- suppressWarnings(as.integer(gsub("[()]", "", tk)))
  if (anyNA(num) || any(num < 0L)) return(NULL)
  out <- grepl("(", tk, fixed = TRUE)
  # In the hyphenated form the parentheses are notation, not semantics: "4-8-4" and "4-(8)-4"
  # are the same CPS design. Blocks ALTERNATE in/out starting with in, so when no block is
  # parenthesised the alternation is what decides. (Reading "2-2-2" as six consecutive periods
  # would turn a 0.50 overlap into 0.83 and make PN-01 fire on a correctly declared design.)
  if (length(tk) > 1L && !any(out)) out <- seq_along(tk) %% 2L == 0L
  per <- integer(0); t <- 0L
  if (!grepl("-", pattern, fixed = TRUE) && length(tk) == 3L && out[2L] && !out[1L] && !out[3L]) {
    n <- num[1L]; m <- num[2L]; k <- max(num[3L], 1L)    # CEPAL n(m)k
    for (i in seq_len(k)) {
      per <- c(per, t + seq_len(n) - 1L); t <- t + n
      if (i < k) t <- t + m                              # el ultimo bloque no descansa
    }
  } else {
    for (i in seq_along(tk)) {
      if (out[i]) t <- t + num[i]
      else { per <- c(per, t + seq_len(num[i]) - 1L); t <- t + num[i] }
    }
  }
  if (!length(per) || t < 1L) return(NULL)
  list(periods = per, cycle = t)
}

# Expected overlap BY LAG, derived from the calendar rather than from the first block.
#
# The previous implementation read only the first block and returned (n1 - 1)/n1, which is
# wrong in three ways that all matter in production:
#   (a) patterns with parentheses and more than three blocks did not parse at all -- they fell
#       through to the plain-integer branch, k came out 1, and the function returned NULL, so
#       alert PN-01 never fired for them. That is exactly where it is most needed: an in-out-in
#       design can have ZERO theoretical overlap at lag 1, and without the check there is no way
#       to tell "the design is like that" from "the unit key is broken";
#   (b) (n_i - 1)/n_i is not the adjacent overlap once there is more than one block. For
#       "3-(1)-2" the true value is 3/5 = 0.60, not 2/3 = 0.67 -- one has to count consecutive
#       period PAIRS over the periods in sample, not look at the first block alone;
#   (c) `n_groups` conflated two different numbers: the groups simultaneously IN SAMPLE
#       (n1 + n3) and the length of the cycle (n1 + m1 + n2). For "2-(2)-2" those are 4 and 6.
#       They are now `n_in` and `cycle`, named for what they are.
#
# The profile is the fraction of a period's sample also present `lag` periods earlier, obtained
# by intersecting the calendar with itself shifted. `overlap` is kept as the lag-1 scalar so the
# existing PN-01 comparison keeps its meaning. (PN-01/parser, 2026-09-09)
.wf_pattern_overlap <- function(pattern, max_lag = 12L) {
  cal <- .wf_pattern_calendar(pattern)
  if (is.null(cal)) return(NULL)
  per <- cal$periods; G <- cal$cycle
  # cohorts in sample at time `t`: those whose entry offset puts `t` inside their spell
  occupies <- function(t) { s <- seq.int(t - G - max(per) - 2L, t); s[(t - s) %in% per] }
  base <- occupies(1000L)
  if (!length(base)) return(NULL)
  prof <- vapply(seq_len(max_lag),
                 function(L) length(intersect(base, occupies(1000L - L))) / length(base),
                 numeric(1))
  names(prof) <- as.character(seq_len(max_lag))
  list(periods = per, cycle = G, n_in = length(per),
       profile = prof, overlap = unname(prof[1L]),
       lags = as.integer(names(prof))[prof > 1e-9])
}

#' Describe the rotating-panel structure of a survey
#'
#' Tags stacked per-wave survey data with its rotation structure so the panel
#' steps and the report can read it, and so the overlap and linkage quality can
#' be inspected *before* any weighting. `panel_design()` computes only; it does
#' not create or change weights. It is the panel analogue of [reference_sample()]:
#' the descriptor lives in `attr(data, "wf_panel")` and the returned object is
#' still an ordinary `data.frame`.
#'
#' `data` must be in **stacked (long) form**: one row per unit per wave, with a
#' `unit` column that is stable across waves and a `wave` column identifying the
#' period. From the `unit` x `wave` membership it derives the observed overlap
#' matrix (the fraction of each wave retained in every other wave, i.e. CEPAL's
#' *traslape*), and, when `rotation_group` is given, the panel-selection
#' probability `Pr(panel selection)` for each adjacent pair and for the full
#' combination -- the reciprocal of which is the CEPAL panel base-weight factor.
#'
#' The linkage quality is measured, not assumed: if a `pattern` is supplied the
#' observed adjacent overlap is compared against the one it implies, and a large
#' gap (alert `PN-01`) is the early warning that the linkage key is unstable
#' (relabelled ids, a redesigned frame, duplicated panels). Uneven rotation-group
#' sizes, which break the scalar reciprocal of `Pr(panel selection)`, raise
#' `PN-02`.
#'
#' @param data a stacked `data.frame`, one row per unit per wave.
#' @param unit one or more column names (a character vector) that together
#'   identify the longitudinal unit, stable across waves. A household is often a
#'   single id (`"ID"`); a person needs several (`c("ID", "nper")` = household id
#'   plus person line number). The columns are pasted into the tracking key.
#' @param wave string: the column holding the wave/period.
#' @param rotation_group optional string: the column holding the rotation group /
#'   panel. Needed to derive `Pr(panel selection)` exactly; without it that field
#'   is left `NA` and only the unit-level overlap is computed.
#' @param cluster optional one or more column names identifying a within-unit
#'   cluster (e.g. the household `"ID"`) when the tracked unit is a person but the
#'   overlap is realised at the household level.
#' @param pattern optional string describing the rotation scheme, for verification
#'   only: CEPAL's `"4(0)1"`, the CPS `"4-8-4"`, or a plain integer like `"6"`.
#'   Nothing in the computation depends on parsing it.
#' @param waves optional character vector giving the wave order explicitly;
#'   defaults to `sort(unique(data[[wave]]))`.
#' @param reference_wave optional wave whose population the longitudinal weight
#'   represents (the calibration target for a longitudinal recipe); defaults to
#'   the first wave. Read by [step_longitudinal()].
#' @return `data`, unchanged as a data frame, with the descriptor in
#'   `attr(data, "wf_panel")` and class `"wf_panel_design"` prepended.
#' @seealso [panel_merge()], [reference_sample()]
#' @examples
#' # person-level tracking: the key is household id + person line number
#' pd <- panel_design(panel_ine, unit = c("id_hogar", "nper"), wave = "ola",
#'                    rotation_group = "grupo_rotacion", cluster = "id_hogar",
#'                    pattern = "6")
#' pd            # overlap matrix, Pr(panel selection), linkage rate, alerts
#' summary(pd)
#' @export
panel_design <- function(data, unit, wave, rotation_group = NULL,
                         cluster = NULL, pattern = NULL, waves = NULL,
                         reference_wave = NULL) {
  if (!is.data.frame(data))
    stop("`data` must be a data.frame in stacked (long) form: one row per unit per wave.",
         call. = FALSE)
  if (missing(unit) || missing(wave))
    stop("`unit` and `wave` are required.", call. = FALSE)
  chk_cols <- function(x, nm, multiple = FALSE) {
    if (is.null(x)) return(invisible())
    if (!is.character(x) || anyNA(x) || !length(x) || (!multiple && length(x) != 1L))
      stop(sprintf("`%s` must be %s.", nm,
                   if (multiple) "one or more column names (a character vector)"
                   else "a single column name (string)"), call. = FALSE)
    miss <- setdiff(x, names(data))
    if (length(miss))
      stop(sprintf("Column(s) %s (`%s`) not found in `data`.",
                   paste(sprintf("'%s'", miss), collapse = ", "), nm), call. = FALSE)
  }
  chk_cols(unit, "unit", multiple = TRUE); chk_cols(wave, "wave")
  chk_cols(rotation_group, "rotation_group"); chk_cols(cluster, "cluster", multiple = TRUE)

  # Build the unit key -- one column, or several pasted together (e.g. a person
  # is household ID + person line number). SEP is a control char unlikely in ids.
  if (anyNA(data[unit]))
    stop("`unit` column(s) must not contain NA (every row is a unit-wave observation).",
         call. = FALSE)
  u <- if (length(unit) == 1L) as.character(data[[unit]])
       else do.call(paste, c(lapply(unit, function(k) as.character(data[[k]])), sep = "\r"))
  wv_raw <- as.character(data[[wave]])
  if (anyNA(wv_raw))
    stop("`wave` must not contain NA (every row is a unit-wave observation).",
         call. = FALSE)
  wlev <- if (is.null(waves)) sort(unique(wv_raw)) else as.character(waves)
  if (!all(wv_raw %in% wlev))
    stop("`waves` must list every value present in the `wave` column.", call. = FALSE)
  ref_wave <- if (is.null(reference_wave)) wlev[1L] else as.character(reference_wave)
  if (length(ref_wave) != 1L || !ref_wave %in% wlev)
    stop("`reference_wave` must be one of the waves.", call. = FALSE)
  W <- length(wlev)
  if (W < 2L)
    stop("A panel needs at least 2 waves; found ", W, ".", call. = FALSE)
  wv <- factor(wv_raw, levels = wlev)

  # A unit key may legitimately repeat within a wave when the tracked unit is
  # coarser than the data row -- e.g. tracking the household (`unit = "ID"`) on
  # person-level microdata, where a household has one row per member. Membership
  # is presence-based (>= 1 row per unit-wave), so duplicates are handled without
  # aggregating: overlap and counts are over distinct units, not rows.

  # Membership (units x waves) and the directional overlap matrix.
  tab     <- table(u, wv)
  present <- matrix(as.integer(tab > 0L), nrow(tab), ncol(tab),
                    dimnames = dimnames(tab))        # units x waves, 0/1 (plain matrix)
  nw      <- colSums(present)                        # sample size per wave
  inter   <- crossprod(present)                      # waves x waves, |i and j|
  overlap <- inter / nw                              # overlap[i, j] = |i cap j| / |i|
  dimnames(overlap) <- list(wlev, wlev)
  waves_per_unit <- rowSums(present)
  n_units  <- nrow(present)
  n_linked <- sum(waves_per_unit >= 2L)

  # Panel-selection probability from rotation-group *cohort* continuity. A group
  # is coincident between two waves when its units are present in both -- detected
  # through unit overlap, not the group label, because labels are recycled when a
  # group rotates out and a new cohort enters under the same label.
  pr_adjacent  <- rep(NA_real_, W - 1L)
  pr_lag       <- rep(NA_real_, W - 1L)     # continuidad de cohortes por REZAGO
  pr_full      <- NA_real_
  grp_sizes    <- NULL
  cohort_sizes <- NULL
  n_groups     <- NA_integer_
  if (!is.null(rotation_group)) {
    g  <- as.character(data[[rotation_group]])
    ug <- tapply(g, u, function(z) z[1L])            # unit -> group (kept across waves)
    grp_of    <- ug[rownames(present)]               # group per unit, in `present` order
    groups_in <- function(sel) length(unique(grp_of[sel]))
    for (i in seq_len(W - 1L)) {
      gi <- groups_in(present[, i] > 0)
      pr_adjacent[i] <- if (gi > 0L)
        groups_in(present[, i] > 0 & present[, i + 1L] > 0) / gi else NA_real_
    }
    # Continuidad por rezago: promedio sobre los pares de olas separados por L. Hace falta
    # para chequear patrones NO contiguos, donde el rezago informativo no es el 1.
    for (L in seq_len(W - 1L)) {
      v <- vapply(seq_len(W - L), function(i) {
        gi <- groups_in(present[, i] > 0)
        if (gi > 0L) groups_in(present[, i] > 0 & present[, i + L] > 0) / gi else NA_real_
      }, numeric(1))
      pr_lag[L] <- if (any(is.finite(v))) mean(v[is.finite(v)]) else NA_real_
    }
    g1 <- groups_in(present[, 1L] > 0)
    pr_full   <- if (g1 > 0L) groups_in(waves_per_unit == W) / g1 else NA_real_
    cells        <- as.integer(table(g, wv)); grp_sizes <- cells[cells > 0L]  # units per group-wave
    cohort_sizes <- as.integer(table(ug))            # units SELECTED per rotation-group cohort
    n_groups     <- length(unique(g))
  }

  # Theoretical overlap from the pattern, and the alerts.
  th <- .wf_pattern_overlap(pattern)
  obs_adjacent <- vapply(seq_len(W - 1L),
                         function(i) overlap[i, i + 1L], numeric(1))
  obs_lag <- vapply(seq_len(W - 1L),
                    function(L) mean(vapply(seq_len(W - L),
                                            function(i) overlap[i, i + L], numeric(1))),
                    numeric(1))
  alerts <- character(0)
  if (!is.null(th)) {
    # PN-01 targets a *broken linkage key*, not ordinary attrition. When the rotation group is
    # known, the clean check is group-cohort continuity, which should match the pattern closely
    # if the key is sound; unit overlap sits below nominal because of attrition, so without
    # groups we only flag a large shortfall.
    #
    # The check runs over the WHOLE overlap profile, not only the adjacent lag. In an in-out-in
    # design the informative lag is not lag 1: "1-(3)-1-(3)-1-(3)-1" has zero theoretical
    # overlap quarter to quarter and 0.75 at lag 4, so an adjacent-only comparison can say
    # nothing about it. (PN-01 profile, 2026-09-09)
    have_pr <- !all(is.na(pr_lag))
    ref     <- if (have_pr) pr_lag else obs_lag
    tol     <- if (have_pr) 0.05 else 0.15
    Lmax    <- min(W - 1L, length(th$profile))
    Ls      <- seq_len(Lmax)
    expct   <- unname(th$profile[Ls])
    short   <- expct - ref[Ls]
    hit     <- which(is.finite(short) & short > tol & expct > 1e-9)
    if (length(hit)) {
      j <- hit[which.max(short[hit])]                 # report the worst lag
      alerts <- c(alerts, sprintf(paste0(
        "[PN-01] %s at lag %d (%.2f) is below the %.2f implied by pattern '%s' by more than ",
        "%.2f; the linkage key may be unstable across waves%s."),
        if (have_pr) "Rotation-group continuity" else "Observed overlap",
        j, ref[j], expct[j], pattern, tol,
        if (have_pr) "" else " (or attrition is unusually high)"))
    }
    # The mirror case: the pattern says these two periods share NO sample, yet they do. That is
    # not attrition -- attrition can only remove overlap -- so it means the declared pattern and
    # the data disagree, or the unit key collides across cohorts.
    # The zero-overlap contradiction can only be asserted once the observation window covers a
    # full cycle. The profile describes a STEADY STATE; a panel observed for fewer periods than
    # its own cycle has not had time to reach it, and its cohorts are still staggered by the
    # start-up. The shipped `panel_cl` is exactly that case -- three waves standing in for a
    # six-period 2-(2)-2, with the return compressed into lag 2 on purpose (see ?panel_datasets)
    # -- and flagging it would be an artefact of the window, not a finding about the data.
    zero  <- if (is.finite(th$cycle) && W >= th$cycle)
      which(expct < 1e-9 & is.finite(ref[Ls]) & ref[Ls] > max(tol, 0.15)) else integer(0)
    if (length(zero)) {
      j <- zero[which.max(ref[zero])]
      alerts <- c(alerts, sprintf(paste0(
        "[PN-07] Pattern '%s' implies NO overlap at lag %d, but %.2f of the sample is shared ",
        "there. The declared pattern and the data disagree, or the `unit` key is reused across ",
        "rotation cohorts."), pattern, j, ref[j]))
    }
  }
  if (!is.null(cohort_sizes) && length(cohort_sizes) > 1L) {
    # Measure unequal SELECTION, not attrition/tenure: use the number of units
    # selected into each rotation-group COHORT (table over unit -> group), not the
    # group-x-wave cells -- pooling those would flag a sliding rotation (groups of
    # different tenure, and older cohorts thinned by attrition) as if the panels had
    # unequal probabilities. Achieved cohort sizes still vary ~10-20% from chance, so
    # only a gross imbalance fires.
    spread <- (max(cohort_sizes) - min(cohort_sizes)) / mean(cohort_sizes)
    if (is.finite(spread) && spread > 0.25)
      alerts <- c(alerts, paste0(
        "[PN-02] Rotation-group cohorts have very uneven sizes (spread ",
        sprintf("%.0f%%", 100 * spread),
        "); the scalar reciprocal of Pr(panel selection) assumes equal-probability ",
        "panels -- supply an explicit selection probability instead."))
  }
  if (n_linked == 0L)
    alerts <- c(alerts, paste0(
      "[PN-06] No unit links across two or more waves: the `unit` key does not ",
      "match between waves, so no change or longitudinal estimate is possible."))

  attr(data, "wf_panel") <- list(
    unit = unit, wave = wave, rotation_group = rotation_group, cluster = cluster,
    waves = wlev, reference_wave = ref_wave, pattern = pattern, n_groups = n_groups,
    n_units = n_units, n_linked = n_linked,
    link_rate = n_linked / n_units,
    max_waves = max(waves_per_unit),
    n_per_wave = stats::setNames(as.integer(nw), wlev),
    overlap = overlap,
    overlap_theoretical = if (is.null(th)) NA_real_ else th$overlap,
    overlap_profile = if (is.null(th)) NULL else th$profile,
    pattern_lags = if (is.null(th)) NULL else th$lags,
    pattern_n_in = if (is.null(th)) NA_integer_ else th$n_in,
    pattern_cycle = if (is.null(th)) NA_integer_ else th$cycle,
    obs_lag = obs_lag,
    pr_adjacent = pr_adjacent, pr_lag = pr_lag, pr_full = pr_full, grp_sizes = grp_sizes,
    alerts = alerts)
  class(data) <- unique(c("wf_panel_design", class(data)))
  data
}

#' @export
print.wf_panel_design <- function(x, ...) {
  p <- attr(x, "wf_panel")
  cat("<weightflow panel design>\n")
  cat(sprintf("  waves      : %d (%s)\n", length(p$waves),
              paste(p$waves, collapse = ", ")))
  cat(sprintf("  unit       : %s%s\n", paste(p$unit, collapse = " + "),
              if (is.null(p$cluster)) "" else
                sprintf("  (cluster: %s)", paste(p$cluster, collapse = " + "))))
  cat(sprintf("  rotation   : %s%s\n",
              if (is.null(p$rotation_group)) "(none)" else p$rotation_group,
              if (is.null(p$pattern)) "" else sprintf("  pattern: %s", p$pattern)))
  cat(sprintf("  units      : %d (linked in >=2 waves: %d, %.0f%%)\n",
              p$n_units, p$n_linked, 100 * p$link_rate))
  cat("  overlap (row wave retained in column wave):\n")
  om <- formatC(p$overlap, format = "f", digits = 2)
  print(as.table(structure(om, dim = dim(p$overlap), dimnames = dimnames(p$overlap))),
        quote = FALSE)
  if (!all(is.na(p$pr_adjacent)))
    cat(sprintf("  Pr(panel selection), adjacent : %s%s\n",
                paste(sprintf("%.3f", p$pr_adjacent), collapse = ", "),
                if (is.finite(p$pr_full)) sprintf("  (full combination: %.3f)", p$pr_full) else ""))
  if (!is.null(p$overlap_profile)) {
    # El perfil completo, no solo el adyacente: en un diseno con hueco el rezago informativo
    # no es el 1, y mostrar un unico numero esconde justamente lo que hay que mirar.
    L <- min(length(p$waves) - 1L, 6L, length(p$overlap_profile))
    cat(sprintf("  overlap implied by pattern    : %s   (lag %s)\n",
                paste(sprintf("%.2f", p$overlap_profile[seq_len(L)]), collapse = " "),
                paste(seq_len(L), collapse = " ")))
    if (!is.na(p$pattern_cycle))
      cat(sprintf("  pattern                       : %d group(s) in sample, cycle %d, useful lags %s\n",
                  p$pattern_n_in, p$pattern_cycle,
                  paste(utils::head(p$pattern_lags, 8L), collapse = ", ")))
  } else if (!is.na(p$overlap_theoretical))
    cat(sprintf("  overlap implied by pattern    : %.2f\n", p$overlap_theoretical))
  if (length(p$alerts)) {
    cat("  alerts:\n")
    for (a in p$alerts) cat("   -", a, "\n")
  }
  invisible(x)
}

#' @export
summary.wf_panel_design <- function(object, ...) {
  p <- attr(object, "wf_panel")
  structure(list(
    waves = p$waves, n_units = p$n_units, n_linked = p$n_linked,
    link_rate = p$link_rate, n_per_wave = p$n_per_wave, overlap = p$overlap,
    overlap_theoretical = p$overlap_theoretical,
    pr_adjacent = p$pr_adjacent, pr_full = p$pr_full,
    grp_sizes = p$grp_sizes, alerts = p$alerts),
    class = "summary.wf_panel_design")
}

#' @export
print.summary.wf_panel_design <- function(x, ...) {
  cat("Panel design summary\n")
  cat(sprintf("  waves            : %s\n", paste(x$waves, collapse = ", ")))
  cat(sprintf("  n per wave       : %s\n",
              paste(sprintf("%s=%d", names(x$n_per_wave), x$n_per_wave), collapse = ", ")))
  cat(sprintf("  units (linked)   : %d (%d, %.1f%%)\n",
              x$n_units, x$n_linked, 100 * x$link_rate))
  cat("  overlap matrix:\n")
  print(round(x$overlap, 3))
  if (length(x$alerts)) { cat("  alerts:\n"); for (a in x$alerts) cat("   -", a, "\n") }
  invisible(x)
}

#' Build the wide longitudinal file from per-wave surveys
#'
#' Joins a named list of per-wave `data.frame`s on a stable unit key into the
#' wide, one-row-per-unit file that the longitudinal recipe consumes. Each wave's
#' non-key columns are suffixed with the wave name, and per-wave presence
#' indicators `.wf_in_<wave>` (and, if `responded` is given, response indicators
#' `.wf_resp_<wave>`) are added so a later `step_attrition()` can model the
#' response pattern.
#'
#' `require = "any"` (the default) keeps every unit seen in at least one wave --
#' which the attrition model needs, because it has to be fitted over responders
#' *and* non-responders. `require = "all"` keeps only the intersection (CEPAL's
#' `s(2) = s1 cap s2 cap ...`); prefer to reach it with `step_attrition()` after
#' estimating, not by dropping units before the model can see them.
#'
#' @param waves a **named** list of per-wave `data.frame`s; the names become the
#'   wave labels and column suffixes.
#' @param by one or more column names (a character vector) forming the unit key,
#'   present in every wave -- e.g. `"ID"` for a household or `c("ID", "nper")` for
#'   a person.
#' @param responded optional string: the name of a response indicator present in
#'   every wave, used to build `.wf_resp_<wave>`.
#' @param require one of `"any"` (union of units, default) or `"all"`
#'   (intersection).
#' @param suffix string inserted before the wave label when renaming columns
#'   (default `"_"`), e.g. `edad` in wave `T1` becomes `edad_T1`.
#' @return a wide `data.frame`, one row per unit, ready for [panel_design()] /
#'   `weighting_spec()`.
#' @seealso [panel_design()]
#' @examples
#' # reshape two waves of the long panel into one wide, one-row-per-unit file
#' wide <- panel_merge(
#'   list(T1 = subset(panel_ine, ola == 1), T2 = subset(panel_ine, ola == 2)),
#'   by = c("id_hogar", "nper"), require = "any")
#' names(wide)                       # per-wave columns are suffixed _T1 / _T2
#' @export
panel_merge <- function(waves, by, responded = NULL,
                        require = c("any", "all"), suffix = "_") {
  require <- match.arg(require)
  if (!is.list(waves) || is.null(names(waves)) || any(!nzchar(names(waves))))
    stop("`waves` must be a NAMED list of per-wave data.frames.", call. = FALSE)
  if (length(waves) < 2L)
    stop("`waves` needs at least 2 waves.", call. = FALSE)
  if (!is.character(by) || anyNA(by) || !length(by))
    stop("`by` must be one or more column names (a character vector).", call. = FALSE)
  if (!is.character(suffix) || length(suffix) != 1L)
    stop("`suffix` must be a single string.", call. = FALSE)
  wn <- names(waves)

  prep_one <- function(df, nm) {
    if (!is.data.frame(df)) stop("Each element of `waves` must be a data.frame.", call. = FALSE)
    miss <- setdiff(by, names(df))
    if (length(miss)) stop(sprintf("`by` column(s) %s not found in wave '%s'.",
                                   paste(sprintf("'%s'", miss), collapse = ", "), nm), call. = FALSE)
    if (!is.null(responded) && !responded %in% names(df))
      stop(sprintf("`responded` column '%s' not found in wave '%s'; a typo would otherwise make .wf_resp_%s all NA silently.",
                   responded, nm, nm), call. = FALSE)
    if (anyNA(df[by])) stop(sprintf("`by` column(s) have NA in wave '%s'.", nm), call. = FALSE)
    if (anyDuplicated(df[, by, drop = FALSE]))
      stop(sprintf("`by` key is not unique in wave '%s' (a unit appears more than once).", nm),
           call. = FALSE)
    keycol <- df[, by, drop = FALSE]
    rest   <- df[, setdiff(names(df), by), drop = FALSE]
    if (ncol(rest)) names(rest) <- paste0(names(rest), suffix, nm)
    out <- cbind(keycol, rest)
    out[[paste0(".wf_in_", nm)]] <- 1L
    if (!is.null(responded)) {
      rc <- paste0(responded, suffix, nm)
      out[[paste0(".wf_resp_", nm)]] <- if (rc %in% names(out))
        as.integer(as.logical(out[[rc]])) else NA_integer_
    }
    out
  }

  parts <- Map(prep_one, waves, wn)
  all <- (require == "any")
  wide <- Reduce(function(a, b) merge(a, b, by = by, all = all), parts)
  for (nm in wn) {
    col <- paste0(".wf_in_", nm)
    wide[[col]][is.na(wide[[col]])] <- 0L
  }
  wide
}

# Pr(panel selection) for a set of combined `waves`, from rotation-group cohort
# continuity: (# rotation groups whose units are present in ALL the waves) /
# (# groups present in the first wave). `data` must be tagged by panel_design()
# and carry a rotation_group. Returns a single probability in (0, 1].
.wf_panel_pr <- function(data, waves) {
  p <- attr(data, "wf_panel")
  if (is.null(p))
    stop("data must be tagged by panel_design().", call. = FALSE)
  if (is.null(p$rotation_group))
    stop("panel_design() needs a `rotation_group` to derive Pr(panel selection).",
         call. = FALSE)
  if (is.null(waves)) waves <- p$waves
  miss <- setdiff(waves, p$waves)
  if (length(miss))
    stop(sprintf("waves %s are not in the panel_design().",
                 paste(sprintf("'%s'", miss), collapse = ", ")), call. = FALSE)
  if (length(waves) < 2L)
    stop("`waves` must name at least 2 combined waves.", call. = FALSE)
  key <- p$unit
  u <- if (length(key) == 1L) as.character(data[[key]])
       else do.call(paste, c(lapply(key, function(k) as.character(data[[k]])), sep = "\r"))
  wv <- as.character(data[[p$wave]])
  g  <- as.character(data[[p$rotation_group]])
  keep <- wv %in% waves
  u <- u[keep]; wv <- wv[keep]; g <- g[keep]
  ug      <- tapply(g, u, function(z) z[1L])           # unit -> group
  present <- table(u, factor(wv, levels = waves)) > 0
  uni     <- rownames(present)
  in_all  <- rowSums(present) == length(waves)
  gall <- length(unique(ug[uni][in_all]))
  gw1  <- length(unique(ug[uni][present[, 1L]]))
  if (gw1 == 0L) return(NA_real_)
  gall / gw1
}

#' Panel-selection probability for a set of combined waves
#'
#' Returns `Pr(panel selection)` for combining `waves` in a [panel_design()] that
#' carries a `rotation_group`: the fraction of rotation-group cohorts present in
#' *all* the combined waves. Its reciprocal is the CEPAL panel base-weight factor
#' used by [step_panel_overlap()] (`prob = panel_pr(pd, c("T1","T2"))`). Surveys
#' without a public rotation-group variable (e.g. the Chilean ENE) cannot use this
#' -- derive the probability another way and pass it to `step_panel_overlap()`.
#'
#' @param object a `wf_panel_design` (from [panel_design()]).
#' @param waves optional character vector of the combined waves; defaults to all.
#' @return a single probability in `(0, 1]`.
#' @seealso [panel_design()], [step_panel_overlap()]
#' @examples
#' pd <- panel_design(panel_ine, unit = c("id_hogar", "nper"), wave = "ola",
#'                    rotation_group = "grupo_rotacion")
#' panel_pr(pd)                    # over all waves
#' panel_pr(pd, c("1", "2"))       # combining waves 1 and 2
#' @export
panel_pr <- function(object, waves = NULL) {
  if (!inherits(object, "wf_panel_design"))
    stop("`object` must come from panel_design().", call. = FALSE)
  .wf_panel_pr(object, waves)
}
