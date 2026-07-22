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
  gsub(">", "&gt;", x, fixed = TRUE)
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

# Which step parameters to display: keep only what the user meaningfully set.
# Drops NULL fields, the internal convergence knobs, "off" logical flags, and the
# default calibration distance, so the "Requested" table is not cluttered with
# defaults the user never touched.
.step_params <- function(step) {
  keep <- setdiff(names(step), c("label", "diagnostics"))
  out  <- list()
  for (p in keep) {
    v <- step[[p]]
    if (is.null(v) || length(v) == 0L) next
    if (p %in% c("maxit", "tol")) next                          # internal knobs
    if (is.logical(v) && length(v) == 1L && !isTRUE(v)) next    # FALSE flag = off
    if (identical(p, "calfun") && identical(v, "linear")) next # default distance
    out[[p]] <- v
  }
  out
}

# data.frame -> HTML table
.df_to_html <- function(df) {
  if (is.null(df) || !nrow(df)) return("<p class='muted'>no diagnostics</p>")
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
  axln <- sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#bbb"/>',
                  c(ml, ml), c(mt + ph, mt), c(ml + pw, ml), c(mt + ph, mt + ph))
  xt <- c(xr[1], mean(xr), xr[2]); yt <- c(yr[1], mean(yr), yr[2])
  xtk <- paste(sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" fill="#777">%s</text>',
               sx(xt), mt + ph + 12, vapply(xt, .fmt_ax, "")), collapse = "")
  ytk <- paste(sprintf('<text x="%.1f" y="%.1f" text-anchor="end" fill="#777">%s</text>',
               ml - 4, sy(yt) + 3, vapply(yt, .fmt_ax, "")), collapse = "")
  xl  <- sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" fill="#555">%s</text>',
                 ml + pw / 2, mt + ph + 25, xlab)
  yl  <- sprintf('<text x="11" y="%.1f" text-anchor="middle" fill="#555" transform="rotate(-90 11 %.1f)">%s</text>',
                 mt + ph / 2, mt + ph / 2, ylab)
  paste0(paste(axln, collapse = ""), xtk, ytk, xl, yl)
}

.svg_frame <- function(body, w, h) sprintf(
  '<svg viewBox="0 0 %d %d" preserveAspectRatio="xMidYMid meet" xmlns="http://www.w3.org/2000/svg" font-family="-apple-system,Segoe UI,Roboto,sans-serif" font-size="9">%s</svg>',
  w, h, body)

# Scatter of weight before (x) vs after (y), with a y = x reference line.
.svg_scatter <- function(x, y, w = 330, h = 215) {
  ml <- 46; mr <- 8; mt <- 8; mb <- 32; pw <- w - ml - mr; ph <- h - mt - mb
  if (length(x) > 800) { i <- sample(length(x), 800); x <- x[i]; y <- y[i] }
  xr <- range(x); yr <- range(c(y, x))
  if (diff(xr) == 0) xr <- xr + c(-1, 1)
  if (diff(yr) == 0) yr <- yr + c(-1, 1)
  sx <- function(v) ml + (v - xr[1]) / diff(xr) * pw
  sy <- function(v) mt + ph - (v - yr[1]) / diff(yr) * ph
  pts <- paste(sprintf('<circle cx="%.1f" cy="%.1f" r="1.6" fill="#3b5bdb" fill-opacity="0.28"/>',
               sx(x), sy(y)), collapse = "")
  lo <- max(xr[1], yr[1]); hi <- min(xr[2], yr[2])
  ln <- sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="red" stroke-dasharray="4 3"/>',
                sx(lo), sy(lo), sx(hi), sy(hi))
  .svg_frame(paste0(.svg_axes(ml, mt, pw, ph, xr, yr, "weight before", "weight after", sx, sy),
                    pts, ln), w, h)
}

