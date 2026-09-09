# ---------------------------------------------------------------------------
# Report cards for the ESTIMATION grammar (step_domain / step_filter /
# step_estimate / collect_estimates) and for the composite regression estimator
# (step_cre).
#
# The weighting report answers "how were these weights built". Neither question
# it answers is the one a subject-matter reader opens a panel report for, which
# is "what did the estimate DO between the two waves, and is the move real". The
# estimation grammar produces exactly that, so it gets its own section: what was
# asked (estimand, subpopulation, disaggregation), what came out (levels, the
# change, its coordinated SE and CI), and how much the overlap bought.
#
# Everything is rendered from what collect_estimates() already computed -- the
# tidy table plus the row-aligned `detail` frame -- so putting the estimates in
# the report never re-runs a replicate.
# ---------------------------------------------------------------------------

# Accept whatever is natural to pass: a collected result, a pipeline that has not
# been collected yet, or a (possibly named) list of either. A pipeline is collected
# here so the caller can write report_panel(estimates = wb |> step_estimate(...)).
# Names become card titles.
.est_normalize <- function(x) {
  if (is.null(x)) return(list())
  one <- function(e) {
    if (inherits(e, "weightflow_estimation_result")) return(e)
    if (inherits(e, "weightflow_estimation")) return(collect_estimates(e))
    stop("`estimates` must be a <weightflow_estimation_result> from collect_estimates(), ",
         "a <weightflow_estimation> pipeline, or a list of those, not a <",
         paste(class(e), collapse = "/"), ">.", call. = FALSE)
  }
  if (inherits(x, c("weightflow_estimation_result", "weightflow_estimation")))
    return(stats::setNames(list(one(x)), ""))
  if (!is.list(x))
    stop("`estimates` must be a <weightflow_estimation_result>, a <weightflow_estimation> ",
         "pipeline, or a list of those.", call. = FALSE)
  out <- lapply(x, one)
  if (is.null(names(out))) names(out) <- rep("", length(out))
  names(out)[is.na(names(out))] <- ""
  out
}

# Common decimals for a whole column, chosen from its magnitude: rates near 0.05
# need four, population totals need none. Mixing them ("0.0712" above "145813.0")
# is what makes a results table unreadable, so every cell of a column shares one rule.
.est_dec <- function(v) {
  m <- suppressWarnings(max(abs(v[is.finite(v)])))
  if (!is.finite(m) || m == 0) return(4L)
  if (m >= 1000) 0L else if (m >= 10) 2L else if (m >= 1) 3L else 4L
}
.est_fmt <- function(x, d) {
  ifelse(is.finite(x), formatC(x, format = "f", digits = d, big.mark = ","), "&ndash;")
}

# A change is "real" at the requested level when its confidence interval clears zero.
# Reported as a flag, not as a p-value: the replicate CI is what was computed.
.est_sig <- function(lo, hi) is.finite(lo) & is.finite(hi) & (lo > 0 | hi < 0)

