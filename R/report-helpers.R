# report helpers: HTML escaping, number/axis formatting, inline SVG plots, pipeline diagram.

# ---------------------------------------------------------------------------
# report_weighting(): self-contained HTML report of a (prepped) recipe.
# No dependencies, no server -- writes an .html file and opens it in the
# browser. Shows the pipeline, what was requested at each step, the per-stage
# summary, and per-step diagnostics.
# ---------------------------------------------------------------------------

# Escape HTML special characters
.html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;",  x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub("\"", "&quot;", x, fixed = TRUE)
  gsub("'", "&#39;", x, fixed = TRUE)
}

# Format a step parameter value into a readable string
.fmt_val <- function(v) {
  if (is.null(v)) return("&mdash;")
  if (inherits(v, "formula") || is.call(v) || is.symbol(v) || is.language(v))
    return(.html_escape(paste(deparse(v), collapse = " ")))
  if (is.data.frame(v)) return(sprintf("data.frame [%d &times; %d]", nrow(v), ncol(v)))
  if (is.list(v)) {
    parts <- vapply(seq_along(v), function(i)
      sprintf("<i>%s</i>: %s", .html_escape(names(v)[i] %||% i), .fmt_val(v[[i]])),
      character(1))
    return(paste(parts, collapse = "<br>"))
  }
  if (is.numeric(v) && !is.null(names(v)))
    return(.html_escape(paste(sprintf("%s=%s", names(v),
           format(v, big.mark = ",", trim = TRUE)), collapse = ", ")))
  .html_escape(paste(format(v, trim = TRUE), collapse = ", "))
}
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# Central number formatting: one place decides decimals per quantity type, so the
# same kind of value reads the same everywhere (weights as integers, no ".000"
# that reads as thousands in some locales; proportions 3 dp; factors 4 dp).
.fmt_num <- function(x, type = c("weight", "count", "prop", "factor", "pct")) {
  type <- match.arg(type)
  if (length(x) != 1L || !is.finite(x)) return("&ndash;")
  switch(type,
    weight = format(round(x, 3), big.mark = ",", trim = TRUE),
    count  = format(round(x),    big.mark = ",", trim = TRUE),
    prop   = formatC(x, format = "f", digits = 3),
    factor = formatC(x, format = "f", digits = 4),
    pct    = if (abs(x) < 5e-9) "0.0%" else sprintf("%+.1f%%", x))
}

# Axis tick labels with no duplicates: increase decimals until distinct (avoids
# "1.05, 1.06, 1.06" on a narrow range).
.uniq_ticks <- function(v) {
  v <- v[is.finite(v)]
  if (!length(v)) return(character(0))
  if (all(v == round(v))) return(format(round(v), big.mark = ",", trim = TRUE))  # integers: no decimals
  if (any(abs(v) >= 1000)) return(format(round(v, 1), big.mark = ",", trim = TRUE))
  for (d in 1:6) {
    labs <- formatC(v, format = "f", digits = d)
    if (!anyDuplicated(labs)) return(labs)
  }
  formatC(v, format = "f", digits = 6)
}

