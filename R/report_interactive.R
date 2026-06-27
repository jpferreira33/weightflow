# ---------------------------------------------------------------------------
# report_weighting_interactive(): modern, self-contained interactive HTML
# report of a (prepped) recipe. PROTOTYPE for a future version.
#
# Keeps everything the classic report_weighting() shows (headline metrics,
# stage summary, per-step requested parameters + diagnostics + deff change)
# but: (a) the pipeline is a dynamic Mermaid diagram whose nodes show the
# variables each step used, and (b) the per-step scatter/histogram are
# interactive Plotly charts. Mermaid and Plotly load from CDN; no R deps.
# ---------------------------------------------------------------------------

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# ---- pipeline as Mermaid, with variables on each node ----------------------
.wf_mermaid2 <- function(object) {
  steps <- object$steps
  nodes <- c(sprintf('base["<b>Base weights</b><br/><span class=\'f\'>%s</span>"]',
                     .html_escape(object$base_weights)))
  edges <- character(0); prev <- "base"

  for (i in seq_along(steps)) {
    s <- steps[[i]]; id <- sprintf("s%d", i)
    vars <- .step_vars(s)
    vtxt <- if (length(vars)) sprintf("<br/><span class='v'>%s</span>",
              .html_escape(paste(vars, collapse = ", "))) else ""
    shape_open <- "[\""; shape_close <- "\"]"; extra_class <- ""

    if (inherits(s, "step_select_within")) { shape_open <- "{\""; shape_close <- "\"}" }
    if (inherits(s, "step_model_calibration")) extra_class <- ":::filled"

    lab <- sprintf("<b>%s</b>%s", .html_escape(s$label %||% class(s)[1]), vtxt)
    nodes <- c(nodes, sprintf("%s%s%s%s%s", id, shape_open, lab, shape_close, extra_class))
    edges <- c(edges, sprintf("%s --> %s", prev, id)); prev <- id
  }
  nodes <- c(nodes, 'fin["<b>Final weights</b><br/><span class=\'f\'>.weight</span>"]')
  edges <- c(edges, sprintf("%s --> fin", prev))

  paste0("flowchart TD\n",
    paste0("  ", nodes, collapse = "\n"), "\n",
    paste0("  ", edges, collapse = "\n"), "\n",
    "  classDef default fill:#eee9fb,stroke:#b9a9ef,color:#2a2150;\n",
    "  classDef filled fill:#5b4bbd,stroke:#5b4bbd,color:#fff;\n")
}

# ---- interactive Plotly charts per step ------------------------------------
# Returns a <div> plus the JS that draws scatter (prev vs cur) and hist (factor)
.wf_plotly_step <- function(prev, cur, idx) {
  keep <- prev > 0 & cur > 0
  if (!any(keep)) return(list(html = "", js = ""))
  px <- prev[keep]; cx <- cur[keep]; fr <- cx / px
  sid <- sprintf("scz%d", idx); hid <- sprintf("hiz%d", idx)

  jnum <- function(v) paste0("[", paste(formatC(v, format = "g", digits = 7), collapse = ","), "]")

  html <- sprintf('<div class="viz"><div id="%s" class="plot"></div><div id="%s" class="plot"></div></div>', sid, hid)
  js <- sprintf('
Plotly.newPlot("%s",
  [{x:%s,y:%s,mode:"markers",type:"scattergl",
    marker:{size:6,color:"#5b4bbd",opacity:.55}}],
  {title:{text:"previous vs new weight",font:{size:13}},
   margin:{l:44,r:12,t:30,b:38},
   xaxis:{title:"previous"},yaxis:{title:"new"},
   paper_bgcolor:"rgba(0,0,0,0)",plot_bgcolor:"rgba(0,0,0,0)"},
  {displayModeBar:false,responsive:true});
Plotly.newPlot("%s",
  [{x:%s,type:"histogram",marker:{color:"#9a8ce6"},nbinsx:24}],
  {title:{text:"adjustment factor (new / previous)",font:{size:13}},
   margin:{l:44,r:12,t:30,b:38},
   xaxis:{title:"factor"},yaxis:{title:"count"},
   paper_bgcolor:"rgba(0,0,0,0)",plot_bgcolor:"rgba(0,0,0,0)"},
  {displayModeBar:false,responsive:true});',
    sid, jnum(px), jnum(cx), hid, jnum(fr))
  list(html = html, js = js)
}