# --- dot-and-whisker chart -------------------------------------------------
# Rows are domain cells; each is a point with its confidence interval and a
# dashed reference at zero (or at the level of the first wave). Intervals that
# clear the reference are drawn solid, the rest hollow -- so which domains moved
# is legible before a single number is read.
.svg_forest <- function(labels, est, lo, hi, lang = "en", ref = 0,
                        title = NULL, w = 620L, lab_w = 168L) {
  ok <- is.finite(est)
  if (!any(ok)) return("")
  labels <- labels[ok]; est <- est[ok]; lo <- lo[ok]; hi <- hi[ok]
  lo[!is.finite(lo)] <- est[!is.finite(lo)]
  hi[!is.finite(hi)] <- est[!is.finite(hi)]
  n  <- length(est)
  rh <- 24L                                     # row pitch
  mt <- 10L; mb <- 34L                          # top margin, bottom axis band
  ml <- lab_w; mr <- 16L
  h  <- mt + n * rh + mb
  pw <- w - ml - mr
  xr <- range(c(lo, hi, ref), finite = TRUE)
  if (!diff(xr)) xr <- xr + c(-1, 1) * max(abs(xr[1]), 1) * 0.05
  pad <- diff(xr) * 0.06; xr <- xr + c(-pad, pad)
  sx <- function(v) ml + (v - xr[1]) / diff(xr) * pw
  yc <- function(i) mt + (i - 0.5) * rh
  d  <- .est_dec(c(est, lo, hi))

  refln <- if (is.finite(ref) && ref >= xr[1] && ref <= xr[2])
    sprintf('<line class="wf-ref" stroke-dasharray="3 3" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>',
            sx(ref), mt, sx(ref), mt + n * rh) else ""
  # zebra banding: with eight regions the eye loses the row on the way to the dot
  band <- paste(vapply(which(seq_len(n) %% 2L == 0L), function(i)
    sprintf('<rect class="p-track" x="%d" y="%.1f" width="%.1f" height="%d" opacity=".5"/>',
            ml, yc(i) - rh / 2, pw, rh), character(1)), collapse = "")
  # with no reference to clear (a level, not a change) there is nothing to be
  # "not significant" against, so every dot is drawn solid
  sig <- if (is.finite(ref)) is.finite(lo) & is.finite(hi) & (lo > ref | hi < ref)
         else rep(TRUE, n)
  rows <- paste(vapply(seq_len(n), function(i) paste0(
    sprintf('<text class="wf-rl" x="%d" y="%.1f" text-anchor="end">%s</text>',
            ml - 10L, yc(i) + 3.5, .html_escape(labels[i])),
    sprintf('<line class="wf-ci" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>',
            sx(lo[i]), yc(i), sx(hi[i]), yc(i)),
    sprintf('<line class="wf-ci" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>',
            sx(lo[i]), yc(i) - 3.5, sx(lo[i]), yc(i) + 3.5),
    sprintf('<line class="wf-ci" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>',
            sx(hi[i]), yc(i) - 3.5, sx(hi[i]), yc(i) + 3.5),
    sprintf('<circle class="wf-dot%s" cx="%.1f" cy="%.1f" r="4"/>',
            if (sig[i]) "" else " ns", sx(est[i]), yc(i))), character(1)), collapse = "")

  xt <- c(xr[1], mean(xr), xr[2])
  axis <- paste0(
    sprintf('<line class="wf-axis" x1="%d" y1="%.1f" x2="%.1f" y2="%.1f"/>',
            ml, mt + n * rh, ml + pw, mt + n * rh),
    paste(sprintf('<line class="wf-tick" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>',
                  sx(xt), mt + n * rh, sx(xt), mt + n * rh + 3), collapse = ""),
    paste(sprintf('<text class="wf-tk" x="%.1f" y="%.1f" text-anchor="%s">%s</text>',
                  sx(xt), mt + n * rh + 15, c("start", "middle", "end"),
                  .est_fmt(xt, d)), collapse = ""))
  if (is.null(title))
    title <- .t("estimate with confidence interval", "estimaci\u00f3n con intervalo de confianza", lang)
  .svg_frame(paste0(band, refln, rows, axis), as.integer(w), as.integer(h), title, lang)
}

