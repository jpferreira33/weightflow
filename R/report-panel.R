# HTML report cards for panel / longitudinal work, ADDED to the existing report and reusing its
# helpers and classes (.report_css / .t / .html_escape / .metric / .tw / .chart_figure / table).
# Every card goes through .panel_card(): headline numbers as a strip across the top, then a body
# that is either full width or a real two-column split. Nothing here overrides a base style; the
# panel-specific pieces are the inline-SVG visuals (Sankey, comparison bars) and the heat matrix,
# and all three take their colours from the report's tokens (--c1..--c6, --heat) so they follow
# the light/dark scheme like every other chart.

# make an .svg_frame() SVG fill its container width
.wf_fullsvg <- function(svg) sub("<svg ", "<svg style=\"width:100%;height:auto\" ", svg, fixed = TRUE)

# heat-mapped matrix as a plain <table> (styled by the report's generic table CSS) with an inline
# cell background by value; optional per-cell SE. No CSS class -> no collision with the original.
.wf_heat_table <- function(m, se = NULL, digits = 3, rowlab = "") {
  fr <- rownames(m); to <- colnames(m)
  fin <- m[is.finite(m)]; rng <- range(c(fin, 0)); span <- max(rng[2] - rng[1], 1e-9)
  th <- paste0("<th class='rh'>", .html_escape(rowlab), "</th>",
               paste0("<th class='numc'>", vapply(to, .html_escape, character(1)), "</th>",
                      collapse = ""))
  rows <- vapply(seq_len(nrow(m)), function(i) {
    tds <- vapply(seq_len(ncol(m)), function(j) {
      v <- m[i, j]
      a <- if (is.finite(v)) 0.08 + 0.55 * (v - rng[1]) / span else 0
      txt <- if (is.finite(v)) formatC(v, format = "f", digits = digits) else "&ndash;"
      if (!is.null(se) && is.finite(se[i, j]))
        txt <- sprintf("%s <span class='se'>(%.3f)</span>", txt, se[i, j])
      # the hue is a token (--heat), only the alpha varies with the value, so the
      # ramp stays legible in the dark scheme instead of freezing a light blue
      sprintf("<td class='h' style='background:rgba(var(--heat),%.2f)'>%s</td>", a, txt)
    }, character(1))
    sprintf("<tr><th class='rh'>%s</th>%s</tr>", .html_escape(fr[i]),
            paste0(tds, collapse = ""))
  }, character(1))
  .tw(sprintf("<table class='heat'><thead><tr>%s</tr></thead><tbody>%s</tbody></table>",
              th, paste0(rows, collapse = "")))
}

.alerts_html <- function(al) {
  if (is.null(al) || !length(al)) return("")
  sprintf("<div class='alert'><ul>%s</ul></div>",
          paste0("<li>", vapply(al, .html_escape, character(1)), "</li>", collapse = ""))
}

