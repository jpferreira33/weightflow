# weightflow — evaluación del estado actual y hoja de ruta

**Fecha:** 26 de agosto de 2026
**Versión evaluada:** 1.2.0.9000 (dev) · CRAN: 1.1.0 (2026-08-19)
**Alcance:** estado del paquete, posicionamiento en el ecosistema, brechas
metodológicas / de producción / de adopción, y bibliografía comentada.

> Documento interno. Vive en `dev/`, que está en `.Rbuildignore`.
> Complementa (no reemplaza) a `dev/ROADMAP.md`, que registra el trabajo
> diferido a nivel de API. Acá el foco es estratégico: hacia dónde va la
> producción estadística y qué de eso weightflow todavía no cubre.

---

## 1. Resumen ejecutivo

weightflow está **metodológicamente maduro y técnicamente sólido**. En términos
de ingeniería (≈9.200 líneas de R contra ≈9.200 de tests, CI en seis workflows,
sin dependencias duras, 18 viñetas, reporte HTML bilingüe, cobertura en Codecov)
está por encima de la mediana de los paquetes de encuestas de CRAN, y por encima
de casi todos los que no vienen de un INE.

La tesis del paquete —*la cascada de ponderación como objeto declarativo, con
réplicas que la re-estiman entera*— es correcta, defendible y llega en el momento
justo: ten Bosch & van der Loo (2026), el documento de referencia sobre software
abierto en estadística oficial, lista literalmente entre sus recomendaciones
"establecer mecanismos para propagar la incertidumbre a través de los pipelines
estadísticos". Eso es, palabra por palabra, lo que hace weightflow.

**Los tres riesgos reales, en orden:**

1. **El claim de novedad está sobre-extendido.** `svrep` (Schneider, Westat) ya
   propaga varianza multi-etapa con `redistribute_weights()` +
   `calibrate_to_sample()`, y `surveysd` (Statistics Austria) ya re-calibra cada
   réplica bootstrap con `recalib()`. Un revisor de JOS o JSSAM los conoce. Hay
   que contrastarlos de frente en el README y en el paper, no esquivarlos.
2. **Falta validación cruzada publicada** contra el software incumbente
   (`survey::calibrate()`, ReGenesees, CALMAR2, SUDAAN `WTADJUST`). Sin eso
   ningún INE lo adopta, por bueno que sea el método.
3. **La receta todavía no es serializable.** Es un objeto de R, no un artefacto
   versionable/diffeable en JSON o YAML. Eso bloquea la promesa de auditoría
   del *método* (no sólo del código), que es el argumento más fuerte frente a
   un INE y frente a los criterios RAP del gobierno británico.

**El área de crecimiento con mayor retorno metodológico** es la que el propio
1.2.0 abrió a medias: **muestras no probabilísticas e integración de datos**.
`step_pseudoweight()` y `reference_sample()` son la puerta de entrada; falta
imputación masiva, doblemente robusto formalizado, y —sobre todo— **diagnóstico
del sesgo residual** (índices tipo SMUB/MUBP), que es lo que un INE necesita para
decidir si publica o no.

---

## 2. Estado actual

### 2.1 Qué hay

| Dimensión | Estado |
|---|---|
| **Cascada** | Completa para encuestas de hogares: elegibilidad desconocida, inelegibles, selección intra-hogar, no respuesta (clases / propensión logit-CART-forest-xgboost con cross-fitting / calibración bifásica), pseudo-pesos para no probabilísticas, calibración (raking, post-estratificación, GREG, acotada, integrativa, ridge, por dominios, `calfun` exponencial), model calibration Wu-Sitter, trimming (manual, Tukey, Potter MSE-óptimo, re-calibración acotada Folsom-Singh), redondeo, reescalado, aserciones. |
| **Varianza** | Bootstrap Rao-Wu re-escalado con FPC, jackknife delete-a-PSU (JK1/JKn), manejo de estratos con una sola UPM, paralelismo, `df` de diseño, IC normal / t / percentil, propagación de la varianza de totales estimados desde una encuesta de referencia. |
| **Diagnóstico** | Kish deff, n efectivo, R-indicators y R-indicators parciales, alertas estructuradas (`weighting_alerts()`), auditoría unidad a unidad (`collect_step_detail()`, `collect_propensities()`) y por dominio (`domain_summary()`), ids estables por paso. |
| **Reporte** | HTML autocontenido bilingüe EN/ES, alineado a GSBPM 5.6 y a los conceptos de calidad del ESS: narrativa, metadatos de referencia, tasas AAPOR (RR1/RR3/RR5), fiabilidad por dominio, ficha de replicación, tabla de impacto por paso, panel de puntos de atención. |
| **Puentes** | `as_svydesign()`, `as_svrepdesign()`, `collect_replicate_weights()`, `as_sae_input()`. |
| **Ingeniería** | Sin dependencias duras (base R ≥ 4.1). CI: R-CMD-check, rhub, no-suggests, test-coverage, pkgdown, draft-pdf. `inst/CITATION`, `inst/WORDLIST`. Preprint arXiv 2607.08491. Listado en la CRAN Task View *OfficialStatistics*, §4.1 *Weighting and Calibration*. |