.metric2 <- function(lab, val)
  sprintf('<div class="metric"><div class="mv">%s</div><div class="ml">%s</div></div>', val, lab)

.df_to_html2 <- function(df) {
  if (is.null(df) || !NROW(df)) return("<p class='muted'>no diagnostics</p>")
  hd <- paste0("<th>", .html_escape(names(df)), "</th>", collapse = "")
  rows <- apply(df, 1, function(r)
    paste0("<tr>", paste0("<td>", .html_escape(as.character(r)), "</td>", collapse = ""), "</tr>"))
  sprintf("<table><thead><tr>%s</tr></thead><tbody>%s</tbody></table>", hd, paste(rows, collapse = ""))
}

# ---- side panel: design type ------------------------------------------------
.wf_design_type <- function(object) {
  has_sel <- any(vapply(object$steps, function(s) inherits(s, "step_select_within"), logical(1)))
  nr_steps <- Filter(function(s) inherits(s, "step_nonresponse"), object$steps)
  engines <- vapply(nr_steps, function(s)
    if (identical(s$method, "propensity")) sprintf("propensity (%s)", s$engine %||% "logit")
    else "weighting classes", character(1))
  design <- if (has_sel) "Select-one per household" else "Take-all roster"
  rows <- c(sprintf("<tr><td class='k'>Within-household</td><td>%s</td></tr>", design))
  if (length(engines))
    rows <- c(rows, sprintf("<tr><td class='k'>Nonresponse</td><td>%s</td></tr>",
                            .html_escape(paste(unique(engines), collapse = "; "))))
  ncal <- sum(vapply(object$steps, function(s) inherits(s, "step_calibrate"), logical(1)))
  if (ncal) {
    cm <- vapply(Filter(function(s) inherits(s, "step_calibrate"), object$steps),
                 function(s) s$detail %||% s$method %||% "calibration", character(1))
    rows <- c(rows, sprintf("<tr><td class='k'>Calibration</td><td>%s</td></tr>",
                            .html_escape(paste(cm, collapse = "; "))))
  }
  sprintf("<table class='params'>%s</table>", paste(rows, collapse = ""))
}

# ---- side panel: case flow (counts and proportions) ------------------------
.wf_case_flow <- function(object) {
  d <- object$data; fin <- object$final_weight; n <- nrow(d)
  cnt <- list()
  grab <- function(cols) {
    for (cc in cols) if (!is.null(d[[cc]])) return(d[[cc]])
    NULL
  }
  unk <- grab(c("unknown_elig", "unknown_eligibility"))
  ine <- grab(c("ineligible"))
  rsp <- grab(c("responded"))
  cnt[[1]] <- data.frame(category = "Total cases", n = n)
  if (!is.null(unk)) cnt[[length(cnt) + 1]] <-
    data.frame(category = "Unknown eligibility", n = sum(unk == 1 | unk == TRUE, na.rm = TRUE))
  if (!is.null(ine)) cnt[[length(cnt) + 1]] <-
    data.frame(category = "Ineligible", n = sum(ine == 1 | ine == TRUE, na.rm = TRUE))
  if (!is.null(rsp)) {
    cnt[[length(cnt) + 1]] <- data.frame(category = "Respondents", n = sum(rsp == 1, na.rm = TRUE))
    cnt[[length(cnt) + 1]] <- data.frame(category = "Nonrespondents", n = sum(rsp == 0, na.rm = TRUE))
  }
  cnt[[length(cnt) + 1]] <- data.frame(category = "Active (final wt > 0)", n = sum(fin > 0))
  df <- do.call(rbind, cnt)
  df$pct <- sprintf("%.1f%%", 100 * df$n / n)
  hd <- "<th>category</th><th>n</th><th>%</th>"
  rows <- apply(df, 1, function(r) sprintf("<tr><td>%s</td><td>%s</td><td>%s</td></tr>",
    .html_escape(r[["category"]]), .html_escape(r[["n"]]), .html_escape(r[["pct"]])))
  sprintf("<table><thead><tr>%s</tr></thead><tbody>%s</tbody></table>", hd, paste(rows, collapse = ""))
}

