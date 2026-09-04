# report narrative: bilingual GSBPM/ESQRS-style prose (executive summary + per-step).

# ============================================================================
# Automatic methodological narrative (GSBPM 5.6 / ESQRS-style prose). Each step
# gets a natural-language paragraph explaining what was done and why, built from
# the step's own parameters and diagnostics, in English or Spanish.
# ============================================================================

# Pick the English or Spanish variant of a string.
.t <- function(en, es, lang) if (identical(lang, "es")) es else en

# Translate the compute-time diagnostic strings (quality alerts from prep(), the
# trimmed/model calibration `note` from apply_step()) for the Spanish report.
# Those are generated without a `lang`, so English is the canonical form (as
# emitted to warnings); this only rewrites them for the HTML display. Detection is
# by the fixed English prefix; the interpolated numbers are preserved, and any
# string that does not match a known pattern passes through unchanged.
.wf_translate <- function(x, lang) {
  if (!identical(lang, "es") || is.null(x) || !length(x)) return(x)
  one <- function(s) {
    if (!is.character(s) || is.na(s)) return(s)
    # Miscalibrated response propensities (R/prep.R)
    if (grepl("^The response propensities look miscalibrated", s)) {
      slope <- sub(".*calibration slope ([0-9.eE+-]+),.*", "\\1", s)
      return(sprintf(paste0(
        "Las propensiones de respuesta parecen mal calibradas (pendiente de ",
        "calibraci\u00f3n %s, ideal 1). Para ponderar por 1/p las probabilidades deben ",
        "estar bien calibradas, no solo discriminar bien. Conviene fijar num_classes ",
        "(p. ej. 5) para agrupar por cuantiles de propensi\u00f3n --que usan solo el ",
        "ordenamiento de las propensiones y por eso son robustos a esta contracci\u00f3n-- ",
        "o revisar el modelo de propensi\u00f3n."), slope))
    }
    # g-factor outside the Deville-Sarndal bounds (R/prep.R)
    if (grepl("g-factor outside the Deville-Sarndal bounds", s)) {
      m <- regmatches(s, regexec(paste0(
        "^([0-9]+) case\\(s\\) with a g-factor outside the Deville-Sarndal bounds ",
        "\\[([^,]+), ([^]]+)\\]: ([0-9]+) below, ([0-9]+) above\\.$"), s))[[1]]
      if (length(m) == 6L)
        return(sprintf(paste0("%s caso(s) con factor g fuera de las cotas de ",
          "Deville-S\u00e4rndal [%s, %s]: %s por debajo, %s por encima."),
          m[2], m[3], m[4], m[5], m[6]))
    }
    # Adjustment cells with no units to adjust to (R/prep.R)
    if (grepl("adjustment cell(s) had no units to adjust to", s, fixed = TRUE))
      return(sub(paste0(" adjustment cell(s) had no units to adjust to (no respondents, ",
        "or all of unknown eligibility); the affected units were set to weight 0. ",
        "Consider collapsing cells or using a coarser grouping."),
        paste0(" celda(s) de ajuste sin unidades a las que ajustar (sin respondentes, ",
        "o todas de elegibilidad desconocida); las unidades afectadas quedaron con peso ",
        "0. Conviene colapsar celdas o usar una agrupaci\u00f3n m\u00e1s gruesa."), s, fixed = TRUE))
    # Units rounded to weight 0 (R/prep.R)
    if (grepl("were rounded to weight 0 and left the active set", s, fixed = TRUE))
      return(sub(paste0(" unit(s) were rounded to weight 0 and left the active set ",
        "(their magnitude was below half the rounding precision, e.g. a small or ",
        "negative calibration weight); they no longer appear in collect_weights(). ",
        "Round to more decimals, or resolve those weights before rounding."),
        paste0(" unidad(es) se redondearon a peso 0 y salieron del conjunto activo (su ",
        "magnitud era inferior a la mitad de la precisi\u00f3n de redondeo, p. ej. un peso de ",
        "calibraci\u00f3n peque\u00f1o o negativo); ya no figuran en collect_weights(). Conviene ",
        "redondear a m\u00e1s decimales, o resolver esos pesos antes de redondear."), s, fixed = TRUE))
    # Very small response propensities (R/prep.R)
    if (grepl("Very small response propensities", s, fixed = TRUE)) {
      s <- sub("Very small response propensities (min p = ",
        "Propensiones de respuesta muy bajas (m\u00edn. p = ", s, fixed = TRUE)
      s <- sub(" among respondents) produce extreme 1/p weights (up to ",
        " entre respondentes) producen pesos 1/p extremos (hasta ", s, fixed = TRUE)
      return(sub("x). Check the propensity model, or trim with step_trim_weights().",
        "x). Conviene revisar el modelo de propensi\u00f3n, o recortar con step_trim_weights().",
        s, fixed = TRUE))
    }
    # Near-certain participation (R/prep.R)
    if (grepl("Near-certain participation", s, fixed = TRUE)) {
      s <- sub("Near-certain participation (max p = ",
        "Participaci\u00f3n casi segura (m\u00e1x. p = ", s, fixed = TRUE)
      return(sub(paste0(") drives the pseudo-weight (1 - p)/p toward 0, so those units ",
        "all but leave the sample. This usually means poor overlap between the sample ",
        "and the reference (a covariate cell the reference barely reaches); review the ",
        "common support or simplify the propensity model."),
        paste0(") lleva el pseudopeso (1 - p)/p hacia 0, por lo que esas unidades ",
        "pr\u00e1cticamente salen de la muestra. Suele indicar escaso solapamiento entre la ",
        "muestra y la referencia (una celda de covariables que la referencia casi no ",
        "cubre); conviene revisar el soporte com\u00fan o simplificar el modelo de propensi\u00f3n."),
        s, fixed = TRUE))
    }
    # Propensity quantile classes collapsed (R/prep.R)
    if (grepl("The response propensities were nearly constant", s, fixed = TRUE))
      return(paste0("Las propensiones de respuesta eran casi constantes, por lo que no ",
        "se pudo formar el num_classes solicitado (los puntos de corte por cuantiles ",
        "colapsaron); todas las unidades quedaron en una \u00fanica clase de ajuste, de modo ",
        "que la correcci\u00f3n por clases no tuvo efecto. Conviene quitar num_classes (usar ",
        "ponderaci\u00f3n 1/p) o revisar el modelo de propensi\u00f3n."))
    # Non-positive nonresponse-calibration g-weight (R/prep.R)
    if (grepl("non-positive calibration g-weight", s, fixed = TRUE))
      return(sub(paste0(" respondent(s) have a non-positive calibration g-weight ",
        "(implied response probability <= 0 or undefined). The nonresponse-calibration ",
        "auxiliaries are ill-behaved; use a bounded distance (logit) or a different ",
        "auxiliary vector."),
        paste0(" respondente(s) tienen un factor g de calibraci\u00f3n no positivo ",
        "(probabilidad de respuesta impl\u00edcita <= 0 o indefinida). Las variables ",
        "auxiliares de la calibraci\u00f3n por no respuesta se comportan mal; conviene usar ",
        "una distancia acotada (logit) o un vector auxiliar distinto."), s, fixed = TRUE))
    # Two-phase: few phase-2 units subsampled (R/prep.R)
    if (grepl("phase-2 sampling unit(s) were subsampled", s, fixed = TRUE)) {
      s <- sub("Only ", "Solo ", s, fixed = TRUE)
      return(sub(paste0(" phase-2 sampling unit(s) were subsampled. The two-phase ",
        "bootstrap resamples the phase-2 variance component (V2) at this level, so few ",
        "units give V2 few degrees of freedom and an unstable phase-2 standard error; ",
        "inspect the split with two_phase_variance() and read the phase-2 SE with care."),
        paste0(" unidad(es) de muestreo de fase 2 fueron submuestreadas. El bootstrap ",
        "bif\u00e1sico remuestrea el componente de varianza de fase 2 (V2) a este nivel, por ",
        "lo que pocas unidades dan a V2 pocos grados de libertad y un error est\u00e1ndar de ",
        "fase 2 inestable; conviene inspeccionar la partici\u00f3n con two_phase_variance() y ",
        "leer el EE de fase 2 con cautela."), s, fixed = TRUE))
    }
    # Two-phase: very small phase-2 selection probability (R/prep.R)
    if (grepl("A very small phase-2 selection probability", s, fixed = TRUE)) {
      s <- sub("A very small phase-2 selection probability (min pi2 = ",
        "Una probabilidad de selecci\u00f3n de fase 2 muy baja (m\u00edn. pi2 = ", s, fixed = TRUE)
      s <- sub(" expands the subsampled weights by up to ",
        " expande los pesos submuestreados hasta ", s, fixed = TRUE)
      return(sub(paste0("x, which inflates the phase-2 variance component (V2). Check ",
        "the phase-2 design or trim the expanded weights."),
        paste0("x, lo que infla el componente de varianza de fase 2 (V2). Conviene ",
        "revisar el dise\u00f1o de fase 2 o recortar los pesos expandidos."), s, fixed = TRUE))
    }
    # Ill-conditioned calibration system (R/prep.R)
    if (grepl("calibration system is ill-conditioned", s, fixed = TRUE)) {
      s <- sub("The calibration system is ill-conditioned (condition number ",
        "El sistema de calibraci\u00f3n est\u00e1 mal condicionado (n\u00famero de condici\u00f3n ",
        s, fixed = TRUE)
      return(sub(paste0("): near-collinear auxiliaries can make the weights unstable. ",
        "Drop a redundant auxiliary, or set penalty = <lambda> (ridge)."),
        paste0("): variables auxiliares casi colineales pueden volver inestables los ",
        "pesos. Conviene quitar una variable auxiliar redundante, o fijar penalty = ",
        "<lambda> (ridge)."), s, fixed = TRUE))
    }
    # Negative calibration weight, remains active (R/prep.R)
    if (grepl("received a NEGATIVE calibration weight", s, fixed = TRUE))
      return(sub(paste0(" unit(s) received a NEGATIVE calibration weight. They remain ",
        "active (counted in the totals and collect_weights()), but a negative weight is ",
        "rarely intended; set `bounds` to keep the calibration factor positive. Note ",
        "that the Kish design effect assumes non-negative weights, so with negatives ",
        "present its value is inflated and not interpretable as an effective-sample ",
        "summary."),
        paste0(" unidad(es) recibieron un peso de calibraci\u00f3n NEGATIVO. Siguen activas ",
        "(se cuentan en los totales y en collect_weights()), pero un peso negativo rara ",
        "vez es lo buscado; conviene fijar `bounds` para mantener positivo el factor de ",
        "calibraci\u00f3n. Nota: el efecto de dise\u00f1o de Kish supone pesos no negativos, por ",
        "lo que con negativos su valor queda inflado y deja de ser interpretable como ",
        "tama\u00f1o muestral efectivo."), s, fixed = TRUE))
    # Trimming did not preserve the weight total (R/prep.R)
    if (grepl("the weight total by", s, fixed = TRUE)) {
      s <- sub("Trimming reduced the weight total by ",
        "El recorte redujo el total de pesos en ", s, fixed = TRUE)
      s <- sub("Trimming increased the weight total by ",
        "El recorte aument\u00f3 el total de pesos en ", s, fixed = TRUE)
      s <- sub("% (from ", "% (de ", s, fixed = TRUE)
      s <- sub(" to ", " a ", s, fixed = TRUE)
      return(sub(paste0("): the mass was not preserved (infeasible bounds absorbed, or ",
        "a floor above the cap). The point estimates shift; check the bounds, or use ",
        "step_trim_calibrated() to trim while preserving totals."),
        paste0("): la masa no se preserv\u00f3 (cotas infactibles absorbidas, o una cota ",
        "inferior por encima de la superior). Los estimadores puntuales se desplazan; ",
        "conviene revisar las cotas, o usar step_trim_calibrated() para recortar ",
        "preservando los totales."), s, fixed = TRUE))
    }
    # Partial-household nonresponse (R/prep.R)
    if (grepl("responded only partially and were treated as whole-household", s, fixed = TRUE)) {
      s <- sub(paste0(" household(s) responded only partially and were treated as ",
        "whole-household nonresponse, discarding "),
        paste0(" hogar(es) respondieron solo parcialmente y se trataron como no ",
        "respuesta de hogar completo, descartando "), s, fixed = TRUE)
      return(sub(paste0(" responding member(s). If you meant person-level nonresponse, ",
        "drop `cluster`."),
        paste0(" integrante(s) que s\u00ed respondieron. Si buscaba no respuesta a nivel de ",
        "persona, quite `cluster`."), s, fixed = TRUE))
    }
    # Negative weights after calibration (R/prep.R)
    if (grepl("negative weight(s) after calibration", s, fixed = TRUE))
      return(sub(paste0(" negative weight(s) after calibration. This can occur with ",
        "linear/GREG calibration; consider a bounded distance (logit or truncated ",
        "linear) and review the auxiliaries."),
        paste0(" peso(s) negativo(s) tras la calibraci\u00f3n. Puede ocurrir con calibraci\u00f3n ",
        "lineal/GREG; conviene considerar una distancia acotada (logit o lineal ",
        "truncada) y revisar las variables auxiliares."), s, fixed = TRUE))
    # Weights below 1 after calibration (R/prep.R)
    if (grepl("below 1 (under-weighting) after calibration", s, fixed = TRUE))
      return(sub(paste0(" weight(s) below 1 (under-weighting) after calibration. ",
        "Consider bounds L<1<U (e.g. a logit distance) to avoid it."),
        paste0(" peso(s) por debajo de 1 (subponderaci\u00f3n) tras la calibraci\u00f3n. Conviene ",
        "considerar cotas L<1<U (p. ej. una distancia logit) para evitarlo."),
        s, fixed = TRUE))
    # Cells with a large adjustment factor (R/prep.R)
    if (grepl("with an adjustment factor >", s, fixed = TRUE)) {
      s <- sub(" cell(s) with an adjustment factor > ",
        " celda(s) con un factor de ajuste > ", s, fixed = TRUE)
      s <- sub(" (max ", " (m\u00e1x. ", s, fixed = TRUE)
      return(sub("). Large factors inflate variance; consider collapsing cells.",
        "). Los factores grandes inflan la varianza; conviene colapsar celdas.", s, fixed = TRUE))
    }
    # Cells with too few cases (R/prep.R)
    if (grepl("Kalton and Flores-Cervantes", s, fixed = TRUE)) {
      s <- sub(" cell(s) with fewer than ", " celda(s) con menos de ", s, fixed = TRUE)
      s <- sub(" cases (smallest observed ", " casos (m\u00ednimo observado ", s, fixed = TRUE)
      s <- sub("). Kalton and Flores-Cervantes (2003) recommend at least 30 per cell; ",
        "). Kalton y Flores-Cervantes (2003) recomiendan al menos 30 por celda; ",
        s, fixed = TRUE)
      s <- sub("consider collapsing cells (a coarser grouping).",
        "conviene colapsar celdas (una agrupaci\u00f3n m\u00e1s gruesa).", s, fixed = TRUE)
      return(sub("consider collapsing cells or switching to raking.",
        "conviene colapsar celdas o pasar a raking.", s, fixed = TRUE))
    }
    # Flexible learner without cross-fitting (R/prep.R)
    if (grepl("Flexible learner", s, fixed = TRUE)) {
      s <- sub("Flexible learner (", "Algoritmo de aprendizaje flexible (", s, fixed = TRUE)
      return(sub(paste0(") without cross-fitting: same-sample predictions can understate ",
        "the variance even under recipe-aware replication, because each unit stays in ",
        "the training set of its own prediction. Set crossfit = 5 to break it (Dagdoug, ",
        "Goga and Haziza 2023; Chernozhukov et al. 2018)."),
        paste0(") sin cross-fitting: las predicciones en la misma muestra pueden ",
        "subestimar la varianza aun con replicaci\u00f3n consciente de la receta, porque cada ",
        "unidad permanece en el conjunto de entrenamiento de su propia predicci\u00f3n. ",
        "Conviene fijar crossfit = 5 para evitarlo (Dagdoug, Goga y Haziza 2023; ",
        "Chernozhukov et al. 2018)."), s, fixed = TRUE))
    }
    # Cross-fitting without a seed (R/prep.R)
    if (grepl("cross-fitting without `crossfit_seed`", s, fixed = TRUE))
      return(paste0("el cross-fitting sin `crossfit_seed` no es reproducible; conviene ",
        "fijar `crossfit_seed` para un resultado estable."))
    # Bounded calibration did not converge (R/adjust-solve.R)
    if (grepl("Bounded calibration did not fully converge", s, fixed = TRUE))
      return("La calibraci\u00f3n acotada no convergi\u00f3 del todo (las cotas pueden ser infactibles).")
    # Singular calibration system (R/adjust-solve.R)
    if (grepl("Singular calibration system", s, fixed = TRUE))
      return("Sistema de calibraci\u00f3n singular (variables auxiliares colineales); se usa la pseudo-inversa.")
    # Missing values grouped into a (missing) cell (R/adjust-solve.R)
    if (grepl("were grouped into a '(missing)' cell", s, fixed = TRUE))
      return(sub(paste0("Missing values in the cell variable(s) `by` were grouped into a ",
        "'(missing)' cell. Those units are adjusted within their own cell; recode the NAs ",
        "if that is not intended."),
        paste0("Los valores faltantes en la(s) variable(s) de celda `by` se agruparon en ",
        "una celda '(missing)'. Esas unidades se ajustan dentro de su propia celda; ",
        "recodifique los NA si no es lo buscado."), s, fixed = TRUE))
    # Trimmed calibration could not preserve every total (R/adjust-trim.R)
    if (grepl("Trimmed calibration could not both stay within", s, fixed = TRUE)) {
      s <- sub("Trimmed calibration could not both stay within [",
        "La calibraci\u00f3n recortada no pudo a la vez quedar dentro de [", s, fixed = TRUE)
      s <- sub("] and preserve every total (max relative deviation = ",
        "] y preservar todos los totales (desviaci\u00f3n relativa m\u00e1xima = ", s, fixed = TRUE)
      return(sub("). The range may be infeasible; widen the bounds or relax the constraints.",
        "). El rango puede ser infactible; ampl\u00ede las cotas o relaje las restricciones.", s, fixed = TRUE))
    }
    # Model-calibration predictions not aligned (R/adjust-trim.R)
    if (grepl("predictions are not aligned with the active sample", s, fixed = TRUE))
      return(paste0("Las predicciones de un step_model_calibration() previo no est\u00e1n ",
        "alineadas con la muestra activa aqu\u00ed (un paso intermedio la cambi\u00f3); el recorte ",
        "preserva solo los m\u00e1rgenes X de `formula`."))
    # Model calibration did not satisfy constraints (R/adjust-trim.R)
    if (grepl("Model calibration did not fully satisfy the constraints for:", s, fixed = TRUE)) {
      s <- sub("Model calibration did not fully satisfy the constraints for: ",
        "La calibraci\u00f3n por modelo no satisfizo del todo las restricciones para: ", s, fixed = TRUE)
      s <- sub(". The achieved totals differ from the targets (max relative deviation = ",
        ". Los totales logrados difieren de los objetivos (desviaci\u00f3n relativa m\u00e1xima = ", s, fixed = TRUE)
      s <- sub("); this can happen with ", "); puede ocurrir con ", s, fixed = TRUE)
      s <- sub(paste0("collinear auxiliaries, an ill-conditioned system, or an infeasible ",
        "`bounds` range; widen the bounds or check the auxiliaries."),
        paste0("auxiliares colineales, un sistema mal condicionado, o un rango de `bounds` ",
        "infactible; ampl\u00ede las cotas o revise las auxiliares."), s, fixed = TRUE)
      return(s)
    }
    # Calibration did not satisfy constraints (R/adjust-calibrate.R)
    if (grepl("Calibration did not satisfy the constraints for:", s, fixed = TRUE)) {
      s <- sub("Calibration did not satisfy the constraints for: ",
        "La calibraci\u00f3n no satisfizo las restricciones para: ", s, fixed = TRUE)
      s <- sub(". The achieved totals differ from the targets (max relative deviation = ",
        ". Los totales logrados difieren de los objetivos (desviaci\u00f3n relativa m\u00e1xima = ", s, fixed = TRUE)
      return(sub(paste0("). Under bounds this can mean the bounds are infeasible; otherwise ",
        "check for collinear auxiliaries or non-uniform within-cluster base weights."),
        paste0("). Con cotas, puede indicar que las cotas son infactibles; si no, revise ",
        "auxiliares colineales o pesos base no uniformes dentro del conglomerado."), s, fixed = TRUE))
    }
    # Calibration totals for empty domain (R/adjust-calibrate.R)
    if (grepl("with no unit in the sample:", s, fixed = TRUE)) {
      s <- sub("The calibration `totals` include domain(s) of '",
        "Los `totals` de calibraci\u00f3n incluyen dominio(s) de '", s, fixed = TRUE)
      s <- sub("' with no unit in the sample: ", "' sin ninguna unidad en la muestra: ", s, fixed = TRUE)
      return(sub(paste0(". Their control totals are dropped, so the weighted total does not ",
        "reach the intended population size. Check the domain coverage of the sample and the totals."),
        paste0(". Sus totales de control se descartan, as\u00ed que el total ponderado no alcanza ",
        "el tama\u00f1o poblacional buscado. Revise la cobertura de dominios de la muestra y los totales."),
        s, fixed = TRUE))
    }
    # Raking did not converge (R/adjust-calibrate.R, R/adjust-poststrata.R)
    if (grepl("Raking did not converge after", s, fixed = TRUE)) {
      s <- sub("Raking did not converge after ", "El raking no convergi\u00f3 tras ", s, fixed = TRUE)
      s <- sub(" iterations (max relative change = ", " iteraciones (cambio relativo m\u00e1ximo = ", s, fixed = TRUE)
      s <- sub(", tolerance = ", ", tolerancia = ", s, fixed = TRUE)
      return(sub(paste0("). The returned weights do not fully satisfy all margins. Consider ",
        "increasing `maxit`, or check that the margin totals are mutually consistent."),
        paste0("). Los pesos devueltos no satisfacen del todo todos los m\u00e1rgenes. Considere ",
        "aumentar `maxit`, o verifique que los totales de los m\u00e1rgenes sean mutuamente ",
        "consistentes."), s, fixed = TRUE))
    }
    # Raking converged but some margin cells unmet (R/adjust-calibrate.R)
    if (grepl("Raking iterations converged but", s, fixed = TRUE)) {
      s <- sub("Raking iterations converged but ", "Las iteraciones de raking convergieron pero ", s, fixed = TRUE)
      s <- sub(" margin cell(s) were not met (e.g. ", " celda(s) de margen no se cumplieron (p. ej. ", s, fixed = TRUE)
      s <- sub(": target ", ": objetivo ", s, fixed = TRUE)
      s <- sub(", achieved ", ", logrado ", s, fixed = TRUE)
      return(sub(paste0("), typically a cell whose weights sum to <= 0 and cannot be raked. ",
        "The returned weights do not satisfy these margins."),
        paste0("), t\u00edpicamente una celda cuyos pesos suman <= 0 y no puede rakearse. Los ",
        "pesos devueltos no satisfacen esos m\u00e1rgenes."), s, fixed = TRUE))
    }
    # Raking stabilised but cells unmet (R/adjust-poststrata.R)
    if (grepl("Raking stabilised but", s, fixed = TRUE)) {
      s <- sub("Raking stabilised but ", "El raking se estabiliz\u00f3 pero ", s, fixed = TRUE)
      s <- sub(" margin cell(s) are not met (max relative deviation = ",
        " celda(s) de margen no se cumplen (desviaci\u00f3n relativa m\u00e1xima = ", s, fixed = TRUE)
      return(sub(paste0("). This usually means a cell has a non-positive weight sum (e.g. ",
        "after an unbounded linear calibration) and was skipped every sweep. Cells: "),
        paste0("). Suele indicar que una celda tiene suma de pesos no positiva (p. ej. tras ",
        "una calibraci\u00f3n lineal sin cotas) y se salte\u00f3 en cada pasada. Celdas: "), s, fixed = TRUE))
    }
    # Post-stratification 0 control total (R/adjust-poststrata.R)
    if (grepl("with a population total of 0 sent their", s, fixed = TRUE)) {
      s <- sub("Post-stratification: ", "Post-estratificaci\u00f3n: ", s, fixed = TRUE)
      s <- sub(" cell(s) with a population total of 0 sent their sample units to weight 0 (",
        " celda(s) con total poblacional 0 mandaron sus unidades muestrales a peso 0 (", s, fixed = TRUE)
      return(sub(paste0("). Those units leave the cascade -- this is a 0 control total, not ",
        "an ordinary nonresponse/ineligibility drop; check the totals if that cell should not be empty."),
        paste0("). Esas unidades salen de la cascada -- es un total de control 0, no una baja ",
        "ordinaria por no respuesta/inelegibilidad; revise los totales si esa celda no deber\u00eda ",
        "estar vac\u00eda."), s, fixed = TRUE))
    }
    # Nonresponse calibration did not satisfy constraints (R/adjustments.R)
    if (grepl("Nonresponse calibration did not fully satisfy the constraints", s, fixed = TRUE)) {
      s <- sub("Nonresponse calibration did not fully satisfy the constraints (max relative deviation = ",
        "La calibraci\u00f3n por no respuesta no satisfizo del todo las restricciones (desviaci\u00f3n relativa m\u00e1xima = ", s, fixed = TRUE)
      return(sub(" -- the bounds/calfun truncated the weights",
        " -- las cotas/calfun truncaron los pesos", s, fixed = TRUE))
    }
    # Model variables not constant within cluster (R/adjustments.R)
    if (grepl("are not constant within some cluster(s) of", s, fixed = TRUE)) {
      s <- sub("Model variable(s) ", "La(s) variable(s) del modelo ", s, fixed = TRUE)
      s <- sub(" are not constant within some cluster(s) of '",
        " no son constantes dentro de alg\u00fan(os) conglomerado(s) de '", s, fixed = TRUE)
      return(sub(paste0("'. Household-level propensity reads one row per cluster (the first), ",
        "so a covariate varying inside a cluster makes the fit (and the weights) depend on ",
        "row order. Use cluster-level covariates, aggregate them per cluster, or drop `cluster` for a person-level adjustment."),
        paste0("'. La propensi\u00f3n a nivel de hogar lee una fila por conglomerado (la primera), ",
        "as\u00ed que una covariable que var\u00eda dentro del conglomerado hace que el ajuste (y los ",
        "pesos) dependan del orden de las filas. Use covariables a nivel de conglomerado, ",
        "agr\u00e9guelas por conglomerado, o quite `cluster` para un ajuste a nivel de persona."), s, fixed = TRUE))
    }
    # Weak proxy for NR sensitivity (R/adjust-nr-sensitivity.R)
    if (grepl("The proxy is weak", s, fixed = TRUE)) {
      s <- sub("The proxy is weak (respondent correlation of y and the auxiliaries = ",
        "El proxy es d\u00e9bil (correlaci\u00f3n en respondentes entre y y las auxiliares = ", s, fixed = TRUE)
      return(sub(paste0("); the ignorance interval is wide and driven by the near-1/rho ",
        "extreme. Add auxiliaries more predictive of y."),
        paste0("); el intervalo de ignorancia es ancho y est\u00e1 dominado por el extremo cercano ",
        "a 1/rho. Agregue auxiliares m\u00e1s predictivas de y."), s, fixed = TRUE))
    }
    # Covariate factor levels differ sample vs reference (R/adjust-pseudoweight.R)
    if (grepl("has factor levels that differ between the sample and the reference", s, fixed = TRUE)) {
      s <- sub("Covariate '", "La covariable '", s, fixed = TRUE)
      s <- sub("' has factor levels that differ between the sample and the reference (",
        "' tiene niveles de factor que difieren entre la muestra y la referencia (", s, fixed = TRUE)
      s <- sub("only in the sample: ", "solo en la muestra: ", s, fixed = TRUE)
      s <- sub("only in the reference: ", "solo en la referencia: ", s, fixed = TRUE)
      return(sub(paste0("); unmatched levels bias the propensity fit and can push ",
        "pseudo-weights to extremes. Harmonise the levels before pseudo-weighting."),
        paste0("); los niveles no coincidentes sesgan el ajuste de propensi\u00f3n y pueden llevar ",
        "los pseudopesos a extremos. Armonice los niveles antes de pseudo-ponderar."), s, fixed = TRUE))
    }
    # Trimmed / model calibration note (R/adjust-trim.R) -- partial substitutions
    s <- sub("^trimmed calibration to ", "calibraci\u00f3n recortada a ", s)
    s <- sub("^g \\(calibration factor\\) in ", "g (factor de calibraci\u00f3n) en ", s)
    s <- sub(" weights raised to lower, ", " pesos elevados a la cota inferior, ", s)
    s <- sub(" capped at upper; f \\(adjustment\\) in ", " recortados a la cota superior; f (ajuste) en ", s)
    s <- sub(", bounds ", ", cotas ", s)
    s <- sub("; one weight per '(.*)' \\(integrative\\)", "; un peso por '\\1' (integrativo)", s)
    s <- sub("; one factor per '(.*)' \\(integrative\\)", "; un factor por '\\1' (integrativo)", s)
    s <- gsub("by group", "por grupo", s)
    s
  }
  vapply(x, one, character(1), USE.NAMES = FALSE)
}

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
  if (inherits(step, "step_subsample"))
    return(.t("second-phase subsampling", "submuestreo de segunda fase", lang))
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
  } else if (inherits(step, "step_subsample")) {
    txt <- .t(
      "A second phase of sampling was undone: the subsampled units had their weight multiplied by the inverse of the phase-2 selection probability, so they represent the whole first-phase sample, and the not-subsampled units left the cascade. When the variance is estimated by bootstrap, weightflow uses the two-phase coupling V = V1 + V2 &mdash; the first-phase sampling variance plus the expected conditional variance of the phase-2 subsample &mdash; which a single-phase bootstrap would understate.",
      "Se deshizo una segunda fase de muestreo: a las unidades submuestreadas se les multiplic&oacute; el peso por el inverso de la probabilidad de selecci&oacute;n de fase 2, para que representen a toda la muestra de primera fase, y las no submuestreadas salieron de la cascada. Cuando la varianza se estima por bootstrap, weightflow usa el acople de dos fases V = V1 + V2 &mdash; la varianza de muestreo de fase 1 m&aacute;s la varianza condicional esperada del submuestreo de fase 2 &mdash; que un bootstrap de una sola fase subestimar&iacute;a.",
      lang)
  } else return("")

  if (!nzchar(txt)) return("")
  sprintf("<p class='methodological-note'>%s</p>", txt)
}

# Auto-generated executive summary paragraph for the top of the report.