# Sankey / alluvial of a gross-flow COUNTS matrix (new visualisation).
.wf_svg_sankey <- function(counts, lang = "en", w = 600, h = 280) {
  m <- counts; tot <- sum(m, na.rm = TRUE)
  if (!is.finite(tot) || tot <= 0) return("")
  fr <- rownames(m); to <- colnames(m); rt <- rowSums(m); ct <- colSums(m)
  pad <- 14; nodew <- 12; gap <- 14; xL <- 104; xR <- w - 104
  Hn <- h - 2 * pad - gap * (max(length(fr), length(to)) - 1)
  sc <- Hn / tot
  ly <- numeric(length(fr)); y <- pad
  for (i in seq_along(fr)) { ly[i] <- y; y <- y + rt[i] * sc + gap }
  ry <- numeric(length(to)); y <- pad
  for (j in seq_along(to)) { ry[j] <- y; y <- y + ct[j] * sc + gap }
  loff <- ly; roff <- ry
  x0 <- xL + nodew; x1 <- xR - nodew; xc <- (x0 + x1) / 2
  rib <- ""
  for (i in seq_along(fr)) for (j in seq_along(to)) {
    f <- m[i, j]; if (!is.finite(f) || f <= 0) next
    thk <- f * sc; a0 <- loff[i]; a1 <- a0 + thk; loff[i] <- a1
    b0 <- roff[j]; b1 <- b0 + thk; roff[j] <- b1
    d <- sprintf("M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f L%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f Z",
                 x0, a0, xc, a0, xc, b0, x1, b0, x1, b1, xc, b1, xc, a1, x0, a1)
    rib <- paste0(rib, sprintf("<path class='p%d' d='%s' fill-opacity='0.42'/>",
                               ((i - 1) %% 6L) + 1L, d))
  }
  nod <- ""
  pc <- function(x) sprintf("%.0f%%", 100 * x / tot)
  for (i in seq_along(fr)) { nh <- max(rt[i] * sc, 0.6)
    nod <- paste0(nod, sprintf(paste0("<rect class='p%d' x='%.1f' y='%.1f' width='%d' height='%.1f' rx='2'/>",
                  "<text class='p-lab' x='%.1f' y='%.1f' text-anchor='end'>%s</text>",
                  "<text class='p-val' x='%.1f' y='%.1f' text-anchor='end'>%s</text>"),
                  ((i - 1) %% 6L) + 1L, xL, ly[i], nodew, nh,
                  xL - 6, ly[i] + nh / 2, .html_escape(fr[i]),
                  xL - 6, ly[i] + nh / 2 + 12, pc(rt[i]))) }
  for (j in seq_along(to)) { nh <- max(ct[j] * sc, 0.6)
    nod <- paste0(nod, sprintf(paste0("<rect class='p-node' x='%.1f' y='%.1f' width='%d' height='%.1f' rx='2'/>",
                  "<text class='p-lab' x='%.1f' y='%.1f'>%s</text>",
                  "<text class='p-val' x='%.1f' y='%.1f'>%s</text>"),
                  xR - nodew, ry[j], nodew, nh,
                  xR + 6, ry[j] + nh / 2, .html_escape(to[j]),
                  xR + 6, ry[j] + nh / 2 + 12, pc(ct[j]))) }
  .wf_fullsvg(.svg_frame(paste0(rib, nod), w, h,
              .t("transition flows", "flujos de transici\u00f3n", lang), lang))
}

# two proportional bars (A/B comparison), responsive width (new visualisation)
.wf_svg_bars2 <- function(frac2, cols, labs, vals, x_lab = 150, w = 580, h = 92,
                          lang = "en", title = NULL) {
  fw <- w - x_lab - 96
  one <- function(y, frac, cls, lab, val) sprintf(
    paste0("<text class='p-lab' x='%d' y='%d' text-anchor='end'>%s</text>",
           "<rect class='p-track' x='%d' y='%d' width='%.1f' height='20' rx='3'/>",
           "<rect class='%s' x='%d' y='%d' width='%.1f' height='20' rx='3'/>",
           "<text class='p-val' x='%.1f' y='%d'>%s</text>"),
    x_lab - 10, y + 14, lab, x_lab, y, fw, cls, x_lab, y, max(fw * frac, 1),
    x_lab + 10 + fw * frac, y + 14, val)
  svg <- .wf_fullsvg(.svg_frame(
    paste0(one(14, frac2[1], cols[1], labs[1], vals[1]),
           one(52, frac2[2], cols[2], labs[2], vals[2])), w, h,
    .t("comparison", "comparaci\u00f3n", lang), lang))
  .chart_figure(svg, title)
}


