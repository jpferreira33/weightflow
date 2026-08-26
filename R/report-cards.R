# report cards: exec summary, status checklist, fieldwork (AAPOR), domains, replication, reproducibility.

.exec_summary <- function(object, ri, de_f, lang, survey = NULL) {
  shorts <- vapply(object$steps, function(s) .step_short(s, lang), character(1))
  n <- length(shorts)
  listed <- paste(sprintf("(%d) %s", seq_len(n), shorts), collapse = ", ")
  neff <- format(round(de_f$n_eff), big.mark = ",")
  # First sentence names the process (and the survey, when supplied).
  s1 <- if (!is.null(survey))
    .t(sprintf("This report documents the survey weighting process for <strong>%s</strong>.", .html_escape(survey)),
       sprintf("Este reporte documenta el proceso de ponderaci&oacute;n de <strong>%s</strong>.", .html_escape(survey)), lang)
    else .t("This report documents the survey weighting process.",
            "Este reporte documenta el proceso de ponderaci&oacute;n de la muestra.", lang)
  s2 <- .t(
    sprintf("%s weighting %s applied: %s.", n, if (n == 1L) "step was" else "steps were", listed),
    sprintf("%s de ponderaci&oacute;n: %s.",
            if (n == 1L) "Se aplic&oacute; 1 paso" else sprintf("Se aplicaron %d pasos", n), listed),
    lang)
  s3 <- .t(
    sprintf("The final survey weights have a Kish design effect of %.3f, corresponding to an effective sample size of %s.", de_f$deff, neff),
    sprintf("Los pesos finales tienen un efecto de dise&ntilde;o de Kish de %.3f, que corresponde a un tama&ntilde;o de muestra efectivo de %s.", de_f$deff, neff),
    lang)
  s4 <- if (!is.null(ri))
    .t(sprintf(" The response R-indicator is %.3f.", ri$R),
       sprintf(" El R-indicator de respuesta es %.3f.", ri$R), lang) else ""
  body <- paste0(s1, " ", s2, " ", s3, s4)
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
  # Only a step that tracks convergence (a calibration) can support the claim; do
  # not print "all steps converged" for a recipe with no such step (vacuously true).
  has_conv <- any(vapply(object$steps,
                         function(s) !is.null(attr(s$diagnostics, "converged")), logical(1)))
  nalert  <- sum(vapply(object$steps, function(s)
    !is.null(s$alerts) && length(s$alerts) > 0L, logical(1)))
  pos <- fin[fin > 0]; med <- if (length(pos)) stats::median(pos) else NA_real_
  n_ext <- if (length(pos)) sum(pos > 4 * med) else 0L
  has_rep <- !is.null(replicates) &&
             inherits(replicates, c("weightflow_boot", "weightflow_jack"))
  item <- function(ok, txt) sprintf("<li><span class='%s'>%s</span> %s</li>",
    if (ok) "ok" else "no", if (ok) "&#10003;" else "&#10007;", txt)
  items <- c(
    if (has_conv) item(nonconv == 0L, if (nonconv == 0L)
      .t("All calibration steps converged.", "Todos los pasos de calibraci\u00f3n convergieron.", lang)
      else .t(sprintf("%d step(s) did not converge.", nonconv),
              sprintf("%d paso(s) no convergieron.", nonconv), lang)) else NULL,
    item(TRUE, .t(sprintf("Final Kish design effect: %.3f (effective sample size: %s).",
                          de_f$deff, format(round(de_f$n_eff), big.mark = ",")),
                  sprintf("Efecto de dise\u00f1o de Kish final: %.3f (tama\u00f1o de muestra efectivo: %s).",
                          de_f$deff, format(round(de_f$n_eff), big.mark = ",")), lang)),
    if (length(pos)) item(n_ext == 0L, if (n_ext == 0L)
      .t("No weights exceed the extreme-weight threshold (four times the median weight).",
         "Ning\u00fan peso supera el umbral de peso extremo (cuatro veces el peso mediano).", lang)
      else .t(sprintf("%d weight(s) exceed the extreme-weight threshold of four times the median weight.", n_ext),
              sprintf("%d peso(s) superan el umbral de peso extremo de cuatro veces el peso mediano.", n_ext), lang)) else NULL,
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
  # Amber at deff >= 1.4, the same "substantial efficiency loss" threshold used by
  # the closing interpretation, so the table and the text agree.
  dcell <- function(v) if (is.na(v)) "&ndash;" else
    sprintf("<span class='%s'>%s%s</span>", if (v >= 1.4) "cell-warn" else "cell-ok", if (v >= 1.4) "&#9888; " else "", d3(v))
  hd <- paste0("<th scope='col'>", c(.t("Domain", "Dominio", lang),
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
.replication_card <- function(rep, lang, object = NULL) {
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
       sprintf("%s of %s", format(nfail, big.mark = ","), format(nrep, big.mark = ","))),
    kv(.t("Strata", "Estratos", lang), format(nstr, big.mark = ",")),
    kv(.t("Mean PSUs per stratum", "UPM por estrato (media)", lang), sprintf("%.1f", mean(pps))),
    if (!is.null(rep$df))
      kv(.t("Degrees of freedom", "Grados de libertad", lang), format(rep$df, big.mark = ",")) else "",
    # FPC is a bootstrap concept only, and only when a non-zero fraction was given.
    if (is_jack) "" else
    kv(.t("Finite-population correction", "Correcci&oacute;n de poblaci&oacute;n finita (FPC)", lang),
       if (!is.null(rep$fpc) && !(is.numeric(rep$fpc) && all(rep$fpc == 0)))
         .t("applied", "aplicada", lang)
       else .t("None (with-replacement bootstrap)", "ninguna (bootstrap con reemplazo)", lang)),
    kv(.t("Lonely-PSU handling", "Manejo de lonely PSU", lang), na(rep$lonely_psu)),
    kv(.t("Recipe-aware replication", "Replicaci\u00f3n recipe-aware", lang),
       if (nrep > 0L && nfail >= nrep)
         .t("not applicable (all replicates failed)", "no aplica (todas las r\u00e9plicas fallaron)", lang)
       else .t("Full weighting procedure re-run for each replicate",
               "todo el procedimiento de ponderaci\u00f3n se recalcula en cada r\u00e9plica", lang)),
    if (!is_jack) kv(.t("Seed", "Semilla", lang), na(rep$seed)) else "",
    kv(.t("Cores", "Cores", lang), na(rep$cores)),
    kv(.t("Run time", "Tiempo de ejecuci\u00f3n", lang), tfmt))
  al <- function(msg) sprintf("<div class='alert'><strong>%s</strong><p>%s</p></div>",
                              .t("Point of attention", "Punto de atenci\u00f3n", lang), msg)
  # N-24: an all-NA replicate matrix cannot yield a variance; say so instead of
  # implying success elsewhere in the report.
  fail_alert <- if (nrep == 0L)
      al(.t("No replicates were produced, so no replication variance is available.",
            "No se produjeron r\u00e9plicas, as\u00ed que no hay varianza por replicaci\u00f3n disponible.", lang))
    else if (nfail >= nrep)
      al(.t(sprintf("All %d replicate(s) failed with NA weights; the replication variance cannot be estimated from these weights.", nrep),
            sprintf("Las %d r\u00e9plica(s) fallaron con pesos NA; no se puede estimar la varianza por replicaci\u00f3n con estos pesos.", nrep), lang))
    else ""
  # N-24: a single-PSU stratum contributes no variance under EITHER the rescaling
  # bootstrap or the delete-a-PSU jackknife (the lone PSU cannot be deleted), so
  # switching method does not fix it -- collapsing the strata does.
  warn <- if (lonely_n > 0L)
      al(.t(sprintf("%d stratum/strata have a single PSU. A single-PSU stratum contributes no variance under either the rescaling bootstrap or the delete-a-PSU jackknife (the lone PSU cannot be deleted), so both understate the variance. Collapse such strata (lonely_psu = \"collapse\") or redefine the strata rather than switching method.", lonely_n),
            sprintf("%d estrato(s) con una sola UPM. Un estrato con una sola UPM no aporta varianza ni con el bootstrap de reescalado ni con el jackknife borra-una-UPM (no se puede borrar la \u00fanica UPM), as\u00ed que ambos la subestiman. Conviene colapsar esos estratos (lonely_psu = \"collapse\") o redefinir los estratos, m\u00e1s que cambiar de m\u00e9todo.", lonely_n), lang))
    else if (mean(pps) < 3)
      al(.t("Few PSUs per stratum: the replication variance can be unstable. Consider more PSUs per stratum or collapsing sparse strata.",
            "Pocas UPM por estrato: la varianza por replicaci\u00f3n puede ser inestable. Conviene m\u00e1s UPM por estrato o colapsar los estratos ralos.", lang))
    else ""
  # Note when the recipe calibrates to totals ESTIMATED from a reference survey:
  # say whether their sampling variance is propagated here or omitted (fixed).
  ref_note <- ""
  if (!is.null(object) && !is.null(object$steps)) {
    hit <- Filter(function(s) inherits(s$population, "wf_reference_sample"), object$steps)
    if (length(hit)) {
      # Only the BOOTSTRAP pairs each replicate with the reference's replicate to
      # re-estimate the totals; the delete-a-PSU jackknife has no such pairing and
      # treats the estimated totals as fixed (see reference_sample() docs). So the
      # propagation claim holds only for a bootstrap object.
      has_rep <- !is_jack &&
        any(vapply(hit, function(s) !is.null(attr(s$population, "wf_ref_replicates")),
                   logical(1)))
      ref_note <- if (has_rep)
        sprintf("<p class='note'>%s</p>", .t(
          "Some control totals are estimated from a reference survey; their sampling variance is propagated through these replicates (each replicate re-estimates the totals from the paired reference replicate; Opsomer and Erciulescu 2021).",
          "Algunos totales de control se estiman a partir de una encuesta de referencia; su variabilidad muestral se propaga en estas r\u00e9plicas (cada r\u00e9plica reestima los totales desde la r\u00e9plica pareada de la referencia; Opsomer y Erciulescu 2021).", lang))
      else
        al(.t("Some control totals are estimated from a reference survey but were treated as fixed (no reference replicate weights supplied), so this replication variance omits their sampling error and may be understated.",
              "Algunos totales de control se estiman a partir de una encuesta de referencia pero se trataron como fijos (sin pesos r\u00e9plica de la referencia), as\u00ed que esta varianza por replicaci\u00f3n omite su error muestral y puede quedar subestimada.", lang))
    }
  }
  # A plain status line when every replicate produced valid weights.
  ok_line <- if (nrep > 0L && nfail == 0L)
    sprintf("<p class='note'>%s</p>", .t(
      sprintf("All %s replicates completed successfully.", format(nrep, big.mark = ",")),
      sprintf("Las %s r\u00e9plicas se completaron correctamente.", format(nrep, big.mark = ",")), lang))
    else ""
  sprintf(
    "<div class='meta racct'><h4>%s</h4><table class='params'><tbody>%s</tbody></table>%s%s%s%s<p class='note'>%s</p></div>",
    .t("Replication-based variance estimation", "Estimaci\u00f3n de la varianza por replicaci\u00f3n", lang),
    body, ok_line, fail_alert, warn, ref_note,
    .t("For each replicate, the complete survey weighting procedure is re-run. The resulting replicate weights therefore reflect the sampling variability associated with the weighting adjustments that are re-estimated within the replication procedure. Use the final and replicate weights with the 'survey' or 'srvyr' package to estimate standard errors, coefficients of variation, and confidence intervals for specific survey estimates.",
       "En cada r\u00e9plica se recalcula todo el procedimiento de ponderaci\u00f3n. Los pesos r\u00e9plica resultantes reflejan la variabilidad muestral asociada a los ajustes de ponderaci\u00f3n que se reestiman dentro del procedimiento de replicaci\u00f3n. Us\u00e1 los pesos finales y los pesos r\u00e9plica con 'survey' o 'srvyr' para estimar errores est\u00e1ndar, coeficientes de variaci\u00f3n e intervalos de confianza de estimaciones concretas.", lang))
}


# Fieldwork outcome rates (AAPOR Standard Definitions). From the recipe's
# eligibility / nonresponse steps we reconstruct the disposition of every case
# -- ineligible (out of scope), unknown eligibility, eligible respondent,
# eligible nonrespondent -- and report the eligibility rate e (proportional /
# CASRO allocation), the e-adjusted response rate RR3 = ER / (ER + ENR + e*UNK) and
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

  f0  <- function(x) format(round(x), big.mark = ",", scientific = FALSE)
  pct <- function(x) sprintf("%.1f%%", 100 * x / cnt[["T"]])
  prr <- function(x) if (is.na(x)) "&ndash;" else sprintf("%.1f%%", 100 * x)
  sym <- function(lbl, sy) sprintf(
    "%s <span class='muted' style='font-family:ui-monospace,Menlo,monospace'>(%s)</span>", lbl, sy)
  lab <- list(
    T  = sym(.t("Total sample (issued cases)", "Muestra total (casos emitidos)", lang), "n"),
    NE = sym(.t("Ineligible / out of scope", "Inelegibles / fuera de alcance", lang), "IN"),
    U  = sym(.t("Unknown eligibility", "Elegibilidad desconocida", lang), "UNK"),
    R  = sym(.t("Eligible respondents", "Elegibles respondentes", lang), "ER"),
    NR = sym(.t("Eligible nonrespondents", "Elegibles no respondentes", lang), "ENR"))
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
                fx("e = (ER + ENR) / (ER + ENR + IN)")), ru[["e"]], rw[["e"]]),
    rrow(paste0(.t("Response rate &mdash; all unknowns eligible (AAPOR RR1)",
                   "Tasa de respuesta &mdash; todos los desconocidos elegibles (AAPOR RR1)", lang),
                fx("RR1 = ER / (ER + ENR + UNK)")), ru[["rr_all"]], rw[["rr_all"]]),
    rrow(paste0(.t("Response rate &mdash; e-adjusted (AAPOR RR3, CASRO)",
                   "Tasa de respuesta &mdash; ajustada por e (AAPOR RR3, CASRO)", lang),
                fx("RR3 = ER / (ER + ENR + e&middot;UNK)")), ru[["rr_e"]], rw[["rr_e"]]),
    rrow(paste0(.t("Response rate &mdash; unknowns excluded (AAPOR RR5)",
                   "Tasa de respuesta &mdash; desconocidos excluidos (AAPOR RR5)", lang),
                fx("RR5 = ER / (ER + ENR)")), ru[["rr_no"]], rw[["rr_no"]]),
    rrow(.t("Nonresponse rate (1 &minus; RR3)", "Tasa de no respuesta (1 &minus; RR3)", lang),
         ru[["nrr"]], rw[["nrr"]]))
  foot <- .t(
    "Symbols: ER = eligible respondents, ENR = eligible nonrespondents, IN = ineligibles, UNK = unknown eligibility, n = total (the disposition counts above; the weighted column uses their base-weighted sums). Response rates follow the AAPOR Standard Definitions; the set notation (ER, ENR, IN, UNK) follows Valliant, Dever and Kreuter (2018, sec. 13.4), who map the AAPOR disposition codes into these sets. e is the eligibility rate among cases of known eligibility (proportional / CASRO allocation). The response rate is shown in three variants, from most to least conservative by how the unknown-eligibility cases (UNK) are treated: RR1 counts all UNK as eligible, ER / (ER + ENR + UNK); RR3 counts the estimated fraction e&middot;UNK (CASRO), ER / (ER + ENR + e&middot;UNK); RR5 excludes UNK, ER / (ER + ENR). Thus RR1 &le; RR3 &le; RR5 (no partials are distinguished, so RR1=RR2, RR3=RR4, RR5=RR6). The weighted column uses the base (design) weights.",
    "S\u00edmbolos: ER = elegibles respondentes, ENR = elegibles no respondentes, IN = inelegibles, UNK = elegibilidad desconocida, n = total (los conteos de la tabla de arriba; la columna ponderada usa sus sumas ponderadas por el peso base). AAPOR Standard Definitions; la notaci&oacute;n de conjuntos (ER, ENR, IN, UNK) sigue a Valliant, Dever y Kreuter (2018, sec. 13.4), que mapean los c&oacute;digos de disposici&oacute;n de AAPOR a estos conjuntos. e es la tasa de elegibilidad entre casos de elegibilidad conocida (asignaci\u00f3n proporcional / CASRO). La tasa de respuesta se muestra en tres variantes, de la m\u00e1s a la menos conservadora seg\u00fan c\u00f3mo se tratan los casos de elegibilidad desconocida (UNK): RR1 cuenta todos los UNK como elegibles, ER / (ER + ENR + UNK); RR3 cuenta la fracci\u00f3n estimada e&middot;UNK (CASRO), ER / (ER + ENR + e&middot;UNK); RR5 excluye los UNK, ER / (ER + ENR). As\u00ed RR1 &le; RR3 &le; RR5 (no se distinguen parciales, por lo que RR1=RR2, RR3=RR4, RR5=RR6). La columna ponderada usa el peso base (de dise\u00f1o).",
    lang)
  # 1.2: when the recipe declares no eligibility steps, U and NE are 0 by
  # construction and RR1 = RR3 = RR5. Say so, so the reader does not misread three
  # identical rates as "there were no unknown-eligibility / ineligible cases".
  note_elig <- if (!length(iu) && !length(id))
    sprintf("<p class='note' style='color:#b45309'>%s</p>",
      .t(paste0("This recipe declares no eligibility steps, so UNK (unknown eligibility) and IN ",
                "(ineligible) are 0 by construction and RR1 = RR3 = RR5. The rates reflect the ",
                "declared steps, not that no such cases existed; add step_unknown_eligibility() / ",
                "step_drop_ineligible() to model eligibility."),
         paste0("Esta receta no declara pasos de elegibilidad, por lo que UNK (elegibilidad ",
                "desconocida) y IN (inelegibles) son 0 por construcci\u00f3n y RR1 = RR3 = RR5. Las ",
                "tasas reflejan los pasos declarados, no que no existieran esos casos; agreg\u00e1 ",
                "step_unknown_eligibility() / step_drop_ineligible() para modelar la elegibilidad."),
         lang)) else ""
  cap_disp <- .t("AAPOR disposition of the issued sample: counts, percentage and base-weighted sums by outcome category.",
                 "Disposici&oacute;n AAPOR de la muestra emitida: conteos, porcentaje y sumas ponderadas por el peso base seg&uacute;n categor&iacute;a de resultado.", lang)
  cap_rate <- .t("AAPOR eligibility and response rates, unweighted and base-weighted.",
                 "Tasas AAPOR de elegibilidad y respuesta, sin ponderar y ponderadas por el peso base.", lang)
  sprintf("<div class='meta racct'><h4>%s</h4>%s
    <table class='params'><caption class='sr-only'>%s</caption><thead><tr><th scope='col'>%s</th><th class='r' scope='col'>%s</th><th class='r' scope='col'>%%</th><th class='r' scope='col'>%s</th></tr></thead><tbody>%s</tbody></table>
    <table class='params' style='margin-top:10px'><caption class='sr-only'>%s</caption><thead><tr><th scope='col'>%s</th><th class='r' scope='col'>%s</th><th class='r' scope='col'>%s</th></tr></thead><tbody>%s</tbody></table>
    <p class='note'>%s</p></div>",
    .t("Fieldwork outcomes (AAPOR)", "Resultados del trabajo de campo (AAPOR)", lang), note_elig,
    cap_disp,
    .t("Disposition", "Disposici\u00f3n", lang),
    .t("n (cases)", "n (casos)", lang),
    .t("weighted (base)", "ponderado (base)", lang), arows,
    cap_rate,
    .t("Rate", "Tasa", lang),
    .t("unweighted", "sin ponderar", lang),
    .t("weighted (base)", "ponderado (base)", lang), rrows, foot)
}

