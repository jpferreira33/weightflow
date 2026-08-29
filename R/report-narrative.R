# report narrative: bilingual GSBPM/ESQRS-style prose (executive summary + per-step).

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
    return(.t("exclusion of ineligible units", "eliminaci\u00f3n de unidades no elegibles", lang))
  if (inherits(step, "step_select_within"))
    return(.t("within-cluster selection adjustment", "ajuste por selecci\u00f3n dentro del conglomerado", lang))
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
    # \u00a71.3: two nonresponse steps (e.g. one at household level via `cluster`, one
    # at person level) otherwise get identical labels. Append the level so they
    # are distinct in the pipeline and tables. Avoid the word "by" for the cluster
    # (that is the adjustment-cell argument), say "at the <cluster> level".
    # Escape user-controlled identifiers (cluster = a column name, engine) before
    # they enter the HTML: .step_short() feeds the exec summary, pipeline diagram,
    # per-stage table, anchors and titles, so an unescaped column name is an XSS
    # vector in a report built from third-party data. Everything else is escaped.
    eng <- .html_escape(step$engine)
    # Humanise the cluster into a level name for the prose; the raw column name
    # (e.g. household_id) stays in the step details, not in the summary label.
    # household_id -> household, so two nonresponse steps (household vs person)
    # still read as distinct.
    pretty <- if (!is.null(step$cluster))
      .html_escape(gsub("_", " ", sub("_id$", "", step$cluster))) else ""
    lvl_en <- if (!is.null(step$cluster)) sprintf("%s-level ", pretty) else ""
    lvl_es <- if (!is.null(step$cluster)) sprintf(" a nivel %s", pretty) else ""
    eng_en <- switch(step$engine %||% "logit",
      logit = "logistic model", tree = "regression tree",
      forest = "random forest", boost = "gradient boosting", eng)
    eng_es <- switch(step$engine %||% "logit",
      logit = "modelo log&iacute;stico", tree = "&aacute;rbol de regresi&oacute;n",
      forest = "random forest", boost = "gradient boosting", eng)
    if (identical(m, "propensity"))
      return(.t(sprintf("%sresponse-propensity adjustment (%s)", lvl_en, eng_en),
                sprintf("ajuste por propensi&oacute;n de respuesta (%s)%s", eng_es, lvl_es), lang))
    return(.t(sprintf("%snonresponse adjustment using weighting classes", lvl_en),
              sprintf("ajuste por no respuesta con clases de ponderaci&oacute;n%s", lvl_es), lang))
  }
  if (inherits(step, "step_calibrate")) {
    vp <- .vars_phrase(.aux_vars(step), lang); greg <- identical(step$method, "linear")
    return(if (nzchar(vp))
      .t(sprintf("%scalibration to %s totals", if (greg) "GREG " else "", vp),
         sprintf("calibraci\u00f3n %sa los totales de %s", if (greg) "GREG " else "", vp), lang)
      else .t("calibration to population totals", "calibraci\u00f3n a totales poblacionales", lang))
  }
  if (inherits(step, "step_model_calibration"))
    return(.t("model-assisted calibration", "calibraci\u00f3n asistida por modelo", lang))
  if (inherits(step, "step_trim_calibrated"))
    return(.t("calibration-preserving weight trimming", "recorte de pesos que preserva la calibraci\u00f3n", lang))
  if (inherits(step, "step_trim_weights"))
    return(.t("weight trimming", "recorte de pesos", lang))
  if (inherits(step, "step_round"))  return(.t("weight rounding", "redondeo de pesos", lang))
  if (inherits(step, "step_rescale")) return(.t("rescaling", "reescalado", lang))
  if (inherits(step, "step_assert")) return(.t("quality checkpoint", "punto de control", lang))
  if (inherits(step, "step_nr_sensitivity"))
    return(.t("nonresponse sensitivity", "sensibilidad a la no respuesta", lang))
  .html_escape(step$label)
}