# ---- side panel: weighted target estimate across ADJUSTMENTS ---------------
# statistic = "mean" or "total". Shows the estimate through the weighting
# ADJUSTMENTS only (nonresponse, calibration, trimming, ...). Design steps such
# as within-household selection (a 1/p design weight, not an adjustment) are
# excluded, since they rescale weights structurally rather than correcting them.
# Computed on a fixed set (units with target observed and positive final weight)
# so the line reflects the adjustments, not changes in composition.
.wf_target_track <- function(object, target, statistic = c("mean", "total")) {
  statistic <- match.arg(statistic)
  if (is.null(target) || is.null(object$data[[target]])) return(list(html = "", js = ""))
  y   <- object$data[[target]]
  fin <- object$final_weight
  base_set <- which(!is.na(y) & fin > 0)
  if (!length(base_set)) return(list(html = "", js = ""))

  # which stages to keep: base + adjustment steps (drop design-only steps)
  design_only <- c("step_select_within")
  stage_names <- names(object$history)
  step_class  <- c("base", vapply(object$steps, function(s) class(s)[1], character(1)))
  keep_stage  <- !(step_class %in% design_only)

  hist_keep <- object$history[keep_stage]
  est <- vapply(hist_keep, function(w) {
    ww <- w[base_set]; yy <- y[base_set]; k <- ww > 0
    if (!any(k)) return(NA_real_)
    if (statistic == "total") sum(ww[k] * yy[k]) else sum(ww[k] * yy[k]) / sum(ww[k])
  }, numeric(1))

  labs <- gsub("^stage_[0-9]+_step_", "", names(hist_keep))
  labs <- gsub("_", " ", labs)
  ylab <- if (statistic == "total") "weighted total" else "weighted mean"
  jnum <- function(v) paste0("[", paste(ifelse(is.na(v), "null",
            formatC(v, format = "g", digits = 7)), collapse = ","), "]")
  jstr <- function(v) paste0("[", paste(sprintf('"%s"', v), collapse = ","), "]")
  html <- '<div id="tgt" class="plot" style="height:260px"></div>'
  js <- sprintf('
Plotly.newPlot("tgt",
  [{x:%s,y:%s,mode:"lines+markers",line:{color:"#5b4bbd",width:2},
    marker:{size:8,color:"#5b4bbd"},connectgaps:true}],
  {title:{text:"%s of %s across adjustments",font:{size:13}},
   margin:{l:64,r:14,t:30,b:84},
   xaxis:{tickangle:-35},yaxis:{title:"%s"},
   paper_bgcolor:"rgba(0,0,0,0)",plot_bgcolor:"rgba(0,0,0,0)"},
  {displayModeBar:false,responsive:true});',
    jstr(labs), jnum(est), ylab, .html_escape(target), ylab)
  list(html = html, js = js)
}