# One card shell for every panel card: the headline numbers become a strip across
# the top (they scan horizontally, like the report's own header tiles) and the
# body below gets the full width. The previous layout dropped `.ddc-facts` into
# one half of a `.cols` grid, where each `.metric` (flex:1;min-width:120px) wrapped
# onto its own row -- a column of six full-width tiles beside an empty half page.
.panel_card <- function(title, metrics, body, note = "", feature = FALSE, wide = FALSE) {
  cls  <- if (feature) "meta feature" else "meta"
  strip <- if (nzchar(metrics)) sprintf("<div class='strip'>%s</div>", metrics) else ""
  bcls <- if (wide) "panel-body wide" else "panel-body"
  bd   <- if (nzchar(body)) sprintf("<div class='%s'>%s</div>", bcls, body) else ""
  nt   <- if (nzchar(note)) sprintf("<p class='note'>%s</p>", note) else ""
  sprintf("<div class='%s'><h3 class='card-t'>%s</h3>%s%s%s</div>", cls, title, strip, bd, nt)
}

# Observed-vs-implied overlap BY LAG. The single adjacent number the card used to show hides
# the thing that matters in a non-contiguous design: in "2-(2)-2" the informative lag is 4, not
# 1, and in PNAD's "1(2)5" the adjacent overlap is zero by construction. This is also exactly
# the comparison PN-01 and PN-07 make, so the reader can see what fired -- or what nearly did.
.overlap_profile_html <- function(p, lang = "en") {
  prof <- p$overlap_profile
  if (is.null(prof) || !length(prof)) return("")
  L <- min(length(p$waves) - 1L, length(prof), 8L)
  if (L < 1L) return("")
  ls   <- seq_len(L)
  have <- !is.null(p$pr_lag) && !all(is.na(p$pr_lag))
  rows <- list(implied = unname(prof[ls]), observed = unname(p$obs_lag[ls]))
  nm   <- c(.t("implied by pattern", "implicado por el esquema", lang),
            .t("observed (units)", "observado (unidades)", lang))
  if (have) { rows$cohort <- unname(p$pr_lag[ls])
              nm <- c(nm, .t("cohort continuity", "continuidad de cohortes", lang)) }
  m <- do.call(rbind, rows)
  dimnames(m) <- list(nm, paste0("L", ls))
  paste0("<div class='viz-h'>",
         .t("Overlap profile by lag: what the rotation pattern implies against what the data shows",
            "Perfil de traslape por rezago: lo que implica el esquema contra lo que muestran los datos",
            lang),
         "</div>",
         .wf_heat_table(m, digits = 2, rowlab = .t("lag", "rezago", lang)))
}

# ---- Card 1: structure and rotation (panel_design) ----  table | heat-map, full width
.panel_design_card <- function(pd, lang = "en") {
  if (is.null(pd)) return("")
  p <- attr(pd, "wf_panel"); if (is.null(p)) return("")
  metrics <- paste0(
    .metric(.t("Waves", "Olas", lang), paste(p$waves, collapse = ", ")),
    .metric(.t("Units", "Unidades", lang), .fmt_num(p$n_units, "count")),
    .metric(.t("Linked in &ge;2 waves", "Enlazadas en &ge;2 olas", lang),
            sprintf("%s (%.0f%%)", .fmt_num(p$n_linked, "count"), 100 * p$link_rate)),
    .metric(.t("Rotation group", "Grupo de rotaci&oacute;n", lang),
            if (is.null(p$rotation_group)) .t("(none)", "(ninguno)", lang) else .html_escape(p$rotation_group)),
    if (!all(is.na(p$pr_adjacent)))
      .metric(.t("Pr(panel selection)", "Pr(selecci&oacute;n paneles)", lang),
              paste(sprintf("%.3f", p$pr_adjacent), collapse = ", ")) else "",
    if (!is.null(p$pattern_cycle) && !is.na(p$pattern_cycle))
      .metric(.t("Pattern", "Esquema", lang),
              sprintf(.t("%d in sample, cycle %d", "%d en muestra, ciclo %d", lang),
                      p$pattern_n_in, p$pattern_cycle)) else "",
    if (!is.null(p$pattern_lags) && length(p$pattern_lags))
      .metric(.t("Lags with overlap", "Rezagos con traslape", lang),
              paste(utils::head(p$pattern_lags, 8L), collapse = ", ")) else "")
  heat <- paste0("<div class='viz-h'>",
                 .t("Overlap: fraction of the row wave retained in the column wave",
                    "Traslape: fracci&oacute;n de la ola fila retenida en la ola columna", lang),
                 "</div>", .wf_heat_table(p$overlap, digits = 2, rowlab = .t("wave", "ola", lang)),
                 .overlap_profile_html(p, lang))
  .panel_card(.t("Panel structure and rotation", "Estructura y rotaci&oacute;n del panel", lang),
              metrics, heat, .alerts_html(p$alerts), feature = TRUE, wide = TRUE)
}