### 2.2 Fortalezas diferenciales (las que hay que defender)

1. **La receta es un objeto de primera clase.** Inspeccionable, imprimible,
   testeable, reutilizable, con ids estables por paso. En `svrep` y en `survey`
   la secuencia es imperativa sobre el objeto de diseño.
2. **Cobertura de las etapas *previas* a la no respuesta.** `step_drop_ineligible()`,
   `step_unknown_eligibility()`, `step_select_within()`. Nadie más las modela
   explícitamente; en la práctica quedan como código ad-hoc del metodólogo.
3. **Trimming como etapa de la receta**, incluida la re-calibración acotada que
   preserva los totales. `svrep` no tiene trimming; `survey` no tiene Potter ni
   Folsom-Singh.
4. **Cero dependencias duras.** Para un INE con control de dependencias e
   instalaciones offline, esto es un argumento operativo real, no cosmético.
   `svrep` arrastra `survey` → `Matrix`, `survival`.
5. **`step_assert()`**: control de calidad declarativo *dentro* de la receta.
   Es exactamente el patrón "las reglas son datos, no código" de la escuela CBS
   (`validate`, `dcmodify`, `errorlocate`), y conviene decirlo con esas palabras.
6. **El reporte de calidad.** Ningún competidor documenta el *proceso* de
   ponderación; todos documentan el *estimador*.

### 2.3 Deuda técnica conocida (de `dev/ROADMAP.md`, vigente)

- BUG-17: `bootstrap_weights()` sin semilla reutiliza parte del stream del RNG.
  **Con los criterios RAP y de reproducibilidad de un INE, esto no es "nicho":
  es un defecto de reproducibilidad y debería subir de prioridad.**
- BUG-19: cross-fitting con niveles raros devuelve el error crudo del motor.
- BUG-25: `DESCRIPTION` lista dos autores y `inst/CITATION` uno. **Resolver antes
  de que el paper esté en producción.**
- `DESCRIPTION` está en 1.1.0.9000 mientras `NEWS.md` encabeza 1.2.0. Alinear.
- **`paper/paper.bib` tiene sólo 8 entradas** (Valliant 2018, Deville-Särndal 1992,
  Rao-Wu 1988, Wu-Sitter 2001, Lemaître-Dufour 1987, Kish 1965, Lumley 2010,
  Kuhn 2022) mientras el README lista ~25 referencias. Para JOS / The R Journal
  el `.bib` va a necesitar toda la bibliografía del §6, más el bloque de trabajo
  relacionado (§6.7).
- Viñetas duplicadas: `trimming.Rmd` y `advanced-methods.Rmd` repiten Potter y
  Folsom-Singh.

---

## 3. Posicionamiento: los tres solapamientos que hay que abordar de frente

### 3.1 `svrep` (Ben Schneider, Westat) — el competidor más cercano

Hace generación de réplicas para diseños difíciles (bootstrap generalizado, Fay
generalizado, SDR, RWYB, doubled-half, dos fases) **y ajustes sobre las réplicas**:
`redistribute_weights()` (no respuesta y elegibilidad desconocida, columna por
columna) y `calibrate_to_estimate()` / `calibrate_to_sample()` (calibración a
estimaciones de otra encuesta propagando su varianza).

**Consecuencia:** la frase "ningún paquete propaga la incertidumbre de todas las
etapas" no sobrevive una revisión. La diferencia genuina es **declaratividad,
cobertura de etapas previas, trimming, diagnóstico del proceso y ausencia de
dependencias** — no la primicia.