# When a calibration step's targets come from reference_sample() the control
# totals are estimates, not census figures. State that, and how their sampling
# variance is handled: propagated through paired replicates, or treated as fixed.
.ref_totals_phrase <- function(step, lang) {
  pop <- step$population
  if (is.null(pop) || !inherits(pop, "wf_reference_sample")) return("")
  n_ref   <- length(attr(pop, "wf_ref_weights"))
  has_rep <- !is.null(attr(pop, "wf_ref_replicates"))
  vclause <- if (has_rep)
    .t("Because the totals are estimates, their sampling variability can be propagated through the recipe-aware bootstrap, where each replicate re-estimates the totals from the paired reference replicate (Opsomer and Erciulescu 2021); the delete-a-PSU jackknife has no such pairing and treats the totals as fixed.",
       "Como los totales son estimaciones, su variabilidad muestral puede propagarse por el bootstrap recipe-aware, donde cada r&eacute;plica reestima los totales desde la r&eacute;plica pareada de la referencia (Opsomer y Erciulescu 2021); el jackknife borra-una-UPM no tiene ese pareo y trata los totales como fijos.", lang)
  else
    .t("The totals are estimates but were treated as fixed (no reference replicate weights supplied), so the reported variance omits their sampling error and may be understated; pass replicates to reference_sample() to propagate it.",
       "Los totales son estimaciones pero se trataron como fijos (sin pesos r&eacute;plica de la referencia), as&iacute; que la varianza reportada omite su error muestral y puede quedar subestimada; pase r&eacute;plicas a reference_sample() para propagarlo.", lang)
  .t(sprintf(" The control totals are not census figures: they were estimated from a reference survey (n = %s). %s",
             format(n_ref, big.mark = ",", scientific = FALSE), vclause),
     sprintf(" Los totales de control no son de censo: se estimaron a partir de una encuesta de referencia (n = %s). %s",
             format(n_ref, big.mark = ",", scientific = FALSE), vclause), lang)
}