# --- one results table -----------------------------------------------------
# `g` is the slice of collect_estimates()'s table for a single estimand, `dg` the
# row-aligned detail slice.
.est_table <- function(g, dg, doms, over, wv, lang) {
  chg <- identical(over, "change")
  rel <- chg && identical(g$type[1], "relative")
  d_e <- .est_dec(c(g$estimate, dg$wave_1, dg$wave_2))
  d_s <- .est_dec(g$se)
  dlab <- function(k) .html_escape(
    if (identical(lang, "es") && k %in% names(.wf_es_labels)) .wf_es_labels[[k]] else k)
  hd <- c(vapply(doms, dlab, character(1)),
          if (chg && any(is.finite(dg$wave_1)))
            c(.html_escape(wv[1]), .html_escape(wv[2])) else character(0),
          if (chg) .t("Change", "Cambio", lang) else .t("Estimate", "Estimaci\u00f3n", lang),
          .t("SE", "EE", lang),
          sprintf("%s %s%%", .t("CI", "IC", lang),
                  format(round(100 * (dg$level[1] %||% 0.95), 4), trim = TRUE)),
          if (chg) .t("vs 0", "vs 0", lang) else .t("CV", "CV", lang),
          if (chg && any(is.finite(g$rho))) "<span class='gk'>&rho;</span>" else character(0))
  numc <- c(rep(FALSE, length(doms)), rep(TRUE, length(hd) - length(doms)))
  numc[length(hd) - (if (chg && any(is.finite(g$rho))) 1L else 0L)] <- FALSE  # the flag column
  sig <- .est_sig(g$ci_lower, g$ci_upper)
  cells <- lapply(seq_len(nrow(g)), function(i) {
    dv <- vapply(doms, function(k) .html_escape(as.character(g[[k]][i])), character(1))
    ci <- sprintf("[%s, %s]", .est_fmt(g$ci_lower[i], d_e), .est_fmt(g$ci_upper[i], d_e))
    flag <- if (chg)
      (if (sig[i]) sprintf("<span class='cell-ok'>%s</span>", "&ne; 0")
       else sprintf("<span class='muted'>%s</span>", .t("n.s.", "n.s.", lang)))
    else {
      cv <- 100 * g$se[i] / abs(g$estimate[i])
      if (is.finite(cv)) sprintf("%.1f%%", cv) else "&ndash;"
    }
    c(dv,
      if (chg && any(is.finite(dg$wave_1)))
        c(.est_fmt(dg$wave_1[i], d_e), .est_fmt(dg$wave_2[i], d_e)) else character(0),
      sprintf("%s%s", if (chg && is.finite(g$estimate[i]) && g$estimate[i] > 0) "+" else "",
              .est_fmt(g$estimate[i], d_e)),
      .est_fmt(g$se[i], d_s), ci, flag,
      if (chg && any(is.finite(g$rho))) .est_fmt(g$rho[i], 3L) else character(0))
  })
  cls <- ifelse(numc, " class='numc'", "")
  body <- paste(vapply(seq_along(cells), function(i)
    sprintf("<tr%s>%s</tr>", if (sig[i] && chg) " class='sig'" else "",
            paste0("<td", cls, ">", cells[[i]], "</td>", collapse = "")),
    character(1)), collapse = "")
  cap <- if (rel) sprintf("<p class='muted'>%s</p>",
                          .t("Relative change (wave 2 / wave 1 &minus; 1).",
                             "Cambio relativo (ola 2 / ola 1 &minus; 1).", lang)) else ""
  paste0(.tw(sprintf("<table class='est'><thead><tr>%s</tr></thead><tbody>%s</tbody></table>",
                     paste0("<th scope='col'", cls, ">", hd, "</th>", collapse = ""), body)), cap)
}

# --- one estimand block ----------------------------------------------------
.est_block <- function(g, dg, doms, wv, lang) {
  over <- g$over[1]
  chg  <- identical(over, "change")
  kind <- switch(over,
    change   = if (identical(g$type[1], "relative"))
                 .t("relative change", "cambio relativo", lang)
               else .t("net change", "cambio neto", lang),
    level    = .t("level", "nivel", lang),
    contrast = .t("linear contrast", "contraste lineal", lang), over)
  tbl <- .est_table(g, dg, doms, over, wv, lang)
  # A single national row has nothing to compare against, so a forest of one dot
  # is noise: show instead what the coordination bought, the way the net-change
  # card does. Two or more rows -> the forest, which is the point of a domain run.
  viz <- if (nrow(g) >= 2L) {
    labs <- if (length(doms))
      apply(g[doms], 1, function(r) paste(as.character(r), collapse = " \u00b7 "))
    else rep(g$estimand[1], nrow(g))
    .chart_figure(
      .svg_forest(labs, g$estimate, g$ci_lower, g$ci_upper, lang,
                  ref = if (chg) 0 else NA_real_,
                  title = sprintf("%s (%s)", g$estimand[1], kind)),
      sprintf("%s &mdash; %s", .html_escape(g$estimand[1]),
              .t("estimate and confidence interval by domain",
                 "estimaci\u00f3n e intervalo de confianza por dominio", lang)))
  } else if (chg && is.finite(dg$se_indep[1]) && dg$se_indep[1] > 0 &&
             is.finite(g$se[1])) {
    .wf_svg_bars2(c(1, min(1, g$se[1] / dg$se_indep[1])), c("p5", "p1"),
                  c(.t("independent waves", "olas independientes", lang),
                    .t("with the overlap", "con el traslape", lang)),
                  c(.est_fmt(dg$se_indep[1], .est_dec(c(g$se, dg$se_indep))),
                    .est_fmt(g$se[1], .est_dec(c(g$se, dg$se_indep)))),
                  x_lab = 150, w = 560, lang = lang,
                  title = .t("Standard error of the change",
                             "Error est\u00e1ndar del cambio", lang))
  } else ""
  gain <- if (chg && is.finite(dg$deff[1]) && dg$deff[1] < 1 && nrow(g) == 1L)
    sprintf("<p class='note'>%s</p>",
            .t(sprintf("The overlap between the waves lowers the variance of the change: the coordinated standard error is %.0f%% of the one that treating the waves as independent would give.",
                       100 * sqrt(dg$deff[1])),
               sprintf("El traslape entre las olas baja la varianza del cambio: el error est\u00e1ndar coordinado es %.0f%% del que dar\u00eda tratar las olas como independientes.",
                       100 * sqrt(dg$deff[1])), lang)) else ""
  sprintf("<div class='estblk'><h4 class='est-h'>%s <span class='est-kind'>%s</span></h4>%s%s%s</div>",
          .html_escape(g$estimand[1]), kind, tbl,
          if (nzchar(viz)) sprintf("<div class='est-viz'>%s</div>", viz) else "", gain)
}

