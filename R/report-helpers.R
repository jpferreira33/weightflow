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
  # A nested fit object (e.g. step_cre's `previous`) is a whole recipe, not a
  # tunable scalar; summarise it in one line instead of dumping its weight
  # vectors (history/final_weight, one number per case) into the report.
  if (inherits(v, c("prepped_weighting_spec", "weighting_spec"))) {
    lab <- if (length(v$steps)) v$steps[[length(v$steps)]]$label else "empty recipe"
    n   <- if (!is.null(v$data)) nrow(v$data) else length(v$final_weight)
    return(.html_escape(sprintf("fit: %s (%s cases)", lab,
                                format(n, big.mark = ",", trim = TRUE))))
  }
  if (is.list(v)) {
    parts <- vapply(seq_along(v), function(i)
      sprintf("<i>%s</i>: %s", .html_escape(names(v)[i] %||% i), .fmt_val(v[[i]])),
      character(1))
    return(paste(parts, collapse = "<br>"))
  }
  # Cap long atomic vectors: no report field should ever spill one value per case.
  cap <- 10L
  if (length(v) > cap) {
    head_v <- if (is.numeric(v)) format(v[seq_len(cap)], big.mark = ",", trim = TRUE)
              else format(v[seq_len(cap)], trim = TRUE)
    # \u2026 as an escape, not a literal: R CMD check requires ASCII-only R code
    return(.html_escape(sprintf("%s, \u2026 (%s values)", paste(head_v, collapse = ", "),
                                format(length(v), big.mark = ",", trim = TRUE))))
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
    weight = format(round(x, 3), big.mark = ",", trim = TRUE, scientific = FALSE),
    count  = format(round(x),    big.mark = ",", trim = TRUE, scientific = FALSE),
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

# Spanish display labels for the standard diagnostic-table column headers and the
# step-parameter keys of the "Requested" table (the data frames and the step list
# carry English/argument names; this only relabels them for the Spanish report).
# Names not in the map (id, n, factor, variable, phi, ...) pass through unchanged.
.wf_es_labels <- c(
  constraint = "restricci\u00f3n", type = "tipo", target = "objetivo", achieved = "logrado",
  method = "m\u00e9todo", decimals = "decimales", sum_before = "suma_antes",
  sum_after = "suma_despu\u00e9s", n_modified = "n_modificados",
  max_total_reldev = "desv_rel_m\u00e1x", propensity_class = "clase_propensi\u00f3n",
  category = "categor\u00eda", `dev %` = "desv. %",
  mean_prop = "prop_media", partial_R = "R_parcial", cell = "celda", class = "clase",
  n_respondents = "n_respondentes", n_known = "n_conocidos", weight_class = "clase_peso",
  min_prob = "prob_m\u00edn", max_prob = "prob_m\u00e1x",
  p_min = "p_m\u00edn", p_max = "p_m\u00e1x",
  n_psu2 = "n_upm2", n_hh = "n_hogares", n_resp_hh = "n_hog_resp",
  level = "nivel", design = "dise\u00f1o", psu = "upm", reference = "referencia",
  floor = "cota_inf", cap = "cota_sup", trimmed = "recortadas",
  redistributed = "redistribuidas", n_dropped = "n_descartadas",
  n_selected = "n_seleccionadas", n_unknown = "n_desconocidas",
  n_nonresponse = "n_no_respuesta", prev_sum = "suma_previa",
  prev_total = "total_previo", deff_before = "deff_antes", deff_after = "deff_despu\u00e9s",
  variable = "variable", threshold = "umbral", importance = "importancia",
  predicted = "predicho", observed = "observado",
  # step-parameter keys (Requested table)
  digits = "d\u00edgitos", by = "por", respondent = "respondente", formula = "f\u00f3rmula",
  engine = "motor", weight_model = "modela_peso", num_classes = "num_clases",
  lower = "inferior", upper = "superior", margins = "m\u00e1rgenes", totals = "totales",
  count = "conteo", bounds = "cotas", penalty = "penalizaci\u00f3n", calfun = "distancia",
  cluster = "conglomerado", population = "poblaci\u00f3n", unknown = "desconocido")
# Values the package writes itself into a diagnostics table (as opposed to the
# arguments the user typed, which stay verbatim so the report matches the code).
# Keyed by column, so a genuine data value that happens to read "household" in
# some other table is never rewritten.
.wf_es_values <- list(
  level  = c(person = "persona", household = "hogar", unit = "unidad"),
  method = c(`1/p per household` = "1/p por hogar", `1/p per unit` = "1/p por unidad"))

.wf_revalue <- function(df, lang) {
  if (!identical(lang, "es") || is.null(df) || !is.data.frame(df)) return(df)
  for (cn in intersect(names(df), names(.wf_es_values))) {
    map <- .wf_es_values[[cn]]
    v   <- as.character(df[[cn]])
    hit <- v %in% names(map)
    if (any(hit)) { v[hit] <- map[v[hit]]; df[[cn]] <- v }
  }
  df
}

.wf_relabel <- function(nms, lang) {
  if (!identical(lang, "es")) return(nms)
  hit <- nms %in% names(.wf_es_labels)
  nms[hit] <- .wf_es_labels[nms[hit]]
  nms
}

# If a diagnostics table has target/achieved columns, insert a relative-%
# difference column right after 'achieved' (100 * (achieved - target)/target),
# then relabel every column header for the Spanish report (display only).
.with_reldiff <- function(df, lang) {
  if (is.null(df) || !is.data.frame(df)) return(df)
  out <- .wf_revalue(df, lang)
  if (all(c("target", "achieved") %in% names(out))) {
    tt  <- suppressWarnings(as.numeric(as.character(out$target)))
    aa  <- suppressWarnings(as.numeric(as.character(out$achieved)))
    rel <- 100 * (aa - tt) / tt
    nm  <- .t("rel. diff (%)", "dif. rel. (%)", lang)
    # < 0.005 rounds to 0.00 at two decimals, so show a plain "0.00%" (no misleading
    # "+0.00%" sign); non-finite (e.g. target 0) shows "-", not a green "+0.000".
    out[[nm]] <- ifelse(is.finite(rel), ifelse(abs(rel) < 0.005, "0.00%", sprintf("%+.2f%%", rel)), "-")
    new <- setdiff(names(out), nm)
    ord <- append(new, nm, after = match("achieved", new))
    out <- out[, ord, drop = FALSE]
  }
  names(out) <- .wf_relabel(names(out), lang)
  out
}

# data.frame -> HTML table. Numeric columns are right-aligned with tabular
# figures (a weighting report is read down its number columns, and ragged left
# alignment makes magnitudes impossible to compare at a glance); the percentage
# columns produced by .with_reldiff() are character but read as numbers, so they
# get the same treatment. The table is wrapped so a wide one scrolls in its own
# box instead of pushing the whole page sideways.
.df_to_html <- function(df, lang = "en") {
  if (is.null(df) || !nrow(df))
    return(sprintf("<p class='muted'>%s</p>",
                   .t("no diagnostics", "sin diagn\u00f3sticos", lang)))
  # A column counts as numeric for alignment if it is numeric, or if every
  # non-missing entry looks like a number/percentage/dash.
  looks_num <- function(col) {
    if (is.numeric(col)) return(TRUE)
    s <- trimws(as.character(col)); s <- s[!is.na(s) & nzchar(s)]
    length(s) > 0 && all(grepl("^[+-]?[0-9,]*\\.?[0-9]+%?$|^&ndash;$|^-$", s))
  }
  isnum <- vapply(df, looks_num, logical(1))
  # Integer-valued numeric columns (counts, calibration targets/totals) get a
  # thousands separator so they read like the header tiles ("1,570", not "1570");
  # display only, never touches a value used in a computation.
  for (nm in names(df)) if (is.numeric(df[[nm]])) {
    col <- df[[nm]]; fin <- is.finite(col)
    out <- if (any(fin) && all(col[fin] == round(col[fin])))
      format(col, big.mark = ",", trim = TRUE, scientific = FALSE)
    else format(round(col, 4), trim = TRUE, scientific = FALSE)
    out[!fin] <- NA_character_            # NA/Inf -> rendered as a dash below
    df[[nm]] <- out
  }
  cls <- ifelse(isnum, " class='numc'", "")
  hd  <- paste0("<th scope='col'", cls, ">", .html_escape(names(df)), "</th>", collapse = "")
  rows <- apply(df, 1, function(r) {
    cells <- ifelse(is.na(r), "&ndash;", .html_escape(as.character(r)))  # NA -> dash, like the rest of the report
    paste0("<tr>", paste0("<td", cls, ">", cells, "</td>", collapse = ""), "</tr>")
  })
  .tw(sprintf("<table><thead><tr>%s</tr></thead><tbody>%s</tbody></table>",
              hd, paste(rows, collapse = "")))
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
  # The first and last x labels sit exactly on the plot edges. Centring them there
  # pushes half the text outside the viewBox and the browser clips it ("12.5" ->
  # "12."), so anchor the outer two inward and only centre the middle one.
  xanch <- c("start", "middle", "end")
  # faint gridlines at the tick positions (drawn first, so they sit behind data).
  # Stroke/fill come from CSS classes, not literals, so the charts follow the
  # report's colour scheme (including dark mode and print).
  grid <- paste(c(
    sprintf('<line class="wf-grid" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>',
            sx(xt), mt, sx(xt), mt + ph),
    sprintf('<line class="wf-grid" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>',
            ml, sy(yt), ml + pw, sy(yt))), collapse = "")
  # thin axis lines
  axln <- sprintf('<line class="wf-axis" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>',
                  c(ml, ml), c(mt + ph, mt), c(ml + pw, ml), c(mt + ph, mt + ph))
  # short tick marks
  tick <- paste(c(
    sprintf('<line class="wf-tick" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>',
            sx(xt), mt + ph, sx(xt), mt + ph + 3),
    sprintf('<line class="wf-tick" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>',
            ml - 3, sy(yt), ml, sy(yt))), collapse = "")
  xtk <- paste(sprintf('<text class="wf-tk" x="%.1f" y="%.1f" text-anchor="%s">%s</text>',
               sx(xt), mt + ph + 14, xanch, .uniq_ticks(xt)), collapse = "")
  ylabs <- if (is.null(yfmt)) .uniq_ticks(yt) else yfmt(yt)
  # Same at the top/bottom of the y axis: nudge the outer labels inward so a tall
  # label is not cut off by the viewBox edge.
  ytk <- paste(sprintf('<text class="wf-tk" x="%.1f" y="%.1f" text-anchor="end">%s</text>',
               ml - 6, sy(yt) + c(2, 3, 7), ylabs), collapse = "")
  xl  <- sprintf('<text class="wf-al" x="%.1f" y="%.1f" text-anchor="middle">%s</text>',
                 ml + pw / 2, mt + ph + 29, xlab)
  yl  <- sprintf('<text class="wf-al" x="11" y="%.1f" text-anchor="middle" transform="rotate(-90 11 %.1f)">%s</text>',
                 mt + ph / 2, mt + ph / 2, ylab)
  paste0(grid, paste(axln, collapse = ""), tick, xtk, ytk, xl, yl)
}

.svg_evolution <- function(labels, y, w = 900L, h = 235L, lang = "en") {
  # N-20: skip the plot if any deff is non-finite (Inf overflow / NaN from
  # all-zero base weights); range()/diff()/any()/min() would otherwise error.
  n <- length(y); if (n < 2L || !all(is.finite(y))) return("")
  disp <- ifelse(seq_len(n) == 1L, "base", as.character(seq_len(n) - 1L))  # base,1,2,...
  ml <- 56; mr <- 22; mt <- 16; mb <- 40; pw <- w - ml - mr; ph <- h - mt - mb
  # A single spiking stage (a 1/p nonresponse step can push deff_K from 1.1 to 55)
  # flattens every other stage onto the baseline on a linear axis, which is
  # exactly where the reader needs to see movement. Switch to log10 when the
  # series spans more than an order of magnitude, and say so on the axis.
  logsc <- all(y > 0) && is.finite(max(y) / min(y)) && max(y) / min(y) >= 12
  ty  <- if (logsc) log10(y) else y
  yr  <- range(ty); if (diff(yr) == 0) yr <- yr + c(-0.05, 0.05)
  pad <- diff(yr) * 0.10; yr <- yr + c(-pad, pad)          # air above/below
  sx <- function(i) ml + (i - 1) / (n - 1) * pw
  sy <- function(v) mt + ph - (v - yr[1]) / diff(yr) * ph
  yt <- pretty(yr, 3)
  yt <- yt[yt >= yr[1] & yt <= yr[2]]      # pretty() overshoots the range; those
  if (!length(yt)) yt <- yr                # ticks drew a stray label under the axis
  grid <- paste(sprintf('<line class="wf-grid" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>',
                        ml, sy(yt), ml + pw, sy(yt)), collapse = "")
  ylabs <- if (logsc) .uniq_ticks(10^yt) else .uniq_ticks(yt)
  ytk  <- paste(sprintf('<text class="wf-tk" x="%.1f" y="%.1f" text-anchor="end">%s</text>',
                        ml - 6, sy(yt) + 3, ylabs), collapse = "")
  d    <- paste(sprintf("%.1f %.1f", sx(seq_len(n)), sy(ty)), collapse = " L ")
  # Soft band under the line: gives the series weight without a heavy fill.
  area <- sprintf('<path class="wf-area" d="M %.1f %.1f L %s L %.1f %.1f Z"/>',
                  sx(1), mt + ph, d, sx(n), mt + ph)
  line <- sprintf('<path class="wf-line" d="M %s" fill="none" stroke-width="2" stroke-linejoin="round"/>', d)
  dots <- paste(sprintf('<circle class="wf-mark" cx="%.1f" cy="%.1f" r="3"/>',
                        sx(seq_len(n)), sy(ty)), collapse = "")
  xtk  <- paste(sprintf('<text class="wf-tk" x="%.1f" y="%.1f" text-anchor="middle">%s</text>',
                        sx(seq_len(n)), mt + ph + 16, .html_escape(disp)), collapse = "")
  dd <- diff(y); ann <- ""
  if (length(dd) && any(dd > 0)) {
    ii  <- which.max(dd) + 1L
    ann <- sprintf('<text class="wf-up" x="%.1f" y="%.1f" text-anchor="middle" font-size="12">&#9650;</text>',
                   sx(ii), sy(ty[ii]) - 7)
  }
  if (length(dd) && min(dd) < -0.0005) {
    jj  <- which.min(dd) + 1L
    ann <- paste0(ann, sprintf('<text class="wf-dn" x="%.1f" y="%.1f" text-anchor="middle" font-size="12">&#9660;</text>',
                               sx(jj), sy(ty[jj]) + 16))
  }
  albl <- .t("deff_K by stage", "deff_K por etapa", lang)
  svg <- paste0('<svg viewBox="0 0 ', w, ' ', h,
         '" width="100%" role="img" aria-label="', albl, '"><title>', albl, '</title>',
         grid, ytk, area, line, dots, xtk, ann, '</svg>')
  ttl <- .t("Kish design effect across weighting steps",
            "Efecto de dise&ntilde;o de Kish por paso de ponderaci&oacute;n", lang)
  if (logsc) ttl <- paste0(ttl, .t(" <span class='muted'>(log scale)</span>",
                                   " <span class='muted'>(escala logar&iacute;tmica)</span>", lang))
  leg <- if (nzchar(ann)) sprintf("<div class='muted' style='margin-top:2px'>%s</div>",
    .t("<span class='sw-up'>&#9650;</span> largest rise in deff_K &#183; <span class='sw-dn'>&#9660;</span> largest drop",
       "<span class='sw-up'>&#9650;</span> mayor aumento del deff_K &#183; <span class='sw-dn'>&#9660;</span> mayor ca&iacute;da", lang)) else ""
  paste0("<figure class='chartblk'><figcaption class='viz-h'>", ttl, "</figcaption>", svg, leg, "</figure>")
}

.svg_frame <- function(body, w, h, title = NULL, lang = "en") {
  if (is.null(title)) title <- .t("diagnostic plot", "gr\u00e1fico de diagn\u00f3stico", lang)
  sprintf('<svg viewBox="0 0 %d %d" preserveAspectRatio="xMidYMid meet" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="%s"><title>%s</title>%s</svg>',
          w, h, title, title, body)
}

# A chart with its caption, as one <figure> so the title travels with the plot
# and cannot be orphaned at a page break.
.chart_figure <- function(svg, title = NULL) {
  if (!nzchar(svg)) return("")
  if (is.null(title)) return(sprintf("<figure class='chartblk'>%s</figure>", svg))
  sprintf("<figure class='chartblk'><figcaption class='viz-h'>%s</figcaption>%s</figure>", title, svg)
}

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
.svg_scatter <- function(x, y, w = 340, h = 224, cap = 3000L, lang = "en", title = NULL) {
  # mr must clear half of the last x tick label; 8px clipped it ("12.5" -> "12.").
  ml <- 56; mr <- 16; mt <- 12; mb <- 36; pw <- w - ml - mr; ph <- h - mt - mb
  i <- .thin_scatter(x, y, cap); x <- x[i]; y <- y[i]
  xr <- range(x); yr <- range(c(y, x))
  if (diff(xr) == 0) xr <- xr + c(-1, 1)
  if (diff(yr) == 0) yr <- yr + c(-1, 1)
  sx <- function(v) ml + (v - xr[1]) / diff(xr) * pw
  sy <- function(v) mt + ph - (v - yr[1]) / diff(yr) * ph
  pts <- paste(sprintf('<circle class="wf-pt" cx="%.1f" cy="%.1f" r="2.4"/>',
               sx(x), sy(y)), collapse = "")
  lo <- max(xr[1], yr[1]); hi <- min(xr[2], yr[2])
  ln  <- sprintf('<line class="wf-ref" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke-dasharray="4 3"/>',
                 sx(lo), sy(lo), sx(hi), sy(hi))
  lbl <- sprintf('<text class="wf-tk" x="%.1f" y="%.1f" text-anchor="end">y = x</text>',
                 sx(hi) - 4, sy(hi) + 13)
  svg <- .svg_frame(paste0(.svg_axes(ml, mt, pw, ph, xr, yr, .t("weight before", "peso antes", lang), .t("weight after", "peso despu\u00e9s", lang), sx, sy),
                    pts, ln, lbl), w, h,
                    .t("weight before vs after", "peso antes vs despu\u00e9s", lang), lang)
  .chart_figure(svg, title)
}

# Histogram of a per-unit quantity (default: the adjustment factor after/before),
# with a reference line at 1.
.svg_hist <- function(v, xlab = NULL, w = 340, h = 224,
                      refline = 1, lang = "en", title = NULL, density = FALSE) {
  if (is.null(xlab))
    xlab <- .t("adjustment factor (after / before)",
               "factor de ajuste (despu\u00e9s / antes)", lang)
  ml <- 52; mr <- 16; mt <- 12; mb <- 36; pw <- w - ml - mr; ph <- h - mt - mb
  v <- v[is.finite(v)]
  if (!length(v)) return("")
  # A handful of extreme values (a 36,000x adjustment factor, say) stretches the
  # axis until every other value collapses onto one pixel and the padded range
  # runs into negative territory for a quantity that cannot be negative. Clip the
  # display to the central 99% when the tail is that long, and say so in a note
  # rather than silently hiding data.
  clipped <- 0L; vfull <- v
  if (length(v) >= 40L) {
    qq <- as.numeric(stats::quantile(v, c(0.005, 0.995)))
    if (is.finite(qq[1]) && is.finite(qq[2]) && qq[2] > qq[1] &&
        diff(range(v)) > 12 * (qq[2] - qq[1])) {
      keep <- v >= qq[1] & v <= qq[2]
      clipped <- sum(!keep); v <- v[keep]
      if (!length(v)) { v <- vfull; clipped <- 0L }
    }
  }
  pos_only <- all(vfull > 0)
  uv <- unique(round(v, 8))
  ylab <- .t("count", "conteo", lang)
  if (length(uv) <= 30L) {
    # Few distinct values (e.g. adjustment-cell factors, integer 1/prob counts): a
    # fixed-bin histogram would show mostly empty bins and a few tall spikes. Draw a
    # frequency-by-VALUE dot plot (lollipop) instead -- one stem + dot per value.
    lv   <- sort(uv)
    cnts <- as.integer(table(factor(round(v, 8), levels = lv)))
    xr <- range(lv); xr <- if (diff(xr) == 0) xr + c(-0.5, 0.5) else xr + diff(xr) * c(-0.08, 0.08)
    if (pos_only) xr[1] <- max(xr[1], 0)     # no negative axis for a positive quantity
    yr <- c(0, max(cnts, 1))
    sx <- function(z) ml + (z - xr[1]) / diff(xr) * pw
    sy <- function(z) mt + ph - (z - yr[1]) / diff(yr) * ph
    xx <- sx(lv); yy <- sy(cnts); y0 <- sy(0)
    stems <- paste(sprintf('<line class="wf-stem" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke-width="2"/>',
                   xx, y0, xx, yy), collapse = "")
    dots  <- paste(sprintf('<circle class="wf-mark" cx="%.1f" cy="%.1f" r="3.2"/>', xx, yy), collapse = "")
    bars  <- paste0(stems, dots)
  } else {
    hh <- graphics::hist(v, breaks = 30, plot = FALSE)
    dd <- if (density) tryCatch(stats::density(v), error = function(e) NULL) else NULL
    if (!is.null(dd)) dd$c <- dd$y * length(v) * diff(hh$breaks)[1]   # density -> count scale
    xr <- range(hh$breaks); if (diff(xr) == 0) xr <- xr + c(-1, 1)
    if (pos_only) xr[1] <- max(xr[1], 0)
    yr <- c(0, max(max(hh$counts), if (!is.null(dd)) max(dd$c) else 0, 1))
    sx <- function(z) ml + (z - xr[1]) / diff(xr) * pw
    sy <- function(z) mt + ph - (z - yr[1]) / diff(yr) * ph
    bars <- paste(sprintf('<rect class="wf-bar" x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="1.5"/>',
                  sx(hh$breaks[-length(hh$breaks)]), sy(hh$counts),
                  pmax(sx(hh$breaks[-1]) - sx(hh$breaks[-length(hh$breaks)]) - 0.5, 0.5),
                  pmax(sy(0) - sy(hh$counts), 0)), collapse = "")
    if (!is.null(dd)) {
      keep <- dd$x >= xr[1] & dd$x <= xr[2]
      bars <- paste0(bars, sprintf('<polyline class="wf-line" points="%s" fill="none" stroke-width="1.6"/>',
                     paste(sprintf("%.1f,%.1f", sx(dd$x[keep]), sy(dd$c[keep])), collapse = " ")))
    }
  }
  vl <- if (!is.null(refline) && refline >= xr[1] && refline <= xr[2])
    paste0(sprintf('<line class="wf-ref" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke-dasharray="4 3"/>',
                   sx(refline), mt, sx(refline), mt + ph),
           sprintf('<text class="wf-tk" x="%.1f" y="%.1f">%s</text>',
                   sx(refline) + 4, mt + 9, .t("factor = 1", "factor = 1", lang))) else ""
  svg <- .svg_frame(paste0(.svg_axes(ml, mt, pw, ph, xr, yr, xlab, ylab, sx, sy),
                    bars, vl), w, h, .html_escape(gsub("<[^>]+>", "", title %||% xlab)), lang)
  if (clipped > 0L)
    svg <- paste0(svg, sprintf("<div class='muted'>%s</div>", .t(
      sprintf("Axis clipped to the central 99%%; %s value(s) outside the range are not drawn.",
              format(clipped, big.mark = ",")),
      sprintf("Eje recortado al 99%% central; %s valor(es) fuera del rango no se dibujan.",
              format(clipped, big.mark = ",")), lang)))
  .chart_figure(svg, title)
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
  keep <- .wf_active(prev) & .wf_active(cur)
  if (!any(keep)) return("")
  sc   <- tryCatch(.svg_scatter(prev[keep], cur[keep], lang = lang,
                     title = .t("Scatter plot of previous vs. updated weights",
                                "Dispersi&oacute;n de pesos previos vs. actualizados", lang)),
                   error = function(e) "")
  fac  <- (cur / prev)[keep]
  xlab <- if (inherits(step, "step_select_within"))
            .t("persons represented (1/prob)", "personas representadas (1/prob)", lang)
          else .t("adjustment factor (after / before)", "factor de ajuste (despu\u00e9s / antes)", lang)
  hi   <- tryCatch(.svg_hist(fac, xlab = xlab, lang = lang,
                     title = .t("Distribution of adjustment factors",
                                "Distribuci&oacute;n de los factores de ajuste", lang)),
                   error = function(e) "")
  if (!nzchar(sc) && !nzchar(hi)) return("")
  note <- if (sum(keep) > 3000L)
    sprintf("<p class='muted'>%s</p>", .t(
      sprintf("Showing 3,000 of %s points (both tails and the largest departures from y = x are kept).", format(sum(keep), big.mark = ",")),
      sprintf("Se muestran 3,000 de %s puntos (se conservan ambas colas y las mayores desviaciones de y = x).", format(sum(keep), big.mark = ",")), lang)) else ""
  sprintf("<div class='viz'>%s%s</div>%s", sc, hi, note)
}

# Compact R-indicator block, rendered inside the (last) nonresponse step card.
.ri_block <- function(ri, lang = "en") {
  ph <- ""
  ptab <- ri$partials
  if (!is.null(ptab)) {
    ptab <- ptab[order(-ptab$partial_R), , drop = FALSE]
    ptab$partial_R <- round(ptab$partial_R, 4)
    names(ptab) <- .wf_relabel(names(ptab), lang)
    ph <- paste0(sprintf("<p class='muted'>%s</p>", .t("Partial R-indicators (0&ndash;0.5):", "R-indicadores parciales (0&ndash;0.5):", lang)), .df_to_html(ptab, lang))
  }
  if (!is.null(ri$num_aux) && length(ri$num_aux))
    ph <- paste0(ph, sprintf(
      .t("<p class='muted'>Numeric auxiliaries are binned into quintiles for their partial; not computable (too few distinct values): %s.</p>",
         "<p class='muted'>Los auxiliares num\u00e9ricos se agrupan en quintiles para su parcial; no computable (muy pocos valores distintos): %s.</p>", lang),
      .html_escape(paste(ri$num_aux, collapse = ", "))))
  sprintf(
    .t("<div class='ri'><h3 class='card-t'>Response representativity (R-indicator)</h3>
<p class='muted'>Design-weighted logistic of response on <code>%s</code> (n = %s). Closer to 1 = more representative response; the partials show which variable drives the gap.</p>
<p class='ri-val'><strong>R = %.3f</strong> <span class='muted'>(0&ndash;1)</span></p>%s</div>",
       "<div class='ri'><h3 class='card-t'>Representatividad de la respuesta (R-indicador)</h3>
<p class='muted'>Log\u00edstica ponderada por dise\u00f1o de la respuesta sobre <code>%s</code> (n = %s). M\u00e1s cerca de 1 = respuesta m\u00e1s representativa; los parciales muestran qu\u00e9 variable explica la brecha.</p>
<p class='ri-val'><strong>R = %.3f</strong> <span class='muted'>(0&ndash;1)</span></p>%s</div>", lang),
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
  # With domain calibration (step_calibrate(by=)) the diagnostics carry a `domain`
  # column and one target PER domain; achieved must be recomputed within that
  # domain, not over the whole sample (which would compare a domain target against
  # the global total and report spurious drift).
  byvar <- object$steps[[kc]]$by
  has_dom <- !is.null(byvar) && "domain" %in% names(dcal) && byvar %in% names(data)
  rows <- lapply(seq_len(nrow(dcal)), function(r) {
    v <- as.character(dcal$variable[r]); ct <- as.character(dcal$category[r])
    tg <- suppressWarnings(as.numeric(dcal$target[r]))
    if (!v %in% names(data) || is.na(tg)) return(NULL)
    sel <- as.character(data[[v]]) == ct
    if (has_dom) sel <- sel & as.character(data[[byvar]]) == as.character(dcal$domain[r])
    ach <- sum(fin[sel], na.rm = TRUE)
    data.frame(variable = v, category = ct, target = round(tg), achieved = round(ach),
               `dev %` = round(if (tg != 0) 100 * (ach - tg) / tg else NA_real_, 2),
               check.names = FALSE, stringsAsFactors = FALSE)
  })
  rows <- do.call(rbind, rows)
  if (is.null(rows) || !nrow(rows)) return("")
  maxdev <- max(abs(rows[["dev %"]]), na.rm = TRUE)
  out <- sprintf(
    .t("<h2 id='drift'>Calibration drift</h2>
<p class='muted'>Steps after calibration (trimming, rounding, rescaling) move the weighted totals away from the calibration targets. <code>achieved</code> is recomputed at the final weights; max deviation %.2f%%.</p>%s",
       "<h2 id='drift'>Deriva de calibraci\u00f3n</h2>
<p class='muted'>Los pasos posteriores a la calibraci\u00f3n (recorte, redondeo, reescalado) alejan los totales ponderados de los objetivos de calibraci\u00f3n. <code>logrado</code> se recalcula con los pesos finales; desviaci\u00f3n m\u00e1xima %.2f%%.</p>%s", lang),
    maxdev, .df_to_html(`names<-`(rows, .wf_relabel(names(rows), lang)), lang))
  attr(out, "maxdev") <- maxdev            # so the closing checklist can read the real drift
  out
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
    "<div class='node node-end'><div class='nl'>%s</div><div class='nv'><code>%s</code></div></div>",
    .t("Base weights", "Pesos base", lang), .html_escape(object$base_weights))
  for (i in seq_along(object$steps)) {
    s <- object$steps[[i]]
    nodes <- c(nodes, sprintf(
      "<div class='node'><div class='nl'><span class='numc'>%d</span>%s</div>%s</div>",
      i, .step_short(s, lang), .chips(.step_vars(s))))
  }
  nodes <- c(nodes, sprintf(
    "<div class='node node-end'><div class='nl'>%s</div><div class='nv'><code>.weight</code></div></div>",
    .t("Final weights", "Pesos finales", lang)))
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
.svg_overlap <- function(p, resp, dw, lang = "en", w = 348, h = 182, title = NULL) {
  ok <- is.finite(p) & is.finite(dw); p <- p[ok]; resp <- as.logical(resp[ok]); dw <- dw[ok]
  if (length(p) < 20L || length(unique(resp)) < 2L) return("")
  ml <- 46; mr <- 16; mt <- 12; mb <- 34; pw <- w - ml - mr; ph <- h - mt - mb
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
  bar <- function(v, cls) paste(vapply(seq_len(K), function(i) sprintf(
    '<rect class="%s" x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill-opacity="0.45"/>',
    cls, sx(br[i]), sy(v[i]), max(sx(br[i + 1]) - sx(br[i]) - 0.5, 0.5),
    max(sy(0) - sy(v[i]), 0)), character(1)), collapse = "")
  leg <- sprintf('<text class="wf-resp" x="%.1f" y="%.1f" font-size="10">%s</text><text class="wf-nonresp" x="%.1f" y="%.1f" font-size="10">%s</text>',
    ml + 6, mt + 10, .t("respondents", "respondentes", lang),
    ml + 6, mt + 22, .t("nonrespondents", "no respondentes", lang))
  svg <- .svg_frame(paste0(.svg_axes(ml, mt, pw, ph, rng, c(0, ymax), "&phi;&#770;",
             .t("share", "proporci\u00f3n", lang), sx, sy),
             bar(hn, "wf-nonresp"), bar(hr, "wf-resp"), leg), w, h,
             .t("propensity overlap", "solapamiento de propensiones", lang), lang)
  .chart_figure(svg, title)
}

# Potter (1990) MSE-optimal trimming curve: estimated bias^2 (rising as the cut
# tightens), remaining variance (falling), and their sum, over the candidate
# thresholds, with the chosen cutoff marked. The two terms are on different
# scales -- this draws the raw heuristic and labels it an approximation.
.svg_potter <- function(grid, bias2, varc, mse, chosen, lang = "en", w = 360, h = 214) {
  ok <- is.finite(grid) & is.finite(mse) & is.finite(bias2) & is.finite(varc)
  grid <- grid[ok]; bias2 <- bias2[ok]; varc <- varc[ok]; mse <- mse[ok]
  if (length(grid) < 3L) return("")
  # Legend sits in a horizontal row in the bottom band, so reserve extra bottom
  # margin (mb) below the x-axis label instead of overlapping the top-left corner.
  ml <- 56; mr <- 12; mt <- 12; mb <- 56; pw <- w - ml - mr; ph <- h - mt - mb
  xr <- range(grid); if (diff(xr) == 0) xr <- xr + c(-1, 1)
  yr <- c(0, max(mse, varc, bias2, 1e-9))
  sx <- function(z) ml + (z - xr[1]) / diff(xr) * pw
  sy <- function(z) mt + ph - z / yr[2] * ph
  path <- function(y, col, wd) sprintf('<path d="M %s" fill="none" stroke="%s" stroke-width="%s"/>',
    paste(sprintf("%.1f %.1f", sx(grid), sy(y)), collapse = " L "), col, wd)
  vln <- sprintf('<line class="wf-chosen" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke-width="1" stroke-dasharray="3,2"/>',
    sx(chosen), mt, sx(chosen), mt + ph)
  vtx <- sprintf('<text class="wf-chosen" x="%.1f" y="%.1f" text-anchor="middle" font-size="10" stroke="none">%s</text>',
    sx(chosen), mt + 9, .t("chosen", "elegido", lang))
  bias_lab <- .t("bias&sup2;", "sesgo&sup2;", lang)
  ly <- h - 8   # single legend row in the reserved bottom band, no overlap
  leg <- sprintf('<text x="%.1f" y="%.1f" font-size="10" fill="var(--accent)">MSE</text><text x="%.1f" y="%.1f" font-size="10" fill="#2a78d6">%s</text><text x="%.1f" y="%.1f" font-size="10" fill="var(--warn)">var</text><text class="wf-chosen" x="%.1f" y="%.1f" font-size="10" stroke="none">%s</text>',
    ml, ly, ml + 40, ly, bias_lab, ml + 96, ly, ml + 126, ly, .t("chosen", "elegido", lang))
  sprintf("<div class='chart1'>%s</div>",
    .svg_frame(paste0(.svg_axes(ml, mt, pw, ph, xr, yr,
               .t("upper threshold", "umbral superior", lang),
               .t("bias&sup2; + var", "sesgo&sup2; + var", lang), sx, sy,
               yfmt = .fmt_si),
               path(varc, "var(--warn)", "1.2"), path(bias2, "#2a78d6", "1.2"),
               path(mse, "var(--accent)", "2"), vln, vtx, leg), w, h,
               .t("Potter MSE curve", "curva ECM de Potter", lang), lang))
}

# The family a step belongs to, as a short badge on the step card: it tells the
# reader at a glance which kind of adjustment they are looking at (coverage,
# nonresponse, calibration, ...) without reading the full label, and gives the
# eye a fixed anchor down the right edge of the cascade.
.step_kind <- function(step, lang) {
  k <- function(en, es) .t(en, es, lang)
  if (inherits(step, c("step_unknown_eligibility", "step_drop_ineligible")))
    return(k("coverage", "cobertura"))
  if (inherits(step, "step_select_within"))     return(k("selection", "selecci\u00f3n"))
  if (inherits(step, "step_subsample"))         return(k("phase 2", "fase 2"))
  if (inherits(step, "step_nonresponse"))       return(k("nonresponse", "no respuesta"))
  if (inherits(step, "step_nr_sensitivity"))    return(k("sensitivity", "sensibilidad"))
  if (inherits(step, "step_pseudoweight"))      return(k("pseudo-weights", "pseudo-pesos"))
  if (inherits(step, c("step_calibrate", "step_model_calibration")))
    return(k("calibration", "calibraci\u00f3n"))
  if (inherits(step, c("step_trim", "step_trim_calibrated", "step_trim_weights")))
    return(k("trimming", "recorte"))
  if (inherits(step, "step_round"))             return(k("rounding", "redondeo"))
  if (inherits(step, "step_rescale"))           return(k("rescaling", "reescalado"))
  if (inherits(step, "step_assert"))            return(k("check", "control"))
  k("step", "paso")
}

# The deff_K / n_eff move a step produced, as a small strip that closes the step
# card. Arrow direction and colour are driven by the sign, so "this step cost
# precision" is visible without reading the numbers.
.delta_strip <- function(de1, de2, lang) {
  d1 <- de1$deff; d2 <- de2$deff
  n1 <- de1$n_eff; n2 <- de2$n_eff
  dir <- if (!is.finite(d1) || !is.finite(d2) || abs(d2 - d1) < 5e-4) "flat"
         else if (d2 > d1) "up" else "down"
  mark <- switch(dir, up = "&#9650;", down = "&#9660;", "&#183;")
  cls  <- switch(dir, up = "sw-up", down = "sw-dn", "muted")
  f3   <- function(x) if (is.finite(x)) sprintf("%.3f", x) else "&ndash;"
  fn   <- function(x) if (is.finite(x)) format(round(x), big.mark = ",") else "&ndash;"
  pctd <- if (is.finite(n1) && is.finite(n2) && n1 > 0)
    sprintf(" <span class='%s'>(%+.1f%%)</span>", cls, 100 * (n2 - n1) / n1) else ""
  sprintf(paste0("<p class='delta'><span><span class='dk'>deff_K</span> ",
                 "<b>%s</b> &rarr; <b>%s</b> <span class='%s'>%s</span></span>",
                 "<span><span class='dk'>n_eff</span> <b>%s</b> &rarr; <b>%s</b>%s</span></p>"),
          f3(d1), f3(d2), cls, mark, fn(n1), fn(n2), pctd)
}
