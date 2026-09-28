# report assets: headline metric card, weight distribution, inline JS
# (theme toggle, per-table CSV download, print). The stylesheet lives in
# R/report-css.R.

# A header tile. `value` is where DATA reaches the page -- a wave label, a domain
# name, a count -- so it is escaped by default; `label` is always a literal written
# in this package (a .t() pair, some of which carry entities like &alpha;), so it is
# passed through. A call site that really does build markup for the value says so
# with raw = TRUE, and then owns the escaping of anything data-derived inside it.
# (SEC-01: a value of the `wave` column reached the page unescaped from here.)
.metric <- function(label, value, raw = FALSE)
  sprintf("<div class='metric'><div class='mv'>%s</div><div class='ml'>%s</div></div>",
          if (isTRUE(raw)) value else .html_escape(as.character(value)), label)

# Wrap a table so a wide one scrolls inside its own box instead of pushing the
# page sideways. Used for every table the report emits.
.tw <- function(x) if (!nzchar(x)) x else sprintf("<div class='tw'>%s</div>", x)

# Distribution summary of the final weights: min, p1, median, p99, max, the
# max/min ratio, and counts of negative, sub-1 and extreme weights. Manuals ask
# for the shape of the distribution, not only the CV. "Extreme" uses 4x the
# median as a convention; adjust to your trimming bounds.
# REP-04: the table used to be computed over fin[fin > 0] while its rows were
# labelled plainly "min", "median", "max/min ratio" -- with a row saying "negative
# weights: 74" right underneath. Measured on a GREG output whose real minimum is
# -29.7 and real median 3.28, the card published 0.094 and 4.23. The false median
# also drives the "extreme (> 4x median)" count here and the matching item in the
# Status checklist, so the extremes were undercounted too. This is the block a
# methodologist reads to decide whether the weights can be delivered, so it
# describes the ACTIVE weights -- negatives included, which this package keeps on
# purpose. The max/min ratio is the one figure that genuinely needs positivity: a
# ratio across a sign change is meaningless, so it is shown only when the minimum
# is positive.
.weight_distribution_html <- function(fin, lang = "en", plots = TRUE) {
  w <- fin[is.finite(fin) & fin != 0]
  if (!length(w)) return(.t("<p class='muted'>No active weights.</p>",
                            "<p class='muted'>Sin pesos activos.</p>", lang))
  qs  <- as.numeric(stats::quantile(w, c(0.01, 0.5, 0.99)))
  med <- qs[2]
  row <- function(k, v) sprintf("<tr><td class='k'>%s</td><td class='numc'>%s</td></tr>", k, v)
  ratio <- if (min(w) > 0) .fmt_num(max(w) / min(w), "prop") else "&ndash;"
  ext   <- if (med > 0) .fmt_num(sum(w > 4 * med), "count") else "&ndash;"
  rows <- paste0(
    row(.t("min", "m\u00edn", lang), .fmt_num(min(w), "weight")),
    row(.t("1st percentile", "percentil 1", lang), .fmt_num(qs[1], "weight")),
    row(.t("median", "mediana", lang), .fmt_num(med, "weight")),
    row(.t("99th percentile", "percentil 99", lang), .fmt_num(qs[3], "weight")),
    row(.t("max", "m\u00e1x", lang), .fmt_num(max(w), "weight")),
    row(.t("max/min ratio", "raz\u00f3n m\u00e1x/m\u00edn", lang), ratio),
    row(.t("negative weights", "pesos negativos", lang), .fmt_num(sum(fin < 0), "count")),
    row(.t("weights &lt; 1", "pesos &lt; 1", lang), .fmt_num(sum(fin > 0 & fin < 1), "count")),
    row(.t("extreme (&gt; 4&times; median)", "extremos (&gt; 4&times; mediana)", lang), ext))
  note <- .t("Extreme = final weight above 4&times; the median (a convention; adjust to your trimming bounds).",
             "Extremo = peso final por encima de 4&times; la mediana (una convenci\u00f3n; ajuste a sus cotas de recorte).", lang)
  tbl <- .tw(sprintf("<table class='params'><tbody>%s</tbody></table>", rows))
  if (!isTRUE(plots))
    return(paste0(tbl, "<p class='note'>", note, "</p>"))
  hist <- tryCatch(.svg_hist(w, xlab = .t("final weight", "peso final", lang),
                             refline = NULL, density = TRUE, lang = lang),
                   error = function(e) "")
  hblock <- if (nzchar(hist))
    sprintf("<div class='wdhist'><div class='viz-h'>%s</div>%s</div>",
            .t("Distribution of the final survey weights",
               "Distribuci&oacute;n de los pesos finales", lang), hist)
  else ""
  paste0("<div class='pgrid'>", tbl, hblock, "</div><p class='note'>", note, "</p>")
}