#' Interactive HTML report of a weighting recipe (prototype)
#'
#' Writes a self-contained, interactive HTML report of a prepped recipe and
#' opens it in the browser. The report shows headline metrics, a dynamic
#' pipeline diagram (built from the actual steps, with the variables each step
#' used), a design summary, a case-flow table, the per-stage summary, and
#' per-step diagnostics with interactive scatter and histogram charts. When a
#' `target` variable is supplied, it also tracks the variable's weighted
#' estimate across the weighting adjustments.
#'
#' The diagram is rendered with Mermaid and the charts with Plotly, both loaded
#' from a CDN, so an internet connection is needed to view the interactive
#' elements (the report file itself is generated with no R dependencies).
#'
#' This is a prototype intended for a future release; its interface may change.
#'
#' @param object a prepped object (output of `prep()`).
#' @param target optional name of a numeric variable in the data. If given, the
#'   report tracks its weighted estimate across the adjustment stages, computed
#'   on a fixed set of units (those with `target` observed and positive final
#'   weight). Design-only steps (e.g. within-household selection) are excluded.
#' @param statistic the estimate computed for `target`: `"mean"` (default) or
#'   `"total"`.
#' @param file output path; if `NULL`, a temporary `.html` file.
#' @param open logical; open the file in the browser.
#' @return (invisibly) the path to the HTML file.
#' @examples
#' fitted <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_calibrate(method = "raking",
#'                  margins = list(region = c(table(population$region)))) |>
#'   prep()
#' \dontrun{
#' report_weighting_interactive(fitted)                       # opens in browser
#' report_weighting_interactive(fitted, target = "income")    # track a variable
#' report_weighting_interactive(fitted, target = "income", statistic = "total")
#' }
#' @export
report_weighting_interactive <- function(object, target = NULL,
                                          statistic = c("mean", "total"),
                                          file = NULL, open = interactive()) {
  if (!inherits(object, "prepped_weighting_spec"))
    stop("Call prep() first; report_weighting_interactive() needs a prepped recipe.")
  statistic <- match.arg(statistic)
  if (is.null(file)) file <- tempfile("weightflow_ireport_", fileext = ".html")

  h   <- object$history
  fin <- object$final_weight
  de_f <- design_effect(fin)

  metrics <- paste0(
    .metric2("Cases", format(length(fin), big.mark = ",")),
    .metric2("Active (final)", format(de_f$n, big.mark = ",")),
    .metric2("Sum of weights", format(round(sum(fin)), big.mark = ",")),
    .metric2("Final Kish deff", sprintf("%.3f", de_f$deff)),
    .metric2("Effective n", format(round(de_f$n_eff), big.mark = ",")))

  stab <- data.frame(
    stage = names(h),
    n_active = vapply(h, function(w) sum(w > 0), integer(1)),
    sum_wts  = vapply(h, function(w) round(sum(w)), numeric(1)),
    cv       = vapply(h, function(w) round(design_effect(w)$cv, 3), numeric(1)),
    deff     = vapply(h, function(w) round(design_effect(w)$deff, 3), numeric(1)),
    n_eff    = vapply(h, function(w) round(design_effect(w)$n_eff), numeric(1)),
    row.names = NULL)

  steps_html <- ""; all_js <- ""
  for (i in seq_along(object$steps)) {
    s <- object$steps[[i]]
    pars <- setdiff(names(s), c("label", "diagnostics"))
    prows <- vapply(pars, function(p)
      sprintf("<tr><td class='k'>%s</td><td>%s</td></tr>", .html_escape(p), .fmt_val(s[[p]])),
      character(1))
    de1 <- design_effect(h[[i]]); de2 <- design_effect(h[[i + 1L]])
    pl <- .wf_plotly_step(h[[i]], h[[i + 1L]], i); all_js <- paste0(all_js, pl$js)
    steps_html <- paste0(steps_html, sprintf(
      '<div class="step"><div class="step-h"><span class="num">%d</span>%s</div>
       <div class="cols"><div><h4>Requested</h4><table class="params">%s</table></div>
       <div><h4>Diagnostics</h4>%s
       <p class="muted">Kish deff %.3f &rarr; %.3f &nbsp;|&nbsp; n_eff %s &rarr; %s</p></div></div>
       %s</div>',
      i, .html_escape(s$label), paste(prows, collapse = ""),
      .df_to_html2(s$diagnostics), de1$deff, de2$deff,
      format(round(de1$n_eff), big.mark = ","), format(round(de2$n_eff), big.mark = ","),
      if (nzchar(pl$html)) paste0("<h4 class='viz-h'>Visual</h4>", pl$html) else ""))
  }

  mermaid <- .wf_mermaid2(object)
  design_html <- .wf_design_type(object)
  flow_html   <- .wf_case_flow(object)
  tgt <- .wf_target_track(object, target, statistic)
  all_js <- paste0(all_js, tgt$js)
  target_panel <- if (nzchar(tgt$html))
    sprintf('<h4>Weighting effect on %s (%s)</h4>%s<p class="muted">Across weighting adjustments only, on a fixed set (units with %s observed and positive final weight). Design steps such as within-household selection are excluded, since they rescale weights structurally rather than adjusting them.</p>',
            .html_escape(target %||% ""), statistic, tgt$html, .html_escape(target %||% "")) else ""

  html <- sprintf('<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>weightflow report</title>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
<script src="https://cdn.plot.ly/plotly-2.32.0.min.js"></script>
<style>
 :root{--indigo:#5b4bbd;--bg:#faf9ff;--ink:#2a2150;--muted:#8a86a0;}
 *{box-sizing:border-box;} body{margin:0;background:var(--bg);color:var(--ink);
  font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;}
 h1{margin:0;font-size:26px;letter-spacing:-.02em;} h2{font-size:16px;margin:28px 0 10px;}
 h4{margin:0 0 8px;font-size:12px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);}
 .pad{padding:28px 40px;} .muted{color:var(--muted);font-size:13px;}
 .cards{display:flex;gap:14px;flex-wrap:wrap;margin:16px 0;}
 .metric{background:#fff;border:1px solid #ece8fb;border-radius:14px;padding:14px 18px;min-width:130px;}
 .mv{font-size:22px;font-weight:700;} .ml{font-size:12px;color:var(--muted);margin-top:2px;}
 .panel{background:#fff;border:1px solid #ece8fb;border-radius:16px;padding:20px;margin-bottom:16px;}
 .grid2{display:grid;grid-template-columns:1.25fr 1fr;gap:16px;align-items:start;}
 @media(max-width:900px){.grid2{grid-template-columns:1fr;}}
 .side .panel{margin-bottom:16px;} .side h4{margin-top:0;}
 .mermaid .f{font-weight:400;font-size:11px;opacity:.8;}
 .mermaid .v{font-weight:400;font-size:10.5px;color:#5b4bbd;}
 table{border-collapse:collapse;width:100%%;font-size:12.5px;} 
 th,td{text-align:left;padding:5px 8px;border-bottom:1px solid #f0eefa;} th{color:var(--muted);}
 .params .k{color:var(--muted);width:120px;}
 .step{background:#fff;border:1px solid #ece8fb;border-radius:14px;padding:18px;margin-bottom:14px;}
 .step-h{display:flex;align-items:center;gap:10px;font-weight:700;margin-bottom:12px;}
 .num{display:inline-flex;width:24px;height:24px;align-items:center;justify-content:center;
   background:var(--indigo);color:#fff;border-radius:50%%;font-size:13px;}
 .cols{display:grid;grid-template-columns:1fr 1fr;gap:18px;} 
 @media(max-width:820px){.cols{grid-template-columns:1fr;}}
 .viz{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:8px;}
 @media(max-width:820px){.viz{grid-template-columns:1fr;}}
 .plot{height:240px;width:100%%;} .viz-h{margin-top:14px;}
 .foot{color:var(--muted);font-size:12px;margin-top:24px;}
</style></head><body>
<div class="pad">
 <h1>weightflow &mdash; weighting recipe</h1>
 <p class="muted">Base weights: <code>%s</code> &nbsp;|&nbsp; %d steps</p>
 <div class="cards">%s</div>
 <h2>Pipeline &amp; design</h2>
 <div class="grid2">
   <div class="panel"><pre class="mermaid">%s</pre></div>
   <div class="side">
     <div class="panel"><h4>Design type</h4>%s</div>
     <div class="panel"><h4>Case flow</h4>%s</div>
     <div class="panel">%s</div>
   </div>
 </div>
 <h2>Per-stage summary</h2>
 <div class="panel">%s</div>
 <h2>Steps</h2>
 %s
 <p class="foot">deff = Kish design effect (1 + CV&sup2;). Charts are interactive (hover, zoom). This report shows weights only; for inference use the survey package.</p>
</div>
<script>
 mermaid.initialize({startOnLoad:true,theme:"base",
   themeVariables:{primaryColor:"#eee9fb",primaryTextColor:"#2a2150",
     primaryBorderColor:"#b9a9ef",lineColor:"#9a8ce6",fontSize:"13px"}});
 window.addEventListener("load",function(){%s});
</script>
</body></html>',
    .html_escape(object$base_weights), length(object$steps), metrics, mermaid,
    design_html, flow_html, target_panel,
    .df_to_html2(stab), steps_html, all_js)

  writeLines(html, file)
  if (isTRUE(open)) try(utils::browseURL(file), silent = TRUE)
  invisible(file)
}