# ---- Card 2: change variance (coordinated) ----
.change_variance_card <- function(ch, lang = "en") {
  if (is.null(ch) || !inherits(ch, "weightflow_change")) return("")
  rel <- identical(ch$type, "relative"); naive_se <- sqrt(ch$Vind)
  # one decimal rule for the estimate and both standard errors: %.5g gave
  # "-0.014951" next to "0.010488" next to "0.0161" and nothing lined up
  d5 <- function(x) if (is.finite(x)) formatC(x, format = "f", digits = 4) else "&ndash;"
  jack <- identical(ch$method, "jackknife")
  meth <- if (jack) .t("coordinated jackknife", "jackknife coordinado", lang)
          else if (is.finite(ch$R)) sprintf(.t("coordinated bootstrap (B = %d)",
                                               "bootstrap coordinado (B = %d)", lang), ch$R)
          else .t("coordinated bootstrap", "bootstrap coordinado", lang)
  metrics <- paste0(
    .metric(.t("Method", "M&eacute;todo", lang), meth),
    .metric(.t("Change", "Cambio", lang), d5(ch$estimate)),
    .metric(.t("SE (coordinated)", "EE (coordinado)", lang), d5(ch$se)),
    .metric(.t("SE (independent)", "EE (independiente)", lang), d5(naive_se)),
    .metric(.t("rho (wave correlation)", "rho (correlaci&oacute;n entre olas)", lang),
            sprintf("%.3f", ch$rho)),
    if (!rel) .metric("deff", sprintf("%.3f", ch$deff_change)) else "")
  msg <- if (rel)
    .t("Relative change; its variance uses the overlap covariance from the coordinated replicates.",
       "Cambio relativo; su varianza usa la covarianza del traslape de las r&eacute;plicas coordinadas.", lang)
  else if (isTRUE(ch$deff_change < 1))
    .t(sprintf("The overlap <strong>lowers</strong> the variance of the change: the coordinated SE is %.0f%% of the independent one, which overstates it.",
               100 * ch$se / naive_se),
       sprintf("El traslape <strong>baja</strong> la varianza del cambio: el EE coordinado es %.0f%% del independiente, que la sobreestima.",
               100 * ch$se / naive_se), lang)
  else .t("With this contrast the between-wave covariance raises the variance.",
          "Con este contraste la covarianza entre olas sube la varianza.", lang)
  viz <- if (!rel && is.finite(naive_se) && naive_se > 0)
    .wf_svg_bars2(c(1, ch$se / naive_se), c("p5", "p1"),
                  c(.t("SE independent", "EE independiente", lang),
                    .t("SE coordinated", "EE coordinado", lang)),
                  c(d5(naive_se), d5(ch$se)), lang = lang,
                  title = .t("Standard error of the net change",
                             "Error est&aacute;ndar del cambio neto", lang)) else ""
  ttl <- sprintf("%s (%s &rarr; %s)%s",
                 .t("Net change variance", "Varianza del cambio neto", lang),
                 .html_escape(ch$waves[1]), .html_escape(ch$waves[2]),
                 if (jack) " [jackknife]" else "")
  .panel_card(ttl, metrics, viz, msg, feature = TRUE, wide = TRUE)
}