# Which step parameters to display: keep only what the user meaningfully set.
# Drops NULL fields, the internal convergence knobs, "off" logical flags, and the
# default calibration distance, so the "Requested" table is not cluttered with
# defaults the user never touched.
.step_params <- function(step) {
  # `alerts` is rendered in its own "Quality alerts" block, not as a parameter;
  # `diagnostics`/`label` are internal. Drop them from the "Requested" table.
  keep <- setdiff(names(step), c("label", "diagnostics", "alerts"))
  if (inherits(step, "step_nonresponse")) {               # drop args ignored by the chosen method
    ign <- switch(step$method %||% "weighting_class",
      weighting_class = c("engine", "formula", "crossfit", "crossfit_seed", "num_classes",
                          "weight_model", "calfun", "bounds", "penalty", "totals", "count",
                          "equal_within_cluster"),
      propensity      = c("calfun", "bounds", "penalty", "totals", "count", "equal_within_cluster"),
      calibration     = c("engine", "crossfit", "crossfit_seed", "num_classes", "weight_model"),
      character(0))
    keep <- setdiff(keep, ign)
  }
  out  <- list()
  for (p in keep) {
    v <- step[[p]]
    if (is.null(v) || length(v) == 0L) next
    if (p %in% c("maxit", "tol")) next                          # internal knobs
    if (identical(p, "env")) next                               # captured NSE environment
    if (is.environment(v) || is.function(v)) next               # non-reproducible internals
    if (is.logical(v) && length(v) == 1L && !isTRUE(v)) next    # FALSE flag = off
    if (identical(p, "calfun") && identical(v, "linear")) next # default distance
    out[[p]] <- v
  }
  out
}

# If a diagnostics table has target/achieved columns, insert a relative-%
# difference column right after 'achieved' (100 * (achieved - target)/target).
.with_reldiff <- function(df, lang) {
  if (is.null(df) || !is.data.frame(df) ||
      !all(c("target", "achieved") %in% names(df))) return(df)
  tt  <- suppressWarnings(as.numeric(as.character(df$target)))
  aa  <- suppressWarnings(as.numeric(as.character(df$achieved)))
  rel <- 100 * (aa - tt) / tt
  nm  <- .t("rel. diff (%)", "dif. rel. (%)", lang)
  df[[nm]] <- ifelse(is.finite(rel), ifelse(abs(rel) < 5e-9, "0.00%", sprintf("%+.2f%%", rel)), "-")
  new <- setdiff(names(df), nm)
  ord <- append(new, nm, after = match("achieved", new))
  df[, ord, drop = FALSE]
}

# data.frame -> HTML table
.df_to_html <- function(df) {
  if (is.null(df) || !nrow(df)) return("<p class='muted'>no diagnostics</p>")
  for (nm in names(df)) if (is.numeric(df[[nm]])) df[[nm]] <- round(df[[nm]], 4)
  hd <- paste0("<th>", .html_escape(names(df)), "</th>", collapse = "")
  rows <- apply(df, 1, function(r)
    paste0("<tr>", paste0("<td>", .html_escape(as.character(r)), "</td>", collapse = ""), "</tr>"))
  sprintf("<table><thead><tr>%s</tr></thead><tbody>%s</tbody></table>",
          hd, paste(rows, collapse = ""))
}

# Hand-rolled SVG plotting: builds the SVG string directly from coordinates,
# with NO graphics device (works without cairo/X11/quartz, fully self-contained).
.fmt_ax <- function(v) {
  if (!is.finite(v)) return("")
  if (abs(v) >= 1000) format(round(v), big.mark = ",", trim = TRUE)
  else formatC(v, digits = 3, format = "g")
}

# Compact SI-style tick labels for large-magnitude axes (e.g. the Potter MSE
# curve, in the millions): 1.27M, 637k. Keeps the left margin small and readable.
.fmt_si <- function(v) vapply(v, function(x) {
  if (!is.finite(x)) return("")
  a <- abs(x); g <- function(z) formatC(z, digits = 3, format = "g")
  if      (a >= 1e12) paste0(g(x / 1e12), "T")
  else if (a >= 1e9)  paste0(g(x / 1e9),  "B")
  else if (a >= 1e6)  paste0(g(x / 1e6),  "M")
  else if (a >= 1e3)  paste0(g(x / 1e3),  "k")
  else                g(x)
}, character(1))