# --- one collected result --------------------------------------------------
.estimates_card <- function(res, title, lang) {
  if (!inherits(res, "weightflow_estimation_result")) return("")
  tab <- res$table
  if (is.null(tab) || !nrow(tab)) return("")
  det <- res$detail
  if (is.null(det) || nrow(det) != nrow(tab)) det <- .na_detail(nrow(tab))
  doms <- res$domains %||% character(0)
  wv   <- res$waves
  jack <- identical(res$method, "jackknife")
  meth <- if (jack) .t("jackknife", "jackknife", lang)
          else .t("bootstrap", "bootstrap", lang)
  reps <- res$replicates %||% NA_integer_
  lev <- stats::median(det$level, na.rm = TRUE)
  nsig <- sum(.est_sig(tab$ci_lower, tab$ci_upper) & tab$over == "change", na.rm = TRUE)
  nchg <- sum(tab$over == "change", na.rm = TRUE)
  metrics <- paste0(
    .metric(.t("Coordinated method", "M\u00e9todo coordinado", lang), meth),
    if (!jack && is.finite(reps))
      .metric(.t("Replicates", "R\u00e9plicas", lang), format(as.integer(reps), big.mark = ",")) else "",
    .metric(.t("Waves", "Olas", lang), .html_escape(paste(wv, collapse = " \u2192 "))),
    .metric(.t("Estimates", "Estimaciones", lang), format(nrow(tab), big.mark = ",")),
    if (length(doms))
      .metric(.t("Disaggregation", "Desagregaci\u00f3n", lang),
              .html_escape(paste(doms, collapse = " \u00d7 "))) else "",
    if (is.finite(lev))
      .metric(.t("Confidence", "Confianza", lang),
              sprintf("%s%%", format(round(100 * lev, 4), trim = TRUE))) else "",
    if (nchg > 0L)
      .metric(.t("Changes clear of 0", "Cambios que superan 0", lang),
              sprintf("%d / %d", nsig, nchg)) else "")
  sub <- if (length(res$filters %||% character(0)))
    sprintf("<p class='note'><strong>%s</strong> <code>%s</code>. %s</p>",
            .t("Subpopulation:", "Subpoblaci\u00f3n:", lang),
            .html_escape(paste(res$filters, collapse = " & ")),
            .t("Rows outside it are masked, not dropped, so the coordinated replicate structure and the overlap covariance are preserved.",
               "Las filas fuera de ella se enmascaran, no se eliminan, as\u00ed se preservan la estructura de r\u00e9plicas coordinadas y la covarianza del traslape.", lang))
  else ""
  # one block per estimand, in the order they were declared
  key <- paste(tab$estimand, tab$over, tab$type, sep = "\r")
  blocks <- paste(vapply(unique(key), function(k) {
    i <- which(key == k)
    .est_block(tab[i, , drop = FALSE], det[i, , drop = FALSE], doms, wv, lang)
  }, character(1)), collapse = "")
  note <- if (nchg > 0L)
    .t("Estimated from the coordinated replicates, so the standard error of a change carries the between-wave covariance the overlap induces; treating the waves as independent would misstate it.",
       "Estimado con las r\u00e9plicas coordinadas, por lo que el error est\u00e1ndar de un cambio lleva la covarianza entre olas que induce el traslape; tratar las olas como independientes lo distorsiona.", lang)
  else
    .t("Estimated from the coordinated replicates, so the standard error reflects the whole weighting recipe re-run per replicate, not sampling alone.",
       "Estimado con las r\u00e9plicas coordinadas, por lo que el error est\u00e1ndar refleja toda la receta de ponderaci\u00f3n reejecutada por r\u00e9plica, no solo el muestreo.", lang)
  ttl <- if (nzchar(title)) .html_escape(title)
         else .t("Estimates", "Estimaciones", lang)
  .panel_card(ttl, metrics, paste0(sub, blocks), note, feature = TRUE, wide = TRUE)
}