# Reference-metadata card (SIMS / ESMS concepts relevant to weighting, GSBPM
# 5.6). `md` is a user-supplied named list; recognised keys get a proper
# bilingual label in a fixed order, and any extra keys are shown generically.
.metadata_card <- function(md, lang) {
  if (is.null(md) || !length(md)) return("")
  # Accept a named vector too, and collapse multi-value entries to one string so a
  # length > 1 value does not break the `if (nzchar(...))` guards or the row sprintf.
  if (!is.list(md)) md <- as.list(md)
  mdv <- function(x) paste(as.character(x), collapse = "; ")
  known <- c(
    survey          = .t("Statistical operation", "Operaci\u00f3n estad\u00edstica", lang),
    reference_period= .t("Reference period", "Per\u00edodo de referencia", lang),
    wave            = .t("Wave / period", "Onda / periodo", lang),
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
  rows <- row(.t("GSBPM sub-process", "Subproceso GSBPM", lang),
              .t("5.6 Calculate weights", "5.6 Calcular ponderaciones", lang))
  for (k in names(known)) if (!is.null(md[[k]]) && nzchar(mdv(md[[k]])))
    rows <- paste0(rows, row(known[[k]], mdv(md[[k]])))
  for (k in setdiff(names(md), names(known)))
    if (nzchar(k) && !is.null(md[[k]]) && nzchar(mdv(md[[k]])))
      rows <- paste0(rows, row(.html_escape(k), mdv(md[[k]])))
  sprintf("<div class='meta'><h4>%s</h4><table class='params'><caption class='sr-only'>%s</caption>%s</table></div>",
          .t("Reference metadata (SIMS / GSBPM 5.6)", "Metadatos de referencia (SIMS / GSBPM 5.6)", lang),
          .t("Reference metadata: key survey and calibration concepts (SIMS / GSBPM 5.6).",
             "Metadatos de referencia: conceptos clave de la encuesta y la calibraci&oacute;n (SIMS / GSBPM 5.6).", lang),
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

# Propensity-model diagnostics for ML nonresponse (method = "propensity"):
# calibration of the estimated propensities (the metric that matters for 1/p
# weighting, not classification), propensity floor/overlap, and covariate
# balance after 1/p weighting. Reads attr(diag, "propensity"); "" otherwise.
.propensity_diagnostics <- function(step, lang) {
  pr <- attr(step$diagnostics, "propensity")
  if (is.null(pr) || is.null(pr$p) || !length(pr$p)) return("")
  p <- as.numeric(pr$p); resp <- as.logical(pr$resp); dw <- as.numeric(pr$dw)
  ok <- is.finite(p) & is.finite(dw) & !is.na(resp)
  p <- p[ok]; resp <- resp[ok]; dw <- dw[ok]
  if (length(p) < 20L || length(unique(resp)) < 2L) return("")
  wm  <- function(x, wt) { sm <- sum(wt); if (sm <= 0) NA_real_ else sum(wt * x) / sm }
  d3  <- function(x) if (!is.finite(x)) "&ndash;" else formatC(x, format = "f", digits = 3)
  pc1 <- function(x) if (!is.finite(x)) "&ndash;" else sprintf("%.1f%%", x)

  # (a) calibration of the propensities, by decile of phi-hat
  br <- unique(stats::quantile(p, probs = 0:10 / 10, na.rm = TRUE, names = FALSE))
  cal_html <- ""
  if (length(br) >= 3L) {
    g  <- cut(p, breaks = br, include.lowest = TRUE)
    hd <- paste0("<th scope='col'>", c(.t("Propensity deciles", "Deciles de propensi&oacute;n", lang), "n",
                           .t("Predicted", "Predicho", lang),
                           .t("Observed", "Observado", lang),
                           .t("Diff.", "Dif.", lang)), "</th>", collapse = "")
    rows <- vapply(levels(g), function(l) {
      sidx <- which(g == l); pd <- wm(p[sidx], dw[sidx])
      ob <- wm(as.numeric(resp[sidx]), dw[sidx]); dif <- ob - pd
      dcell <- if (!is.finite(dif)) "<span class='muted'>&mdash;</span>"
               else sprintf("<span class='%s'>%+.3f</span>",
                            if (abs(dif) > 0.05) "cell-warn" else "cell-ok", dif)
      sprintf("<tr><td>%s</td><td>%d</td><td>%s</td><td>%s</td><td>%s</td></tr>",
              .html_escape(l), length(sidx), d3(pd), d3(ob), dcell)
    }, character(1))
    cal_html <- sprintf("<table class='stagetbl'><thead><tr>%s</tr></thead><tbody>%s</tbody></table>",
                        hd, paste(rows, collapse = ""))
  }
  lp  <- stats::qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
  cox <- tryCatch(suppressWarnings(stats::glm(as.integer(resp) ~ lp,
           family = stats::binomial(), weights = dw)), error = function(e) NULL)
  slope <- if (!is.null(cox)) unname(stats::coef(cox)[2]) else NA_real_
  intc  <- if (!is.null(cox)) unname(stats::coef(cox)[1]) else NA_real_
  brier <- wm((as.numeric(resp) - p)^2, dw)
  cal_note <- .t(
    sprintf("Calibration slope %s (ideal 1), intercept %s (ideal 0), Brier %s. For 1/&phi;&#770; weighting the estimated propensities must be well-calibrated, not merely discriminative: among units with &phi;&#770; near a value, that fraction should respond.",
            d3(slope), d3(intc), d3(brier)),
    sprintf("Pendiente de calibraci\u00f3n %s (ideal 1), intercepto %s (ideal 0), Brier %s. Para ponderar por 1/&phi;&#770; las propensiones estimadas deben estar bien calibradas, no solo discriminar: entre unidades con &phi;&#770; cercana a un valor, esa fracci\u00f3n deber\u00eda responder.",
            d3(slope), d3(intc), d3(brier)), lang)

  # (b) floor / overlap among respondents (they carry the 1/p weights)
  pr_r <- p[resp]; dw_r <- dw[resp]
  flo  <- function(t) 100 * wm(as.numeric(pr_r < t), dw_r)
  floor_note <- .t(
    sprintf("Respondents with &phi;&#770; below 0.10: %s; below 0.05: %s (min %s). Small propensities become large 1/&phi;&#770; weights; a very sharp model can hide extreme weights in a few units.",
            pc1(flo(0.10)), pc1(flo(0.05)), d3(min(pr_r))),
    sprintf("Respondentes con &phi;&#770; bajo 0.10: %s; bajo 0.05: %s (m\u00ednimo %s). Las propensiones chicas se vuelven pesos 1/&phi;&#770; grandes; un modelo muy filoso puede esconder pesos extremos en pocas unidades.",
            pc1(flo(0.10)), pc1(flo(0.05)), d3(min(pr_r))), lang)

  # (c) covariate balance: weighted respondents (before dw, after dw/p) vs the
  # full eligible sample (target, weighted by dw); standardized differences.
  bal_html <- ""
  cov <- tryCatch(pr$covars[ok, , drop = FALSE], error = function(e) NULL)
  if (!is.null(cov) && ncol(cov)) {
    mm <- tryCatch(stats::model.matrix(~ ., data = cov)[, -1, drop = FALSE],
                   error = function(e) NULL)
    if (!is.null(mm) && ncol(mm)) {
      wa <- dw_r / pr_r
      rr <- lapply(colnames(mm), function(cn) {
        x  <- mm[, cn]; mt <- wm(x, dw); st <- sqrt(wm((x - mt)^2, dw))
        if (!is.finite(st) || st <= 0) return(NULL)
        data.frame(v = cn, before = (wm(x[resp], dw[resp]) - mt) / st,
                   after = (wm(x[resp], wa) - mt) / st, stringsAsFactors = FALSE)
      })
      bal <- do.call(rbind, rr)
      if (!is.null(bal) && nrow(bal)) {
        hd <- paste0("<th scope='col'>", c(.t("Covariate", "Covariable", lang),
                     .t("Std. diff. before", "Dif. estand. antes", lang),
                     .t("Std. diff. after", "Dif. estand. despu\u00e9s", lang)),
                     "</th>", collapse = "")
        brows <- vapply(seq_len(nrow(bal)), function(i) sprintf(
          "<tr><td>%s</td><td>%+.3f</td><td><span class='%s'>%+.3f</span></td></tr>",
          .html_escape(bal$v[i]), bal$before[i],
          if (is.finite(bal$after[i]) && abs(bal$after[i]) > 0.1) "cell-warn" else "cell-ok",
          bal$after[i]), character(1))
        bal_html <- sprintf("<p class='muted'>%s</p><table class='stagetbl'><thead><tr>%s</tr></thead><tbody>%s</tbody></table>",
          .t("Standardized differences of the model covariates: weighted respondents vs the full eligible sample (target). |diff| &gt; 0.1 is flagged.",
             "Diferencias estandarizadas de las covariables del modelo: respondentes ponderados vs la muestra elegible completa (objetivo). Se marca |dif| &gt; 0.1.", lang),
          hd, paste(brows, collapse = ""))
      }
    }
  }

  # model spec / hyperparameters (auditability: what model produced these p-hat)
  eng <- pr$engine %||% "logit"
  cf  <- if (is.null(pr$crossfit)) .t("in-sample (no cross-fitting)", "en muestra (sin cross-fitting)", lang)
         else sprintf(.t("%d-fold cross-fitting", "cross-fitting de %d folds", lang), pr$crossfit)
  wgt <- if (is.null(pr$weight_model) || isTRUE(pr$weight_model)) .t("design-weighted fit", "ajuste ponderado por dise\u00f1o", lang)
         else .t("unweighted fit", "ajuste sin ponderar", lang)
  cls <- if (is.null(pr$num_classes)) .t("1/&phi;&#770; per unit", "1/&phi;&#770; por unidad", lang)
         else sprintf(.t("%d propensity classes", "%d clases de propensi\u00f3n", lang), pr$num_classes)
  hyp <- switch(eng,
    boost  = " (nrounds=150, max_depth=4, eta=0.1)",
    forest = " (ranger defaults: num.trees=500, mtry=floor(sqrt(p)))",
    tree   = " (rpart defaults: cp=0.01, minsplit=20)",
    logit  = .t(" (weighted logistic regression)", " (regresi\u00f3n log\u00edstica ponderada)", lang),
    "")
  spec_note <- sprintf("<p class='muted'><strong>%s:</strong> %s &middot; %s &middot; %s &middot; %s%s</p>",
    .t("Model", "Modelo", lang), .html_escape(eng), cf, wgt, cls, hyp)

  # weighted AUC (approx, ties ignored): P(phi-hat higher for a respondent)
  wauc <- function(pp, rr, ww) tryCatch({
    o <- order(pp); r2 <- rr[o]; w2 <- ww[o]
    below <- cumsum(w2 * (!r2)) - w2 * (!r2)
    Wr <- sum(w2[r2]); Wn <- sum(w2[!r2])
    if (Wr > 0 && Wn > 0) sum((w2 * r2) * below) / (Wr * Wn) else NA_real_
  }, error = function(e) NA_real_)
  auc <- wauc(p, resp, dw)
  auc_note <- .t(
    sprintf("Weighted AUC %s. Moderate AUC is fine here; a very high AUC is a flag to check the weight tails and the missing-at-random assumption, not a goal.", d3(auc)),
    sprintf("AUC ponderada %s. Un AUC moderado est\u00e1 bien; un AUC muy alto es una se\u00f1al para revisar las colas de los pesos y el supuesto MAR, no un objetivo.", d3(auc)), lang)

  # in-sample refit (once, report time only) for variable importance and the
  # in-sample vs out-of-fold overfitting gap. Fully guarded; never breaks the report.
  imp <- NULL; pin <- NULL
  covd <- tryCatch(pr$covars[ok, , drop = FALSE], error = function(e) NULL)
  if (!is.null(pr$formula) && !is.null(covd) && ncol(covd)) {
    tr <- covd; tr$.y <- as.integer(resp); tr$.wts <- dw
    f2 <- stats::update(pr$formula, .y ~ .)
    tryCatch({
      if (eng == "logit") {
        m  <- suppressWarnings(stats::glm(f2, data = tr, family = stats::binomial(), weights = .wts))
        zz <- summary(m)$coefficients
        sel <- rownames(zz) != "(Intercept)"   # keep names: a single covariate would
        imp <- stats::setNames(abs(zz[sel, "z value"]), rownames(zz)[sel])  # drop them
        pin <- as.numeric(stats::predict(m, type = "response"))
      } else if (eng == "tree" && requireNamespace("rpart", quietly = TRUE)) {
        tr$.y <- factor(tr$.y, levels = c(0, 1))
        m <- rpart::rpart(f2, data = tr, method = "class", weights = .wts)
        imp <- m$variable.importance
        pin <- as.numeric(stats::predict(m, type = "prob")[, "1"])
      } else if (eng == "forest" && requireNamespace("ranger", quietly = TRUE)) {
        tr$.y <- factor(tr$.y, levels = c(0, 1))
        m <- ranger::ranger(f2, data = tr, probability = TRUE, case.weights = dw,
                            importance = "impurity", num.threads = 1L, seed = 1L)
        imp <- ranger::importance(m)
        pin <- as.numeric(stats::predict(m, data = tr)$predictions[, "1"])
      } else if (eng == "boost" && requireNamespace("xgboost", quietly = TRUE)) {
        rhs <- stats::reformulate(attr(stats::terms(pr$formula), "term.labels"))
        M   <- stats::model.matrix(rhs, data = tr)
        M   <- M[, colnames(M) != "(Intercept)", drop = FALSE]
        m   <- xgboost::xgb.train(params = list(objective = "binary:logistic",
                 max_depth = 4, eta = 0.1, nthread = 1L),
                 data = xgboost::xgb.DMatrix(M, label = tr$.y, weight = dw),
                 nrounds = 150L, verbose = 0)
        gi  <- xgboost::xgb.importance(model = m)
        imp <- stats::setNames(gi$Gain, gi$Feature)
        pin <- as.numeric(stats::predict(m, M))
      }
    }, error = function(e) NULL)
  }
  imp_html <- ""
  if (!is.null(imp) && length(imp) && !is.null(names(imp))) {
    imp <- imp[is.finite(imp) & imp > 0]
    if (length(imp) && !is.null(names(imp))) {
      imp <- sort(imp, decreasing = TRUE); top <- utils::head(imp, 5L)
      rel <- 100 * top / sum(imp)
      hd  <- paste0("<th scope='col'>", c(.t("Variable", "Variable", lang),
                              .t("Importance (%)", "Importancia (%)", lang)), "</th>", collapse = "")
      irows <- vapply(seq_along(top), function(i)
        sprintf("<tr><td>%s</td><td>%.1f%%</td></tr>", .html_escape(names(top)[i]), rel[i]), character(1))
      imp_html <- sprintf("<p class='muted'>%s</p><table class='stagetbl'><thead><tr>%s</tr></thead><tbody>%s</tbody></table>",
        .t(sprintf("Top predictors of response (%s importance, relative).", eng),
           sprintf("Principales predictores de la respuesta (importancia de %s, relativa).", eng), lang),
        hd, paste(irows, collapse = ""))
    }
  }
  stab_note <- ""
  if (!is.null(pr$crossfit) && !is.null(pin) && length(pin) == length(p)) {
    auc_in <- wauc(pin, resp, dw)
    stab_note <- sprintf("<p class='muted'>%s</p>", .t(
      sprintf("Out-of-fold AUC %s vs in-sample AUC %s (gap %s). A large gap means the learner overfits; all diagnostics above use the out-of-fold predictions.",
              d3(auc), d3(auc_in), d3(auc_in - auc)),
      sprintf("AUC out-of-fold %s vs in-sample %s (brecha %s). Una brecha grande indica sobreajuste; todos los diagn\u00f3sticos de arriba usan las predicciones out-of-fold.",
              d3(auc), d3(auc_in), d3(auc_in - auc)), lang))
  }

  ov <- tryCatch(.svg_overlap(p, resp, dw, lang,
                   title = .t("Common support of estimated response propensities",
                              "Soporte com&uacute;n de las propensiones de respuesta estimadas", lang)),
                 error = function(e) "")
  if (nzchar(ov)) ov <- sprintf("<div class='wdhist'>%s</div>", ov)
  sprintf("<div class='ri'><h4>%s</h4>%s%s%s<p class='note'>%s</p><p class='muted'>%s</p>%s<p class='muted'>%s</p>%s%s</div>",
          .t("Propensity model diagnostics", "Diagn\u00f3sticos del modelo de propensi\u00f3n", lang),
          spec_note, imp_html, cal_html, cal_note, auc_note, stab_note, floor_note, ov, bal_html)
}

# Unified nonresponse diagnostics for method = "calibration" (Sarndal-Lundstrom):
# the response model is implicit in the g-weights, so we expose the implicit
# response propensity phi-hat = 1/g, its distribution, the share with phi-hat > 1
# (g < 1, auxiliaries pushing the wrong way), and the information level
# (InfoS = full-sample totals, InfoU = population totals). Reads attr "calib_nr".
.calib_nr_diagnostics <- function(step, lang, object = NULL, y_vars = NULL) {
  cn <- attr(step$diagnostics, "calib_nr")
  if (is.null(cn) || is.null(cn$g) || !length(cn$g)) return("")
  g <- as.numeric(cn$g); dw <- as.numeric(cn$dw)
  ok <- is.finite(g) & is.finite(dw); g <- g[ok]; dw <- dw[ok]
  if (!length(g)) return("")
  gpos <- g > 0; n_bad <- sum(!gpos)          # non-positive g: no valid 1/g
  phi  <- 1 / g[gpos]
  d3  <- function(x) if (!is.finite(x)) "&ndash;" else formatC(x, format = "f", digits = 3)
  pc1 <- function(x) if (!is.finite(x)) "&ndash;" else sprintf("%.1f%%", x)
  wm  <- function(x, wt) { fin <- is.finite(x); sm <- sum(wt[fin])
    if (sm <= 0) NA_real_ else sum(wt[fin] * x[fin]) / sm }
  q <- tryCatch(as.numeric(stats::quantile(phi, c(0, .01, .5, .99, 1), na.rm = TRUE, names = FALSE)),
                error = function(e) rep(NA_real_, 5))
  info_lab <- if (identical(cn$info, "population"))
    .t("InfoU (population totals)", "InfoU (totales poblacionales)", lang)
  else .t("InfoS (full-sample totals)", "InfoS (totales de la muestra completa)", lang)
  pct_gt1 <- 100 * wm(as.numeric(g > 0 & g < 1), dw)
  pct_neg <- 100 * wm(as.numeric(g <= 0), dw)
  row <- function(k, v) sprintf("<tr><td class='k'>%s</td><td>%s</td></tr>", k, v)
  excl <- if (n_bad > 0) .t(sprintf(" (excluding %d unit(s) with non-positive g)", n_bad),
                            sprintf(" (excluye %d unidad(es) con g no positivo)", n_bad), lang) else ""
  dist <- paste0(row(paste0("min<span class='muted'>", excl, "</span>"), d3(q[1])),
                 row(.t("1st percentile", "percentil 1", lang), d3(q[2])),
                 row(.t("median", "mediana", lang), d3(q[3])),
                 row(.t("99th percentile", "percentil 99", lang), d3(q[4])), row("max", d3(q[5])))
  note <- .t(
    sprintf("Implicit response propensity &phi;&#770; = 1/g, recovered from the calibration g-weights. Information level: <strong>%s</strong>. Respondents with &phi;&#770; &gt; 1 (g &lt; 1): %s; non-positive g: %s. A large share with &phi;&#770; &gt; 1 signals the auxiliary vector pushes the wrong way for part of the sample (Sarndal and Lundstrom 2005).",
            info_lab, pc1(pct_gt1), pc1(pct_neg)),
    sprintf("Propensi\u00f3n de respuesta impl\u00edcita &phi;&#770; = 1/g, recuperada de los g-weights de la calibraci\u00f3n. Nivel de informaci\u00f3n: <strong>%s</strong>. Respondentes con &phi;&#770; &gt; 1 (g &lt; 1): %s; g no positivo: %s. Una fracci\u00f3n grande con &phi;&#770; &gt; 1 indica que el vector auxiliar empuja en la direcci\u00f3n equivocada para parte de la muestra (Sarndal y Lundstrom 2005).",
            info_lab, pc1(pct_gt1), pc1(pct_neg)), lang)
  # (4i/4ii) auxiliary-vector quality (Sarndal-Lundstrom): does each auxiliary
  # explain response, and (if y_vars given) the outcomes y?
  aux_html <- ""
  cov <- tryCatch(cn$aux, error = function(e) NULL)
  if (!is.null(cov) && ncol(cov) && !is.null(cn$resp)) {
    resp2 <- as.logical(cn$resp); dwa <- as.numeric(cn$dw_all)
    ok2 <- is.finite(dwa) & !is.na(resp2)
    cov <- cov[ok2, , drop = FALSE]; resp2 <- resp2[ok2]; dwa <- dwa[ok2]
    mm <- tryCatch(stats::model.matrix(~ ., data = cov)[, -1, drop = FALSE], error = function(e) NULL)
    yv <- NULL
    if (!is.null(object) && !is.null(y_vars) && !is.null(cn$elig_idx)) {
      yn0 <- intersect(y_vars, names(object$data))
      if (length(yn0)) yv <- tryCatch(object$data[cn$elig_idx, yn0, drop = FALSE][ok2, , drop = FALSE],
                                      error = function(e) NULL)
    }
    if (!is.null(mm) && ncol(mm) && length(unique(resp2)) >= 2L) {
      wm2 <- function(x, w) { f <- is.finite(x); s <- sum(w[f]); if (s <= 0) NA_real_ else sum(w[f] * x[f]) / s }
      wsd <- function(x, w) { m <- wm2(x, w); sqrt(wm2((x - m)^2, w)) }
      wcor <- function(x, y, w) { k <- is.finite(x) & is.finite(y) & is.finite(w) & w > 0
        x <- x[k]; y <- y[k]; w <- w[k]; W <- sum(w); if (W <= 0) return(NA_real_)
        mx <- sum(w * x) / W; my <- sum(w * y) / W
        sx <- sqrt(sum(w * (x - mx)^2) / W); sy <- sqrt(sum(w * (y - my)^2) / W)
        if (sx <= 0 || sy <= 0) NA_real_ else sum(w * (x - mx) * (y - my)) / W / (sx * sy) }
      sdif <- vapply(colnames(mm), function(nm) { x <- mm[, nm]; sp <- wsd(x, dwa)
        if (!is.finite(sp) || sp <= 0) NA_real_ else (wm2(x[resp2], dwa[resp2]) - wm2(x[!resp2], dwa[!resp2])) / sp },
        numeric(1))
      ynm  <- if (!is.null(yv)) names(yv) else character(0)
      ycor <- if (length(ynm)) lapply(ynm, function(yy) { y <- suppressWarnings(as.numeric(yv[[yy]]))
        vapply(colnames(mm), function(nm) wcor(mm[resp2, nm], y[resp2], dwa[resp2]), numeric(1)) }) else list()
      d3b <- function(x) if (!is.finite(x)) "&ndash;" else formatC(x, format = "f", digits = 3)
      hd <- paste0("<th scope='col'>", c(.t("Auxiliary", "Auxiliar", lang),
             .t("Explains response (std. diff.)", "Explica respuesta (dif. estand.)", lang),
             vapply(ynm, function(yy) sprintf(.t("Corr. with %s", "Corr. con %s", lang), .html_escape(yy)), character(1))),
             "</th>", collapse = "")
      arows <- vapply(seq_along(colnames(mm)), function(i) {
        yc <- if (length(ycor)) paste(vapply(ycor, function(v) sprintf("<td>%s</td>", d3b(v[i])), character(1)), collapse = "") else ""
        sprintf("<tr><td>%s</td><td>%s</td>%s</tr>", .html_escape(colnames(mm)[i]),
                if (is.finite(sdif[i])) sprintf("%+.3f", sdif[i]) else "&mdash;", yc) }, character(1))
      aux_html <- sprintf("<p class='muted'>%s</p><table class='stagetbl'><thead><tr>%s</tr></thead><tbody>%s</tbody></table>",
        .t("Auxiliary-vector quality (Sarndal-Lundstrom): a good auxiliary should explain response (large |std. diff.|) and, ideally, the outcomes y (large |corr.|). Auxiliaries near zero add little to the nonresponse correction.",
           "Calidad del vector auxiliar (Sarndal-Lundstrom): un buen auxiliar deber\u00eda explicar la respuesta (|dif. estand.| grande) y, idealmente, las y (|corr.| grande). Los auxiliares cerca de cero aportan poco a la correcci\u00f3n por no respuesta.", lang),
        hd, paste(arows, collapse = ""))
    }
  }
  sprintf("<div class='ri'><h4>%s</h4><p class='muted'>%s</p><table class='params'>%s</table>%s</div>",
          .t("Nonresponse calibration diagnostics", "Diagn\u00f3sticos de calibraci\u00f3n por no respuesta", lang),
          note, dist, aux_html)
}

# Calibration diagnostics for step_calibrate (method = "linear"/GREG): negative
# and at-bound weights, chi-square distance, conditioning of the system (with a
# ridge pointer), expected efficiency gain for optional y_vars, and a note when
# the margins overlap a prior nonresponse adjustment. Reads attr "calibrate".

# Human-readable condition number kappa(X'X): a plain-language state word (how
# collinear / near-redundant the auxiliaries are, i.e. how stable the weights
# are) plus the technical number in parentheses, formatted as m x 10^e instead of
# raw scientific notation. Warns (red) past the ill-conditioning threshold.
.kappa_fmt <- function(k) {
  if (!is.finite(k)) return("&ndash;")
  if (k < 1000) return(format(round(k)))
  e <- floor(log10(k)); m <- round(k / 10^e, 1)
  sprintf("%s&times;10<sup>%d</sup>", format(m), e)
}
.kappa_cell <- function(k, lang) {
  if (!is.finite(k)) return("<span class='cell-ok'>&ndash;</span>")
  st <- if (k > 1e10) list(cls = "cell-warn",
                           w = .t("ill-conditioned", "mal condicionada", lang))
        else if (k > 1e4) list(cls = "cell-ok", w = .t("moderate", "moderada", lang))
        else list(cls = "cell-ok", w = .t("stable", "estable", lang))
  sprintf("<span class='%s'>%s (&kappa; &asymp; %s)</span>", st$cls, st$w, .kappa_fmt(k))
}
.calibrate_diagnostics <- function(step, lang, object = NULL, y_vars = NULL) {
  dm <- attr(step$diagnostics, "calib_domains")
  cd <- attr(step$diagnostics, "calibrate")
  if (is.null(cd) || is.null(cd$g) || !length(cd$g)) {
    if (!is.null(dm) && nrow(dm))
      return(paste0(.calib_domain_table(dm, lang), .calib_overlap_note(step, object, lang)))
    return("")
  }
  g <- as.numeric(cd$g); d <- as.numeric(cd$d)
  ok <- is.finite(g) & is.finite(d); g <- g[ok]; d <- d[ok]
  if (!length(g)) return("")
  cov  <- tryCatch(cd$covars[ok, , drop = FALSE], error = function(e) NULL)
  aidx <- cd$active_idx[ok]
  d3 <- function(x) if (!is.finite(x)) "&ndash;" else formatC(x, format = "f", digits = 3)
  nf <- function(x) if (!is.finite(x)) "&ndash;" else format(round(x), big.mark = ",", trim = TRUE)
  w <- d * g; n_neg <- sum(w < 0); bnd <- cd$bounds
  row <- function(k, v) sprintf("<tr><td class='k'>%s</td><td>%s</td></tr>", k, v)
  tab <- paste0(
    row(.t("g range", "rango de g", lang), sprintf("[%s, %s]", d3(min(g)), d3(max(g)))),
    row(.t("negative weights", "pesos negativos", lang),
        sprintf("<span class='%s'>%s</span>", if (n_neg > 0) "cell-warn" else "cell-ok", nf(n_neg))),
    if (!is.null(bnd)) row(.t("at lower bound", "en cota inferior", lang), nf(sum(abs(g - bnd[1]) < 1e-6))) else "",
    if (!is.null(bnd)) row(.t("at upper bound", "en cota superior", lang), nf(sum(abs(g - bnd[2]) < 1e-6))) else "",
    row(.t("chi-square distance &Sigma;(w&minus;d)&sup2;/d", "distancia chi-cuadrado &Sigma;(w&minus;d)&sup2;/d", lang), d3(cd$chi2)),
    row(.t("Auxiliary collinearity", "Colinealidad de auxiliares", lang),
        if (isTRUE(cd$pooled)) .t("per domain (see table below)", "por dominio (ver tabla abajo)", lang)
        else .kappa_cell(cd$cond, lang)))
  notes <- character(0)
  if (n_neg > 0)
    notes <- c(notes, .t(
      sprintf("%s unit(s) received a negative weight (g &lt; 0), the classic linear-calibration accident. Use bounds = c(lo, hi) or calfun = \"raking\" to keep the weights positive.", nf(n_neg)),
      sprintf("%s unidad(es) recibieron peso negativo (g &lt; 0), el accidente cl\u00e1sico de la calibraci\u00f3n lineal. Us\u00e1 bounds = c(lo, hi) o calfun = \"raking\" para mantener pesos positivos.", nf(n_neg)), lang))
  if (is.finite(cd$cond) && cd$cond > 1e10)
    notes <- c(notes, .t(
      "The calibration system is ill-conditioned (near-collinear auxiliaries), so the factors can be unstable. Drop a redundant auxiliary, or set penalty = <lambda> for a ridge-stabilized calibration.",
      "El sistema de calibraci\u00f3n est\u00e1 mal condicionado (auxiliares casi colineales), as\u00ed que los factores pueden ser inestables. Quit\u00e1 un auxiliar redundante, o us\u00e1 penalty = <lambda> para una calibraci\u00f3n ridge estabilizada.", lang))
  eff <- ""
  if (!is.null(object) && !is.null(y_vars) && !is.null(cov) && ncol(cov)) {
    yn <- intersect(y_vars, names(object$data))
    Xm <- tryCatch(stats::model.matrix(cd$formula, data = cov), error = function(e) NULL)
    if (length(yn) && !is.null(Xm) && nrow(Xm) == length(aidx)) {
      wr2 <- function(y) {
        kk <- is.finite(y) & is.finite(d) & d > 0
        fit <- tryCatch(stats::lm.wfit(Xm[kk, , drop = FALSE], y[kk], d[kk]), error = function(e) NULL)
        if (is.null(fit)) return(NA_real_)
        my <- sum(d[kk] * y[kk]) / sum(d[kk]); sst <- sum(d[kk] * (y[kk] - my)^2)
        if (sst <= 0) return(NA_real_)
        1 - sum(d[kk] * (y[kk] - fit$fitted.values)^2) / sst
      }
      rows <- vapply(yn, function(v) {
        r2 <- wr2(suppressWarnings(as.numeric(object$data[aidx, v])))
        sprintf("<tr><td>%s</td><td>%s</td></tr>", .html_escape(v),
                if (is.finite(r2)) sprintf("%.1f%%", 100 * max(r2, 0)) else "&ndash;")
      }, character(1))
      eff <- sprintf("<p class='muted'>%s</p><table class='stagetbl'><thead><tr><th scope='col'>%s</th><th scope='col'>%s</th></tr></thead><tbody>%s</tbody></table>",
        .t("Expected efficiency gain: weighted R&sup2; of each outcome on the auxiliaries -- roughly the variance reduction the calibration buys for a total of that outcome.",
           "Ganancia de eficiencia esperada: R&sup2; ponderado de cada variable sobre los auxiliares -- aproximadamente la reducci\u00f3n de varianza que la calibraci\u00f3n logra para un total de esa variable.", lang),
        .t("Outcome", "Variable", lang), .t("Expected var. reduction", "Reducci\u00f3n de var. esperada", lang),
        paste(rows, collapse = ""))
    }
  }
  ovl <- .calib_overlap_note(step, object, lang)
  # (3) influence by constraint: share of the chi-square distance each margin
  # drives. Exact for unbounded linear (g - 1 = X lambda); shown only there.
  infl <- ""
  if (!isTRUE(cd$pooled) && identical(cd$calfun, "linear") && is.null(cd$bounds) && !is.null(cov) && ncol(cov)) {
    Xi <- tryCatch(stats::model.matrix(cd$formula, data = cov), error = function(e) NULL)
    if (!is.null(Xi) && nrow(Xi) == length(g)) {
      lam <- tryCatch(as.numeric(solve(crossprod(Xi), crossprod(Xi, g - 1))), error = function(e) NULL)
      if (!is.null(lam)) {
        contrib <- lam * as.numeric(crossprod(Xi, d * (g - 1)))   # per-column contribution to the distance
        tot <- sum(abs(contrib))
        if (is.finite(tot) && tot > 0) {
          sh <- 100 * abs(contrib) / tot; ord <- order(-sh); cn2 <- colnames(Xi)
          hd <- paste0("<th scope='col'>", c(.t("Constraint", "Restricci\u00f3n", lang),
                                 .t("Share of movement", "% del movimiento", lang)), "</th>", collapse = "")
          irows <- vapply(ord, function(i) sprintf("<tr><td>%s</td><td>%.0f%%</td></tr>",
                          .html_escape(cn2[i]), sh[i]), character(1))
          infl <- sprintf("<p class='muted'>%s</p><table class='stagetbl'><thead><tr>%s</tr></thead><tbody>%s</tbody></table>",
            .t("Influence by constraint: share of the calibration distance each margin drives (which totals move the weights most).",
               "Influencia por restricci\u00f3n: parte de la distancia de calibraci\u00f3n que aporta cada margen (qu\u00e9 totales mueven m\u00e1s los pesos).", lang),
            hd, paste(irows, collapse = ""))
        }
      }
    }
  }
  dom_tbl <- if (!is.null(dm) && nrow(dm)) .calib_domain_table(dm, lang) else ""
  notes_html <- if (length(notes)) paste0("<p class='note'>", notes, "</p>", collapse = "") else ""
  sprintf("<div class='ri'><h4>%s</h4><table class='params'>%s</table>%s%s%s%s</div>%s",
          .t("Calibration diagnostics", "Diagn\u00f3sticos de calibraci\u00f3n", lang),
          tab, notes_html, ovl, infl, eff, dom_tbl)
}

# Per-domain calibration summary (step_calibrate with by=): one row per domain
# with n, g range, negative / at-bound counts, conditioning and convergence.
# Troublesome domains (negatives, non-convergence, wide g) are listed first --
# the small domain with extreme g is where the partition strains.
.calib_domain_table <- function(dm, lang) {
  d3 <- function(x) if (!is.finite(x)) "&ndash;" else formatC(x, format = "f", digits = 3)
  nf <- function(x) if (!is.finite(x)) "&ndash;" else format(round(x), big.mark = ",", trim = TRUE)
  hd <- paste0("<th scope='col'>", c(.t("Domain", "Dominio", lang), "n", .t("g range", "rango de g", lang),
               .t("neg.", "neg.", lang), .t("at bounds", "en cotas", lang), .t("collinearity", "colinealidad", lang),
               .t("converged", "convergi\u00f3", lang)), "</th>", collapse = "")
  ord <- order(-dm$n_neg, dm$converged, -(dm$g_max - dm$g_min))
  rows <- vapply(ord, function(i) sprintf(
    "<tr><td>%s</td><td>%s</td><td>[%s, %s]</td><td><span class='%s'>%s</span></td><td>%s</td><td>%s</td><td>%s</td></tr>",
    .html_escape(as.character(dm$domain[i])), nf(dm$n[i]), d3(dm$g_min[i]), d3(dm$g_max[i]),
    if (dm$n_neg[i] > 0) "cell-warn" else "cell-ok", nf(dm$n_neg[i]), nf(dm$n_bound[i]),
    .kappa_cell(dm$cond[i], lang),
    if (isTRUE(dm$converged[i])) "&#10003;" else "<span class='cell-warn'>&#10007;</span>"),
    character(1))
  sprintf("<div class='ri'><h4>%s</h4><p class='muted'>%s</p><table class='stagetbl'><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>",
    .t("Calibration diagnostics by domain", "Diagn\u00f3sticos de calibraci\u00f3n por dominio", lang),
    .t("Each domain is calibrated independently; small domains with extreme g, weights at the bounds, negative weights or non-convergence are where the partition strains. Troublesome domains are listed first.",
       "Cada dominio se calibra por separado; los dominios chicos con g extremos, pesos en las cotas, pesos negativos o sin convergencia son donde la partici\u00f3n sufre. Los problem\u00e1ticos van primero.", lang),
    hd, paste(rows, collapse = ""))
}

# Note when the calibration margins overlap the variables of an earlier
# nonresponse adjustment: the calibration partially re-absorbs that adjustment.
.calib_overlap_note <- function(step, object, lang) {
  if (is.null(object) || is.null(step$formula)) return("")
  calvars <- all.vars(step$formula); nrv <- character(0)
  for (st in object$steps) if (inherits(st, "step_nonresponse"))
    nrv <- c(nrv, if (!is.null(st$formula)) all.vars(st$formula) else character(0),
             if (!is.null(st$by)) as.character(st$by) else character(0))
  shared <- intersect(calvars, unique(nrv))
  if (!length(shared)) return("")
  sprintf("<p class='note'>%s</p>", .t(
    sprintf("These margins cover variables also used by the earlier nonresponse adjustment (%s); the calibration partially re-absorbs that adjustment. Its variability is still captured if you estimate variance with the recipe-aware bootstrap/jackknife.", .html_escape(paste(shared, collapse = ", "))),
    sprintf("Estos m\u00e1rgenes cubren variables tambi\u00e9n usadas por el ajuste por no respuesta previo (%s); la calibraci\u00f3n re-absorbe parcialmente ese ajuste. Su variabilidad igual se captura si estim\u00e1s varianza con el bootstrap/jackknife recipe-aware.", .html_escape(paste(shared, collapse = ", "))), lang))
}

# Trimming diagnostics: what the trim bought (bias-variance trade-off), not just
# what it did. Reads attr(diagnostics, "trim_rec") captured by the three trim
# steps. Sections: (1) winsorization accounting; (2) bias cost with y_vars, or a
# concentration proxy without; (3) Potter MSE curve; (4) threshold sensitivity;
# (5) "calibration undid the trim" check; (6) variant specifics + % touched;
# (7) inert-trim alert. Each section is guarded, so a missing piece is skipped.
.trim_diagnostics <- function(step, lang, object = NULL, y_vars = NULL) {
  rec <- attr(step$diagnostics, "trim_rec")
  if (is.null(rec) || is.null(rec$wb) || !length(rec$wb)) return("")
  wb <- as.numeric(rec$wb); wa <- as.numeric(rec$wa)
  cap <- as.numeric(rec$cap); flo <- as.numeric(rec$floor)
  ok <- is.finite(wb) & is.finite(wa)
  wb <- wb[ok]; wa <- wa[ok]; cap <- cap[ok]; flo <- flo[ok]
  n <- length(wb); if (!n) return("")
  nf <- function(x) if (!is.finite(x)) "&ndash;" else format(round(x), big.mark = ",", trim = TRUE)
  sf <- function(x) if (!is.finite(x)) "&ndash;" else format(round(x, 1), big.mark = ",", trim = TRUE, nsmall = 1)
  pf <- function(x) if (!is.finite(x)) "&ndash;" else sprintf("%.1f%%", x)
  kish <- function(x) { x <- x[is.finite(x) & x > 0]; if (length(x) < 2L) NA_real_ else length(x) * sum(x^2) / sum(x)^2 }
  below <- is.finite(flo) & wb < flo
  above <- is.finite(cap) & wb > cap
  within <- !below & !above
  n_touch <- sum(below | above); pct <- 100 * n_touch / n
  tot_b <- sum(wb); tot_a <- sum(wa)
  preserved <- abs(tot_a - tot_b) <= 1e-6 * max(abs(tot_b), 1)

  # --- (1) winsorization accounting ---
  band <- function(sel) c(nn = sum(sel), sb = sum(wb[sel]), sa = sum(wa[sel]))
  b_lo <- band(below); b_in <- band(within); b_hi <- band(above)
  brow <- function(lab, b) sprintf("<tr><td class='k'>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>",
    lab, nf(b["nn"]), sf(b["sb"]), sf(b["sa"]), sf(b["sa"] - b["sb"]))
  acct <- sprintf(
    "<table class='params'><thead><tr><th scope='col'>%s</th><th scope='col'>n</th><th scope='col'>%s</th><th scope='col'>%s</th><th scope='col'>%s</th></tr></thead><tbody>%s%s%s</tbody></table>",
    .t("band", "banda", lang), .t("sum before", "suma antes", lang), .t("sum after", "suma despues", lang),
    .t("mass moved", "masa movida", lang),
    brow(.t("below floor", "bajo cota inf.", lang), b_lo),
    brow(.t("within band", "dentro", lang), b_in),
    brow(.t("above cap", "sobre cota sup.", lang), b_hi))
  disp <- if (identical(rec$redistribute, "calibration"))
    .t("The trimmed mass was re-absorbed by the bounded re-calibration, which preserves the calibration totals by construction.",
       "La masa recortada fue reabsorbida por la re-calibraci\u00f3n acotada, que preserva los totales de calibraci\u00f3n por construcci\u00f3n.", lang)
  else if (identical(rec$redistribute, "none") || !preserved)
    .t(sprintf("The trimmed mass was absorbed (weight total fell by %s, %s): the point estimates shift.", sf(tot_b - tot_a), pf(100 * (tot_b - tot_a) / tot_b)),
       sprintf("La masa recortada fue absorbida (el total de pesos baj\u00f3 %s, %s): los estimadores puntuales se corren.", sf(tot_b - tot_a), pf(100 * (tot_b - tot_a) / tot_b)), lang)
  else
    .t("The trimmed mass was redistributed to the units within band, so the weight total is preserved.",
       "La masa recortada se redistribuy\u00f3 a las unidades dentro de banda, as\u00ed que el total de pesos se preserva.", lang)
  sec1 <- sprintf("<p class='muted'>%s</p>%s<p class='note'>%s</p>",
    .t("What the trim did: units below the floor / within band / above the cap, with the weight sum before and after and the net mass moved.",
       "Qu\u00e9 hizo el recorte: unidades bajo la cota inferior / dentro / sobre la cota superior, con la suma de pesos antes y despu\u00e9s y la masa neta movida.", lang),
    acct, disp)

  # --- (2) bias cost with y, else concentration proxy ---
  bias <- ""
  yn <- if (!is.null(object) && !is.null(y_vars)) intersect(y_vars, names(object$data)) else character(0)
  if (length(yn)) {
    wm <- function(y, w) { sw <- sum(w); if (sw <= 0) NA_real_ else sum(w * y) / sw }
    rows <- vapply(yn, function(v) {
      y <- suppressWarnings(as.numeric(object$data[rec$idx[ok], v])); kk <- is.finite(y)
      yb <- wm(y[kk], wb[kk]); ya <- wm(y[kk], wa[kk]); sh <- ya - yb
      sw <- sum(wa[kk]); se <- if (sw <= 0) NA_real_ else sqrt(sum(wa[kk]^2 * (y[kk] - ya)^2)) / sw
      sprintf("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>", .html_escape(v),
        if (is.finite(sh) && is.finite(yb) && yb != 0) sprintf("%+.1f%%", 100 * sh / yb) else "&ndash;",
        if (is.finite(sh) && is.finite(se) && se > 0) sprintf("%+.2f", sh / se) else "&ndash;",
        if (is.finite(se)) sf(se) else "&ndash;")
    }, character(1))
    bias <- sprintf("<p class='muted'>%s</p><table class='stagetbl'><thead><tr><th scope='col'>%s</th><th scope='col'>%s</th><th scope='col'>%s</th><th scope='col'>SE</th></tr></thead><tbody>%s</tbody></table>",
      .t("Bias cost: how much the trim moved each estimated mean, as a percent and in standard errors of the (post-trim) estimate. Small multiples of an SE are cheap; large ones are the price paid for the variance reduction.",
         "Costo en sesgo: cu\u00e1nto movi\u00f3 el recorte cada media estimada, en porcentaje y en errores est\u00e1ndar del estimador (post-recorte). M\u00faltiplos chicos de un SE son baratos; grandes son el precio de la reducci\u00f3n de varianza.", lang),
      .t("outcome", "variable", lang), .t("shift", "corrimiento", lang), .t("shift (SE)", "corrim. (SE)", lang),
      paste(rows, collapse = ""))
  } else if (!is.null(rec$by)) {
    by <- rec$by[ok]; touched <- below | above; tb <- table(by[touched])
    if (length(tb)) {
      sh <- 100 * as.numeric(tb) / sum(as.numeric(tb)); ord <- order(-sh)
      rows <- vapply(ord, function(i) sprintf("<tr><td>%s</td><td>%s</td><td>%s</td></tr>",
        .html_escape(names(tb)[i]), nf(as.numeric(tb)[i]), pf(sh[i])), character(1))
      conc <- if (max(sh) > 60) sprintf("<p class='note'>%s</p>", .t(
        sprintf("The trimmed units concentrate in one domain (%s: %s): the induced bias is localized, not spread across the sample.", .html_escape(names(tb)[which.max(sh)]), pf(max(sh))),
        sprintf("Las unidades recortadas se concentran en un dominio (%s: %s): el sesgo inducido es localizado, no repartido en la muestra.", .html_escape(names(tb)[which.max(sh)]), pf(max(sh))), lang)) else ""
      bias <- sprintf("<p class='muted'>%s</p><table class='stagetbl'><thead><tr><th scope='col'>%s</th><th scope='col'>%s</th><th scope='col'>%%</th></tr></thead><tbody>%s</tbody></table>%s",
        .t("Where the trimmed units fall (pass y_vars for the estimator shift itself). Concentration in one cell means the bias is localized there.",
           "D\u00f3nde caen las unidades recortadas (pas\u00e1 y_vars para el corrimiento del estimador). Concentraci\u00f3n en una celda implica sesgo localizado.", lang),
        .t("domain", "dominio", lang), .t("trimmed", "recortadas", lang), paste(rows, collapse = ""), conc)
    }
  }

  # --- (3) Potter MSE curve ---
  pot <- attr(step$diagnostics, "potter"); potter_svg <- ""
  if (!is.null(pot) && !is.null(pot$grid) && length(pot$grid) > 2L)
    potter_svg <- sprintf(
      "<div class='pgrid'>%s<div class='pgrid-note muted'>%s</div></div>",
      .svg_potter(pot$grid, pot$bias2, pot$varc, pot$mse, pot$chosen, lang),
      .t("Potter MSE-optimal threshold: estimated bias&sup2; (rising as you trim harder), remaining variance (falling), and their sum; the dashed line is the chosen cutoff. The two terms are on different scales -- this is the raw Potter heuristic, shown as an approximation.",
         "Umbral MSE-\u00f3ptimo de Potter: bias&sup2; estimado (crece al recortar m\u00e1s), varianza remanente (cae) y su suma; la l\u00ednea punteada es el corte elegido. Los dos t\u00e9rminos est\u00e1n en escalas distintas -- es la heur\u00edstica cruda de Potter, mostrada como aproximaci\u00f3n.", lang))

  # --- (4) threshold sensitivity (clip-based; approximate for calibrated) ---
  sens <- ""
  if (rec$kind %in% c("weights", "ratio")) {
    yv <- if (length(yn)) suppressWarnings(as.numeric(object$data[rec$idx[ok], yn[1]])) else NULL
    srows <- vapply(c(0.5, 0.75, 1, 1.5, 2), function(k) {
      capk <- cap * k; wak <- pmin(wb, capk); exc <- sum(wb - wak); free <- wak < capk
      if (exc > 0 && any(free)) wak[free] <- wak[free] + exc * wak[free] / sum(wak[free])
      dk <- kish(wak)
      ysh <- if (!is.null(yv)) { a <- sum(wak * yv) / sum(wak); b <- sum(wb * yv) / sum(wb); 100 * (a - b) / b } else NA_real_
      sprintf("<tr><td>%s&times;</td><td>%s</td><td>%s</td><td>%s</td></tr>", format(k), nf(sum(wb > capk)),
        if (is.finite(dk)) formatC(dk, format = "f", digits = 3) else "&ndash;",
        if (is.finite(ysh)) sprintf("%+.1f%%", ysh) else "&ndash;")
    }, character(1))
    sens <- sprintf("<p class='muted'>%s</p><table class='stagetbl'><thead><tr><th scope='col'>%s</th><th scope='col'>%s</th><th scope='col'>deff</th><th scope='col'>%s</th></tr></thead><tbody>%s</tbody></table>",
      .t("Sensitivity: the cutoff at multiples of the chosen threshold -- units trimmed, resulting deff and (with y) the estimator shift. A flat block means the decision is robust. Clip-based approximation.",
         "Sensibilidad: el corte en m\u00faltiplos del umbral elegido -- unidades recortadas, deff resultante y (con y) el corrimiento del estimador. Un bloque plano indica decisi\u00f3n robusta. Aproximaci\u00f3n por recorte simple.", lang),
      .t("threshold", "umbral", lang), .t("trimmed", "recortadas", lang), .t("y shift", "corrim. y", lang),
      paste(srows, collapse = ""))
  }

  # --- (5) did a later calibration undo this trim? ---
  undone <- ""
  if (!is.null(object) && !is.null(object$steps) && !is.null(object$final_weight)) {
    si <- which(vapply(object$steps, function(x) identical(x, step), logical(1)))
    if (length(si) == 1L) {
      is_cal <- function(x) inherits(x, c("step_calibrate", "step_model_calibration")) ||
        (inherits(x, "step_nonresponse") && identical(x$method, "calibration"))
      if (any(vapply(object$steps[-seq_len(si)], is_cal, logical(1)))) {
        fw <- as.numeric(object$final_weight)[rec$idx[ok]]; tolc <- 1e-6 * pmax(abs(cap), 1)
        exceed <- sum(is.finite(cap) & is.finite(fw) & fw > cap + tolc)
        if (exceed > 0) undone <- sprintf("<p class='note'>%s</p>", .t(
          sprintf("%s final weight(s) exceed the cap applied here: a later calibration re-inflated them above this trim. Use step_trim_calibrated() (range-restricted, totals-preserving calibration) or trim after calibrating.", nf(exceed)),
          sprintf("%s peso(s) final(es) superan la cota aplicada aqu\u00ed: una calibraci\u00f3n posterior los reinfl\u00f3 por encima de este recorte. Us\u00e1 step_trim_calibrated() (calibraci\u00f3n de rango restringido que preserva los totales) o record\u00e1 despu\u00e9s de calibrar.", nf(exceed)), lang))
      }
    }
  }

  # --- (6) variant specifics ---
  variant <- ""
  if (identical(rec$kind, "calibrated") && !is.null(rec$by)) {
    by <- rec$by[ok]; f <- as.numeric(rec$f)[ok]
    dd <- do.call(rbind, lapply(unique(by), function(g) { sel <- by == g
      data.frame(dom = g, n = sum(sel), at_lo = sum(below[sel]), at_hi = sum(above[sel]),
                 fmin = min(f[sel]), fmax = max(f[sel]), stringsAsFactors = FALSE) }))
    ord <- order(-(dd$at_lo + dd$at_hi), -(dd$fmax - dd$fmin))
    rows <- vapply(ord, function(i) sprintf("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>[%s, %s]</td></tr>",
      .html_escape(as.character(dd$dom[i])), nf(dd$n[i]), nf(dd$at_lo[i]), nf(dd$at_hi[i]),
      formatC(dd$fmin[i], format = "f", digits = 3), formatC(dd$fmax[i], format = "f", digits = 3)), character(1))
    variant <- sprintf("<p class='muted'>%s</p><table class='stagetbl'><thead><tr><th scope='col'>%s</th><th scope='col'>n</th><th scope='col'>%s</th><th scope='col'>%s</th><th scope='col'>%s</th></tr></thead><tbody>%s</tbody></table>",
      .t("Per subgroup: units at the lower / upper bound and the range of the adjustment factor. Subgroups straining against their bounds are listed first.",
         "Por subgrupo: unidades en la cota inferior / superior y el rango del factor de ajuste. Los subgrupos que fuerzan sus cotas van primero.", lang),
      .t("subgroup", "subgrupo", lang), .t("at lower", "en inf.", lang), .t("at upper", "en sup.", lang),
      .t("f range", "rango de f", lang), paste(rows, collapse = ""))
  }
  if (identical(rec$kind, "weights") && identical(rec$redistribute, "uniform") &&
      is.finite(rec$unredist) && rec$unredist > 1e-9)
    variant <- paste0(variant, sprintf("<p class='note'>%s</p>", .t(
      sprintf("%s of weight could not be redistributed (no eligible untrimmed unit remained) and was absorbed; the total fell by that much.", sf(rec$unredist)),
      sprintf("%s de peso no pudo redistribuirse (no qued\u00f3 unidad sin recortar elegible) y fue absorbido; el total baj\u00f3 en esa cantidad.", sf(rec$unredist)), lang)))

  # % of the sample touched -- a trim reaching past the tails is a hidden recalibration
  touch_note <- if (pct > 10) sprintf("<p class='note'>%s</p>", .t(
      sprintf("This step touched %s of the sample -- that is a recalibration in disguise, not a tail trim. Reconsider the threshold.", pf(pct)),
      sprintf("Este paso toc\u00f3 %s de la muestra -- eso es una recalibraci\u00f3n encubierta, no un recorte de colas. Reconsider\u00e1 el umbral.", pf(pct)), lang))
    else if (pct > 5) sprintf("<p class='note'>%s</p>", .t(
      sprintf("This step touched %s of the sample; check it is trimming tails, not reshaping the bulk.", pf(pct)),
      sprintf("Este paso toc\u00f3 %s de la muestra; verific\u00e1 que recorta colas, no que reforma el grueso.", pf(pct)), lang))
    else ""

  # --- (7) inert trim ---
  ddeff <- rec$deff_before - rec$deff_after
  inert <- if (is.finite(ddeff) && abs(ddeff) < 0.005 && pct < 0.5) sprintf("<p class='note'>%s</p>", .t(
      "This trimming step had no material effect (deff essentially unchanged, under 0.5% of units touched); consider removing it to simplify the cascade.",
      "Este paso de recorte no tuvo efecto material (deff casi sin cambio, menos del 0.5% de unidades tocadas); consider\u00e1 quitarlo para simplificar la cascada.", lang)) else ""

  hd <- function(t) sprintf("<h5 class='trim-h'>%s</h5>", t)
  paste0("<div class='ri'><h4>", .t("Trimming diagnostics", "Diagn\u00f3sticos de recorte", lang), "</h4>",
    sec1,
    if (nzchar(bias))       paste0(hd(.t("Bias cost", "Costo en sesgo", lang)), bias) else "",
    if (nzchar(potter_svg)) paste0(hd(.t("Potter threshold", "Umbral de Potter", lang)), potter_svg) else "",
    if (nzchar(sens))       paste0(hd(.t("Sensitivity", "Sensibilidad", lang)), sens) else "",
    if (nzchar(variant))    paste0(hd(.t("Variant details", "Detalle por variante", lang)), variant) else "",
    touch_note, undone, inert, "</div>")
}