# Histogram of a per-unit quantity (default: the adjustment factor after/before),
# with a reference line at 1.
.svg_hist <- function(v, xlab = "adjustment factor (after / before)", w = 330, h = 215) {
  ml <- 40; mr <- 8; mt <- 8; mb <- 32; pw <- w - ml - mr; ph <- h - mt - mb
  v <- v[is.finite(v)]
  if (!length(v)) return("")
  hh <- graphics::hist(v, breaks = 30, plot = FALSE)
  xr <- range(hh$breaks); yr <- c(0, max(hh$counts))
  if (diff(xr) == 0) xr <- xr + c(-1, 1)
  if (yr[2] == 0) yr[2] <- 1
  sx <- function(z) ml + (z - xr[1]) / diff(xr) * pw
  sy <- function(z) mt + ph - (z - yr[1]) / diff(yr) * ph
  bars <- paste(sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#9aa7d8"/>',
                sx(hh$breaks[-length(hh$breaks)]), sy(hh$counts),
                pmax(sx(hh$breaks[-1]) - sx(hh$breaks[-length(hh$breaks)]) - 0.5, 0.5),
                pmax(sy(0) - sy(hh$counts), 0)), collapse = "")
  vl <- if (1 >= xr[1] && 1 <= xr[2])
    sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="red" stroke-dasharray="4 3"/>',
            sx(1), mt, sx(1), mt + ph) else ""
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
.step_visual <- function(step, prev, cur) {
  if (inherits(step, .no_visual)) return("")
  keep <- prev > 0 & cur > 0
  if (!any(keep)) return("")
  sc   <- tryCatch(.svg_scatter(prev[keep], cur[keep]), error = function(e) "")
  fac  <- (cur / prev)[keep]
  xlab <- if (inherits(step, "step_select_within"))
            "persons represented (1/prob)" else "adjustment factor (after / before)"
  hi   <- tryCatch(.svg_hist(fac, xlab = xlab), error = function(e) "")
  if (!nzchar(sc) && !nzchar(hi)) return("")
  sprintf("<div class='viz'><div>%s</div><div>%s</div></div>", sc, hi)
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

# A vertical flow diagram of the pipeline (base -> steps -> final), with the
# variables each step used shown as chips. Pure HTML/CSS (no graphics device).
.pipeline_diagram <- function(object) {
  nodes <- sprintf(
    "<div class='node node-end'><div class='nl'>Base weights</div><div class='nv'><code>%s</code></div></div>",
    .html_escape(object$base_weights))
  for (i in seq_along(object$steps)) {
    s <- object$steps[[i]]
    nodes <- c(nodes, sprintf(
      "<div class='node'><div class='nl'><span class='num'>%d</span>%s</div>%s</div>",
      i, .html_escape(s$label), .chips(.step_vars(s))))
  }
  nodes <- c(nodes,
    "<div class='node node-end'><div class='nl'>Final weights</div><div class='nv'><code>.weight</code></div></div>")
  paste0("<div class='flow'>",
         paste(nodes, collapse = "<div class='arrow'>&darr;</div>"), "</div>")
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
#'   adjustment-factor histogram). Uses ggplot2 if installed, else base graphics.
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
report_weighting <- function(object, file = NULL, open = TRUE, plots = TRUE) {
  if (!inherits(object, "prepped_weighting_spec"))
    stop("Call prep() first; report_weighting() needs a prepped recipe.")
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
    .metric("Final Kish deff", sprintf("%.3f", de_f$deff)),
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
    viz <- if (plots) .step_visual(s, h[[i]], h[[i + 1L]]) else ""
    ri_step <- if (i == nr_last && !is.null(ri)) .ri_block(ri) else ""
    steps_html <- paste0(steps_html, sprintf(
      "<div class='step'><div class='step-h'><span class='num'>%d</span>%s</div>
       <div class='cols'><div><h4>Requested</h4><table class='params'>%s</table></div>
       <div><h4>Diagnostics</h4>%s%s
       <p class='muted'>Kish deff %.3f &rarr; %.3f &nbsp;|&nbsp; n_eff %s &rarr; %s</p>%s</div></div>%s</div>",
      i, .html_escape(s$label), paste(prows, collapse = ""),
      .df_to_html(s$diagnostics), extra,
      de1$deff, de2$deff, format(round(de1$n_eff), big.mark = ","),
      format(round(de2$n_eff), big.mark = ","), ri_step,
      if (nzchar(viz)) paste0("<h4 class='viz-h'>Visual</h4>", viz) else ""))
  }

  diagram <- .pipeline_diagram(object)
  allvars <- unique(c(object$base_weights, unlist(lapply(object$steps, .step_vars))))
  vars_chips <- .chips(allvars)

  # Provenance line for auditability: when, and with which versions, it was made.
  prov <- sprintf("Generated %s &middot; weightflow %s &middot; R %s.%s",
    format(Sys.time(), "%Y-%m-%d %H:%M"),
    as.character(utils::packageVersion("weightflow")),
    R.version$major, R.version$minor)

  drift <- .calibration_drift(object)
  wdist <- .weight_distribution_html(fin)

  html <- sprintf("<!DOCTYPE html><html><head><meta charset='utf-8'>
<title>weightflow report</title>%s</head><body>
<h1>weightflow &mdash; weighting recipe</h1>
<p class='muted'>Base weights: <code>%s</code> &nbsp;|&nbsp; %d steps</p>
<p class='prov'>%s</p>
<div class='cards'>%s</div>
<h2>Pipeline</h2>%s
<p class='muted'>Variables used:</p>%s
<h2>Per-stage summary</h2>%s
<h2>Weight distribution (final)</h2>%s
<h2>Steps</h2>%s
%s
<p class='foot'>deff = Kish design effect (1 + CV&sup2;). This report shows weights only; for inference use the 'survey' package.</p>
</body></html>", .report_css(), .html_escape(object$base_weights),
    length(object$steps), prov, cards, diagram, vars_chips, .df_to_html(stab), wdist, steps_html, drift)

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
.weight_distribution_html <- function(fin) {
  wnz <- fin[fin > 0]
  if (!length(wnz)) return("<p class='muted'>No positive weights.</p>")
  qs  <- as.numeric(stats::quantile(wnz, c(0.01, 0.5, 0.99)))
  med <- qs[2]
  row <- function(k, v) sprintf("<tr><td class='k'>%s</td><td>%s</td></tr>", k, v)
  rows <- paste0(
    row("min", sprintf("%.3f", min(wnz))),
    row("p1", sprintf("%.3f", qs[1])),
    row("median", sprintf("%.3f", med)),
    row("p99", sprintf("%.3f", qs[3])),
    row("max", sprintf("%.3f", max(wnz))),
    row("max/min ratio", sprintf("%.1f", max(wnz) / min(wnz))),
    row("negative weights", sprintf("%d", sum(fin < 0))),
    row("weights &lt; 1", sprintf("%d", sum(fin > 0 & fin < 1))),
    row("extreme (&gt; 4&times; median)", sprintf("%d", sum(wnz > 4 * med))))
  paste0("<table class='params'>", rows, "</table>",
         "<p class='muted'>Extreme = final weight above 4&times; the median ",
         "(a convention; adjust to your trimming bounds).</p>")
}

.report_css <- function() "<style>
:root{--ink:#1a1a2e;--mut:#6b7280;--line:#e5e7eb;--accent:#3b5bdb;--bg:#f7f7fb}
*{box-sizing:border-box}body{font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
color:var(--ink);max-width:980px;margin:32px auto;padding:0 20px;background:#fff;line-height:1.45}
h1{font-size:24px;margin:0 0 4px}h2{font-size:18px;margin:28px 0 10px;border-bottom:1px solid var(--line);padding-bottom:6px}
h4{margin:0 0 6px;font-size:12px;text-transform:uppercase;letter-spacing:.05em;color:var(--mut)}
.muted{color:var(--mut);font-size:13px}.note{color:var(--accent);font-size:13px;margin:6px 0 0}
.alert{margin:8px 0 0;padding:8px 12px;border-left:3px solid #d97706;background:#fffbeb;border-radius:6px;font-size:13px}
.alert strong{color:#b45309;display:block;margin-bottom:4px}.alert ul{margin:0;padding-left:18px}
.prov{color:var(--mut);font-size:12px;margin:0 0 10px}
code{background:var(--bg);padding:2px 6px;border-radius:4px;font-size:13px}
.cards{display:flex;gap:12px;flex-wrap:wrap;margin:16px 0}
.metric{flex:1;min-width:120px;background:var(--bg);border:1px solid var(--line);border-radius:10px;padding:14px}
.mv{font-size:22px;font-weight:650}.ml{color:var(--mut);font-size:12px;margin-top:2px}
table{border-collapse:collapse;width:100%;font-size:13px;margin:4px 0}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--mut);font-weight:600;font-size:11px;text-transform:uppercase;letter-spacing:.04em}
.params td.k{color:var(--mut);width:42%;font-weight:600}
.step{border:1px solid var(--line);border-radius:12px;padding:16px;margin:14px 0;box-shadow:0 1px 2px rgba(0,0,0,.03)}
.step-h{font-weight:650;font-size:15px;display:flex;align-items:center;gap:10px;margin-bottom:10px}
.num{display:inline-flex;width:24px;height:24px;align-items:center;justify-content:center;
background:var(--accent);color:#fff;border-radius:50%;font-size:13px}
.cols{display:grid;grid-template-columns:1fr 1fr;gap:20px}
@media(max-width:680px){.cols{grid-template-columns:1fr}}
.viz{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-top:8px}
.viz svg{max-width:100%;height:auto}.viz-h{margin-top:14px}
@media(max-width:680px){.viz{grid-template-columns:1fr}}
.ri{margin-top:12px;border-top:1px dashed var(--line);padding-top:10px}
.ri-val{font-size:16px;margin:6px 0}
.flow{display:flex;flex-direction:column;align-items:stretch;margin:14px 0;max-width:560px}
.node{border:1px solid var(--line);border-radius:10px;padding:10px 14px;background:#fff}
.node-end{background:var(--bg);border-style:dashed}
.nl{font-weight:600;font-size:14px;display:flex;align-items:center;gap:8px}
.nv{margin-top:3px}
.arrow{text-align:center;color:var(--mut);font-size:18px;line-height:1.2;margin:3px 0}
.chips{margin-top:7px;display:flex;flex-wrap:wrap;gap:5px}
.chip{background:#eef2ff;color:var(--accent);border:1px solid #dbe3ff;border-radius:999px;
padding:1px 9px;font-size:11px;font-family:ui-monospace,Menlo,monospace}
.foot{color:var(--mut);font-size:12px;margin-top:28px;border-top:1px solid var(--line);padding-top:12px}
</style>"