**Movimiento recomendado: interoperar, no competir.** Aceptar un `svyrep.design`
de `svrep` como fuente de réplicas en `bootstrap_weights()` / `jackknife_weights()`
convierte al competidor en complemento y te regala toda su teoría fina de
generación de réplicas sin escribirla.

### 3.2 `surveysd` (Statistics Austria)

`draw.bootstrap()` + `recalib()` ya es "bootstrap que re-aplica la calibración",
para paneles rotativos EU-SILC. Diferencia defendible: weightflow re-aplica *toda*
la cascada, no sólo el IPF, y no está atado a la estructura de panel rotativo ni a
`data.table`.

### 3.3 `metasurvey` (Loprete, da Silva, Machado — UdelaR)

Mismo vocabulario (*step*, *recipe*, *bake*), mismo origen geográfico, soporta la
ECH. **Delimitalo explícitamente y primero vos:** metasurvey declara la
transformación y armonización de la microdata; weightflow declara la construcción
del peso. Son complementarios y una viñeta que los use juntos sobre la ECH sería
un activo, no una concesión.

---

## 4. Brechas y oportunidades

### A. Métodos

Ordenadas por relevancia para "los tiempos que corren".

#### A1. Muestras no probabilísticas: completar lo que 1.2.0 abrió · **prioridad alta**

`step_pseudoweight()` cubre el brazo IPW. Faltan los otros dos brazos del marco
canónico (Chen, Li & Wu 2020; Wu 2022):

- **`step_mass_impute()`** — imputación masiva: ajustar el modelo del resultado
  en la muestra no probabilística y predecirlo sobre la muestra probabilística de
  referencia, estimando con los pesos de ésta. Es el dual del pseudo-peso y
  frecuentemente más eficiente. Motores: los mismos que ya tenés (`y_model()`).
- **Doblemente robusto formalizado.** Hoy se puede *combinar*
  `step_pseudoweight()` + `step_calibrate(reference_sample())` a mano; falta el
  estimador DR con su varianza correcta (la que reconoce que ambos modelos fueron
  estimados). Ver Chen-Li-Wu (2020) y Yang, Kim & Song (2020).
- **Varianza:** `nonprobsvy` ya tiene bootstrap y varianza analítica para estos
  estimadores y su roadmap declara "replicate weights". Vigilalo: ahí puede
  aparecer solapamiento, o una oportunidad de integración.

#### A2. Diagnóstico del sesgo residual · **prioridad alta, alto retorno / bajo costo**

Esta es la brecha más valiosa y la más barata. Ya tenés R-indicators (que miden
*representatividad de la respuesta* respecto de las covariables observadas). Falta
lo que mide el sesgo **bajo no-ignorabilidad**, que es lo que un INE necesita para
decidir si publica:

- **SMUB / MUBP** (Little, West, Boonstra & Hu 2020; Andridge & Little 2011;
  Andridge et al. 2019 para proporciones): un índice sencillo indexado por un
  parámetro de sensibilidad φ ∈ [0,1] que interpola entre MAR (φ=0) y
  no-ignorabilidad total (φ=1). Se calcula con lo que ya tenés en el objeto
  `prepped_weighting_spec`.
- **Análisis de sensibilidad** presentado en el reporte HTML como una curva de
  la estimación contra φ. Esto convierte el reporte de "documentación" en
  "instrumento de decisión editorial".