.svg_axes <- function(ml, mt, pw, ph, xr, yr, xlab, ylab, sx, sy, yfmt = NULL) {
  xt <- c(xr[1], mean(xr), xr[2]); yt <- c(yr[1], mean(yr), yr[2])
  # faint gridlines at the tick positions (drawn first, so they sit behind data)
  grid <- paste(c(
    sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#eef0f4"/>',
            sx(xt), mt, sx(xt), mt + ph),
    sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#eef0f4"/>',
            ml, sy(yt), ml + pw, sy(yt))), collapse = "")
  # thin axis lines
  axln <- sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#d5d9e0" stroke-width="0.8"/>',
                  c(ml, ml), c(mt + ph, mt), c(ml + pw, ml), c(mt + ph, mt + ph))
  # short tick marks
  tick <- paste(c(
    sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#cbd0d8"/>',
            sx(xt), mt + ph, sx(xt), mt + ph + 3),
    sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#cbd0d8"/>',
            ml - 3, sy(yt), ml, sy(yt))), collapse = "")
  xtk <- paste(sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="10" fill="#6b7280">%s</text>',
               sx(xt), mt + ph + 13, .uniq_ticks(xt)), collapse = "")
  ylabs <- if (is.null(yfmt)) .uniq_ticks(yt) else yfmt(yt)
  ytk <- paste(sprintf('<text x="%.1f" y="%.1f" text-anchor="end" font-size="10" fill="#6b7280">%s</text>',
               ml - 5, sy(yt) + 3, ylabs), collapse = "")
  xl  <- sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="11" fill="#6b7280">%s</text>',
                 ml + pw / 2, mt + ph + 27, xlab)
  yl  <- sprintf('<text x="11" y="%.1f" text-anchor="middle" font-size="11" fill="#6b7280" transform="rotate(-90 11 %.1f)">%s</text>',
                 mt + ph / 2, mt + ph / 2, ylab)
  paste0(grid, paste(axln, collapse = ""), tick, xtk, ytk, xl, yl)
}

.svg_evolution <- function(labels, y, w = 640L, h = 190L) {
  n <- length(y); if (n < 2L) return("")
  disp <- ifelse(seq_len(n) == 1L, "base", as.character(seq_len(n) - 1L))  # base,1,2,...
  ml <- 48; mr <- 14; mt <- 12; mb <- 34; pw <- w - ml - mr; ph <- h - mt - mb
  yr <- range(y); if (diff(yr) == 0) yr <- yr + c(-0.05, 0.05)
  pad <- diff(yr) * 0.10; yr <- yr + c(-pad, pad)          # aire arriba/abajo
  sx <- function(i) ml + (i - 1) / (n - 1) * pw
  sy <- function(v) mt + ph - (v - yr[1]) / diff(yr) * ph
  yt <- pretty(yr, 3)
  grid <- paste(sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#eef" stroke-width="1"/>',
                        ml, sy(yt), ml + pw, sy(yt)), collapse = "")
  ytk  <- paste(sprintf('<text x="%.1f" y="%.1f" text-anchor="end" font-size="10" fill="#6b7280">%s</text>',
                        ml - 6, sy(yt) + 3, .uniq_ticks(yt)), collapse = "")
  d    <- paste(sprintf("%.1f %.1f", sx(seq_len(n)), sy(y)), collapse = " L ")
  line <- sprintf('<path d="M %s" fill="none" stroke="#3d3580" stroke-width="2"/>', d)
  dots <- paste(sprintf('<circle cx="%.1f" cy="%.1f" r="3" fill="#3d3580"/>',
                        sx(seq_len(n)), sy(y)), collapse = "")
  xtk  <- paste(sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="10" fill="#6b7280">%s</text>',
                        sx(seq_len(n)), mt + ph + 16, .html_escape(disp)), collapse = "")
  dd <- diff(y); ann <- ""
  if (length(dd) && any(dd > 0)) {
    ii  <- which.max(dd) + 1L
    ann <- sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="12" fill="#b45309">&#9650;</text>',
                   sx(ii), sy(y[ii]) - 7)
  }
  if (length(dd) && min(dd) < -0.0005) {
    jj  <- which.min(dd) + 1L
    ann <- paste0(ann, sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="12" fill="#065f46">&#9660;</text>',
                               sx(jj), sy(y[jj]) + 16))
  }
  paste0('<svg viewBox="0 0 ', w, ' ', h,
         '" width="100%" role="img" aria-label="Kish design effect by stage" font-family="-apple-system,Segoe UI,Roboto,sans-serif"><title>deff_K by stage</title>',
         grid, ytk, line, dots, xtk, ann, '</svg>')
}