# ---- Card 2b: replication-based variance estimation for the COORDINATED object ----
# Same title/format as the package's .replication_card, adapted for wave_bootstrap/wave_jackknife.
.change_replication_card <- function(wb, lang = "en") {
  if (is.null(wb) || !inherits(wb, c("weightflow_wave_boot", "weightflow_wave_jack"))) return("")
  is_jack <- inherits(wb, "weightflow_wave_jack")
  d1 <- wb$data[[1]]
  st <- if (is.null(wb$strata)) rep("1", nrow(d1)) else as.character(d1[[wb$strata]])
  cl <- if (is.null(wb$psu)) as.character(seq_len(nrow(d1))) else as.character(d1[[wb$psu]])
  nstr <- length(unique(st)); pps <- tapply(cl, st, function(z) length(unique(z)))
  method <- if (is_jack)
    .t("Coordinated jackknife (delete-one PSU, coordinated across waves)",
       "Jackknife coordinado (borra-una-UPM, coordinado entre olas)", lang)
    else .t("Coordinated bootstrap (Rao-Wu, coordinated across waves by PSU)",
            "Bootstrap coordinado (Rao-Wu, coordinado entre olas por UPM)", lang)
  nrep  <- if (is_jack) length(wb$union_psu) else wb$R
  refit <- wb$refit_steps %||% "all"
  recipe <- if (identical(refit, "all"))
    .t("Full weighting procedure re-run for each replicate",
       "todo el procedimiento de ponderaci&oacute;n se recalcula en cada r&eacute;plica", lang)
  else .t(sprintf("Only these steps re-run per replicate: %s (earlier steps frozen)", paste(refit, collapse = ", ")),
          sprintf("Solo estos pasos se recalculan por r&eacute;plica: %s (los previos congelados)", paste(refit, collapse = ", ")), lang)
  kv <- function(k, v) sprintf("<tr><td class='k'>%s</td><td class='r'>%s</td></tr>", k, v)
  na <- function(x) if (is.null(x) || (length(x) == 1L && is.na(x))) "-" else as.character(x)
  body <- paste0(
    kv(.t("Method", "M&eacute;todo", lang), method),
    kv(.t("Waves", "Olas", lang), paste(wb$waves, collapse = ", ")),
    kv(if (is_jack) .t("Delete-one replicates", "R&eacute;plicas borra-una", lang) else .t("Replicates (B)", "R&eacute;plicas (B)", lang),
       format(nrep, big.mark = ",")),
    kv(.t("Strata", "Estratos", lang), format(nstr, big.mark = ",")),
    kv(.t("Mean PSUs per stratum", "UPM por estrato (media)", lang), sprintf("%.1f", mean(pps))),
    kv(.t("Recipe-aware replication", "Replicaci&oacute;n recipe-aware", lang), recipe),
    if (!is_jack) kv(.t("Seed", "Semilla", lang), na(wb$seed)) else "")
  note <- .t("The replicates are <strong>coordinated</strong> by PSU across waves: a PSU present in several waves gets the same resampling in all of them, so the between-wave sampling covariance the panel overlap induces is captured, and the honest variance of a net change follows (V = V1 + V2 - 2*Cov). Ignoring the coordination (a separate per-wave bootstrap) over-states the variance of change.",
             "Las r&eacute;plicas est&aacute;n <strong>coordinadas</strong> por UPM entre olas: una UPM presente en varias olas recibe el mismo remuestreo en todas, as&iacute; que se captura la covarianza entre olas que induce el traslape, y sale la varianza honesta del cambio (V = V1 + V2 - 2*Cov). Ignorar la coordinaci&oacute;n (un bootstrap separado por ola) sobreestima la varianza del cambio.", lang)
  sprintf("<div class='meta racct feature'><h3 class='card-t'>%s</h3><table class='params'><tbody>%s</tbody></table><p class='note'>%s</p></div>",
          .t("Replication-based variance estimation (coordinated)",
             "Estimaci&oacute;n de la varianza por replicaci&oacute;n (coordinada)", lang), body, note)
}