# --- the whole section -----------------------------------------------------
.estimates_section <- function(x, lang = "en") {
  els <- .est_normalize(x)
  if (!length(els)) return("")
  cards <- paste(vapply(seq_along(els), function(i)
    .estimates_card(els[[i]], names(els)[i] %||% "", lang), character(1)), collapse = "\n")
  if (!nzchar(gsub("\\s", "", cards))) return("")
  paste0(sprintf("<h2 id='estimates'>%s</h2>", .t("Estimates", "Estimaciones", lang)),
         sprintf("<p class='muted'>%s</p>",
                 .t("What the weights were built for: levels, net changes and their precision, requested declaratively with step_domain() / step_filter() / step_estimate().",
                    "Para lo que se construyeron los pesos: niveles, cambios netos y su precisi\u00f3n, pedidos de forma declarativa con step_domain() / step_filter() / step_estimate().", lang)),
         cards)
}

# ---------------------------------------------------------------------------
# step_cre(): the composite block, read as a composite block
#
# The generic diagnostics table shows the augmented calibration as one flat list of
# constraints named z1.all.emp, z2.F.unemp -- correct and unreadable. The composite
# block is the whole point of the estimator, so it gets its own card: what share of
# the estimate is anchored on the previous wave (alpha), which previous-wave status
# totals are being reproduced, and by how much they miss.
# ---------------------------------------------------------------------------

# z1.all.emp -> block 1, cell "all", status "emp"; anything unexpected is left whole.
.cre_parse_z <- function(v) {
  m <- regmatches(v, regexec("^z([0-9]+)\\.(.*)\\.([^.]+)$", v))
  do.call(rbind, lapply(seq_along(v), function(i) {
    p <- m[[i]]
    if (length(p) == 4L)
      data.frame(blk = as.integer(p[2]), cell = p[3], status = p[4], stringsAsFactors = FALSE)
    else data.frame(blk = NA_integer_, cell = v[i], status = "", stringsAsFactors = FALSE)
  }))
}