- **Diagnóstico de balance al estilo `cobalt`**: SMD, ratio de varianzas, eCDF,
  distancias distribucionales (KS, Cramér-von Mises, Earth Mover's). El paquete
  `balance` de Meta ya fijó ese estándar visual y los revisores lo esperan.
  Hoy weightflow no calcula SMD (verificado: no hay `smd`/`std_diff` en `R/`).

#### A3. Calibración moderna · **prioridad media-alta**

- **Calibración por entropía generalizada** (Kwon, Kim & Qiu 2025, JASA;
  paquete `GECal`). Mete los pesos de diseño en las *restricciones* y no en la
  función objetivo; da calibración "debiased" y una teoría de inferencia
  post-calibración. Es la novedad teórica más citada del bienio.
- **Puente conceptual con *entropy balancing*** (Hainmueller 2012). Es la misma
  familia matemática llegando desde la literatura causal. Señalarlo en la
  documentación es barato y posiciona bien.
- **Calibración conjunta de totales y cuantiles** (Harms & Duchesne 2006;
  Beręsewicz, paquete `jointCalib`). Muy pertinente para ingresos y pobreza:
  calibrar a la mediana del ingreso, no sólo al total.
- **Calibración regularizada más allá de ridge**: LASSO / elastic-net cuando hay
  muchas auxiliares (McConville, Breidt, Lee & Moisen 2017; paquete `mase`).
  Tenés ridge; falta selección de variables.
- **`q`-weights de Deville-Särndal** (pesos de costo). Ya está en tu roadmap
  interno; toca el solver central.

#### A4. Registros administrativos y marcos combinados · **prioridad media**

El movimiento estructural de la década: los totales de control ya no vienen de un
censo decenal sino de registros. Implicancias concretas:

- **Totales de control con error.** Hoy `reference_sample()` propaga la varianza
  de totales estimados *de una encuesta*. Falta el caso de totales de un
  **registro con error de cobertura o de enlace**. Ver la literatura de
  *generalised accuracy estimation* para estadística basada en múltiples registros.
- **Propagación del error de enlace (record linkage) a la varianza.** Cuando el
  marco o la variable auxiliar viene de un registro enlazado probabilísticamente,
  la incertidumbre del enlace es una componente de varianza que hoy nadie propaga
  en un paquete de ponderación. Sería genuinamente novedoso.
- Interfaz práctica: aceptar en `step_calibrate()` totales con una matriz de
  covarianza asociada (que es lo que `svrep::calibrate_to_estimate()` ya hace).

#### A5. Estimación robusta y outliers · **prioridad media-baja**

`step_trim*()` ataca los pesos extremos. No ataca los **valores extremos de la
variable de interés**, que es el problema clásico de encuestas de empresas e
ingresos. La familia de sesgo condicional (Beaumont, Haziza & Ruiz-Gazen 2013,
Biometrika) da un marco unificado; `robsurvey` lo implementa a nivel de estimador.
Un `step_winsorize()` a nivel de peso, documentado como *distinto* del trimming
de calibración, cerraría el hueco. **Ojo:** hoy la documentación de `step_trim`
puede confundirse con el "weight trimming" robusto de `robsurvey`; conviene
diferenciarlos explícitamente.

#### A6. SAE y estimación bayesiana · **prioridad baja (frontera correcta)**

`as_sae_input()` es la decisión correcta: exportar, no modelar. Extensiones
baratas: benchmarking de las estimaciones de área a los totales calibrados, y
exportar también la matriz de covarianza entre dominios desde las réplicas (hoy
sólo el error estándar por dominio), que es lo que un Fay-Herriot multivariado
necesita. MRP queda fuera de alcance y está bien que quede fuera.

### B. Producción e infraestructura

#### B1. Serializar la receta · **prioridad máxima**

Es la brecha que más limita la promesa del paquete. Un `weighting_spec` debería
poder escribirse y leerse como **JSON o YAML**: entonces el *método* —no sólo el
código— entra en git, se diffea entre olas, se revisa en un PR, se archiva junto
al microdato y se describe en vocabulario GSIM 2.0 (*Process Step*, *Process
Design*, *Rule*, *Parameter*).

```r
spec_to_json(recipe, "ech_2026_t1.json")
recipe <- spec_from_json("ech_2026_t1.json")
```

Verificado: hoy no hay nada de JSON/YAML en `R/`. Sin dependencias duras se puede
hacer con un serializador propio mínimo, o con `jsonlite` en `Suggests`.

Esto habilita de golpe:
- `report_weighting(compare = old_fit)`, el diff ola contra ola que ya está en tu
  roadmap (los ids estables por paso ya están hechos: la mitad del trabajo);
- auditoría del método por un tercero sin ejecutar R;
- el criterio RAP #4 (control de versiones) aplicado a la metodología.

#### B2. Reproducibilidad exacta · **prioridad alta**

BUG-17 (bootstrap sin semilla reutiliza parte del stream) deja de ser nicho en
cuanto el objetivo es un INE. Un INE necesita **reproducibilidad bit a bit**.
Recomendación: RNG por réplica con semillas derivadas determinísticamente de una
semilla raíz (streams L'Ecuyer-CMRG), documentado y testeado. Y un test de
regresión que verifique igualdad bit a bit entre corridas y entre `cores = 1` y
`cores = 4`.

#### B3. Escala · **prioridad media**

ReGenesees existe porque Istat necesitaba calibrar millones de registros, y por
eso tiene **calibración particionada**. Tu `by =` va en esa dirección pero no está
pensado como estrategia de escalabilidad. Falta:

- un benchmark publicado (tiempo y memoria) con n = 10⁵, 10⁶ y 500 réplicas;
- documentar el techo práctico honestamente;
- perfilar el solver de calibración (`R/adjust-solve.R`, 268 líneas) — es el
  cuello de botella esperable.

#### B4. Metadatos y estándares · **prioridad media**

- Etiquetar la documentación con **GSBPM 5.2, sub-proceso 5.6** (la versión
  vigente del GSBPM es la 5.2, endosada en mayo de 2025; el reporte hoy dice
  "GSBPM 5.6" a secas, que se lee como una versión inexistente — vale la pena
  precisarlo: *GSBPM v5.2, sub-proceso 5.6 "Calculate weights"*).
- Bloque **JSON embebido en el reporte HTML** con los indicadores clave (deff,
  n efectivo, tasas AAPOR, alertas), para que un pipeline lo consuma sin parsear
  HTML. Ya está insinuado en tu roadmap.
- Explorar que `step_assert()` pueda consumir un DSD de SDMX o un fragmento DDI,
  como ya hace `validate`. Es el gancho que mete a weightflow en la conversación
  de metadatos de un INE.
- Si se apunta a servicio compartido: la tríada documental de **CSPA 2.0**.

#### B5. Confidencialidad · **prioridad baja (frontera correcta)**

Los pesos son un vector de re-identificación conocido (un peso muy bajo señala un
estrato chico). No hace falta implementar SDC —`sdcMicro` existe— pero **una
alerta** cuando la distribución de pesos permite identificar celdas de tamaño
mínimo, y un párrafo en la viñeta de producción sobre redondeo de pesos para
difusión, es barato y muestra madurez.

### C. Adopción y comunidad

Ordenado por retorno sobre esfuerzo.

| # | Acción | Costo | Retorno |
|---|---|---|---|
| 1 | **PR a `SNStatComp/awesome-official-statistics-software`**, sección *Estimation and weighting*. Hoy no figura (sí figurás en la CRAN Task View). | ~1 hora | Alto: es la lista que miran los INEs europeos |
| 2 | **Validación cruzada publicada** contra `survey::calibrate()`, ReGenesees, CALMAR2 e idealmente SUDAAN `WTADJUST`, sobre datos públicos, como viñeta y como sección del paper | 2-4 semanas | **Decisivo para adopción en INEs** |
| 3 | **Paper**: `The R Journal` (nicho libre: el vol. 18/1 de marzo 2026 no tiene nada de encuestas) o `Journal of Official Statistics` (donde salió ReGenesees). El track de journal de **uRos2026** cierra el **15-ene-2027** | — | Alto |
| 4 | **Caso de producción documentado con la ECH del INE Uruguay.** Es el activo más valioso que tenés y encaja con el track de reproducibilidad de uRos | — | Muy alto |
| 5 | **Peer review de rOpenSci** bajo los *Statistical Software Standards v0.2.0*. No existe todavía categoría "survey/design-based" — hay oportunidad de contribuirla | 1-2 meses | Sello de calidad máximo |
| 6 | **R Consortium ISC grant** (financió `nonprobsvy`). Convocatorias periódicas | ~1 semana de escritura | Financiamiento real |
| 7 | Segundo paper **metodológico** (JSSAM o Survey Methodology) sobre la varianza recipe-aware, una vez hecha la validación cruzada | — | Alto, más lento |

**Advertencia sobre JOSS:** publicó `samplics`, pero rechaza envíos cuyo aporte
sea sustancialmente metodológico. weightflow lo es. Serviría *además de* otro
venue, no en lugar de.

---

## 5. Hoja de ruta propuesta

### 1.2.0 — cerrar (semanas)
- Alinear `DESCRIPTION` (1.2.0) con `NEWS.md`; resolver la discrepancia de
  autoría `DESCRIPTION` vs `inst/CITATION`.
- Precisar "GSBPM v5.2, sub-proceso 5.6" en reporte y documentación.
- Consolidar `trimming.Rmd` y `advanced-methods.Rmd`.
- PR a la awesome list.

### 1.3.0 — "auditable y reproducible" (1-2 meses)
1. **`spec_to_json()` / `spec_from_json()`** — serialización de la receta.
2. **Reproducibilidad exacta del bootstrap** (BUG-17, streams L'Ecuyer + tests
   bit a bit, incluyendo `cores` > 1).
3. **`report_weighting(compare = old_fit)`** — diff ola contra ola.
4. **Diagnóstico de balance** al estilo `cobalt`: SMD, ratio de varianzas, eCDF,
   en `summary()` y en el reporte.
5. **Bloque JSON embebido** en el reporte.
6. `weighting_alerts(as = "data.frame")` con enum de tipo y severidad, y
   `prep(on_alert = )` (Prioridad A de tu roadmap).
7. `check(spec)`: dry run sin estimar (Prioridad B).

### 1.4.0 — "el sesgo que no se ve" (2-3 meses)
1. **Índices SMUB / MUBP** y curva de sensibilidad en φ, en el reporte.
2. **`step_mass_impute()`** y estimador doblemente robusto con varianza correcta.
3. **`step_winsorize()`** para outliers de la variable de interés, diferenciado
   del trimming de pesos.
4. **Interoperar con `svrep`**: aceptar un `svyrep.design` como fuente de réplicas.
5. Benchmark de escala publicado.

### 2.0.0 — "calibración moderna" (6+ meses)
1. **Calibración por entropía generalizada** (`calfun = "entropy"`), con el puente
   documentado hacia entropy balancing.
2. **Calibración conjunta de totales y cuantiles**.
3. **Calibración regularizada con selección** (LASSO / elastic-net).
4. **`q`-weights** de Deville-Särndal.
5. **Totales de control con matriz de covarianza** (registros, enlaces), y
   propagación del error de enlace a la varianza. *Este es el que puede dar un
   paper metodológico propio.*
6. `logit` en `step_trim_calibrated()`; `by` + `reference_sample()` (F-11).

---

## 6. Bibliografía

Referencias verificadas vía búsqueda web en agosto de 2026. Las que ya están
citadas en el README y en `paper/paper.bib` no se repiten acá: lo que sigue es lo
**nuevo o faltante**, agrupado por la brecha que sustenta.

### 6.1 Muestras no probabilísticas e integración de datos (§A1)

- **Chen, Y., Li, P., & Wu, C. (2020).** Doubly Robust Inference With
  Nonprobability Survey Samples. *JASA*, 115(532), 2011-2021.
  DOI: 10.1080/01621459.2019.1677241 — *el marco canónico IPW + outcome model.
  Base teórica de `step_mass_impute()` y del estimador DR.*
- **Wu, C. (2022).** Statistical inference with non-probability survey samples.
  *Survey Methodology*, 48(2). Statistics Canada 12-001-X.
  https://www150.statcan.gc.ca/n1/pub/12-001-x/2022002/article/00002-eng.htm
  — *la revisión de referencia, con discusión de Lohr, Rao, Beaumont y otros en
  el mismo número. Leer también los comentarios: son un mapa del debate.*
- **Yang, S., & Kim, J. K. (2020).** Statistical data integration in survey
  sampling: a review. *Japanese Journal of Statistics and Data Science*, 3, 625-650.
  DOI: 10.1007/s42081-020-00093-w · arXiv:2001.03259
- **Yang, S., Kim, J. K., & Song, R. (2020).** Doubly robust inference when
  combining probability and non-probability samples with high-dimensional data.
  *JRSS-B*, 82(2), 445-465.
- **Elliott, M. R., & Valliant, R. (2017).** Inference for nonprobability samples.
  *Statistical Science*, 32(2), 249-264. — *ya citado como base de
  `step_pseudoweight()`; queda acá por completitud del bloque.*
- **Chrostowski, Ł., Chlebicki, P., & Beręsewicz, M. (2025).** nonprobsvy — An R
  package for modern methods for non-probability surveys. arXiv:2504.04255.
  — *el competidor/complemento directo en este frente.*
- **Cobo, B., Ferri-García, R., Rueda-Sánchez, J. L., & Rueda, M. (2024).**
  Software review for inference with non-probability surveys.
  *The Survey Statistician*, N90.
  https://isi-iass.org/home/wp-content/uploads/Survey_Statistician_2024_July_N90_06.pdf

### 6.2 Diagnóstico del sesgo residual (§A2)

- **Little, R. J. A., West, B. T., Boonstra, P. S., & Hu, J. (2020).** Measures of
  the Degree of Departure from Ignorable Sample Selection. *JSSAM*, 8(5), 932-964.
  https://academic.oup.com/jssam/article-abstract/8/5/932/5556334
  — **la referencia central de SMUB. Es el paper a implementar.**
- **Andridge, R. R., & Little, R. J. A. (2011).** Proxy pattern-mixture analysis
  for survey nonresponse. *Journal of Official Statistics*, 27(2), 153-180.
  — *el antecedente: el índice para no respuesta antes de generalizarse a
  selección no probabilística.*
- **Andridge, R. R., West, B. T., Little, R. J. A., Boonstra, P. S., &
  Alvarado-Leiton, F. (2019).** Indices of non-ignorable selection bias for
  proportions estimated from non-probability samples. *JRSS-C*, 68(5), 1465-1483.
  https://academic.oup.com/jrsssc/article/68/5/1465/7058617
  — *la versión para proporciones, que es el caso de uso típico (pobreza,
  desempleo).*
- **Schouten, B., Cobben, F., & Bethlehem, J. (2009).** Indicators for the
  representativeness of survey response. *Survey Methodology*, 35(1), 101-113.
  — *ya implementado (R-indicators); queda como ancla del bloque.*
- **Sarig, T., Galili, T., et al. (2023).** balance — a Python package for
  balancing biased data samples. arXiv:2307.06024.
  — *no es metodología nueva, pero fija el estándar visual de diagnóstico de
  balance (ASMD, KL, Earth Mover's, Cramér-von Mises) que conviene igualar.*

### 6.3 Calibración moderna (§A3)

- **Kwon, Y., Kim, J. K., & Qiu, Y. (2025).** Debiased Calibration Estimation
  Using Generalized Entropy in Survey Sampling. *JASA*.
  DOI: 10.1080/01621459.2025.2537452 · paquete `GECal`
  — **la novedad teórica del bienio en calibración.**
- **Beręsewicz, M. (2023).** A note on joint calibration estimators for totals and
  quantiles. arXiv:2308.13281 · paquete `jointCalib`
- **Harms, T., & Duchesne, P. (2006).** On calibration estimation for quantiles.
  *Survey Methodology*, 32(1), 37-52.
- **McConville, K. S., Breidt, F. J., Lee, T. C. M., & Moisen, G. G. (2017).**
  Model-Assisted Survey Regression Estimation with the Lasso. *JSSAM*, 5(2), 131-158.
  https://academic.oup.com/jssam/article/5/2/131/3775768 · paquete `mase`
- **Hainmueller, J. (2012).** Entropy balancing for causal effects. *Political
  Analysis*, 20(1), 25-46. — *el puente con la literatura causal.*
- **Kott, P. S.** — la teoría detrás de SUDAAN `WTADJUST` / `WTADJX`: ajuste por
  no respuesta **y** calibración en un mismo marco, con no respuesta NMAR y
  varianza que reconoce que los pesos fueron estimados. Es la referencia teórica
  más cercana a weightflow fuera del mundo R.
  https://www.rti.org/rti-press-publication/calibration-weighting-stratified-simple-random-sample-sudaan/fulltext.pdf

### 6.4 Estimación robusta (§A5)

- **Beaumont, J.-F., Haziza, D., & Ruiz-Gazen, A. (2013).** A unified approach to
  robust estimation in finite population sampling. *Biometrika*, 100(3), 555-569.
  https://academic.oup.com/biomet/article-abstract/100/3/555/302384
  — *el marco del sesgo condicional; base de un `step_winsorize()`.*
- **Beaumont, J.-F., & Rivest, L.-P. (2009).** Dealing with outliers in survey
  data. En *Handbook of Statistics* 29A, 247-279.
- Paquete `robsurvey` (Schoch) — M/GM-estimadores, winsorización, GREG robusto.
  **Diferenciar explícitamente su "weight trimming" del trimming de calibración
  de weightflow: hoy la nomenclatura se presta a confusión.**

### 6.5 Registros administrativos y error de enlace (§A4)

- **Scalable Generalised Accuracy Estimation for Multisource Register-based
  Official Statistics** (2025). arXiv:2502.10182.
  — *el estado del arte en medir exactitud cuando la fuente son registros
  múltiples.*
- **Moretti, A., et al. (2023).** Improving Probabilistic Record Linkage Using
  Statistical Prediction Models. *International Statistical Review*.
  DOI: 10.1111/insr.12535
- Statistics Canada, *Data integration* (2025), Methodology R&D Program.
  https://www150.statcan.gc.ca/n1/pub/12-206-x/2025001/01-eng.htm

### 6.6 Estadística oficial, software y estándares (§B, §C)

- **ten Bosch, O., & van der Loo, M. P. J. (2026).** Statistical open source
  software for official statistics: State of play and future directions.
  *Statistical Journal of the IAOS*, 42(1). DOI: 10.1177/18747655251411424
  — **la cita más importante de esta lista.** Cataloga 153 herramientas, propone
  siete principios (entre ellos "mejorar herramientas existentes antes que
  duplicar" — de ahí la recomendación de interoperar con `svrep`), y entre sus
  recomendaciones futuras figura *establecer mecanismos para propagar la
  incertidumbre a través de los pipelines estadísticos*: la tesis de weightflow,
  enunciada por terceros. **Va en la introducción del paper.**
- **UNECE (2025).** GSBPM v5.2. https://unece.org/statistics/gsbpm-v5.2 ·
  https://unece.github.io/GSBPM-5.2/ — *sub-proceso 5.6 "Calculate weights".*
- **UNECE.** GSIM 2.0. https://unece.github.io/GSIM-2.0/ — *vocabulario para
  describir la receta serializada: Process Step, Process Design, Rule, Parameter.*
- **UK Government Analysis Function.** Reproducible Analytical Pipelines strategy.
  https://analysisfunction.civilservice.gov.uk/policy-store/reproducible-analytical-pipelines-strategy/
  — *los siete criterios del "minimum viable RAP". weightflow cumple casi todos;
  la serialización de la receta cierra el que falta.*
- **Schneider, B. (2025).** Extensions of the survey package in R.
  *The Survey Statistician*, N91.
  https://isi-iass.org/home/wp-content/uploads/Survey_Statistician_2025_January_N91_06.pdf
  — *el autor de `svrep` explicando su propio nicho. Lectura obligatoria antes de
  escribir la sección de trabajo relacionado.*
- **Zardetto, D. (2015).** ReGenesees: an advanced R system for calibration,
  estimation and sampling error assessment in complex sample surveys.
  *Journal of Official Statistics*, 31(2), 177-203. DOI: 10.1515/jos-2015-0013
  — *el modelo de paper a imitar: software de INE publicado en JOS.*
- **Valliant, R., & Dever, J. A.** *Survey Weights: A Step-by-Step Guide to
  Calculation*. Stata Press. — *el libro cuya lógica weightflow implementa.
  Debería estar citado en el paper como tal.*
- **rOpenSci.** Statistical Software Standards v0.2.0.
  https://stats-devguide.ropensci.org/standards.html
  — exige tests de recuperación de parámetros, de condiciones límite y de
  susceptibilidad al ruido. No hay todavía una categoría "survey/design-based":
  oportunidad de contribuirla.
- **uRos2026** — París, 18-20 de noviembre de 2026, organizado por INSEE.
  Track de journal con envío hasta el **15-ene-2027**.
  https://r-project.ro/conference2026.html

### 6.7 Software a citar en "trabajo relacionado"

`survey` (Lumley) · `srvyr` · `svrep` (Schneider) · `surveysd` (Statistics
Austria) · `ReGenesees` (Istat) · `icarus` y `gustave` (INSEE) · `GECal` ·
`jointCalib` · `CalibrateSSB` (SSB) · `inca` · `nonprobsvy` · `NonProbEst` ·
`PracTools` · `robsurvey` · `mase` · `WeightIt` / `cobalt` (Greifer) ·
`metasurvey` (UdelaR) · `balance` (Meta, Python) · `svy` (ex-`samplics`, Python,
pre-alpha) · `ipfraking` (Stata) · SUDAAN `WTADJUST`/`WTADJX` · CALMAR2 (INSEE).

---

## 7. Las cinco cosas si sólo se pueden hacer cinco

1. **Serializar la receta a JSON/YAML.** Desbloquea auditoría, diff entre olas,
   GSIM y RAP de un solo golpe. Es la brecha que más limita la tesis del paquete.
2. **Reproducibilidad bit a bit del bootstrap** (BUG-17). Sin esto no hay INE.
3. **Índices SMUB + curva de sensibilidad en el reporte.** Alto retorno, bajo
   costo, y convierte el reporte en instrumento de decisión editorial.
4. **Validación cruzada publicada** contra `survey`, ReGenesees y CALMAR2.
   Es el requisito de entrada a cualquier INE.
5. **Reescribir la sección de trabajo relacionado** contrastando de frente con
   `svrep` y `surveysd`, y explorar aceptar réplicas de `svrep`. Convierte el
   principal riesgo de revisión en un argumento de interoperabilidad.