.svg_frame <- function(body, w, h, title = "diagnostic plot") sprintf(
  '<svg viewBox="0 0 %d %d" preserveAspectRatio="xMidYMid meet" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="%s" font-family="-apple-system,Segoe UI,Roboto,sans-serif" font-size="9"><title>%s</title>%s</svg>',
  w, h, title, title, body)

# Deterministic thinning for the scatter (rendering only). Keeps both tails on
# each axis (smallest/largest weights before and after) and the largest
# departures from y = x, then systematically thins the dense core. Reproducible
# across runs and never drops the outliers. Returns indices into x/y.
.thin_scatter <- function(x, y, cap = 3000L) {
  if (length(x) <= cap) return(seq_along(x))
  d   <- abs(y - x)
  ne  <- min(100L, length(x))
  ext <- unique(c(order(x)[seq_len(ne)], order(x, decreasing = TRUE)[seq_len(ne)],
                  order(y)[seq_len(ne)], order(y, decreasing = TRUE)[seq_len(ne)],
                  order(d, decreasing = TRUE)[seq_len(min(200L, length(x)))]))
  rest  <- setdiff(seq_along(x), ext)
  nthin <- max(0L, cap - length(ext))
  thin  <- if (nthin > 0L && length(rest) > 0L)
    rest[round(seq.int(1, length(rest), length.out = min(nthin, length(rest))))] else integer(0)
  unique(c(ext, thin))
}

# Scatter of weight before (x) vs after (y), with a y = x reference line.
.svg_scatter <- function(x, y, w = 330, h = 215, cap = 3000L, lang = "en") {
  ml <- 54; mr <- 8; mt <- 8; mb <- 32; pw <- w - ml - mr; ph <- h - mt - mb
  i <- .thin_scatter(x, y, cap); x <- x[i]; y <- y[i]
  xr <- range(x); yr <- range(c(y, x))
  if (diff(xr) == 0) xr <- xr + c(-1, 1)
  if (diff(yr) == 0) yr <- yr + c(-1, 1)
  sx <- function(v) ml + (v - xr[1]) / diff(xr) * pw
  sy <- function(v) mt + ph - (v - yr[1]) / diff(yr) * ph
  pts <- paste(sprintf('<circle cx="%.1f" cy="%.1f" r="2.4" fill="#7a6ad0" fill-opacity="0.24"/>',
               sx(x), sy(y)), collapse = "")
  lo <- max(xr[1], yr[1]); hi <- min(xr[2], yr[2])
  ln  <- sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#6b7280" stroke-dasharray="4 3"/>',
                 sx(lo), sy(lo), sx(hi), sy(hi))
  lbl <- sprintf('<text x="%.1f" y="%.1f" text-anchor="end" font-size="10" fill="#6b7280">y = x</text>',
                 sx(hi) - 3, sy(hi) + 12)
  .svg_frame(paste0(.svg_axes(ml, mt, pw, ph, xr, yr, .t("weight before", "peso antes", lang), .t("weight after", "peso despu\u00e9s", lang), sx, sy),
                    pts, ln, lbl), w, h)
}