.cre_diagnostics <- function(step, lang = "en") {
  # The CRE flag lives in attr(diagnostics, "cre") and in the step's class, not in a
  # `step$cre` field (which never exists, so this card used to never render).
  if (!inherits(step, "step_cre")) return("")
  dg <- step$diagnostics
  if (!is.data.frame(dg) || !"block" %in% names(dg)) return("")
  cre <- attr(dg, "cre"); cal <- attr(dg, "calibrate")
  z   <- dg[dg$block == "z", , drop = FALSE]
  seed <- isTRUE(cre$seed) || !nrow(z)
  alpha <- cre$alpha %||% NA_real_
  g <- cal$g
  metrics <- paste0(
    .metric(.t("Composite weight <span class='gk'>&alpha;</span>",
               "Peso compuesto <span class='gk'>&alpha;</span>", lang),
            if (is.finite(alpha)) sprintf("%.2f", alpha) else "&ndash;"),
    .metric(.t("Composite constraints", "Restricciones compuestas", lang),
            format(nrow(z), big.mark = ",")),
    .metric(.t("Demographic constraints", "Restricciones demogr\u00e1ficas", lang),
            format(sum(dg$block == "x"), big.mark = ",")),
    if (!is.null(g) && length(g))
      .metric(.t("g-factor range", "rango del factor g", lang),
              sprintf("[%.3f, %.3f]", min(g), max(g))) else "",
    .metric(.t("Constraints met", "Restricciones cumplidas", lang),
            if (isTRUE(attr(dg, "converged")))
              sprintf("<span class='cell-ok'>%d / %d</span>", nrow(dg), nrow(dg))
            else sprintf("<span class='cell-warn'>%s</span>",
                         .t("not all", "no todas", lang))))

  if (seed) {
    body <- ""
    note <- .t("Seed wave: with no previous wave to anchor on there is no composite block, so the step is an ordinary linear calibration to the demographic totals. The composite structure appears from the second wave onwards.",
               "Ola semilla: sin ola previa en la que anclarse no hay bloque compuesto, as\u00ed que el paso es una calibraci\u00f3n lineal ordinaria a los totales demogr\u00e1ficos. La estructura compuesta aparece a partir de la segunda ola.", lang)
  } else {
    pz <- .cre_parse_z(z$variable)
    dev <- abs(z$achieved - z$target) / pmax(abs(z$target), 1)
    d_t <- .est_dec(c(z$target, z$achieved))
    rows <- paste(vapply(seq_len(nrow(z)), function(i) sprintf(
      "<tr><td>%s</td><td>%s</td><td>%s</td><td class='numc'>%s</td><td class='numc'>%s</td><td class='numc'>%s</td></tr>",
      if (is.na(pz$blk[i])) "&ndash;" else sprintf("%d", pz$blk[i]),
      .html_escape(if (identical(pz$cell[i], "all"))
        .t("national", "pa\u00eds", lang) else pz$cell[i]),
      .html_escape(pz$status[i]),
      .est_fmt(z$target[i], d_t), .est_fmt(z$achieved[i], d_t),
      if (is.finite(dev[i]))
        sprintf("<span class='%s'>%.2g%%</span>",
                if (dev[i] < 1e-6) "cell-ok" else "cell-warn", 100 * dev[i]) else "&ndash;"),
      character(1)), collapse = "")
    tbl <- .tw(sprintf("<table><thead><tr><th scope='col'>%s</th><th scope='col'>%s</th><th scope='col'>%s</th><th scope='col' class='numc'>%s</th><th scope='col' class='numc'>%s</th><th scope='col' class='numc'>%s</th></tr></thead><tbody>%s</tbody></table>",
      .t("Block", "Bloque", lang), .t("Cell", "Celda", lang),
      .t("Status", "Estado", lang),
      .t("Target (Z-hat)", "Objetivo (Z-hat)", lang),
      .t("Achieved", "Logrado", lang), .t("Deviation", "Desv\u00edo", lang), rows))
    mix <- if (is.finite(alpha))
      .wf_svg_bars2(c(alpha, max(0, 1 - alpha)), c("p1", "p6"),
                    c(.t("previous wave", "ola previa", lang),
                      .t("current wave", "ola actual", lang)),
                    c(sprintf("%.0f%%", 100 * alpha), sprintf("%.0f%%", 100 * (1 - alpha))),
                    x_lab = 130, w = 560, lang = lang,
                    title = .t("Composite mix: how much of the estimator the previous wave anchors",
                               "Mezcla compuesta: cu\u00e1nto del estimador ancla la ola previa", lang)) else ""
    # one flow container, so the CSV button the report script injects lands
    # inside it instead of becoming another row of the card grid
    body <- sprintf("<div class='creblk'>%s%s</div>", tbl, mix)
    note <- .t("The composite block adds the previous wave's status totals, carried forward through the units common to both waves, to the demographic constraints. Reproducing them is what makes the month-to-month change smoother than two independently calibrated waves would give; the demographic totals still hold exactly.",
               "El bloque compuesto agrega a las restricciones demogr\u00e1ficas los totales de estado de la ola previa, arrastrados por las unidades comunes a ambas olas. Reproducirlos es lo que hace que el cambio mes a mes sea m\u00e1s suave que el de dos olas calibradas por separado; los totales demogr\u00e1ficos se siguen cumpliendo exactamente.", lang)
  }
  .panel_card(.t("Composite regression estimator", "Estimador de regresi\u00f3n compuesto", lang),
              metrics, body, note, feature = TRUE, wide = TRUE)
}
