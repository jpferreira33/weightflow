# report assets: headline metric card, weight distribution, inline CSS and JS (download/print).

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

.report_js <- function() '
(function(){
  var Q = String.fromCharCode(34), NL = String.fromCharCode(10);
  function dl(name, text){
    var blob = new Blob([text], {type:"text/csv;charset=utf-8;"});
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url; a.download = name;
    document.body.appendChild(a); a.click();
    document.body.removeChild(a); URL.revokeObjectURL(url);
  }
  function cell(t){
    t = (t == null ? "" : String(t)).trim();
    if (t.indexOf(",") >= 0 || t.indexOf(Q) >= 0) t = Q + t.split(Q).join(Q + Q) + Q;
    return t;
  }
  function tableCsv(tbl){
    var out = [], trs = tbl.querySelectorAll("tr");
    for (var r = 0; r < trs.length; r++){
      var cs = trs[r].querySelectorAll("th,td"), row = [];
      for (var c = 0; c < cs.length; c++) row.push(cell(cs[c].textContent));
      out.push(row.join(","));
    }
    return out.join(NL);
  }
  function nameFor(tbl, i){
    var el = tbl.previousElementSibling, nm = "";
    while (el){
      if (/^H[1-4]$/.test(el.tagName) || (el.className || "").indexOf("muted") >= 0){ nm = el.textContent; break; }
      el = el.previousElementSibling;
    }
    nm = (nm || "").replace(/[^a-z0-9]+/gi, "-").replace(/^-+|-+$/g, "").toLowerCase();
    return "weightflow-" + (nm || "table") + "-" + i + ".csv";
  }
  window.addEventListener("beforeprint", function(){ document.querySelectorAll("details").forEach(function(d){ d.open = true; }); });
  var pdf = document.getElementById("wf-pdf");
  if (pdf) pdf.onclick = function(){ window.print(); };
  var tables = document.querySelectorAll("table"), i = 0;
  for (var k = 0; k < tables.length; k++){
    var tbl = tables[k];
    if (!tbl.querySelector("thead")) continue;
    i++;
    var b = document.createElement("button");
    b.className = "dlcsv noprint"; b.type = "button"; b.textContent = "CSV";
    b.title = "Download this table as CSV";
    (function(t, idx){ b.onclick = function(){ dl(nameFor(t, idx), tableCsv(t)); }; })(tbl, i);
    tbl.parentNode.insertBefore(b, tbl);
  }
})();
'

.report_css <- function() "<style>
:root{--ink:#1a1a2e;--mut:#6b7280;--line:#e5e7eb;--accent:#3d3580;--bg:#f7f7fb}
.sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
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
.chart1{margin-top:10px;max-width:440px}.chart1 svg{width:100%;height:auto}
.pgrid{display:grid;grid-template-columns:minmax(0,440px) minmax(0,1fr);gap:18px;align-items:center;margin-top:8px}
.pgrid .chart1{margin-top:0}.pgrid-note{font-size:0.92em;line-height:1.5}
@media(max-width:680px){.pgrid{grid-template-columns:1fr}}
@media(max-width:680px){.viz{grid-template-columns:1fr}}
.ri{margin-top:12px;border-top:1px dashed var(--line);padding-top:10px}
.trim-h{font-size:12px;font-weight:600;margin:12px 0 4px;color:#374151}
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
.toolbar{display:flex;gap:8px;margin:6px 0}.wfbtn{cursor:pointer;font:inherit;border:1px solid var(--line);background:var(--bg);color:var(--accent);border-radius:8px;padding:6px 14px;font-size:13px}.wfbtn:hover{background:#efecf8}.dlcsv{cursor:pointer;font:inherit;border:1px solid var(--line);background:#fff;color:var(--accent);border-radius:6px;padding:2px 9px;font-size:11px;margin:0 0 5px;display:inline-block}.dlcsv:hover{background:#efecf8}@media print{.step,.exec,.meta,.metric,.node,.repro,table,.viz,.ri{break-inside:avoid;page-break-inside:avoid}h2{break-after:avoid;page-break-after:avoid}details.steps>summary{display:none}.toc{position:static}body{max-width:none;margin:0}.noprint{display:none}}
</style>"
