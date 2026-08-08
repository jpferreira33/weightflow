# report cards: exec summary, status checklist, fieldwork (AAPOR), domains, replication, reproducibility.

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
