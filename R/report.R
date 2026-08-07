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

.svg_axes <- function(ml, mt, pw, ph, xr, yr, xlab, ylab, sx, sy) {
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
  ytk <- paste(sprintf('<text x="%.1f" y="%.1f" text-anchor="end" font-size="10" fill="#6b7280">%s</text>',
               ml - 5, sy(yt) + 3, .uniq_ticks(yt)), collapse = "")
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
.svg_scatter <- function(x, y, w = 330, h = 215, cap = 3000L) {
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
  .svg_frame(paste0(.svg_axes(ml, mt, pw, ph, xr, yr, "weight before", "weight after", sx, sy),
                    pts, ln, lbl), w, h)
}

# Histogram of a per-unit quantity (default: the adjustment factor after/before),
# with a reference line at 1.
.svg_hist <- function(v, xlab = "adjustment factor (after / before)", w = 330, h = 215, refline = 1) {
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
  .svg_frame(paste0(.svg_axes(ml, mt, pw, ph, xr, yr, xlab, "count", sx, sy),
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
  sc   <- tryCatch(.svg_scatter(prev[keep], cur[keep]), error = function(e) "")
  fac  <- (cur / prev)[keep]
  xlab <- if (inherits(step, "step_select_within"))
            "persons represented (1/prob)" else "adjustment factor (after / before)"
  hi   <- tryCatch(.svg_hist(fac, xlab = xlab), error = function(e) "")
  if (!nzchar(sc) && !nzchar(hi)) return("")
  note <- if (sum(keep) > 3000L)
    sprintf("<p class='muted'>%s</p>", .t(
      sprintf("Showing 3,000 of %s points (both tails and the largest departures from y = x are kept).", format(sum(keep), big.mark = ",")),
      sprintf("Se muestran 3.000 de %s puntos (se conservan ambas colas y las mayores desviaciones de y = x).", format(sum(keep), big.mark = ",")), lang)) else ""
  sprintf("<div class='viz'><div>%s</div><div>%s</div></div>%s", sc, hi, note)
}

# Compact R-indicator block, rendered inside the (last) nonresponse step card.
.ri_block <- function(ri) {
  ph <- ""
  ptab <- ri$partials
  if (!is.null(ptab)) {
    ptab <- ptab[order(-ptab$partial_R), , drop = FALSE]
    ptab$partial_R <- round(ptab$partial_R, 4)
    ph <- paste0("<p class='muted'>Partial R-indicators:</p>", .df_to_html(ptab))
  }
  sprintf(
    "<div class='ri'><h4>Response representativity (R-indicator)</h4>
<p class='muted'>Design-weighted logistic of response on <code>%s</code> (n = %s). Closer to 1 = more representative response; the partials show which variable drives the gap.</p>
<p class='ri-val'><strong>R = %.3f</strong></p>%s</div>",
    .html_escape(paste(ri$aux, collapse = ", ")),
    format(ri$n_eligible, big.mark = ","), ri$R, ph)
}

# Steps that run AFTER calibration (trimming, rounding, rescaling) move the
# weighted totals away from the calibration targets. This recomputes the last
# calibration's categorical targets at the FINAL weights and reports the drift.
# Only shown when there is a calibration step followed by at least one more step.
.calibration_drift <- function(object) {
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
    "<h2>Calibration drift</h2>
<p class='muted'>Steps after calibration (trimming, rounding, rescaling) move the weighted totals away from the calibration targets. <code>achieved</code> is recomputed at the final weights; max deviation %.2f%%.</p>%s",
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
  act <- if (!is.null(hn)) vapply(hn, function(w) sum(w > 0), integer(1)) else integer(0)
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

# ============================================================================
# Automatic methodological narrative (GSBPM 5.6 / ESQRS-style prose). Each step
# gets a natural-language paragraph explaining what was done and why, built from
# the step's own parameters and diagnostics, in English or Spanish.
# ============================================================================

# Pick the English or Spanish variant of a string.
.t <- function(en, es, lang) if (identical(lang, "es")) es else en

# Bold, comma-separated list of a step's auxiliary variables (formula / by /
# margins), with a language-aware final conjunction; a generic phrase if none.
.narr_vars <- function(step, lang) {
  v <- character(0)
  if (!is.null(step$formula)) v <- c(v, all.vars(step$formula))
  if (!is.null(step$by))      v <- c(v, as.character(step$by))
  if (!is.null(step$margins)) v <- c(v, names(step$margins))
  v <- unique(v[nzchar(v)])
  if (!length(v)) return(.t("the auxiliary variables", "las variables auxiliares", lang))
  b <- sprintf("<strong>%s</strong>", .html_escape(v))
  if (length(b) == 1L) return(b)
  paste0(paste(b[-length(b)], collapse = ", "), .t(" and ", " y ", lang), b[length(b)])
}

.deff_phrase <- function(de1, de2, lang)
  .t(sprintf("The Kish design effect went from %.3f to %.3f.", de1$deff, de2$deff),
     sprintf("El efecto de dise\u00f1o de Kish pas\u00f3 de %.3f a %.3f.", de1$deff, de2$deff), lang)

# A short human phrase for a step, used in the executive summary.
.aux_vars <- function(step) {
  if (!is.null(step$margins) && length(step$margins) && !is.null(names(step$margins)))
    return(names(step$margins))
  if (!is.null(step$formula)) {
    tl <- tryCatch(attr(stats::terms(step$formula), "term.labels"), error = function(e) character(0))
    return(tl)
  }
  character(0)
}
.vars_phrase <- function(v, lang) {
  v <- vapply(v[nzchar(v)], .html_escape, "")
  if (!length(v)) return("")
  if (length(v) == 1L) return(unname(v))
  paste0(paste(v[-length(v)], collapse = ", "), " ", .t("and", "y", lang), " ", v[length(v)])
}

.step_short <- function(step, lang) {
  if (inherits(step, "step_unknown_eligibility"))
    return(.t("unknown-eligibility adjustment", "ajuste por elegibilidad desconocida", lang))
  if (inherits(step, "step_drop_ineligible"))
    return(.t("removal of ineligible units", "eliminaci\u00f3n de unidades no elegibles", lang))
  if (inherits(step, "step_select_within"))
    return(.t("within-household selection", "selecci\u00f3n dentro del hogar", lang))
  if (inherits(step, "step_nonresponse")) {
    m <- step$method %||% "weighting_class"
    if (identical(m, "calibration")) {
      vp <- .vars_phrase(.aux_vars(step), lang)
      return(if (nzchar(vp))
        .t(sprintf("nonresponse calibration to %s", vp),
           sprintf("calibraci\u00f3n de no respuesta a %s", vp), lang)
        else .t("nonresponse adjustment (calibration)",
                "ajuste por no respuesta (calibraci\u00f3n)", lang))
    }
    return(switch(m,
      weighting_class = .t("nonresponse adjustment (weighting classes)",
                           "ajuste por no respuesta (clases de ponderaci\u00f3n)", lang),
      propensity = .t(sprintf("nonresponse adjustment (propensity, %s)", step$engine),
                      sprintf("ajuste por no respuesta (propensi\u00f3n, %s)", step$engine), lang)))
  }
  if (inherits(step, "step_calibrate")) {
    vp <- .vars_phrase(.aux_vars(step), lang); greg <- identical(step$method, "linear")
    return(if (nzchar(vp))
      .t(sprintf("%scalibration to %s", if (greg) "GREG " else "", vp),
         sprintf("calibraci\u00f3n %sa %s", if (greg) "GREG " else "", vp), lang)
      else .t("calibration to population totals", "calibraci\u00f3n a totales poblacionales", lang))
  }
  if (inherits(step, "step_model_calibration"))
    return(.t("model-assisted calibration", "calibraci\u00f3n asistida por modelo", lang))
  if (inherits(step, "step_trim_calibrated"))
    return(.t("calibration-preserving trimming", "recorte que preserva la calibraci\u00f3n", lang))
  if (inherits(step, "step_trim_weights"))
    return(.t("weight trimming", "recorte de pesos", lang))
  if (inherits(step, "step_round"))  return(.t("rounding", "redondeo", lang))
  if (inherits(step, "step_rescale")) return(.t("rescaling", "reescalado", lang))
  if (inherits(step, "step_assert")) return(.t("quality checkpoint", "punto de control", lang))
  .html_escape(step$label)
}

# The per-step methodological paragraph.
.step_narrative <- function(step, de1, de2, ri, is_nr_last, lang) {
  vlab <- .narr_vars(step, lang)
  txt  <- ""

  if (inherits(step, "step_unknown_eligibility")) {
    lvl <- if (!is.null(step$cluster)) .t("at the household level", "a nivel de hogar", lang)
           else .t("at the unit level", "a nivel de unidad", lang)
    txt <- .t(
      sprintf("Cases of unknown eligibility had their weight redistributed to the resolved (known-eligibility) cases %s, so the unresolved cases do not bias the eligible totals.", lvl),
      sprintf("A los casos de elegibilidad desconocida se les redistribuy\u00f3 el peso entre los casos resueltos (de elegibilidad conocida) %s, para que los no resueltos no sesguen los totales de elegibles.", lvl),
      lang)
  } else if (inherits(step, "step_drop_ineligible")) {
    txt <- .t("Units identified as out of scope (ineligible) were removed from the cascade, setting their weight to zero so they do not contribute to any later estimate.",
              "Las unidades identificadas como fuera del universo (no elegibles) se eliminaron de la cascada, poniendo su peso en cero para que no contribuyan a ninguna estimaci\u00f3n posterior.", lang)
  } else if (inherits(step, "step_select_within")) {
    txt <- .t("A within-household selection adjustment was applied: the selected person's weight was multiplied by the inverse of its within-household selection probability, so it represents all the eligible members of the household.",
              "Se aplic\u00f3 un ajuste por selecci\u00f3n dentro del hogar: el peso de la persona seleccionada se multiplic\u00f3 por el inverso de su probabilidad de selecci\u00f3n intra-hogar, de modo que representa a todos los miembros elegibles del hogar.", lang)
  } else if (inherits(step, "step_nonresponse")) {
    m <- step$method %||% "weighting_class"
    if (m == "weighting_class") {
      txt <- .t(
        sprintf("The nonresponse adjustment was made by weighting classes (adjustment cells) defined by %s: within each cell the respondents' weights were inflated to represent the nonrespondents, under the assumption that response is ignorable given those variables.", vlab),
        sprintf("El ajuste por no respuesta se realiz\u00f3 mediante clases de ponderaci\u00f3n (celdas de ajuste) definidas por %s: dentro de cada celda se infl\u00f3 el peso de los respondentes para representar a los no respondentes, bajo el supuesto de que la respuesta es ignorable dadas esas variables.", vlab),
        lang)
    } else if (m == "propensity") {
      cf <- if (!is.null(step$crossfit))
        .t(sprintf(" with %d-fold cross-fitting", step$crossfit),
           sprintf(" con validaci\u00f3n cruzada de %d particiones", step$crossfit), lang) else ""
      cls <- if (!is.null(step$num_classes))
        .t(sprintf(" The estimated propensities were grouped into %d classes to stabilise the adjustment.", step$num_classes),
           sprintf(" Las propensiones estimadas se agruparon en %d clases para estabilizar el ajuste.", step$num_classes), lang)
        else .t(" Each respondent was reweighted by the inverse of its estimated propensity.",
                " Cada respondente se reponder\u00f3 por el inverso de su propensi\u00f3n estimada.", lang)
      txt <- .t(
        sprintf("The nonresponse adjustment used a response-propensity model based on the <strong>%s</strong> algorithm%s, with predictors %s selected for their association with the response pattern and their availability for every eligible case in the sample.%s", step$engine, cf, vlab, cls),
        sprintf("El ajuste por no respuesta us\u00f3 un modelo de propensi\u00f3n basado en el algoritmo <strong>%s</strong>%s, con las variables predictoras %s, elegidas por su asociaci\u00f3n con el patr\u00f3n de respuesta y su disponibilidad para todos los casos elegibles en la muestra.%s", step$engine, cf, vlab, cls),
        lang)
    } else {
      tgt <- if (is.null(step$totals))
        .t("the full-sample (respondents + nonrespondents) design-weighted totals",
           "los totales ponderados por dise\u00f1o de la muestra completa (respondentes + no respondentes)", lang)
        else .t("the supplied population totals", "los totales poblacionales provistos", lang)
      integ <- if (isTRUE(step$equal_within_cluster))
        .t(", with one weight per household (integrative)", ", con un peso por hogar (integrativa)", lang) else ""
      txt <- .t(
        sprintf("The nonresponse adjustment used the two-phase calibration approach (Sarndal-Lundstrom): the respondents' weights were calibrated to %s of %s%s, so the adjusted estimates reproduce the pre-nonresponse ones.", tgt, vlab, integ),
        sprintf("El ajuste por no respuesta us\u00f3 el enfoque de calibraci\u00f3n a dos fases (Sarndal-Lundstrom): se calibraron los pesos de los respondentes a %s de %s%s, de modo que las estimaciones ajustadas reproducen las previas a la no respuesta.", tgt, vlab, integ),
        lang)
    }
    if (isTRUE(is_nr_last) && !is.null(ri)) {
      top <- ""
      if (!is.null(ri$partials) && nrow(ri$partials)) {
        pt <- ri$partials[order(-ri$partials$partial_R), , drop = FALSE]
        k  <- min(2L, nrow(pt))
        tv <- sprintf("<strong>%s</strong> (%.4f)", .html_escape(pt$variable[seq_len(k)]),
                      pt$partial_R[seq_len(k)])
        top <- .t(sprintf(" The variables with the largest remaining influence are %s.", paste(tv, collapse = ", ")),
                  sprintf(" Las variables con mayor influencia remanente son %s.", paste(tv, collapse = ", ")), lang)
      }
      txt <- paste0(txt, .t(
        sprintf(" The resulting R-indicator is %.3f (closer to 1 means a more representative response and lower nonresponse-bias risk).%s", ri$R, top),
        sprintf(" El R-indicator resultante es %.3f (m\u00e1s cerca de 1 indica una respuesta m\u00e1s representativa y menor riesgo de sesgo por no respuesta).%s", ri$R, top),
        lang))
    }
  } else if (inherits(step, "step_calibrate")) {
    meth <- switch(step$method %||% "raking",
      raking = .t("raking (iterative proportional fitting of the margins)",
                  "raking (ajuste iterativo proporcional de los m\u00e1rgenes)", lang),
      poststratify = .t("post-stratification (adjustment to the joint cell counts)",
                        "post-estratificaci\u00f3n (ajuste a los conteos de celdas conjuntas)", lang),
      linear = .t("linear (GREG) calibration", "calibraci\u00f3n lineal (GREG)", lang),
      .t("calibration", "calibraci\u00f3n", lang))
    dist <- if (!is.null(step$calfun) && identical(step$method, "linear") && step$calfun != "linear")
      .t(sprintf(" using the %s distance", step$calfun), sprintf(" con la distancia %s", step$calfun), lang) else ""
    bnd <- if (!is.null(step$bounds))
      .t(sprintf(", bounded so the adjustment factor stays in (%.2f, %.2f)", step$bounds[1], step$bounds[2]),
         sprintf(", acotada para que el factor de ajuste quede en (%.2f, %.2f)", step$bounds[1], step$bounds[2]), lang) else ""
    integ <- if (isTRUE(step$equal_within_cluster))
      .t(", integrative (one weight per household)", ", integrativa (un peso por hogar)", lang) else ""
    ridge <- if (!is.null(step$penalty))
      .t(", ridge-penalised for stability", ", con penalizaci\u00f3n ridge para estabilidad", lang) else ""
    txt <- paste0(.t(
      sprintf("The weights were calibrated to the known population totals of %s using %s%s%s%s%s, so the weighted sample reproduces those totals while staying as close as possible to the incoming weights (Deville and Sarndal 1992).", vlab, meth, dist, bnd, integ, ridge),
      sprintf("Los pesos se calibraron a los totales poblacionales conocidos de %s mediante %s%s%s%s%s, de modo que la muestra ponderada reproduce esos totales manteni\u00e9ndose lo m\u00e1s cerca posible de los pesos de entrada (Deville y Sarndal 1992).", vlab, meth, dist, bnd, integ, ridge),
      lang), " ", .deff_phrase(de1, de2, lang))
  } else if (inherits(step, "step_model_calibration")) {
    txt <- paste0(.t(
      "Model-assisted (Wu-Sitter) calibration was applied: predictions of the outcome model were used as auxiliaries and calibrated to their population totals, borrowing strength from the predictive model.",
      "Se aplic\u00f3 calibraci\u00f3n asistida por modelo (Wu-Sitter): las predicciones del modelo de resultado se usaron como auxiliares y se calibraron a sus totales poblacionales, aprovechando la fuerza del modelo predictivo.",
      lang), " ", .deff_phrase(de1, de2, lang))
  } else if (inherits(step, "step_trim_calibrated")) {
    # Preserved totals are ONLY the formula's auxiliaries; `by` is the subgroup
    # for the bounds, not a preserved total, so it must not appear in `vlab`.
    fv   <- all.vars(step$formula)
    vlab <- {
      b <- sprintf("<strong>%s</strong>", .html_escape(fv))
      if (length(b) <= 1L) paste(b, collapse = "")
      else paste0(paste(b[-length(b)], collapse = ", "),
                  .t(" and ", " y ", lang), b[length(b)])
    }
    per_group <- !is.null(step$by) &&
      (length(step$lower) > 1L || length(step$upper) > 1L)
    if (per_group) {
      grps <- unique(c(names(step$lower), names(step$upper)))
      pick <- function(b, g, d) if (is.null(b)) d
                                else if (length(b) > 1L) format(b[[g]]) else format(b)
      per  <- vapply(grps, function(g)
        sprintf("%s [%s, %s]", .html_escape(g), pick(step$lower, g, "-Inf"),
                pick(step$upper, g, "Inf")),
        character(1))
      byl  <- .html_escape(step$by)
      rlab <- .t(sprintf("with per-%s bounds (%s)", byl, paste(per, collapse = "; ")),
                 sprintf("con cotas por %s (%s)", byl, paste(per, collapse = "; ")), lang)
    } else {
      lo <- if (is.null(step$lower)) "-Inf" else format(step$lower)
      up <- if (is.null(step$upper)) "Inf"  else format(step$upper)
      rlab <- .t(sprintf("into the range [%s, %s]", lo, up),
                 sprintf("al rango [%s, %s]", lo, up), lang)
    }
    integ <- if (isTRUE(step$equal_within_cluster))
      .t(", one factor per household", ", un factor por hogar", lang) else ""
    txt <- paste0(.t(
      sprintf("The calibrated weights were trimmed %s while preserving the calibration totals of %s (a range-restricted, totals-preserving re-calibration%s), so the trimming reduces extreme weights without breaking the calibration constraints.", rlab, vlab, integ),
      sprintf("Los pesos calibrados se recortaron %s preservando los totales de calibraci\u00f3n de %s (una recalibraci\u00f3n acotada que conserva los totales%s), de modo que el recorte reduce los pesos extremos sin romper las restricciones de calibraci\u00f3n.", rlab, vlab, integ),
      lang), " ", .deff_phrase(de1, de2, lang))
  } else if (inherits(step, "step_trim_weights")) {
    rng <- sprintf("[%s, %s]", format(step$lower),
                   if (is.null(step$upper)) .t("auto", "autom\u00e1tico", lang) else format(step$upper))
    rule <- if (identical(step$method, "potter"))
      .t("Potter's MSE-optimal rule", "la regla \u00f3ptima en ECM de Potter", lang)
      else .t("the Tukey fence rule", "la regla del cerco de Tukey", lang)
    txt <- paste0(.t(
      sprintf("Extreme weights were trimmed to the interval %s (%s), redistributing the trimmed mass among the untrimmed units to preserve the total.", rng, rule),
      sprintf("Los pesos extremos se recortaron al intervalo %s (%s), redistribuyendo la masa recortada entre las unidades no recortadas para preservar el total.", rng, rule),
      lang), " ", .deff_phrase(de1, de2, lang))
  } else if (inherits(step, "step_round")) {
    txt <- .t("The final weights were rounded, for delivery of integer or fixed-precision weights.",
              "Los pesos finales se redondearon, para entregar pesos enteros o de precisi\u00f3n fija.", lang)
  } else if (inherits(step, "step_rescale")) {
    txt <- .t("The weights were rescaled so their sum matches the requested target (the number of units or a fixed population total).",
              "Los pesos se reescalaron para que su suma coincida con el objetivo pedido (el n\u00famero de unidades o un total poblacional fijo).", lang)
  } else if (inherits(step, "step_assert")) {
    txt <- .t("A quality checkpoint verified the weight diagnostics (design effect, weight ratio, effective sample size) against the configured thresholds.",
              "Un punto de control de calidad verific\u00f3 los diagn\u00f3sticos de los pesos (efecto de dise\u00f1o, raz\u00f3n de pesos, tama\u00f1o efectivo) contra los umbrales configurados.", lang)
  } else return("")

  if (!nzchar(txt)) return("")
  sprintf("<p class='methodological-note'>%s</p>", txt)
}

# Auto-generated executive summary paragraph for the top of the report.
.exec_summary <- function(object, ri, de_f, lang, survey = NULL) {
  shorts <- vapply(object$steps, function(s) .step_short(s, lang), character(1))
  n <- length(shorts)
  listed <- paste(sprintf("(%d) %s", seq_len(n), shorts), collapse = ", ")
  what <- if (!is.null(survey))
    .t(sprintf("the weights for <strong>%s</strong>", .html_escape(survey)),
       sprintf("los pesos de <strong>%s</strong>", .html_escape(survey)), lang)
    else .t("the survey weights", "los pesos de la encuesta", lang)
  ri_s <- if (!is.null(ri))
    .t(sprintf("; the response R-indicator is %.3f", ri$R),
       sprintf("; el R-indicator de respuesta es %.3f", ri$R), lang) else ""
  body <- .t(
    sprintf("This report documents the construction of %s. %d adjustment %s applied: %s. The final weights have a Kish design effect of %.3f (effective sample size %s%s).",
            what, n, if (n == 1L) "step was" else "steps were", listed, de_f$deff,
            format(round(de_f$n_eff), big.mark = ","), ri_s),
    sprintf("Este reporte documenta la construcci\u00f3n de %s. Se aplicaron %d paso%s de ajuste: %s. Los pesos finales tienen un efecto de dise\u00f1o de Kish de %.3f (tama\u00f1o de muestra efectivo %s%s).",
            what, n, if (n == 1L) "" else "s", listed, de_f$deff,
            format(round(de_f$n_eff), big.mark = ","), ri_s),
    lang)
  sprintf("<div class='exec'><h4>%s</h4><p>%s</p></div>",
          .t("Executive summary", "Resumen ejecutivo", lang), body)
}

# Aggregates non-convergence and quality alerts across steps into a top panel
# with conservative, templated recommendations. Empty string when all clear.
.attention_panel <- function(object, lang) {
  items <- character(0)
  for (i in seq_along(object$steps)) {
    st  <- object$steps[[i]]
    lbl <- .html_escape(st$label)
    if (identical(attr(st$diagnostics, "converged"), FALSE))
      items <- c(items, .t(
        sprintf("<strong>Step %d (%s)</strong> did not converge &mdash; relax the bounds or increase <code>maxit</code>, and check that the margins are mutually consistent.", i, lbl),
        sprintf("<strong>Paso %d (%s)</strong> no convergi\u00f3 &mdash; relaje las cotas o aumente <code>maxit</code>, y verifique que los m\u00e1rgenes sean consistentes entre s\u00ed.", i, lbl), lang))
    al <- st$alerts
    if (!is.null(al) && length(al))
      for (a in al)
        items <- c(items, sprintf("<strong>%s %d (%s)</strong>: %s",
                                  .t("Step", "Paso", lang), i, lbl, .html_escape(a)))
  }
  if (!length(items)) return("")
  sprintf("<div class='exec attention'><h4>%s</h4><ul>%s</ul></div>",
          .t("Points of attention", "Puntos de atenci\u00f3n", lang),
          paste0("<li>", items, "</li>", collapse = ""))
}

# Truthful status checklist (green when OK, amber when not) for the summary.
.status_checklist <- function(object, de_f, fin, replicates, lang) {
  nonconv <- sum(vapply(object$steps, function(s)
    identical(attr(s$diagnostics, "converged"), FALSE), logical(1)))
  nalert  <- sum(vapply(object$steps, function(s)
    !is.null(s$alerts) && length(s$alerts) > 0L, logical(1)))
  pos <- fin[fin > 0]; med <- stats::median(pos); n_ext <- sum(pos > 4 * med)
  has_rep <- !is.null(replicates) &&
             inherits(replicates, c("weightflow_boot", "weightflow_jack"))
  item <- function(ok, txt) sprintf("<li><span class='%s'>%s</span> %s</li>",
    if (ok) "ok" else "no", if (ok) "&#10003;" else "&#10007;", txt)
  items <- c(
    item(nonconv == 0L, if (nonconv == 0L)
      .t("All calibration steps converged.", "Todos los pasos de calibraci\u00f3n convergieron.", lang)
      else .t(sprintf("%d step(s) did not converge.", nonconv),
              sprintf("%d paso(s) no convergieron.", nonconv), lang)),
    item(TRUE, .t(sprintf("Final Kish design effect = %.3f (effective n = %s).",
                          de_f$deff, format(round(de_f$n_eff), big.mark = ",")),
                  sprintf("Efecto de dise\u00f1o de Kish final = %.3f (n efectivo = %s).",
                          de_f$deff, format(round(de_f$n_eff), big.mark = ",")), lang)),
    item(n_ext == 0L, if (n_ext == 0L)
      .t("No extreme weights (above 4x the median).", "Sin pesos extremos (mayores a 4x la mediana).", lang)
      else .t(sprintf("%d extreme weight(s) above 4x the median.", n_ext),
              sprintf("%d peso(s) extremo(s) por encima de 4x la mediana.", n_ext), lang)),
    item(has_rep, if (has_rep)
      .t("Replicate weights for variance created.", "Pesos r\u00e9plica para la varianza creados.", lang)
      else .t("Replicate weights not created (add bootstrap/jackknife for variance).",
              "Sin pesos r\u00e9plica (agregue bootstrap/jackknife para la varianza).", lang)))
  for (si in seq_along(object$steps)) {
    al <- object$steps[[si]]$alerts
    if (!is.null(al) && length(al))
      for (a in al)
        items <- c(items, item(FALSE, sprintf("%s %d (%s): %s",
                   .t("Step", "Paso", lang), si, .html_escape(object$steps[[si]]$label), .html_escape(a))))
  }
  sprintf("<div class='exec'><h4>%s</h4><ul class='chk'>%s</ul></div>",
          .t("Status", "Estado", lang), paste(items, collapse = ""))
}

# Optional card: per-domain reliability. `domains` is a formula whose terms
# become one table each ("+" = separate tables, ":" = crossed). Each table shows
# n, sum of weights, CV, Kish deff and effective n within the domain.
.domain_reliability <- function(object, domains, lang) {
  if (is.null(domains)) return("")
  tl <- tryCatch(attr(stats::terms(stats::as.formula(domains)), "term.labels"),
                 error = function(e) character(0))
  if (!length(tl)) return("")
  d   <- object$data
  fin <- object$final_weight
  d3  <- function(x) formatC(x, format = "f", digits = 3)
  num <- function(x) format(round(x), big.mark = ",")
  dcell <- function(v) if (is.na(v)) "&ndash;" else
    sprintf("<span class='%s'>%s%s</span>", if (v > 1.3) "cell-warn" else "cell-ok", if (v > 1.3) "&#9888; " else "", d3(v))
  hd <- paste0("<th>", c(.t("Domain", "Dominio", lang),
                         .t("Active units (n)", "Unidades activas (n)", lang),
                         .t("Sum of weights (&Sigma;w)", "Suma de pesos (&Sigma;w)", lang),
                         .t("CV of weights", "CV de los pesos", lang),
                         .t("deff_K", "deff_K", lang),
                         .t("Effective n (n_eff)", "n efectivo (n_eff)", lang)),
               "</th>", collapse = "")
  tables <- character(0)
  for (term in tl) {
    vars <- strsplit(term, ":", fixed = TRUE)[[1]]
    if (!all(vars %in% names(d))) next
    g <- interaction(lapply(vars, function(v) as.character(d[[v]])),
                     drop = TRUE, sep = " \u00d7 ")
    rows <- vapply(levels(g), function(l) {
      idx <- which(g == l)
      de  <- design_effect(fin[idx])
      sprintf("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>",
              .html_escape(l), num(de$n), num(sum(fin[idx])),
              if (is.na(de$cv)) "&ndash;" else d3(de$cv), dcell(de$deff), num(de$n_eff))
    }, character(1))
    tables <- c(tables, sprintf(
      "<p class='muted'>%s <code>%s</code></p><table class='stagetbl'><thead><tr>%s</tr></thead><tbody>%s</tbody></table>",
      .t("By", "Por", lang), .html_escape(term), hd, paste(rows, collapse = "")))
  }
  if (!length(tables)) return("")
  sprintf("<div class='meta'><h4>%s</h4>%s<p class='note'>%s</p></div>",
          .t("Domain reliability", "Fiabilidad por dominio", lang),
          paste(tables, collapse = ""),
          .t("Effective sample size and design effect within each domain; domains with a small effective n yield less reliable estimates.",
             "Tama\u00f1o de muestra efectivo y efecto de dise\u00f1o dentro de cada dominio; los dominios con n efectivo chico dan estimaciones menos confiables.", lang))
}

# Optional card: replication design for variance (from a weightflow_boot /
# weightflow_jack object passed via `replicates`). Reads only stored metadata.
.replication_card <- function(rep, lang) {
  if (is.null(rep) || !inherits(rep, c("weightflow_boot", "weightflow_jack")))
    return("")
  is_jack <- inherits(rep, "weightflow_jack")
  method <- if (is_jack)
    (if (!is.null(rep$strata))
       .t("Jackknife (delete-a-PSU, JKn)", "Jackknife (borra-una-UPM, JKn)", lang)
     else .t("Jackknife (JK1)", "Jackknife (JK1)", lang))
    else .t("Bootstrap (Rao-Wu rescaling)", "Bootstrap (reescalado Rao-Wu)", lang)
  d  <- rep$data
  st <- if (is.null(rep$strata)) rep("1", nrow(d)) else as.character(d[[rep$strata]])
  cl <- if (is.null(rep$psu)) as.character(seq_len(nrow(d))) else as.character(d[[rep$psu]])
  nstr     <- length(unique(st))
  pps      <- tapply(cl, st, function(z) length(unique(z)))
  lonely_n <- sum(pps < 2L)
  secs <- rep$elapsed
  nrep  <- if (!is.null(rep$replicates)) ncol(rep$replicates) else rep$R
  nfail <- if (!is.null(rep$replicates)) sum(apply(rep$replicates, 2, anyNA)) else 0L
  tfmt <- if (is.null(secs) || is.na(secs)) "-" else
    if (secs < 90) sprintf("%.1f s", secs) else sprintf("%.1f min", secs / 60)
  na  <- function(x) if (is.null(x) || (length(x) == 1L && is.na(x))) "-" else as.character(x)
  kv  <- function(k, v) sprintf("<tr><td class='k'>%s</td><td class='r'>%s</td></tr>", k, v)
  body <- paste0(
    kv(.t("Method", "M\u00e9todo", lang), method),
    kv(.t("Replicates (B)", "R\u00e9plicas (B)", lang), format(rep$R, big.mark = ",")),
    kv(.t("Failed replicates", "R\u00e9plicas fallidas", lang),
       sprintf("%s of %s%s", format(nfail, big.mark = ","), format(nrep, big.mark = ","),
               if (nfail == 0L) .t(" (all usable)", " (todas utilizables)", lang) else "")),
    kv(.t("Strata", "Estratos", lang), format(nstr, big.mark = ",")),
    kv(.t("PSUs per stratum (mean)", "UPM por estrato (media)", lang), sprintf("%.1f", mean(pps))),
    kv(.t("Lonely-PSU handling", "Manejo de lonely PSU", lang), na(rep$lonely_psu)),
    kv(.t("Recipe-aware", "Recipe-aware", lang),
       .t("yes (whole cascade re-run per replicate)", "s\u00ed (toda la cascada por r\u00e9plica)", lang)),
    if (!is_jack) kv(.t("Seed", "Semilla", lang), na(rep$seed)) else "",
    kv(.t("Cores", "Cores", lang), na(rep$cores)),
    kv(.t("Run time", "Tiempo de ejecuci\u00f3n", lang), tfmt))
  warn <- if (lonely_n > 0L || mean(pps) < 3) sprintf(
    "<div class='alert'><strong>%s</strong><p>%s</p></div>",
    .t("Point of attention", "Punto de atenci\u00f3n", lang),
    .t(sprintf("%d stratum/strata have a single PSU; with few PSUs per stratum prefer JKn over the rescaling bootstrap, which underestimates the variance.", lonely_n),
       sprintf("%d estrato(s) con una sola UPM; con pocas UPM por estrato conviene JKn sobre el bootstrap de reescalado, que subestima la varianza.", lonely_n), lang)) else ""
  sprintf(
    "<div class='meta racct'><h4>%s</h4><table class='params'><tbody>%s</tbody></table>%s<p class='note'>%s</p></div>",
    .t("Replication design for variance", "Dise\u00f1o de replicaci\u00f3n para la varianza", lang),
    body, warn,
    .t("Replicate weights carry the variability of every adjustment. For standard errors, CV and confidence intervals of specific estimates, use these weights with the 'survey' or 'srvyr' package.",
       "Los pesos r\u00e9plica arrastran la variabilidad de cada ajuste. Para errores est\u00e1ndar, CV e intervalos de confianza de estimaciones concretas, us\u00e1 estos pesos con 'survey' o 'srvyr'.", lang))
}


# Fieldwork outcome rates (AAPOR Standard Definitions). From the recipe's
# eligibility / nonresponse steps we reconstruct the disposition of every case
# -- ineligible (out of scope), unknown eligibility, eligible respondent,
# eligible nonrespondent -- and report the eligibility rate e (proportional /
# CASRO allocation), the e-adjusted response rate RR3 = R / (R + NR + e*U) and
# the nonresponse rate, both unweighted and weighted by the base (design)
# weights. Returns "" when the recipe has no nonresponse step.
.response_account <- function(object, lang) {
  steps <- object$steps
  is_nr <- vapply(steps, function(s) inherits(s, "step_nonresponse"), logical(1))
  if (!any(is_nr)) return("")
  h   <- object$history
  bw  <- h[["base"]]
  dat <- object$data
  n   <- length(bw)
  ev  <- function(expr, active) {
    v <- tryCatch(as.logical(.eval_cond(expr, dat)), error = function(e) NULL)
    if (is.null(v) || length(v) != n) return(rep(FALSE, n))
    v[is.na(v)] <- FALSE
    v & active
  }
  U <- NE <- rep(FALSE, n)
  iu <- which(vapply(steps, function(s) inherits(s, "step_unknown_eligibility"), logical(1)))
  if (length(iu)) { k <- iu[1L]; U  <- ev(steps[[k]]$unknown,    h[[k]] > 0) }
  id <- which(vapply(steps, function(s) inherits(s, "step_drop_ineligible"), logical(1)))
  if (length(id)) { k <- id[1L]; NE <- ev(steps[[k]]$ineligible, h[[k]] > 0) }
  kr   <- max(which(is_nr))
  actr <- h[[kr]] > 0
  R    <- ev(steps[[kr]]$respondent, actr)
  NR   <- actr & !R

  cnt  <- c(T = n, NE = sum(NE), U = sum(U), R = sum(R), NR = sum(NR))
  wsum <- c(T = sum(bw), NE = sum(bw[NE]), U = sum(bw[U]),
            R = sum(bw[R]), NR = sum(bw[NR]))
  rate <- function(r, nr, ne, u) {
    known <- r + nr
    e   <- if (known + ne > 0) known / (known + ne) else NA_real_
    ee  <- if (is.na(e)) 0 else e
    rr_all <- if (r + nr + u > 0)      r / (r + nr + u)      else NA_real_  # RR1: todos los U elegibles
    rr_e   <- if (r + nr + ee * u > 0) r / (r + nr + ee * u) else NA_real_  # RR3/CASRO: fraccion e*U
    rr_no  <- if (r + nr > 0)          r / (r + nr)          else NA_real_  # RR5: U excluidos
    c(e = e, rr_all = rr_all, rr_e = rr_e, rr_no = rr_no, nrr = 1 - rr_e)
  }
  ru <- rate(cnt[["R"]],  cnt[["NR"]],  cnt[["NE"]],  cnt[["U"]])
  rw <- rate(wsum[["R"]], wsum[["NR"]], wsum[["NE"]], wsum[["U"]])

  f0  <- function(x) format(round(x), big.mark = ",")
  pct <- function(x) sprintf("%.1f%%", 100 * x / cnt[["T"]])
  prr <- function(x) if (is.na(x)) "&ndash;" else sprintf("%.1f%%", 100 * x)
  sym <- function(lbl, sy) sprintf(
    "%s <span class='muted' style='font-family:ui-monospace,Menlo,monospace'>(%s)</span>", lbl, sy)
  lab <- list(
    T  = sym(.t("Total sample (issued cases)", "Muestra total (casos emitidos)", lang), "n"),
    NE = sym(.t("Ineligible / out of scope", "Inelegibles / fuera de alcance", lang), "NE"),
    U  = sym(.t("Unknown eligibility", "Elegibilidad desconocida", lang), "U"),
    R  = sym(.t("Eligible respondents", "Elegibles respondentes", lang), "R"),
    NR = sym(.t("Eligible nonrespondents", "Elegibles no respondentes", lang), "NR"))
  arows <- paste(vapply(c("T", "NE", "U", "R", "NR"), function(k)
    sprintf("<tr><td class='k'>%s</td><td class='r'>%s</td><td class='r'>%s</td><td class='r'>%s</td></tr>",
            lab[[k]], f0(cnt[[k]]),
            if (k == "T") "" else pct(cnt[[k]]), f0(wsum[[k]])), character(1)),
    collapse = "")
  rrow <- function(name, u, w)
    sprintf("<tr><td class='k'>%s</td><td class='r'>%s</td><td class='r'>%s</td></tr>",
            name, prr(u), prr(w))
  fx <- function(f) sprintf(
    "<div class='muted' style='font-weight:400;font-family:ui-monospace,Menlo,monospace;margin-top:2px'>%s</div>", f)
  rrows <- paste0(
    rrow(paste0(.t("Eligibility rate (e)", "Tasa de elegibilidad (e)", lang),
                fx("e = (R + NR) / (R + NR + NE)")), ru[["e"]], rw[["e"]]),
    rrow(paste0(.t("Response rate &mdash; all unknowns eligible (AAPOR RR1)",
                   "Tasa de respuesta &mdash; todos los desconocidos elegibles (AAPOR RR1)", lang),
                fx("RR1 = R / (R + NR + U)")), ru[["rr_all"]], rw[["rr_all"]]),
    rrow(paste0(.t("Response rate &mdash; e-adjusted (AAPOR RR3, CASRO)",
                   "Tasa de respuesta &mdash; ajustada por e (AAPOR RR3, CASRO)", lang),
                fx("RR3 = R / (R + NR + e&middot;U)")), ru[["rr_e"]], rw[["rr_e"]]),
    rrow(paste0(.t("Response rate &mdash; unknowns excluded (AAPOR RR5)",
                   "Tasa de respuesta &mdash; desconocidos excluidos (AAPOR RR5)", lang),
                fx("RR5 = R / (R + NR)")), ru[["rr_no"]], rw[["rr_no"]]),
    rrow(.t("Nonresponse rate (1 &minus; RR3)", "Tasa de no respuesta (1 &minus; RR3)", lang),
         ru[["nrr"]], rw[["nrr"]]))
  foot <- .t(
    "Symbols: R = eligible respondents, NR = eligible nonrespondents, NE = ineligibles, U = unknown eligibility, n = total (the disposition counts above; the weighted column uses their base-weighted sums). AAPOR Standard Definitions. e is the eligibility rate among cases of known eligibility (proportional / CASRO allocation). The response rate is shown in three variants, from most to least conservative by how the unknown-eligibility cases (U) are treated: RR1 counts all U as eligible, R / (R + NR + U); RR3 counts the estimated fraction e&middot;U (CASRO), R / (R + NR + e&middot;U); RR5 excludes U, R / (R + NR). Thus RR1 &le; RR3 &le; RR5 (no partials are distinguished, so RR1=RR2, RR3=RR4, RR5=RR6). The weighted column uses the base (design) weights.",
    "S\u00edmbolos: R = elegibles respondentes, NR = elegibles no respondentes, NE = inelegibles, U = elegibilidad desconocida, n = total (los conteos de la tabla de arriba; la columna ponderada usa sus sumas ponderadas por el peso base). AAPOR Standard Definitions. e es la tasa de elegibilidad entre casos de elegibilidad conocida (asignaci\u00f3n proporcional / CASRO). La tasa de respuesta se muestra en tres variantes, de la m\u00e1s a la menos conservadora seg\u00fan c\u00f3mo se tratan los casos de elegibilidad desconocida (U): RR1 cuenta todos los U como elegibles, R / (R + NR + U); RR3 cuenta la fracci\u00f3n estimada e&middot;U (CASRO), R / (R + NR + e&middot;U); RR5 excluye los U, R / (R + NR). As\u00ed RR1 &le; RR3 &le; RR5 (no se distinguen parciales, por lo que RR1=RR2, RR3=RR4, RR5=RR6). La columna ponderada usa el peso base (de dise\u00f1o).",
    lang)
  sprintf("<div class='meta racct'><h4>%s</h4>
    <table class='params'><thead><tr><th>%s</th><th class='r'>%s</th><th class='r'>%%</th><th class='r'>%s</th></tr></thead><tbody>%s</tbody></table>
    <table class='params' style='margin-top:10px'><thead><tr><th>%s</th><th class='r'>%s</th><th class='r'>%s</th></tr></thead><tbody>%s</tbody></table>
    <p class='note'>%s</p></div>",
    .t("Fieldwork outcomes (AAPOR)", "Resultados del trabajo de campo (AAPOR)", lang),
    .t("Disposition", "Disposici\u00f3n", lang),
    .t("n (cases)", "n (casos)", lang),
    .t("weighted (base)", "ponderado (base)", lang), arows,
    .t("Rate", "Tasa", lang),
    .t("unweighted", "sin ponderar", lang),
    .t("weighted (base)", "ponderado (base)", lang), rrows, foot)
}

# Reference-metadata card (SIMS / ESMS concepts relevant to weighting, GSBPM
# 5.6). `md` is a user-supplied named list; recognised keys get a proper
# bilingual label in a fixed order, and any extra keys are shown generically.
.metadata_card <- function(md, lang) {
  if (is.null(md) || !length(md)) return("")
  known <- c(
    survey          = .t("Statistical operation", "Operaci\u00f3n estad\u00edstica", lang),
    reference_period= .t("Reference period", "Per\u00edodo de referencia", lang),
    geography       = .t("Geographic coverage", "Cobertura geogr\u00e1fica", lang),
    producer        = .t("Producer / unit", "Productor / unidad", lang),
    author          = .t("Prepared by", "Elaborado por", lang),
    contact         = .t("Contact", "Contacto", lang),
    frame           = .t("Sampling frame / source", "Marco muestral / fuente", lang),
    totals_source   = .t("Calibration totals: source", "Totales de calibraci\u00f3n: fuente", lang),
    totals_date     = .t("Calibration totals: reference date", "Totales de calibraci\u00f3n: fecha de referencia", lang),
    version         = .t("Version", "Versi\u00f3n", lang),
    confidentiality = .t("Confidentiality", "Confidencialidad", lang),
    notes           = .t("Notes", "Notas", lang))
  row <- function(k, v) sprintf("<tr><td class='k'>%s</td><td>%s</td></tr>",
                                k, .html_escape(as.character(v)))
  rows <- row(.t("GSBPM sub-process", "Subproceso GSBPM", lang), "5.6 Calculate weights")
  for (k in names(known)) if (!is.null(md[[k]]) && nzchar(as.character(md[[k]])))
    rows <- paste0(rows, row(known[[k]], md[[k]]))
  for (k in setdiff(names(md), names(known)))
    if (nzchar(k) && !is.null(md[[k]]) && nzchar(as.character(md[[k]])))
      rows <- paste0(rows, row(.html_escape(k), md[[k]]))
  sprintf("<div class='meta'><h4>%s</h4><table class='params'>%s</table></div>",
          .t("Reference metadata (SIMS / GSBPM 5.6)", "Metadatos de referencia (SIMS / GSBPM 5.6)", lang),
          rows)
}

#' Build a nice HTML report of the weighting recipe
#'
#' Writes a self-contained HTML file (no dependencies, no server) showing the
#' pipeline, the parameters requested at each step, the per-stage summary
#' (n, sum, CV, Kish deff, effective n) and per-step diagnostics, and opens it
#' in the browser.
#'
#' @param object a prepped object (output of prep()).
#' @param file output path; if NULL, a temporary .html file.
#' @param open logical; open the file in the browser.
#' @param plots logical; add per-step plots (weight before-vs-after scatter and
#'   adjustment-factor histogram), drawn as self-contained inline SVG (no graphics
#'   device or extra package required).
#' @param narrative logical; add an auto-generated methodological narrative -- an
#'   executive summary at the top and a natural-language paragraph on each step
#'   explaining what was done and why (built from the step's own parameters and
#'   diagnostics), in the spirit of a GSBPM / ESQRS methodological report.
#' @param lang language of the narrative: "en" (default) or "es".
#' @param metadata optional named list of reference metadata (SIMS / ESMS
#'   concepts) shown as a header card, e.g. `survey`, `reference_period`,
#'   `geography`, `producer`, `author`, `contact`, `frame`, `totals_source`,
#'   `totals_date`, `version`, `confidentiality`, `notes`. Recognised keys get a
#'   proper label; any other key is shown as given. `survey` is also woven into
#'   the executive summary. `totals_source`/`totals_date` document where the
#'   calibration control totals come from and their reference date.
#' @param replicates optional `weightflow_boot` or `weightflow_jack` object
#'   (from `bootstrap_weights()` / `jackknife_weights()`). If given, a
#'   "Replication design for variance" card documents the method, number of
#'   replicates, strata / PSU structure, lonely-PSU handling, seed, cores and
#'   run time, and warns when few PSUs per stratum favour JKn.
#' @param domains optional one-sided formula of grouping variables for a
#'   per-domain reliability card. Each term becomes one table (`+` = separate
#'   tables, `:` = crossed), showing the active n, sum of weights, CV, Kish
#'   design effect and effective sample size within each domain. E.g.
#'   `domains = ~ region + region:sex`.
#' @return (invisibly) the path to the HTML file.
#' @examples
#' fitted <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   prep()
#' \donttest{
#' # writes a self-contained HTML report to a temporary file (open = FALSE so
#' # nothing is launched); use open = TRUE to view it in the browser.
#' path <- report_weighting(fitted, open = FALSE)
#' }
# Lightweight, dependency-free 31-bit fingerprint of character pieces. Not a
# cryptographic hash; enough to tell "same recipe/data" from "changed".
.hash32 <- function(...) {
  b <- utf8ToInt(enc2utf8(paste(unlist(list(...)), collapse = "\u001f")))
  h <- 0
  for (x in b) h <- (h * 31 + x) %% 2147483647
  sprintf("%07x", as.integer(h))
}

# Reproducibility / audit-trail card: seed, recipe fingerprint, data fingerprint
# and environment. Two runs with the same fingerprints are exactly comparable.
.reproducibility_card <- function(object, replicates, lang) {
  steps_sig <- vapply(object$steps, function(st) {
    keep <- setdiff(names(st), c("env", "diagnostics", "alerts", "label"))
    paste(deparse(st[keep]), collapse = "")
  }, character(1))
  recipe_fp <- .hash32(object$base_weights, steps_sig)
  d <- object$data
  data_fp <- if (is.null(d)) "-" else .hash32(
    paste(dim(d), collapse = "x"),
    paste(names(d), collapse = ","),
    paste(vapply(d, function(col) class(col)[1], character(1)), collapse = ","),
    sprintf("%.3f", sum(object$history[["base"]], na.rm = TRUE)),
    sprintf("%.3f", sum(object$final_weight, na.rm = TRUE)))
  seed <- if (!is.null(replicates) && !is.null(replicates$seed)) as.character(replicates$seed) else "-"
  env  <- sprintf("R %s.%s &middot; weightflow %s", R.version$major, R.version$minor,
                  as.character(utils::packageVersion("weightflow")))
  kv <- function(k, v) sprintf("<tr><td class='k'>%s</td><td class='r'><code>%s</code></td></tr>", k, v)
  rows <- paste0(
    kv(.t("Seed", "Semilla", lang), .html_escape(seed)),
    kv(.t("Recipe fingerprint", "Huella de la receta", lang), recipe_fp),
    kv(.t("Data fingerprint", "Huella de los datos", lang), data_fp),
    kv(.t("Rows &times; columns", "Filas &times; columnas", lang),
       if (is.null(d)) "-" else sprintf("%s &times; %d", format(nrow(d), big.mark = ","), ncol(d))),
    kv(.t("Environment", "Entorno", lang), env))
  sprintf("<div class='meta repro'><h4>%s</h4><table class='params'>%s</table><p class='note'>%s</p></div>",
    .t("Reproducibility - audit trail", "Reproducibilidad - traza de auditor\u00eda", lang),
    rows,
    .t("Two runs showing the same recipe and data fingerprints are exactly comparable; any difference indicates a change in code, data or environment. The fingerprint is a lightweight checksum of the recipe specification and of the data shape and weight totals (no microdata is stored).",
       "Dos corridas con las mismas huellas de receta y de datos son exactamente comparables; cualquier diferencia indica un cambio en el c\u00f3digo, los datos o el entorno. La huella es un checksum liviano de la especificaci\u00f3n de la receta y de la forma de los datos y los totales de pesos (no se guarda microdato).", lang))
}

report_weighting <- function(object, file = NULL, open = TRUE, plots = TRUE,
                             narrative = TRUE, lang = c("en", "es"),
                             metadata = NULL, replicates = NULL, domains = NULL) {
  if (!inherits(object, "prepped_weighting_spec"))
    stop("Call prep() first; report_weighting() needs a prepped recipe.")
  lang <- match.arg(lang)
  if (is.null(file)) file <- tempfile("weightflow_report_", fileext = ".html")

  h    <- object$history
  fin  <- object$final_weight
  de_f <- design_effect(fin)
  de_b <- design_effect(h[["base"]])

  # Headline metrics
  cards <- paste0(
    .metric("Cases", format(length(fin), big.mark = ",")),
    .metric("Active (final)", format(de_f$n, big.mark = ",")),
    .metric("Sum of weights", format(round(sum(fin)), big.mark = ",")),
    .metric("Final deff_K", sprintf("%.3f", de_f$deff)),
    .metric("Effective n", format(round(de_f$n_eff), big.mark = ",")))

  # Stage summary table
  stab <- data.frame(
    stage    = names(h),
    n_active = vapply(h, function(w) sum(w > 0), integer(1)),
    sum_wts  = vapply(h, function(w) round(sum(w)), numeric(1)),
    cv       = vapply(h, function(w) round(design_effect(w)$cv, 3), numeric(1)),
    deff     = vapply(h, function(w) round(design_effect(w)$deff, 3), numeric(1)),
    n_eff    = vapply(h, function(w) round(design_effect(w)$n_eff), numeric(1)),
    row.names = NULL)

  # Per-stage table with readable, self-explanatory headers (not raw column names)
  stab_html <- local({
    slab <- .stage_labels(object, lang)
    hdr <- c(.t("Stage", "Etapa", lang),
             .t("Active units (n)", "Unidades activas (n)", lang),
             .t("Sum of weights (&Sigma;w)", "Suma de pesos (&Sigma;w)", lang),
             .t("CV of weights", "CV de los pesos", lang),
             .t("deff_K", "deff_K", lang),
             .t("Effective n (n_eff)", "n efectivo (n_eff)", lang))
    hd  <- paste0("<th>", hdr, "</th>", collapse = "")
    num <- function(x) format(x, big.mark = ",")
    d3  <- function(x) formatC(x, format = "f", digits = 3)
    dcell <- function(v) sprintf("<span class='%s'>%s%s</span>",
                                 if (v > 1.3) "cell-warn" else "cell-ok", if (v > 1.3) "&#9888; " else "", d3(v))
    rows <- vapply(seq_len(nrow(stab)), function(i) sprintf(
      "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>",
      slab[i], num(stab$n_active[i]), num(stab$sum_wts[i]),
      d3(stab$cv[i]), dcell(stab$deff[i]), num(stab$n_eff[i])), character(1))
    sprintf("<table class='stagetbl'><thead><tr>%s</tr></thead><tbody>%s</tbody></table>",
            hd, paste(rows, collapse = ""))
  })
  imp_html <- local({
    if (nrow(stab) < 2L) "" else {
      dd <- diff(stab$deff); dc <- diff(stab$cv)
      tot <- sum(abs(dd)); share <- if (tot > 0) 100 * abs(dd) / tot else rep(0, length(dd))
      lab  <- vapply(object$steps, function(s) .step_short(s, lang), "")
      imax <- if (any(dd > 0)) which.max(dd) else 0L
      eff  <- function(j) {
        x <- dd[j]
        if (round(x, 3) == 0) .t("negligible impact", "impacto insignificante", lang)
        else if (x < 0) {
          if (grepl("trim", lab[j], ignore.case = TRUE))
            .t("recovers efficiency (trimming)", "recupera eficiencia (recorte)", lang)
          else .t("recovers efficiency", "recupera eficiencia", lang)
        } else if (j == imax)
          .t("largest increase in variability", "mayor aumento de variabilidad", lang)
        else .t("increases variability", "aumenta la variabilidad", lang)
      }
      cell <- function(v) sprintf("<span class='%s'>%s%+.3f</span>",
                                  if (v > 0.001) "cell-warn" else if (v < -0.001) "cell-ok" else "", if (v > 0.001) "&#9888; " else "", v)
      hd <- paste0("<th>", c(.t("Step", "Paso", lang), "&Delta; deff_K", "&Delta; CV",
                             .t("Contribution to deff_K change", "Contribuci\u00f3n al cambio del deff_K", lang),
                             .t("Effect", "Efecto", lang)), "</th>", collapse = "")
      rows <- vapply(seq_along(dd), function(j) sprintf(
        "<tr><td>%s</td><td>%s</td><td>%s</td><td>%.0f%%</td><td>%s</td></tr>",
        lab[j], cell(dd[j]), sprintf("%+.3f", dc[j]), share[j], eff(j)),
        character(1))
      nr <- nrow(stab)
      t_deff <- stab$deff[nr] - stab$deff[1]; t_cv <- stab$cv[nr] - stab$cv[1]
      t_neff <- if (stab$n_eff[1] > 0) 100 * (stab$n_eff[nr] - stab$n_eff[1]) / stab$n_eff[1] else NA_real_
      total_row <- sprintf(
        "<tr style='font-weight:600;border-top:2px solid var(--line)'><td>%s</td><td>%s</td><td>%s</td><td></td><td>%s</td></tr>",
        .t("Total (base &rarr; final)", "Total (base &rarr; final)", lang),
        cell(t_deff), sprintf("%+.3f", t_cv),
        if (is.na(t_neff)) "" else .t(sprintf("effective sample %+.0f%%", t_neff),
                                      sprintf("muestra efectiva %+.0f%%", t_neff), lang))
      sprintf("<p class='muted'>%s</p><table class='stagetbl'><thead><tr>%s</tr></thead><tbody>%s%s</tbody></table>",
              .t("Impact of each weighting step (change vs the previous stage)",
                 "Impacto de cada paso de ponderaci\u00f3n (cambio respecto de la etapa anterior)", lang),
              hd, paste(rows, collapse = ""), total_row)
    }
  })
  stab_html <- paste0(stab_html, imp_html,
    sprintf("<p class='muted'>%s</p>",
            .t("Kish design effect by stage (0 = base, 1..k as in the table above); &#9650; largest increase, &#9660; recovered efficiency", "Efecto de dise\u00f1o de Kish por etapa (base y 1..k seg\u00fan la tabla de arriba); &#9650; mayor aumento, &#9660; eficiencia recuperada", lang)),
    .svg_evolution(stab$stage, stab$deff),
    sprintf("<p class='note'>%s</p>",
            .t("Read these changes in context: a rise at a calibration step need not mean lost precision (calibration to informative auxiliaries can raise the design effect while lowering variance), whereas a rise at a nonresponse step trades variance for reduced bias. See the note at the foot of the report.",
               "Le\u00e9 estos cambios en contexto: un aumento en un paso de calibraci\u00f3n no implica necesariamente p\u00e9rdida de precisi\u00f3n (la calibraci\u00f3n a auxiliares informativos puede aumentar el efecto de dise\u00f1o y a la vez reducir la varianza), mientras que un aumento en un paso de no respuesta cambia varianza por menor sesgo. Ver la nota al pie del reporte.", lang)))

  # R-indicator, shown inside the LAST nonresponse step (it is computed from that
  # step's auxiliaries), not as a separate top-level section.
  ri      <- .r_indicator(object)
  is_nr   <- vapply(object$steps, function(s) inherits(s, "step_nonresponse"), logical(1))
  nr_last <- if (any(is_nr)) max(which(is_nr)) else 0L

  # Per-step cards
  steps_html <- ""
  for (i in seq_along(object$steps)) {
    s <- object$steps[[i]]
    pp <- .step_params(s)
    prows <- if (length(pp))
      vapply(names(pp), function(p)
        sprintf("<tr><td class='k'>%s</td><td>%s</td></tr>",
                .html_escape(p), .fmt_val(pp[[p]])), character(1))
      else "<tr><td class='muted' colspan='2'>defaults only</td></tr>"
    note <- attr(s$diagnostics, "note")
    it   <- attr(s$diagnostics, "iterations")
    cv   <- attr(s$diagnostics, "converged")
    al   <- s$alerts
    alerts_html <- if (!is.null(al) && length(al))
      paste0("<div class='alert'><strong>Quality alerts</strong><ul>",
             paste0("<li>", vapply(al, .html_escape, character(1)), "</li>", collapse = ""),
             "</ul></div>") else ""
    conv_html <- if (identical(cv, FALSE))
      paste0("<div class='alert'><strong>Did not converge</strong>",
             "<p>The calibration stopped without satisfying all margins",
             if (!is.null(it)) sprintf(" (after %d iterations)", it) else "",
             ". The returned weights do not fully reproduce the requested totals. ",
             "Increase <code>maxit</code> or check that the margins are ",
             "mutually consistent.</p></div>") else ""
    iter_html <- if (!is.null(it)) {
      if (identical(cv, FALSE))
        sprintf("<p class='muted'>stopped after %d iterations (did not converge)</p>", it)
      else sprintf("<p class='muted'>converged in %d iterations</p>", it)
    } else ""
    extra <- paste0(
      iter_html,
      if (!is.null(note)) sprintf("<p class='note'>%s</p>", .html_escape(note)) else "",
      conv_html, alerts_html)
    de1 <- design_effect(h[[i]]); de2 <- design_effect(h[[i + 1L]])
    viz <- if (plots) .step_visual(s, h[[i]], h[[i + 1L]], lang) else ""
    ri_step <- if (i == nr_last && !is.null(ri)) .ri_block(ri) else ""
    narr <- if (isTRUE(narrative))
      .step_narrative(s, de1, de2, ri, i == nr_last, lang) else ""
    steps_html <- paste0(steps_html, sprintf(
      "<div class='step' id='step-%d'><div class='step-h'><span class='num'>%d</span>%s</div>%s
       <div class='cols'><div><h4>Requested</h4><table class='params'>%s</table></div>
       <div><h4>Diagnostics</h4>%s%s
       <p class='muted'>deff_K %.3f &rarr; %.3f &nbsp;|&nbsp; n_eff %s &rarr; %s</p>%s</div></div>%s</div>",
      i, i, .step_short(s, lang), narr, paste(prows, collapse = ""),
      .df_to_html(.with_reldiff(s$diagnostics, lang)), extra,
      de1$deff, de2$deff, format(round(de1$n_eff), big.mark = ","),
      format(round(de2$n_eff), big.mark = ","), ri_step,
      if (nzchar(viz)) paste0("<h4 class='viz-h'>Visual</h4>", viz) else ""))
  }

  diagram <- .pipeline_diagram(object, lang)
  allvars <- unique(c(object$base_weights, unlist(lapply(object$steps, .step_vars))))
  vars_chips <- .chips(allvars)

  # Provenance line for auditability: when, and with which versions, it was made.
  prov <- sprintf("Generated %s &middot; weightflow %s &middot; R %s.%s",
    format(Sys.time(), "%Y-%m-%d %H:%M"),
    as.character(utils::packageVersion("weightflow")),
    R.version$major, R.version$minor)

  drift <- .calibration_drift(object)
  wdist <- .weight_distribution_html(fin, lang, plots)
  exec  <- if (isTRUE(narrative)) .exec_summary(object, ri, de_f, lang, metadata$survey) else ""
  exec  <- paste0(exec, .status_checklist(object, de_f, object$final_weight, replicates, lang))
  exec  <- paste0(exec, .attention_panel(object, lang))
  imsg  <- if (de_f$deff < 1.2)
             .t("weight variability is low.", "la variabilidad de los pesos es baja.", lang)
           else if (de_f$deff < 1.4)
             .t("the efficiency loss is moderate.", "la p\u00e9rdida de eficiencia es moderada.", lang)
           else .t("consider reviewing the calibration or the trimming bounds.",
                   "conviene revisar la calibraci\u00f3n o las cotas de recorte.", lang)
  exec  <- paste0(exec, sprintf("<div class='exec'><p>%s</p></div>", .t(
    sprintf("Interpretation: the Kish design effect is %.3f (effective sample %s); %s",
            de_f$deff, format(round(de_f$n_eff), big.mark = ","), imsg),
    sprintf("Interpretaci\u00f3n: el efecto de dise\u00f1o de Kish es %.3f (muestra efectiva %s); %s",
            de_f$deff, format(round(de_f$n_eff), big.mark = ","), imsg), lang)))
  repl_html <- .replication_card(replicates, lang)
  domain_html <- .domain_reliability(object, domains, lang)
  step_anchors <- paste(vapply(seq_along(object$steps), function(i)
    sprintf("<a href='#step-%d'>%d</a>", i, i), character(1)), collapse = " ")
  toc_html <- sprintf(
    "<div class='toc'><strong>%s</strong> <a href='#pipeline'>%s</a> &middot; <a href='#stages'>%s</a> &middot; <a href='#weights'>%s</a> &middot; <a href='#steps'>%s</a> <span class='tsteps'>%s</span></div>",
    .t("Jump to:", "Ir a:", lang), .t("Pipeline", "Pipeline", lang),
    .t("Per-stage summary", "Resumen por etapa", lang),
    .t("Weight distribution", "Distribuci\u00f3n de pesos", lang),
    .t("Steps", "Pasos", lang), step_anchors)
  meta_html <- .metadata_card(metadata, lang)
  racct <- .response_account(object, lang)
  repro_html <- .reproducibility_card(object, replicates, lang)

  done_txt <- local({
    ns  <- length(object$steps)
    ncv <- sum(vapply(object$steps, function(st)
      identical(attr(st$diagnostics, "converged"), FALSE), logical(1)))
    nal <- sum(vapply(object$steps, function(st)
      !is.null(st$alerts) && length(st$alerts) > 0L, logical(1)))
    nis <- ncv + nal
    lead <- if (nis == 0L)
      .t("Recipe completed successfully.", "Receta completada con \u00e9xito.", lang)
    else .t(sprintf("Recipe completed with %d point(s) of attention.", nis),
            sprintf("Receta completada con %d punto(s) de atenci\u00f3n.", nis), lang)
    it <- c(sprintf("%d %s", ns, .t("weighting steps", "pasos de ponderaci\u00f3n", lang)))
    if (ncv == 0L) it <- c(it, .t("calibration constraints preserved",
                                  "restricciones de calibraci\u00f3n preservadas", lang))
    if (!is.null(replicates)) it <- c(it, .t("replicate weights created",
                                             "pesos r\u00e9plica creados", lang))
    it <- c(it, .t("report generated", "reporte generado", lang))
    sprintf("<p class='done'><strong>%s</strong> &nbsp; %s</p>",
            lead, paste(it, collapse = " &middot; "))
  })
  foot_txt <- .t(
    "deff_K = 1 + CV&sup2; is the Kish design effect (n = active units; CV = coefficient of variation of the weights), a measure of weight variability benchmarked against equal weighting (Kish 1992). The corresponding effective sample size is n_eff = (&Sigma;w)&sup2; / &Sigma;w&sup2; = n / deff_K. It assumes equal weights would be optimal, so read it in context: when the weights correlate with the outcome, as calibration to informative auxiliaries induces, deff_K overstates the variance and can rise even as precision improves (Spencer 2000; Little and Vartivarian 2005); a nonresponse adjustment instead accepts extra weight variability to reduce bias, so a high deff_K there reflects a more genuine bias-variance trade-off, and unequal weights can still beat equal ones when response and the outcome both depend on the adjustment variables. deff_K is best used as a post-hoc diagnostic: large values flag a step that may inject unjustified variability, or an error worth checking (Valliant, Dever and Kreuter 2018). This report shows the weights only; for design-based inference (standard errors, confidence intervals) use the 'survey' or 'srvyr' package.",
    "deff_K = 1 + CV&sup2; es el efecto de dise\u00f1o de Kish (n = unidades activas; CV = coeficiente de variaci\u00f3n de los pesos), una medida de la variabilidad de los pesos comparada contra la ponderaci\u00f3n igual (Kish 1992). El tama\u00f1o de muestra efectivo correspondiente es n_eff = (&Sigma;w)&sup2; / &Sigma;w&sup2; = n / deff_K. Supone que la ponderaci\u00f3n igual ser\u00eda \u00f3ptima, as\u00ed que conviene leerlo en contexto: cuando los pesos correlacionan con la variable de inter\u00e9s, como induce la calibraci\u00f3n a auxiliares informativos, el deff_K sobreestima la varianza y puede subir aunque la precisi\u00f3n mejore (Spencer 2000; Little y Vartivarian 2005); en cambio un ajuste por no respuesta acepta m\u00e1s variabilidad para reducir el sesgo, por lo que un deff_K alto ah\u00ed refleja un compromiso sesgo-varianza m\u00e1s real, y los pesos desiguales pueden aun as\u00ed superar a los iguales cuando la respuesta y la variable de inter\u00e9s dependen de las variables de ajuste. El deff_K conviene usarlo como diagn\u00f3stico posterior: valores grandes se\u00f1alan un paso que puede inyectar variabilidad injustificada, o un error que vale la pena revisar (Valliant, Dever y Kreuter 2018). Este reporte muestra solo los pesos; para inferencia basada en el dise\u00f1o (errores est\u00e1ndar, intervalos de confianza) us\u00e1 el paquete 'survey' o 'srvyr'.",
    lang)
  # HTML assembled by named interpolation (paste0), not a positional sprintf, so
  # sections cannot be misaligned when one is added or removed.
  html <- paste0(
    sprintf("<!DOCTYPE html><html lang='%s'><head><meta charset='utf-8'>\n", lang),
    "<title>weightflow report</title>", .report_css(), "</head><body>\n",
    "<h1>weightflow &mdash; weighting recipe</h1>\n",
    "<p class='muted'>Base weights: <code>", .html_escape(object$base_weights),
      "</code> &nbsp;|&nbsp; ", length(object$steps), " steps</p>\n",
    "<p class='prov'>", prov, "</p>\n",
    toc_html, "\n",
    meta_html, "\n",
    "<div class='cards'>", cards, "</div>\n",
    racct, "\n",
    exec, "\n",
    repro_html, "\n",
    "<h2 id='pipeline'>Pipeline</h2>", diagram, "\n",
    "<p class='muted'>Variables used:</p>", vars_chips, "\n",
    "<h2 id='stages'>Per-stage summary</h2>", stab_html, "\n",
    repl_html, "\n",
    domain_html, "\n",
    "<h2 id='weights'>Weight distribution (final)</h2>", wdist, "\n",
    "<h2 id='steps'>Steps</h2>\n",
    "<details class='steps' open><summary>",
      .t("Show / hide per-step detail", "Mostrar / ocultar detalle por paso", lang),
      "</summary>\n",
    steps_html, "\n</details>\n",
    drift, "\n",
    done_txt, "\n",
    "<p class='foot'>", foot_txt, "</p>\n",
    "</body></html>")

  writeLines(html, file)
  if (open) try(utils::browseURL(file), silent = TRUE)
  invisible(file)
}

.metric <- function(label, value)
  sprintf("<div class='metric'><div class='mv'>%s</div><div class='ml'>%s</div></div>",
          value, label)

# Distribution summary of the final weights: min, p1, median, p99, max, the
# max/min ratio, and counts of negative, sub-1 and extreme weights. Manuals ask
# for the shape of the distribution, not only the CV. "Extreme" uses 4x the
# median as a convention; adjust to your trimming bounds.
.weight_distribution_html <- function(fin, lang = "en", plots = TRUE) {
  wnz <- fin[fin > 0]
  if (!length(wnz)) return(.t("<p class='muted'>No positive weights.</p>",
                              "<p class='muted'>Sin pesos positivos.</p>", lang))
  qs  <- as.numeric(stats::quantile(wnz, c(0.01, 0.5, 0.99)))
  med <- qs[2]
  row <- function(k, v) sprintf("<tr><td class='k'>%s</td><td>%s</td></tr>", k, v)
  rows <- paste0(
    row("min", .fmt_num(min(wnz), "weight")),
    row("p1", .fmt_num(qs[1], "weight")),
    row(.t("median", "mediana", lang), .fmt_num(med, "weight")),
    row("p99", .fmt_num(qs[3], "weight")),
    row("max", .fmt_num(max(wnz), "weight")),
    row(.t("max/min ratio", "raz\u00f3n max/min", lang), .fmt_num(max(wnz) / min(wnz), "prop")),
    row(.t("negative weights", "pesos negativos", lang), .fmt_num(sum(fin < 0), "count")),
    row(.t("weights &lt; 1", "pesos &lt; 1", lang), .fmt_num(sum(fin > 0 & fin < 1), "count")),
    row(.t("extreme (&gt; 4&times; median)", "extremos (&gt; 4&times; mediana)", lang),
        .fmt_num(sum(wnz > 4 * med), "count")))
  note <- .t("Extreme = final weight above 4&times; the median (a convention; adjust to your trimming bounds).",
             "Extremo = peso final por encima de 4&times; la mediana (una convenci\u00f3n; ajuste a sus cotas de recorte).", lang)
  if (!isTRUE(plots))
    return(paste0("<table class='params'>", rows, "</table><p class='muted'>", note, "</p>"))
  hist <- tryCatch(.svg_hist(wnz, xlab = .t("final weight", "peso final", lang), refline = NULL),
                   error = function(e) "")
  sprintf("<table class='params'>%s</table><p class='muted'>%s</p><div class='wdhist'>%s</div>",
    rows, note, hist)
}

.report_css <- function() "<style>
:root{--ink:#1a1a2e;--mut:#6b7280;--line:#e5e7eb;--accent:#3d3580;--bg:#f7f7fb}
*{box-sizing:border-box}body{font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
color:var(--ink);max-width:980px;margin:32px auto;padding:0 20px;background:#fff;line-height:1.45}
h1{font-size:24px;margin:0 0 4px}h2{font-size:18px;margin:28px 0 10px;border-bottom:1px solid var(--line);padding-bottom:6px}
h4{margin:0 0 6px;font-size:12px;text-transform:uppercase;letter-spacing:.05em;color:var(--mut)}
.muted{color:var(--mut);font-size:13px}.note{color:var(--accent);font-size:13px;margin:6px 0 0}
.methodological-note{margin:2px 0 12px;padding:10px 14px;background:#f6f5fb;border-left:3px solid var(--accent);border-radius:0 8px 8px 0;font-size:13.5px;line-height:1.6;color:#33334d}
.exec{margin:16px 0 4px;padding:14px 16px;background:var(--bg);border:1px solid var(--line);border-radius:12px}
.exec h4{margin:0 0 6px}.attention h4{color:#b45309}.attention ul{margin:6px 0 0;padding-left:18px;font-size:14px;line-height:1.6;color:var(--ink)}.exec p{margin:0;font-size:14px;line-height:1.6;color:var(--ink)}
.meta{margin:12px 0;padding:14px 16px;background:#fff;border:1px solid var(--line);border-radius:12px}
.meta h4{margin:0 0 8px}.meta table{margin:0}.meta td.k{color:var(--mut);width:42%;font-weight:600}
.alert{margin:8px 0 0;padding:8px 12px;border-left:3px solid #e8941f;background:#fdf4e6;border-radius:6px;font-size:13px}
.alert strong{color:#b45309;display:block;margin-bottom:4px}.alert ul{margin:0;padding-left:18px}
.prov{color:var(--mut);font-size:12px;margin:0 0 10px}
code{background:var(--bg);padding:2px 6px;border-radius:4px;font-size:13px}
.cards{display:flex;gap:12px;flex-wrap:wrap;margin:16px 0}
.metric{flex:1;min-width:120px;background:var(--bg);border:1px solid var(--line);border-radius:10px;padding:14px}
.mv{font-size:22px;font-weight:650}.ml{color:var(--mut);font-size:12px;margin-top:2px}
table{border-collapse:collapse;width:100%;font-size:13px;margin:4px 0}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--mut);font-weight:600;font-size:11px;text-transform:uppercase;letter-spacing:.04em}
.stagetbl th{text-transform:none;letter-spacing:normal;font-size:11.5px}
.params td.k{color:var(--mut);width:42%;font-weight:600}
.racct td.r,.racct th.r{text-align:right;font-variant-numeric:tabular-nums;width:auto}.racct td.k{font-weight:600;color:var(--ink)}
.step{border:1px solid var(--line);border-radius:12px;padding:16px;margin:14px 0;box-shadow:0 1px 2px rgba(0,0,0,.03)}
.step-h{font-weight:650;font-size:15px;display:flex;align-items:center;gap:10px;margin-bottom:10px}
.num{display:inline-flex;width:24px;height:24px;align-items:center;justify-content:center;
background:var(--accent);color:#fff;border-radius:50%;font-size:13px}
.cols{display:grid;grid-template-columns:1fr 1fr;gap:20px}
@media(max-width:680px){.cols{grid-template-columns:1fr}}
.viz{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-top:8px}
.viz svg{max-width:100%;height:auto}.viz-h{margin-top:14px}.wdhist{margin-top:12px;max-width:480px}.wdhist svg{width:100%;height:auto}
@media(max-width:680px){.viz{grid-template-columns:1fr}}
.ri{margin-top:12px;border-top:1px dashed var(--line);padding-top:10px}
.ri-val{font-size:16px;margin:6px 0}
.flow{display:flex;flex-direction:column;align-items:stretch;margin:14px 0;max-width:560px}
.node{border:1px solid var(--line);border-radius:10px;padding:10px 14px;background:#fff}
.node-end{background:var(--bg);border-style:dashed}
.nl{font-weight:600;font-size:14px;display:flex;align-items:center;gap:8px}
.nv{margin-top:3px}
.arrow{text-align:center;color:var(--mut);font-size:18px;line-height:1.2;margin:3px 0}.arrow .fn{font-size:11px;color:var(--mut);font-family:ui-monospace,Menlo,monospace;vertical-align:2px}
.chips{margin-top:7px;display:flex;flex-wrap:wrap;gap:5px}
.chip{background:#efecf8;color:var(--accent);border:1px solid #ddd6f0;border-radius:999px;
padding:1px 9px;font-size:11px;font-family:ui-monospace,Menlo,monospace}
.foot{color:var(--mut);font-size:12px;margin-top:28px;border-top:1px solid var(--line);padding-top:12px}.cell-ok{background:#ecfdf5;color:#065f46;padding:1px 6px;border-radius:4px}.cell-warn{background:#fef3c7;color:#b45309;padding:1px 6px;border-radius:4px}.toc{background:var(--bg);border:1px solid var(--line);border-radius:10px;padding:9px 16px;margin:12px 0 4px;font-size:13px;position:sticky;top:0;z-index:9}.tsteps a{display:inline-block;min-width:16px;text-align:center;color:var(--accent);text-decoration:none;font-size:12px;padding:0 2px}.toc a{color:var(--accent);text-decoration:none}details.steps>summary{cursor:pointer;font-size:13px;color:var(--accent);margin:6px 0;list-style:none}details.steps>summary::-webkit-details-marker{display:none}.chk{list-style:none;padding-left:0;margin:6px 0;font-size:14px}.chk li{margin:3px 0}.chk .ok{color:#065f46;font-weight:600}.chk .no{color:#b45309;font-weight:600}.done{margin-top:20px;padding:12px 16px;background:var(--bg);border:1px solid var(--line);border-radius:10px;font-size:13px;color:var(--ink)}
@media print{.step,.exec,.meta,.metric,.node,.repro,table,.viz,.ri{break-inside:avoid;page-break-inside:avoid}h2{break-after:avoid;page-break-after:avoid}details.steps>summary{display:none}.toc{position:static}body{max-width:none;margin:0}}
</style>"