# Inline JS: colour-scheme toggle, per-table CSV export, print. `lang` only
# reaches the few user-visible strings (button labels/tooltips).
.report_js <- function(lang = "en") {
  i18n <- function(en, es) if (identical(lang, "es")) es else en
  sprintf('
(function(){
  var Q = String.fromCharCode(34), NL = String.fromCharCode(10);
  var T_CSV = %s, T_LIGHT = %s, T_DARK = %s;

  /* ---- colour scheme -------------------------------------------------- */
  var root = document.documentElement, btn = document.getElementById("wf-theme");
  function store(k, v){ try { localStorage.setItem(k, v); } catch (e) {} }
  function recall(k){ try { return localStorage.getItem(k); } catch (e) { return null; } }
  function sysDark(){
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  }
  function isDark(){
    var a = root.getAttribute("data-theme");
    return a ? a === "dark" : sysDark();
  }
  function paint(){
    if (!btn) return;
    var d = isDark();
    btn.textContent = d ? T_LIGHT : T_DARK;
    btn.setAttribute("aria-pressed", d ? "true" : "false");
  }
  var saved = recall("wf-theme");
  if (saved === "dark" || saved === "light") root.setAttribute("data-theme", saved);
  paint();
  if (btn) btn.onclick = function(){
    var next = isDark() ? "light" : "dark";
    root.setAttribute("data-theme", next); store("wf-theme", next); paint();
  };

  /* ---- print ---------------------------------------------------------- */
  window.addEventListener("beforeprint", function(){
    var ds = document.querySelectorAll("details");
    for (var i = 0; i < ds.length; i++) ds[i].open = true;
  });
  var pdf = document.getElementById("wf-pdf");
  if (pdf) pdf.onclick = function(){ window.print(); };

  /* ---- per-table CSV -------------------------------------------------- */
  function dl(name, text){
    var blob = new Blob(["\\ufeff" + text], {type:"text/csv;charset=utf-8;"});
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url; a.download = name;
    document.body.appendChild(a); a.click();
    document.body.removeChild(a); URL.revokeObjectURL(url);
  }
  function cell(t){
    t = (t == null ? "" : String(t)).trim();
    var SQ = String.fromCharCode(39), CR = String.fromCharCode(13), TAB = String.fromCharCode(9);
    var bad = "=+-@" + TAB + CR;
    if (t.length && bad.indexOf(t.charAt(0)) >= 0) t = SQ + t;
    if (t.indexOf(",") >= 0 || t.indexOf(Q) >= 0 || t.indexOf(NL) >= 0 || t.indexOf(CR) >= 0)
      t = Q + t.split(Q).join(Q + Q) + Q;
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
    var el = tbl.closest(".tw") || tbl, nm = "";
    el = el.previousElementSibling;
    while (el){
      if (/^H[1-4]$/.test(el.tagName) || (el.className || "").indexOf("muted") >= 0
          || (el.className || "").indexOf("col-h") >= 0){ nm = el.textContent; break; }
      el = el.previousElementSibling;
    }
    nm = (nm || "").replace(/[^a-z0-9]+/gi, "-").replace(/^-+|-+$/g, "").toLowerCase();
    return "weightflow-" + (nm || "table") + "-" + i + ".csv";
  }
  var tables = document.querySelectorAll("table"), i = 0;
  for (var k = 0; k < tables.length; k++){
    var tbl = tables[k];
    if (!tbl.querySelector("thead")) continue;
    i++;
    var b = document.createElement("button");
    b.className = "dlcsv noprint"; b.type = "button"; b.textContent = "CSV";
    b.title = T_CSV;
    (function(t, idx){ b.onclick = function(){ dl(nameFor(t, idx), tableCsv(t)); }; })(tbl, i);
    var host = tbl.closest(".tw") || tbl;
    host.parentNode.insertBefore(b, host);
  }
})();
',
    .js_str(i18n("Download this table as CSV", "Descargar esta tabla como CSV")),
    .js_str(i18n("Light", "Claro")),
    .js_str(i18n("Dark", "Oscuro")))
}

# A JS string literal, safely quoted (the report is a single self-contained file,
# so the label text is interpolated into the inline <script>).
.js_str <- function(x) {
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub('"', '\\"', x, fixed = TRUE)
  x <- gsub("<", "\\u003c", x, fixed = TRUE)
  paste0('"', x, '"')
}