# Histogram of a per-unit quantity (default: the adjustment factor after/before),
# with a reference line at 1.
.svg_hist <- function(v, xlab = "adjustment factor (after / before)", w = 330, h = 215, refline = 1, lang = "en") {
  ml <- 48; mr <- 8; mt <- 8; mb <- 32; pw <- w - ml - mr; ph <- h - mt - mb
  v <- v[is.finite(v)]
  if (!length(v)) return("")
  hh <- graphics::hist(v, breaks = 30, plot = FALSE)
  xr <- range(hh$breaks); yr <- c(0, max(hh$counts))
  if (diff(xr) == 0) xr <- xr + c(-1, 1)
  if (yr[2] == 0) yr[2] <- 1
  sx <- function(z) ml + (z - xr[1]) / diff(xr) * pw
  sy <- function(z) mt + ph - (z - yr[1]) / diff(yr) * ph
  bars <- paste(sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="1.5" fill="#b7abdf"/>',
                sx(hh$breaks[-length(hh$breaks)]), sy(hh$counts),
                pmax(sx(hh$breaks[-1]) - sx(hh$breaks[-length(hh$breaks)]) - 0.5, 0.5),
                pmax(sy(0) - sy(hh$counts), 0)), collapse = "")
  vl <- if (!is.null(refline) && refline >= xr[1] && refline <= xr[2])
    paste0(sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#6b7280" stroke-dasharray="4 3"/>',
                   sx(refline), mt, sx(refline), mt + ph),
           sprintf('<text x="%.1f" y="%.1f" font-size="10" fill="#6b7280">factor = 1</text>',
                   sx(refline) + 3, mt + 9)) else ""
  .svg_frame(paste0(.svg_axes(ml, mt, pw, ph, xr, yr, xlab, .t("count", "conteo", lang), sx, sy),
                    bars, vl), w, h)
}

# Per-step visual, dispatched by step type. Steps that only zero-out weights,
# round or rescale add nothing visual, so they get no plot. The rest get the
# weight before-vs-after scatter plus a histogram of the adjustment factor
# (after / before), over the units kept active by the step. For within-household
# selection the factor is 1/prob, i.e. the number of eligibles the selected
# person represents.
.no_visual <- c("step_drop_ineligible", "step_round", "step_rescale", "step_assert")
.step_visual <- function(step, prev, cur, lang = "en") {
  if (inherits(step, .no_visual)) return("")
  keep <- prev > 0 & cur > 0
  if (!any(keep)) return("")
  sc   <- tryCatch(.svg_scatter(prev[keep], cur[keep], lang = lang), error = function(e) "")
  fac  <- (cur / prev)[keep]
  xlab <- if (inherits(step, "step_select_within"))
            .t("persons represented (1/prob)", "personas representadas (1/prob)", lang)
          else .t("adjustment factor (after / before)", "factor de ajuste (despu\u00e9s / antes)", lang)
  hi   <- tryCatch(.svg_hist(fac, xlab = xlab, lang = lang), error = function(e) "")
  if (!nzchar(sc) && !nzchar(hi)) return("")
  note <- if (sum(keep) > 3000L)
    sprintf("<p class='muted'>%s</p>", .t(
      sprintf("Showing 3,000 of %s points (both tails and the largest departures from y = x are kept).", format(sum(keep), big.mark = ",")),
      sprintf("Se muestran 3.000 de %s puntos (se conservan ambas colas y las mayores desviaciones de y = x).", format(sum(keep), big.mark = ",")), lang)) else ""
  sprintf("<div class='viz'><div>%s</div><div>%s</div></div>%s", sc, hi, note)
}