# The per-step methodological paragraph.
.step_narrative <- function(step, de1, de2, ri, is_nr_last, lang) {
  vlab <- .narr_vars(step, lang)
  txt  <- ""

  if (inherits(step, "step_unknown_eligibility")) {
    lvl <- if (!is.null(step$cluster)) .t("at the household level", "a nivel de hogar", lang)
           else .t("at the unit level", "a nivel de unidad", lang)
    byv <- if (!is.null(step$by))
             sprintf(.t(" by <strong>%s</strong>", " por <strong>%s</strong>", lang),
                     .html_escape(paste(step$by, collapse = ", "))) else ""
    txt <- .t(
      sprintf("Cases of unknown eligibility had their weight redistributed to the resolved (known-eligibility) cases%s %s, so the unresolved cases do not bias the eligible totals.", byv, lvl),
      sprintf("A los casos de elegibilidad desconocida se les redistribuy\u00f3 el peso entre los casos resueltos (de elegibilidad conocida)%s %s, para que los no resueltos no sesguen los totales de elegibles.", byv, lvl),
      lang)
  } else if (inherits(step, "step_drop_ineligible")) {
    txt <- .t("Units identified as out of scope (ineligible) were removed from the cascade, setting their weight to zero so they do not contribute to any later estimate.",
              "Las unidades identificadas como fuera del universo (no elegibles) se eliminaron de la cascada, poniendo su peso en cero para que no contribuyan a ninguna estimaci\u00f3n posterior.", lang)
  } else if (inherits(step, "step_select_within")) {
    txt <- .t("A within-cluster selection adjustment was applied: the selected unit's weight was multiplied by the inverse of its within-cluster selection probability, so it represents all the eligible units of the cluster (e.g. the household).",
              "Se aplic\u00f3 un ajuste por selecci\u00f3n dentro del conglomerado: el peso de la unidad seleccionada se multiplic\u00f3 por el inverso de su probabilidad de selecci\u00f3n intra-conglomerado, de modo que representa a todas las unidades elegibles del conglomerado (p. ej. el hogar).", lang)
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
      lang), " ", .deff_phrase(de1, de2, lang), .ref_totals_phrase(step, lang))
  } else if (inherits(step, "step_model_calibration")) {
    txt <- paste0(.t(
      "Model-assisted (Wu-Sitter) calibration was applied: predictions of the outcome model were used as auxiliaries and calibrated to their population totals, borrowing strength from the predictive model.",
      "Se aplic\u00f3 calibraci\u00f3n asistida por modelo (Wu-Sitter): las predicciones del modelo de resultado se usaron como auxiliares y se calibraron a sus totales poblacionales, aprovechando la fuerza del modelo predictivo.",
      lang), " ", .deff_phrase(de1, de2, lang), .ref_totals_phrase(step, lang))
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
    # lower = NULL is legal (no floor). format(NULL) is character(0), which would
    # collapse the whole paragraph to length 0 and crash the report -> show "-Inf".
    rng <- sprintf("[%s, %s]",
                   if (is.null(step$lower)) "-Inf" else format(step$lower),
                   if (is.null(step$upper)) .t("auto", "autom\u00e1tico", lang) else format(step$upper))
    # only an AUTOMATIC cutoff has a rule to name; with manual bounds there is none
    rlab <- if (is.null(step$upper)) {
      rule <- if (identical(step$method, "potter"))
        .t("Potter's MSE-optimal rule", "la regla \u00f3ptima en ECM de Potter", lang)
      else .t("the Tukey fence rule", "la regla del cerco de Tukey", lang)
      sprintf(" (%s)", rule)
    } else ""
    # did the redistribution actually preserve the total? compare the diag masses
    dg <- step$diagnostics
    sb <- suppressWarnings(as.numeric(dg$sum_before)[1])
    sa <- suppressWarnings(as.numeric(dg$sum_after)[1])
    preserved <- is.finite(sb) && is.finite(sa) && abs(sa - sb) <= 1e-6 * max(abs(sb), 1)
    tail <- if (preserved)
      .t("The trimmed mass was redistributed among the untrimmed units, preserving the weight total.",
         "La masa recortada se redistribuy\u00f3 entre las unidades no recortadas, preservando el total de pesos.", lang)
    else
      .t(sprintf("The requested bounds were infeasible, so the trimmed mass could not be fully redistributed and the weight total fell by %.1f%%.", 100 * (sb - sa) / sb),
         sprintf("Las cotas pedidas eran infactibles, as\u00ed que la masa recortada no pudo redistribuirse del todo y el total de pesos cay\u00f3 %.1f%%.", 100 * (sb - sa) / sb), lang)
    intro <- .t(sprintf("Extreme weights were trimmed to the interval %s%s.", rng, rlab),
                sprintf("Los pesos extremos se recortaron al intervalo %s%s.", rng, rlab), lang)
    txt <- paste0(intro, " ", tail, " ", .deff_phrase(de1, de2, lang))
  } else if (inherits(step, "step_round")) {
    txt <- .t("The final weights were rounded, for delivery of integer or fixed-precision weights.",
              "Los pesos finales se redondearon, para entregar pesos enteros o de precisi\u00f3n fija.", lang)
  } else if (inherits(step, "step_rescale")) {
    txt <- .t("The weights were rescaled so their sum matches the requested target (the number of units or a fixed population total).",
              "Los pesos se reescalaron para que su suma coincida con el objetivo pedido (el n\u00famero de unidades o un total poblacional fijo).", lang)
  } else if (inherits(step, "step_assert")) {
    txt <- .t("A quality checkpoint verified the weight diagnostics (design effect, weight ratio, effective sample size) against the configured thresholds.",
              "Un punto de control de calidad verific\u00f3 los diagn\u00f3sticos de los pesos (efecto de dise\u00f1o, raz\u00f3n de pesos, tama\u00f1o efectivo) contra los umbrales configurados.", lang)
  } else if (inherits(step, "step_pseudoweight")) {
    vp  <- .vars_phrase(all.vars(step$formula), lang)
    cf  <- if (!is.null(step$crossfit))
      .t(sprintf(" with %d-fold cross-fitting", step$crossfit),
         sprintf(" con validaci\u00f3n cruzada de %d particiones", step$crossfit), lang) else ""
    cls <- if (!is.null(step$num_classes))
      .t(sprintf(" The propensities were grouped into %d classes to stabilise the pseudo-weight.", step$num_classes),
         sprintf(" Las propensiones se agruparon en %d clases para estabilizar el pseudo-peso.", step$num_classes), lang)
      else ""
    txt <- .t(
      sprintf("The non-probability sample was pooled with the probability reference and a participation-propensity model (<strong>%s</strong> algorithm%s) was fitted over %s. Each non-probability unit received the pseudo-weight (1 - p)/p, the participation odds, which inflates it to the population so the weights sum to the reference's estimated population size (Elliott and Valliant 2017); the reference trains the model and is then dropped.%s Common support between the sample and the reference is the central assumption; see the propensity diagnostics below.", step$engine, cf, vp, cls),
      sprintf("La muestra no probabil\u00edstica se combin\u00f3 con la referencia probabil\u00edstica y se ajust\u00f3 un modelo de propensi\u00f3n de participaci\u00f3n (algoritmo <strong>%s</strong>%s) sobre %s. Cada unidad no probabil\u00edstica recibi\u00f3 el pseudo-peso (1 - p)/p, las probabilidades relativas de participaci\u00f3n, que la expanden a la poblaci\u00f3n de modo que los pesos suman el tama\u00f1o poblacional estimado por la referencia (Elliott y Valliant 2017); la referencia entrena el modelo y luego se descarta.%s El soporte com\u00fan entre la muestra y la referencia es el supuesto central; ver los diagn\u00f3sticos de propensi\u00f3n abajo.", step$engine, cf, vp, cls),
      lang)
  } else if (inherits(step, "step_nr_sensitivity")) {
    txt <- .t("A proxy pattern-mixture sensitivity analysis (Andridge and Little 2011) was run. It does not change the weights: it reports how far the study mean could move under nonignorable nonresponse, as an ignorance interval indexed by a single parameter. See the sensitivity block.",
              "Se corri\u00f3 un an\u00e1lisis de sensibilidad por mixtura de patrones con proxy (Andridge y Little 2011). No cambia los pesos: informa cu\u00e1nto podr\u00eda moverse la media bajo no respuesta no ignorable, como un intervalo de ignorancia indexado por un solo par\u00e1metro. Ver el bloque de sensibilidad.", lang)
  } else return("")

  if (!nzchar(txt)) return("")
  sprintf("<p class='methodological-note'>%s</p>", txt)
}

# Auto-generated executive summary paragraph for the top of the report.
