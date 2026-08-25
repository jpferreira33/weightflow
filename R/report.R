# report_weighting(): assembles the self-contained HTML report from the pieces below and the card/helper modules.

#' Self-contained HTML quality report for a weighting recipe
#'
#' Writes a single, self-contained HTML file documenting how a prepped recipe
#' turned the design base weights into the final weights: the cascade, the
#' parameters requested at each step, the per-stage weight summary, the
#' step-specific diagnostics (calibration, nonresponse, trimming), the fieldwork
#' outcome rates and an audit trail. It is the deliverable to attach to a
#' methodological report or a weighting annex: everything is inline, so the file
#' opens offline and can be archived or emailed as one artifact.
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
#' @param y_vars optional character vector of survey outcome variables. When a
#'   nonresponse-by-calibration step is present, the auxiliary-quality table adds,
#'   for each auxiliary, its weighted correlation with each `y` among respondents
#'   (Sarndal-Lundstrom criterion (ii): a good auxiliary also explains the `y`).
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

report_weighting <- function(object, file = NULL, open = TRUE, plots = TRUE,
                             narrative = TRUE, lang = c("en", "es"),
                             metadata = NULL, replicates = NULL, domains = NULL,
                             y_vars = NULL) {
  if (!inherits(object, "prepped_weighting_spec"))
    stop("Call prep() first; report_weighting() needs a prepped recipe.")
  lang <- match.arg(lang)
  # Accept a named vector for `metadata` too: coerce to a list up front so the
  # downstream `metadata$survey` access and the metadata card both work.
  if (!is.null(metadata) && !is.list(metadata)) metadata <- as.list(metadata)
  if (is.null(file)) file <- tempfile("weightflow_report_", fileext = ".html")

  h    <- object$history
  fin  <- object$final_weight
  de_f <- design_effect(fin)
  de_b <- design_effect(h[["base"]])

  # Headline metrics
  cards <- paste0(
    .metric(.t("Cases", "Casos", lang), format(length(fin), big.mark = ",")),
    .metric(.t("Active (final)", "Activas (final)", lang), format(de_f$n, big.mark = ",")),
    .metric(.t("Sum of weights", "Suma de pesos", lang), format(round(sum(fin)), big.mark = ",", scientific = FALSE)),
    .metric(.t("Final deff_K", "deff_K final", lang),
            if (is.finite(de_f$deff)) sprintf("%.3f", de_f$deff) else "&mdash;"),
    .metric(.t("Effective n", "n efectivo", lang), format(round(de_f$n_eff), big.mark = ",", scientific = FALSE)))

  # Stage summary table
  stab <- data.frame(
    stage    = names(h),
    n_active = vapply(h, function(w) sum(.wf_active(w)), integer(1)),
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
    hd  <- paste0("<th scope='col'>", hdr, "</th>", collapse = "")
    num <- function(x) format(x, big.mark = ",", scientific = FALSE)
    d3  <- function(x) formatC(x, format = "f", digits = 3)
    dcell <- function(v) {
      if (!is.finite(v)) return("<span class='muted'>&mdash;</span>")   # N-20: deff overflow / NaN
      sprintf("<span class='%s'>%s%s</span>",                            # amber at deff >= 1.4
              if (v >= 1.4) "cell-warn" else "cell-ok", if (v >= 1.4) "&#9888; " else "", d3(v))
    }
    rows <- vapply(seq_len(nrow(stab)), function(i) sprintf(
      "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>",
      slab[i], num(stab$n_active[i]), num(stab$sum_wts[i]),
      d3(stab$cv[i]), dcell(stab$deff[i]), num(stab$n_eff[i])), character(1))
    sprintf("<table class='stagetbl'><caption class='sr-only'>%s</caption><thead><tr>%s</tr></thead><tbody>%s</tbody></table>",
            .t("Per-stage weight summary: active units, sum of weights, CV, design effect and effective sample size at each stage.",
               "Resumen de pesos por etapa: unidades activas, suma de pesos, CV, efecto de dise&ntilde;o y tama&ntilde;o de muestra efectivo en cada etapa.", lang),
            hd, paste(rows, collapse = ""))
  })
  imp_html <- local({
    if (nrow(stab) < 2L) "" else {
      dd <- diff(stab$deff); dc <- diff(stab$cv)
      # N-20: deff may overflow to Inf (base weight 1e300) or be NaN (all base
      # weights 0) with a successful prep(); keep the impact table honest and
      # non-fatal instead of erroring on "missing value where TRUE/FALSE needed".
      tot <- sum(abs(dd), na.rm = TRUE)
      share <- if (tot > 0) 100 * abs(dd) / tot else rep(0, length(dd))
      share[!is.finite(share)] <- 0
      lab  <- vapply(seq_along(object$steps),
                     function(j) sprintf("%d &middot; %s", j, .step_short(object$steps[[j]], lang)), "")
      imax <- if (any(dd > 0, na.rm = TRUE)) which.max(dd) else 0L
      eff  <- function(j) {
        x <- dd[j]
        if (!is.finite(x)) .t("not available", "no disponible", lang)
        else if (round(x, 3) == 0) .t("negligible impact", "impacto insignificante", lang)
        else if (x < 0) {
          if (grepl("trim", lab[j], ignore.case = TRUE))
            .t("recovers efficiency (trimming)", "recupera eficiencia (recorte)", lang)
          else .t("recovers efficiency", "recupera eficiencia", lang)
        } else if (j == imax)
          .t("largest increase in variability", "mayor aumento de variabilidad", lang)
        else .t("increases variability", "aumenta la variabilidad", lang)
      }
      cell <- function(v) {
        if (!is.finite(v)) return("<span class='muted'>&mdash;</span>")
        sprintf("<span class='%s'>%s%+.3f</span>",
                if (v > 0.001) "cell-warn" else if (v < -0.001) "cell-ok" else "",
                if (v > 0.001) "&#9888; " else "", v)
      }
      pm3  <- function(v) if (is.finite(v)) sprintf("%+.3f", v) else "&mdash;"
      hd <- paste0("<th scope='col'>", c(.t("Step", "Paso", lang), "&Delta; deff_K", "&Delta; CV",
                             .t("Contribution to deff_K change", "Contribuci\u00f3n al cambio del deff_K", lang),
                             .t("Effect", "Efecto", lang)), "</th>", collapse = "")
      rows <- vapply(seq_along(dd), function(j) sprintf(
        "<tr><td>%s</td><td>%s</td><td>%s</td><td>%.0f%%</td><td>%s</td></tr>",
        lab[j], cell(dd[j]), pm3(dc[j]), share[j], eff(j)),
        character(1))
      nr <- nrow(stab)
      t_deff <- stab$deff[nr] - stab$deff[1]; t_cv <- stab$cv[nr] - stab$cv[1]
      t_neff <- if (isTRUE(stab$n_eff[1] > 0) && is.finite(stab$n_eff[nr]))
                  100 * (stab$n_eff[nr] - stab$n_eff[1]) / stab$n_eff[1] else NA_real_
      total_row <- sprintf(
        "<tr style='font-weight:600;border-top:2px solid var(--line)'><td>%s</td><td>%s</td><td>%s</td><td></td><td>%s</td></tr>",
        .t("Total (base &rarr; final)", "Total (base &rarr; final)", lang),
        cell(t_deff), pm3(t_cv),
        if (is.na(t_neff)) "" else .t(sprintf("effective sample %+.0f%%", t_neff),
                                      sprintf("muestra efectiva %+.0f%%", t_neff), lang))
      sprintf("<p class='muted'>%s</p><table class='stagetbl'><caption class='sr-only'>%s</caption><thead><tr>%s</tr></thead><tbody>%s%s</tbody></table>",
              .t("Impact of each weighting step (change vs the previous stage)",
                 "Impacto de cada paso de ponderaci\u00f3n (cambio respecto de la etapa anterior)", lang),
              .t("Impact of each weighting step on the design effect, CV and effective sample size.",
                 "Impacto de cada paso de ponderaci&oacute;n sobre el efecto de dise&ntilde;o, el CV y el tama&ntilde;o de muestra efectivo.", lang),
              hd, paste(rows, collapse = ""), total_row)
    }
  })
  stab_html <- paste0(stab_html, imp_html,
    sprintf("<p class='muted'>%s</p>",
            .t("Kish design effect by stage (0 = base, 1..k as in the table above); &#9650; largest increase, &#9660; recovered efficiency", "Efecto de dise\u00f1o de Kish por etapa (base y 1..k seg\u00fan la tabla de arriba); &#9650; mayor aumento, &#9660; eficiencia recuperada", lang)),
    .svg_evolution(stab$stage, stab$deff, lang = lang),
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
    conv_html <- if (identical(cv, FALSE)) {
      itn <- if (!is.null(it)) sprintf(.t(" (after %d iterations)", " (tras %d iteraciones)", lang), it) else ""
      sprintf("<div class='alert'><strong>%s</strong><p>%s%s. %s</p></div>",
        .t("Did not converge", "No convergi\u00f3", lang),
        .t("The calibration stopped without satisfying all margins",
           "La calibraci\u00f3n se detuvo sin satisfacer todos los m\u00e1rgenes", lang), itn,
        .t("The returned weights do not fully reproduce the requested totals. Increase <code>maxit</code> or check that the margins are mutually consistent.",
           "Los pesos devueltos no reproducen del todo los totales pedidos. Aument\u00e1 <code>maxit</code> o verific\u00e1 que los m\u00e1rgenes sean mutuamente consistentes.", lang))
    } else ""
    iter_html <- if (!is.null(it)) {
      if (identical(cv, FALSE))
        sprintf(.t("<p class='muted'>stopped after %d iterations (did not converge)</p>",
                   "<p class='muted'>detenido tras %d iteraciones (no convergi\u00f3)</p>", lang), it)
      else if (identical(cv, TRUE))
        sprintf(.t("<p class='muted'>converged in %d iterations</p>",
                   "<p class='muted'>convergi\u00f3 en %d iteraciones</p>", lang), it)
      else                          # convergence not tracked: state the count only, no claim
        sprintf(.t("<p class='muted'>%d iterations</p>",
                   "<p class='muted'>%d iteraciones</p>", lang), it)
    } else ""
    extra <- paste0(
      iter_html,
      if (!is.null(note)) sprintf("<p class='note'>%s</p>", .html_escape(note)) else "",
      conv_html, alerts_html)
    de1 <- design_effect(h[[i]]); de2 <- design_effect(h[[i + 1L]])
    viz <- if (plots) .step_visual(s, h[[i]], h[[i + 1L]], lang) else ""
    ri_step <- if (i == nr_last && !is.null(ri)) .ri_block(ri, lang) else ""
    prop_diag <- .propensity_diagnostics(s, lang)   # full-width, below the 2 columns
    cnr_diag  <- .calib_nr_diagnostics(s, lang, object, y_vars)  # nonresponse-by-calibration
    cal_diag  <- .calibrate_diagnostics(s, lang, object, y_vars) # step_calibrate diagnostics
    trim_diag <- .trim_diagnostics(s, lang, object, y_vars)      # trimming bias-variance trade-off
    narr <- if (isTRUE(narrative))
      .step_narrative(s, de1, de2, ri, i == nr_last, lang) else ""
    steps_html <- paste0(steps_html, sprintf(
      "<div class='step' id='step-%d'><div class='step-h'><span class='num'>%d</span>%s</div>%s
       <div class='cols'><div><h4>%s</h4><table class='params'>%s</table></div>
       <div><h4>%s</h4>%s%s
       <p class='muted'>deff_K %.3f &rarr; %.3f &nbsp;|&nbsp; n_eff %s &rarr; %s</p>%s</div></div>%s</div>",
      i, i, .step_short(s, lang), narr,
      .t("Requested", "Solicitado", lang), paste(prows, collapse = ""),
      .t("Diagnostics", "Diagn\u00f3sticos", lang),
      .df_to_html(.with_reldiff(s$diagnostics, lang)), extra,
      de1$deff, de2$deff, format(round(de1$n_eff), big.mark = ","),
      format(round(de2$n_eff), big.mark = ","), ri_step,
      paste0(prop_diag, cnr_diag, cal_diag, trim_diag, if (nzchar(viz)) paste0(sprintf("<h4 class='viz-h'>%s</h4>", .t("Visual", "Visual", lang)), viz) else "")))
  }

  diagram <- .pipeline_diagram(object, lang)
  allvars <- unique(c(object$base_weights, unlist(lapply(object$steps, .step_vars))))
  vars_chips <- .chips(allvars)

  # Provenance line for auditability: when, and with which versions, it was made.
  prov <- sprintf(paste0(.t("Generated", "Generado", lang), " %s &middot; weightflow %s &middot; R %s.%s"),
    format(Sys.time(), "%Y-%m-%d %H:%M"),
    as.character(utils::packageVersion("weightflow")),
    R.version$major, R.version$minor)

  drift <- .calibration_drift(object, lang)
  wdist <- .weight_distribution_html(fin, lang, plots)
  exec  <- if (isTRUE(narrative)) .exec_summary(object, ri, de_f, lang, metadata$survey) else ""
  exec  <- paste0(exec, .status_checklist(object, de_f, object$final_weight, replicates, lang))
  exec  <- paste0(exec, .attention_panel(object, lang))
  imsg  <- if (!is.finite(de_f$deff))
             .t("the design effect could not be computed \u2014 check the weights.",
                "no se pudo calcular el efecto de dise\u00f1o \u2014 revis\u00e1 los pesos.", lang)
           else if (de_f$deff < 1.2)
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
  repl_html <- .replication_card(replicates, lang, object)
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
    # \u00a71.1: the calibration can converge exactly and then a later rounding/trimming
    # step move the totals off target. Read the real post-calibration drift so the
    # closing line cannot claim "constraints preserved" while the drift table shows
    # a 1.2% deviation. A drift above 1% is itself a point of attention.
    md <- attr(drift, "maxdev")
    drift_att <- !is.null(md) && is.finite(md) && md >= 1
    nis <- ncv + nal + drift_att
    lead <- if (nis == 0L)
      .t("Recipe completed successfully.", "Receta completada con \u00e9xito.", lang)
    else .t(sprintf("Recipe completed with %d point%s of attention.", nis, if (nis == 1L) "" else "s"),
            sprintf("Receta completada con %d punto%s de atenci\u00f3n.", nis, if (nis == 1L) "" else "s"), lang)
    it <- c(sprintf("%d %s", ns, if (ns == 1L) .t("weighting step", "paso de ponderaci\u00f3n", lang)
                                 else .t("weighting steps", "pasos de ponderaci\u00f3n", lang)))
    # Claim "calibration constraints preserved" when the recipe has a
    # constraint-imposing step. Post-stratification meets its targets exactly by
    # construction and emits no `converged` attribute, so it was being excluded;
    # include it (and the other calibration steps) by class as well.
    has_constraints <- any(vapply(object$steps, function(st)
      inherits(st, c("step_calibrate", "step_model_calibration", "step_trim_calibrated")) ||
      !is.null(attr(st$diagnostics, "converged")), logical(1)))
    if (has_constraints && ncv == 0L)
      it <- c(it, if (is.null(md) || !is.finite(md) || md < 0.05)
                    .t("calibration constraints preserved",
                       "restricciones de calibraci\u00f3n preservadas", lang)
                  else .t(sprintf("calibration totals within %.2f%% of target after rounding/trimming", md),
                          sprintf("totales de calibraci\u00f3n dentro de %.2f%% del objetivo tras redondeo/recorte", md), lang))
    if (!is.null(replicates) && inherits(replicates, c("weightflow_boot", "weightflow_jack"))) {
      rmat  <- replicates$replicates
      nrp   <- if (!is.null(rmat)) ncol(rmat) else replicates$R
      nfl   <- if (!is.null(rmat)) sum(apply(rmat, 2, anyNA)) else 0L
      it <- c(it, if (isTRUE(nrp > 0L) && nfl >= nrp)
                    .t("replicate weights FAILED (all replicates NA)",
                       "pesos r\u00e9plica FALLARON (todas las r\u00e9plicas NA)", lang)
                  else if (nfl > 0L)
                    .t(sprintf("replicate weights created (%d of %d replicates failed)", nfl, nrp),
                       sprintf("pesos r\u00e9plica creados (%d de %d r\u00e9plicas fallaron)", nfl, nrp), lang)
                  else .t("replicate weights created", "pesos r\u00e9plica creados", lang))
    }
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
    sprintf("<!DOCTYPE html><html lang='%s'><head><meta charset='utf-8'>\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n", lang),
    sprintf("<title>%s</title>", .t("weightflow report", "reporte weightflow", lang)), .report_css(), "</head><body>\n",
    sprintf("<h1>weightflow &mdash; %s</h1>\n", .t("weighting recipe", "receta de ponderaci\u00f3n", lang)),
    sprintf("<p class='muted'>%s: <code>%s</code> &nbsp;|&nbsp; %d %s</p>\n",
            .t("Base weights", "Pesos base", lang),
            if (isTRUE(object$nonprob)) .t("1 (non-probability sample)",
                                           "1 (muestra no probabil&iacute;stica)", lang)
            else .html_escape(object$base_weights),
            length(object$steps),
            if (length(object$steps) == 1L) .t("step", "paso", lang)
            else .t("steps", "pasos", lang)),
    "<p class='prov'>", prov, "</p>\n",
    if (isTRUE(object$nonprob))
      sprintf("<div class='alert'><strong>%s</strong> %s</div>\n",
        .t("Non-probability sample.", "Muestra no probabil&iacute;stica.", lang),
        .t("This sample has no design weights; inference relies on adjustment against a probability reference (pseudo-weights and/or model calibration) and on the assumption that participation is ignorable given the covariates used. Estimates and their variances are model-dependent and should be read with that caveat.",
           "Esta muestra no tiene pesos de dise&ntilde;o; la inferencia se apoya en el ajuste contra una referencia probabil&iacute;stica (pseudo-pesos y/o calibraci&oacute;n por modelo) y en el supuesto de que la participaci&oacute;n es ignorable dadas las covariables usadas. Las estimaciones y sus varianzas dependen del modelo y deben leerse con esa advertencia.", lang))
    else "",
    "<div class='toolbar noprint'><button type='button' id='wf-pdf' class='wfbtn'>",
      .t("Download PDF", "Descargar PDF", lang), "</button></div>\n",
    "<nav aria-label=\"Contents\">", toc_html, "</nav>\n",
    "<main>\n",
    meta_html, "\n",
    "<div class='cards'>", cards, "</div>\n",
    racct, "\n",
    exec, "\n",
    repro_html, "\n",
    sprintf("<h2 id='pipeline'>%s</h2>", .t("Pipeline", "Flujo de pasos", lang)), diagram, "\n",
    sprintf("<p class='muted'>%s</p>", .t("Variables used:", "Variables usadas:", lang)), vars_chips, "\n",
    sprintf("<h2 id='stages'>%s</h2>", .t("Per-stage summary", "Resumen por etapa", lang)), stab_html, "\n",
    repl_html, "\n",
    domain_html, "\n",
    sprintf("<h2 id='weights'>%s</h2>", .t("Weight distribution (final)", "Distribuci\u00f3n de pesos (final)", lang)), wdist, "\n",
    sprintf("<h2 id='steps'>%s</h2>\n", .t("Steps", "Pasos", lang)),
    "<details class='steps' open><summary>",
      .t("Show / hide per-step detail", "Mostrar / ocultar detalle por paso", lang),
      "</summary>\n",
    steps_html, "\n</details>\n",
    drift, "\n",
    done_txt, "\n",
    "</main>\n",
    "<footer><p class='foot'>", foot_txt, "</p></footer>\n",
    "<script>", .report_js(), "</script>\n",
    "</body></html>")

  # Write UTF-8 bytes explicitly. Plain writeLines() re-encodes to the native
  # charset, which mangles accents/symbols in a non-UTF-8 locale (e.g. Windows
  # latin1) even for lang="en" reports (dates, names in the metadata).
  outdir <- dirname(file)
  if (!dir.exists(outdir))
    stop(sprintf(paste0("Cannot write the report: directory '%s' does not exist. ",
                        "Create it first or choose another path."), outdir),
         call. = FALSE)
  con <- file(file, open = "wb")
  on.exit(close(con), add = TRUE)
  writeLines(enc2utf8(html), con, useBytes = TRUE)
  if (open) try(utils::browseURL(file), silent = TRUE)
  invisible(file)
}