# ---- Card 3: attrition / retention (a prepped longitudinal spec) ----
.attrition_card <- function(fit, lang = "en") {
  if (is.null(fit) || !inherits(fit, "prepped_weighting_spec")) return("")
  w <- fit$final_weight; n0 <- length(w); nret <- sum(is.finite(w) & w != 0)
  amet <- vapply(fit$steps, function(s) s$attrition_method %||% NA_character_, character(1))
  amet <- amet[!is.na(amet)]
  metrics <- paste0(
    .metric(.t("Frame (all waves)", "Marco (todas las olas)", lang), .fmt_num(n0, "count")),
    .metric(.t("Retained", "Retenidas", lang),
            sprintf("%s (%.0f%%)", .fmt_num(nret, "count"), 100 * nret / max(n0, 1))),
    if (length(amet))
      .metric(.t("Attrition method", "M&eacute;todo de atrici&oacute;n", lang),
              paste(amet, collapse = ", ")) else "")
  viz <- .wf_svg_bars2(c(1, nret / max(n0, 1)), c("p-node", "p1"),
                       c(.t("Frame", "Marco", lang), .t("Retained", "Retenidas", lang)),
                       c(.fmt_num(n0, "count"),
                         sprintf("%s (%.0f%%)", .fmt_num(nret, "count"), 100 * nret / max(n0, 1))),
                       lang = lang,
                       title = .t("Longitudinal frame and retained units",
                                  "Marco longitudinal y unidades retenidas", lang))
  .panel_card(.t("Attrition and retention", "Atrici&oacute;n y retenci&oacute;n", lang), metrics, viz,
          .t("The longitudinal weight represents the units that stayed in the target population and responded across all combined waves; out-of-scope units drop (weight 0) and nonresponse is reweighted.",
             "El peso longitudinal representa a las unidades que permanecieron en la poblaci&oacute;n objetivo y respondieron en todas las olas combinadas; las fuera de alcance se descartan (peso 0) y la no respuesta se repondera.", lang),
              wide = TRUE)
}

# ---- Card 4: gross flows ----  matrix (left) | Sankey (right), full width
.transition_card <- function(tr, lang = "en") {
  if (is.null(tr) || !inherits(tr, "weightflow_transition")) return("")
  boot <- inherits(tr, "weightflow_transition_boot")
  m  <- if (boot) tr$estimate else tr$matrix
  se <- if (boot) tr$se else NULL
  fmt <- switch(tr$format, row = "P(to | from)", col = "P(from | to)",
                joint = "P(from, to)", counts = .t("weighted counts", "conteos ponderados", lang))
  heat   <- .wf_heat_table(m, se = se, digits = 3,
                           rowlab = sprintf("%s \\ %s", .html_escape(tr$from), .html_escape(tr$to)))
  note   <- sprintf("<p class='muted'>%s%s</p>", fmt,
                    if (boot) .t(" &mdash; cell (SE) from the bootstrap", " &mdash; celda (EE) del bootstrap", lang) else "")
  sankey <- if (!is.null(tr$counts)) .wf_svg_sankey(tr$counts, lang) else ""
  ttl <- sprintf("%s: %s &rarr; %s",
                 .t("Gross flows (transition matrix)", "Flujos brutos (matriz de transici&oacute;n)", lang),
                 .html_escape(tr$from), .html_escape(tr$to))
  .panel_card(ttl, "", paste0("<div>", heat, note, "</div><div>", sankey, "</div>"),
              feature = TRUE)
}