# Compact R-indicator block, rendered inside the (last) nonresponse step card.
.ri_block <- function(ri, lang = "en") {
  ph <- ""
  ptab <- ri$partials
  if (!is.null(ptab)) {
    ptab <- ptab[order(-ptab$partial_R), , drop = FALSE]
    ptab$partial_R <- round(ptab$partial_R, 4)
    ph <- paste0(sprintf("<p class='muted'>%s</p>", .t("Partial R-indicators:", "R-indicadores parciales:", lang)), .df_to_html(ptab))
  }
  if (!is.null(ri$num_aux) && length(ri$num_aux))
    ph <- paste0(ph, sprintf(
      .t("<p class='muted'>Numeric auxiliaries are binned into quintiles for their partial; not computable (too few distinct values): %s.</p>",
         "<p class='muted'>Los auxiliares num\u00e9ricos se agrupan en quintiles para su parcial; no computable (muy pocos valores distintos): %s.</p>", lang),
      .html_escape(paste(ri$num_aux, collapse = ", "))))
  sprintf(
    .t("<div class='ri'><h4>Response representativity (R-indicator)</h4>
<p class='muted'>Design-weighted logistic of response on <code>%s</code> (n = %s). Closer to 1 = more representative response; the partials show which variable drives the gap.</p>
<p class='ri-val'><strong>R = %.3f</strong></p>%s</div>",
       "<div class='ri'><h4>Representatividad de la respuesta (R-indicador)</h4>
<p class='muted'>Log\u00edstica ponderada por dise\u00f1o de la respuesta sobre <code>%s</code> (n = %s). M\u00e1s cerca de 1 = respuesta m\u00e1s representativa; los parciales muestran qu\u00e9 variable explica la brecha.</p>
<p class='ri-val'><strong>R = %.3f</strong></p>%s</div>", lang),
    .html_escape(paste(ri$aux, collapse = ", ")),
    format(ri$n_eligible, big.mark = ","), ri$R, ph)
}

# Steps that run AFTER calibration (trimming, rounding, rescaling) move the
# weighted totals away from the calibration targets. This recomputes the last
# calibration's categorical targets at the FINAL weights and reports the drift.
# Only shown when there is a calibration step followed by at least one more step.
.calibration_drift <- function(object, lang = "en") {
  is_cal <- vapply(object$steps, function(s) inherits(s, "step_calibrate"), logical(1))
  if (!any(is_cal)) return("")
  kc <- max(which(is_cal))
  if (kc == length(object$steps)) return("")                 # nothing after calibration
  dcal <- object$steps[[kc]]$diagnostics
  if (is.null(dcal) || !all(c("variable", "category", "target") %in% names(dcal)))
    return("")                                               # e.g. linear/GREG: skip
  data <- object$data; fin <- object$final_weight
  rows <- lapply(seq_len(nrow(dcal)), function(r) {
    v <- as.character(dcal$variable[r]); ct <- as.character(dcal$category[r])
    tg <- suppressWarnings(as.numeric(dcal$target[r]))
    if (!v %in% names(data) || is.na(tg)) return(NULL)
    ach <- sum(fin[as.character(data[[v]]) == ct], na.rm = TRUE)
    data.frame(variable = v, category = ct, target = round(tg), achieved = round(ach),
               `dev %` = round(if (tg != 0) 100 * (ach - tg) / tg else NA_real_, 2),
               check.names = FALSE, stringsAsFactors = FALSE)
  })
  rows <- do.call(rbind, rows)
  if (is.null(rows) || !nrow(rows)) return("")
  maxdev <- max(abs(rows[["dev %"]]), na.rm = TRUE)
  sprintf(
    .t("<h2>Calibration drift</h2>
<p class='muted'>Steps after calibration (trimming, rounding, rescaling) move the weighted totals away from the calibration targets. <code>achieved</code> is recomputed at the final weights; max deviation %.2f%%.</p>%s",
       "<h2>Deriva de calibraci\u00f3n</h2>
<p class='muted'>Los pasos posteriores a la calibraci\u00f3n (recorte, redondeo, reescalado) alejan los totales ponderados de los objetivos de calibraci\u00f3n. <code>logrado</code> se recalcula con los pesos finales; desviaci\u00f3n m\u00e1xima %.2f%%.</p>%s", lang),
    maxdev, .df_to_html(rows))
}

# Variables of the dataset a step refers to (captured expressions + by/cluster
# + calibration margin names).
.lang_vars <- function(x)
  if (is.null(x)) character(0) else tryCatch(all.vars(x), error = function(e) character(0))

.step_vars <- function(step) {
  v <- character(0)
  for (f in c("unknown", "prob", "n_eligible", "ineligible", "respondent",
              "formula", "x_formula"))
    if (!is.null(step[[f]])) v <- c(v, .lang_vars(step[[f]]))
  for (f in c("by", "cluster"))
    if (!is.null(step[[f]])) v <- c(v, as.character(step[[f]]))
  if (!is.null(step[["margins"]])) v <- c(v, names(step[["margins"]]))
  unique(v[nzchar(v)])
}

.chips <- function(vars)
  if (!length(vars)) "" else paste0("<div class='chips'>",
    paste(sprintf("<span class='chip'>%s</span>", .html_escape(vars)), collapse = ""),
    "</div>")

# Readable stage labels shared by the per-stage table and the step anchors:
# base + one per step ("3 - Nonresponse adjustment (...)").
.stage_labels <- function(object, lang)
  c(.t("Base weights", "Pesos base", lang),
    vapply(seq_along(object$steps),
           function(i) sprintf("%d \u00b7 %s", i, .step_short(object$steps[[i]], lang)),
           character(1)))

# A vertical flow diagram of the pipeline (base -> steps -> final), with the
# variables each step used shown as chips. Pure HTML/CSS (no graphics device).
.pipeline_diagram <- function(object, lang) {
  nodes <- sprintf(
    "<div class='node node-end'><div class='nl'>Base weights</div><div class='nv'><code>%s</code></div></div>",
    .html_escape(object$base_weights))
  for (i in seq_along(object$steps)) {
    s <- object$steps[[i]]
    nodes <- c(nodes, sprintf(
      "<div class='node'><div class='nl'><span class='num'>%d</span>%s</div>%s</div>",
      i, .step_short(s, lang), .chips(.step_vars(s))))
  }
  nodes <- c(nodes,
    "<div class='node node-end'><div class='nl'>Final weights</div><div class='nv'><code>.weight</code></div></div>")
  hn  <- object$history
  act <- if (!is.null(hn)) vapply(hn, function(w) sum(.wf_active(w)), integer(1)) else integer(0)
  arrows <- vapply(seq_len(length(nodes) - 1L), function(t) {
    lbl <- if (t <= length(act))
      sprintf(" <span class='fn'>n = %s</span>", format(act[t], big.mark = ",")) else ""
    sprintf("<div class='arrow'>&darr;%s</div>", lbl)
  }, character(1))
  out <- character(0)
  for (t in seq_along(nodes)) {
    out <- c(out, nodes[t])
    if (t < length(nodes)) out <- c(out, arrows[t])
  }
  paste0("<div class='flow'>", paste(out, collapse = ""), "</div>")
}

# Overlap (common-support) plot for ML nonresponse: two weighted histograms of
# the estimated propensity phi-hat, respondents vs nonrespondents. Poor overlap
# (little common support) is the visual warning about the MAR assumption.
.svg_overlap <- function(p, resp, dw, lang = "en", w = 340, h = 170) {
  ok <- is.finite(p) & is.finite(dw); p <- p[ok]; resp <- as.logical(resp[ok]); dw <- dw[ok]
  if (length(p) < 20L || length(unique(resp)) < 2L) return("")
  ml <- 42; mr <- 8; mt <- 10; mb <- 30; pw <- w - ml - mr; ph <- h - mt - mb
  rng <- range(p); if (diff(rng) == 0) rng <- rng + c(-0.05, 0.05)
  K  <- 24L; br <- seq(rng[1], rng[2], length.out = K + 1L)
  wprop <- function(sel) {
    if (!any(sel) || sum(dw[sel]) <= 0) return(rep(0, K))
    idx <- findInterval(p[sel], br, rightmost.closed = TRUE, all.inside = TRUE)
    v <- tapply(dw[sel], factor(idx, levels = seq_len(K)), sum)
    v[is.na(v)] <- 0; as.numeric(v) / sum(dw[sel])
  }
  hr <- wprop(resp); hn <- wprop(!resp); ymax <- max(hr, hn, 1e-9)
  sx <- function(z) ml + (z - rng[1]) / diff(rng) * pw
  sy <- function(z) mt + ph - z / ymax * ph
  bar <- function(v, fill) paste(vapply(seq_len(K), function(i) sprintf(
    '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" fill-opacity="0.45"/>',
    sx(br[i]), sy(v[i]), max(sx(br[i + 1]) - sx(br[i]) - 0.5, 0.5),
    max(sy(0) - sy(v[i]), 0), fill), character(1)), collapse = "")
  leg <- sprintf('<text x="%.1f" y="%.1f" font-size="10" fill="#2a78d6">%s</text><text x="%.1f" y="%.1f" font-size="10" fill="#e8941f">%s</text>',
    ml + 6, mt + 10, .t("respondents", "respondentes", lang),
    ml + 6, mt + 22, .t("nonrespondents", "no respondentes", lang))
  .svg_frame(paste0(.svg_axes(ml, mt, pw, ph, rng, c(0, ymax), "&phi;&#770;",
             .t("share", "proporci\u00f3n", lang), sx, sy),
             bar(hn, "#e8941f"), bar(hr, "#2a78d6"), leg), w, h, "propensity overlap")
}

# Potter (1990) MSE-optimal trimming curve: estimated bias^2 (rising as the cut
# tightens), remaining variance (falling), and their sum, over the candidate
# thresholds, with the chosen cutoff marked. The two terms are on different
# scales -- this draws the raw heuristic and labels it an approximation.
.svg_potter <- function(grid, bias2, varc, mse, chosen, lang = "en", w = 360, h = 190) {
  ok <- is.finite(grid) & is.finite(mse) & is.finite(bias2) & is.finite(varc)
  grid <- grid[ok]; bias2 <- bias2[ok]; varc <- varc[ok]; mse <- mse[ok]
  if (length(grid) < 3L) return("")
  ml <- 56; mr <- 12; mt <- 12; mb <- 32; pw <- w - ml - mr; ph <- h - mt - mb
  xr <- range(grid); if (diff(xr) == 0) xr <- xr + c(-1, 1)
  yr <- c(0, max(mse, varc, bias2, 1e-9))
  sx <- function(z) ml + (z - xr[1]) / diff(xr) * pw
  sy <- function(z) mt + ph - z / yr[2] * ph
  path <- function(y, col, wd) sprintf('<path d="M %s" fill="none" stroke="%s" stroke-width="%s"/>',
    paste(sprintf("%.1f %.1f", sx(grid), sy(y)), collapse = " L "), col, wd)
  vln <- sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#c0392b" stroke-width="1" stroke-dasharray="3,2"/>',
    sx(chosen), mt, sx(chosen), mt + ph)
  vtx <- sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="10" fill="#c0392b">%s</text>',
    sx(chosen), mt + 9, .t("chosen", "elegido", lang))
  leg <- sprintf('<text x="%.1f" y="%.1f" font-size="10" fill="#3d3580">MSE</text><text x="%.1f" y="%.1f" font-size="10" fill="#2a78d6">bias&sup2;</text><text x="%.1f" y="%.1f" font-size="10" fill="#e8941f">var</text>',
    ml + 6, mt + 10, ml + 6, mt + 22, ml + 44, mt + 22)
  sprintf("<div class='chart1'>%s</div>",
    .svg_frame(paste0(.svg_axes(ml, mt, pw, ph, xr, yr,
               .t("upper threshold", "umbral superior", lang), "bias&sup2; + var", sx, sy,
               yfmt = .fmt_si),
               path(varc, "#e8941f", "1.2"), path(bias2, "#2a78d6", "1.2"),
               path(mse, "#3d3580", "2"), vln, vtx, leg), w, h, "Potter MSE curve"))
}