#' Panel / longitudinal HTML report
#'
#' Builds an HTML report by ADDING the panel cards to the standard report. When a longitudinal
#' weight is given, it renders the full [report_weighting()] page for that weight (cascade, weight
#' distribution, deff, ...) and injects a "Panel / longitudinal" section with the rotation
#' structure ([panel_design()]), the coordinated net-change variance ([change_estimate()]), the
#' attrition/retention summary, and the gross flows ([transition_matrix()] / [boot_transition()]).
#' Without a longitudinal weight it writes a small standalone page with those cards. Any argument
#' may be `NULL`; its card is skipped.
#'
#' @param design a `wf_panel_design` from [panel_design()].
#' @param change a `weightflow_change` from [change_estimate()] / [change_mean()].
#' @param longitudinal a prepped longitudinal `weighting_spec`; when given, the report is the full
#'   weighting report of that weight with the panel section added.
#' @param transition a `weightflow_transition` / `_boot` from the flow functions.
#' @param coordinated the coordinated [wave_bootstrap()] / [wave_jackknife()] object behind
#'   `change`, so the report shows a "Replication-based variance estimation" card stating the
#'   coordinated method, replicates, strata, PSUs, recipe-aware setting and seed.
#' @param estimates results of the estimation grammar: a `weightflow_estimation_result` from
#'   [collect_estimates()], an uncollected [step_estimate()] pipeline (collected here), or a
#'   named list of either -- the names become the card titles. Each becomes a results block
#'   with the levels behind a change, its coordinated standard error and confidence interval,
#'   a dot-and-whisker chart across the [step_domain()] cells, and the subpopulation any
#'   [step_filter()] restricted it to.
#' @param variance the longitudinal-weight [bootstrap_weights()] / jackknife object, so the base
#'   report shows the variance/replication card (deff, method, replicates) for the longitudinal
#'   weight instead of "replicate weights not created". The coordinated CHANGE variance is shown by
#'   the `change` card.
#' @param file output path; a temporary `.html` if `NULL`.
#' @param open open the file in a browser.
#' @param lang `"en"` (default) or `"es"`.
#' @return the path to the written HTML file, invisibly.
#' @seealso [report_weighting()], [panel_design()], [change_estimate()], [boot_transition()]
#' @export
report_panel <- function(design = NULL, change = NULL, longitudinal = NULL,
                         transition = NULL, coordinated = NULL, estimates = NULL,
                         variance = NULL, file = NULL,
                         open = TRUE, lang = c("en", "es")) {
  lang <- match.arg(lang)
  if (is.null(design) && is.null(change) && is.null(longitudinal) &&
      is.null(transition) && is.null(estimates))
    stop("Supply at least one of design / change / longitudinal / transition / estimates.",
         call. = FALSE)
  # Validate the class of every supplied argument up front. Without this a wrong-class
  # object (e.g. report_panel(fit) putting `fit` into `design`) passes the guard above,
  # its card renders as "" and the report is written VALID BUT EMPTY -- a silent failure
  # the user reads as success (audit A5). Fail loudly instead.
  .chk <- function(x, arg, classes) {
    if (!is.null(x) && !inherits(x, classes))
      stop(sprintf("`%s` must be %s, not a <%s>.", arg,
                   paste(sprintf("a <%s>", classes), collapse = " or "),
                   paste(class(x), collapse = "/")), call. = FALSE)
  }
  .chk(design,       "design",       "wf_panel_design")
  .chk(change,       "change",       "weightflow_change")
  .chk(longitudinal, "longitudinal", "prepped_weighting_spec")
  .chk(transition,   "transition",   "weightflow_transition")
  .chk(coordinated,  "coordinated",  c("weightflow_wave_boot", "weightflow_wave_jack"))
  .chk(variance,     "variance",     c("weightflow_boot", "weightflow_jack"))
  if (is.null(file)) file <- tempfile("weightflow_panel_", fileext = ".html")
  # Collected once, up front: an uncollected pipeline is evaluated here, and the
  # error (a bad domain column, an estimand that fails on every cell) must surface
  # before any HTML is written rather than as an empty card.
  est_html <- .estimates_section(estimates, lang)
  section <- paste0(
    sprintf("<h2 id='panel'>%s</h2>", .t("Panel / longitudinal", "Panel / longitudinal", lang)),
    .panel_design_card(design, lang), "\n",
    .change_variance_card(change, lang), "\n",
    .change_replication_card(coordinated, lang), "\n",
    .attrition_card(longitudinal, lang), "\n",
    .transition_card(transition, lang), "\n",
    est_html)

  if (inherits(longitudinal, "prepped_weighting_spec")) {
    reps <- if (inherits(variance, c("weightflow_boot", "weightflow_jack"))) variance else NULL
    tmp  <- report_weighting(longitudinal, file = tempfile(fileext = ".html"),
                             open = FALSE, lang = lang, replicates = reps)
    # mark the bytes as UTF-8 on the way in: report_weighting() writes UTF-8, and
    # without the declaration a non-UTF-8 locale leaves the string "unknown", so
    # the sub()s below and enc2utf8() on the way out both choke on the accents
    html <- paste(readLines(tmp, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    # The panel cards used to be injected at the very top of <main>, i.e. BEFORE
    # the report identified itself (metadata card, headline tiles, summary). Put
    # them after the summary and before the cascade: first what the panel is,
    # then how the longitudinal weight was built from it.
    html <- if (grepl("<h2 id='pipeline'>", html, fixed = TRUE))
      sub("<h2 id='pipeline'>", paste0(section, "\n<h2 id='pipeline'>"), html, fixed = TRUE)
    else sub("<main>\n", paste0("<main>\n", section, "\n"), html, fixed = TRUE)
    # ... and give it an entry in the contents, next to the other sections
    toc <- sprintf("<a href='#panel'>%s</a> &middot; ", .t("Panel", "Panel", lang))
    if (nzchar(est_html))
      toc <- paste0(toc, sprintf("<a href='#estimates'>%s</a> &middot; ",
                                 .t("Estimates", "Estimaciones", lang)))
    html <- sub("<a href='#pipeline'>", paste0(toc, "<a href='#pipeline'>"),
                html, fixed = TRUE)
    # the document is a panel report, not a plain weighting report
    html <- sub(.t("survey weighting report", "reporte de ponderaci&oacute;n", lang),
                .t("panel / longitudinal report", "reporte de panel / longitudinal", lang),
                html, fixed = TRUE)
    html <- sub(sprintf("<title>weightflow &mdash; %s</title>",
                        .t("survey weighting report", "reporte de ponderaci&oacute;n", lang)),
                sprintf("<title>weightflow &mdash; %s</title>",
                        .t("panel / longitudinal report", "reporte de panel / longitudinal", lang)),
                html, fixed = TRUE)
  } else {
    html <- paste0(
      sprintf("<!DOCTYPE html><html lang='%s'><head><meta charset='utf-8'>", lang),
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
      sprintf("<title>%s</title>", .t("weightflow &mdash; panel report",
                                      "weightflow &mdash; reporte de panel", lang)),
      .report_css(), "</head><body>\n",
      "<header class='masthead'>",
      sprintf("<h1><span class='wf-mark'>weightflow</span> &mdash; %s</h1>",
              .t("panel / longitudinal report", "reporte de panel / longitudinal", lang)),
      sprintf("<p class='prov'>%s %s &middot; weightflow %s</p>",
              .t("Generated", "Generado", lang), format(Sys.time(), "%Y-%m-%d %H:%M"),
              as.character(utils::packageVersion("weightflow"))),
      "</header>\n",
      sprintf("<div class='toolbar noprint'><button type='button' id='wf-pdf' class='wfbtn'>%s</button><button type='button' id='wf-theme' class='wfbtn' aria-pressed='false'>%s</button></div>\n",
              .t("Download PDF", "Descargar PDF", lang), .t("Dark", "Oscuro", lang)),
      "<main>\n", section, "\n</main>\n",
      "<script>", .report_js(lang), "</script>\n</body></html>")
  }
  con <- file(file, open = "wb"); on.exit(close(con), add = TRUE)
  writeLines(enc2utf8(html), con, useBytes = TRUE)
  close(con); on.exit()
  if (isTRUE(open)) tryCatch(utils::browseURL(file), error = function(e) NULL)
  invisible(file)
}
