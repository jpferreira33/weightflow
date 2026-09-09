# report_panel(): assembles the four panel cards (structure/rotation, change variance,
# attrition/retention, gross flows) into a standalone HTML file. Any object may be NULL.

test_that("report_panel writes an HTML file with the supplied cards", {
  skip_on_cran()
  pd <- panel_design(panel_ine, unit = c("id_hogar", "nper"), wave = "ola",
                     rotation_group = "grupo_rotacion", pattern = "6")
  wb <- wave_bootstrap(
    list(T1 = weighting_spec(subset(panel_ine, ola == 1 & disp == "R"), base_weights = w_base),
         T2 = weighting_spec(subset(panel_ine, ola == 2 & disp == "R"), base_weights = w_base)),
    replicates = 60, strata = "estrato", psu = "psu", seed = 1, progress = FALSE)
  ch <- change_mean(wb, "desocupado")

  wide <- panel_merge(list(T1 = panel_ine[panel_ine$ola == 1, ], T2 = panel_ine[panel_ine$ola == 2, ]),
                      by = c("id_hogar", "nper"), require = "all")
  wide$e1 <- ifelse(is.na(wide$ocupado_T1), "inact", ifelse(wide$ocupado_T1 == 1, "ocup", "desoc"))
  wide$e2 <- ifelse(is.na(wide$ocupado_T2), "inact", ifelse(wide$ocupado_T2 == 1, "ocup", "desoc"))
  fit <- prep(weighting_spec(wide, base_weights = w_base_T1) |>
                step_drop_ineligible(disp_T2 == "OS") |>
                step_attrition(respondent = disp_T2 == "R", method = "weighting_class", by = "region_T1"))
  tr <- transition_matrix(fit, "e1", "e2", format = "row")   # plain (no bootstrap) -> no SE shown
  blong <- bootstrap_weights(weighting_spec(wide, base_weights = w_base_T1) |>
                               step_drop_ineligible(disp_T2 == "OS") |>
                               step_attrition(respondent = disp_T2 == "R", method = "weighting_class", by = "region_T1"),
                             replicates = 40, strata = "estrato_T1", psu = "psu_T1", seed = 1, progress = FALSE)

  f <- report_panel(design = pd, change = ch, longitudinal = fit, transition = tr,
                    variance = blong, file = tempfile(fileext = ".html"), open = FALSE, lang = "en")
  expect_true(file.exists(f))
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_match(html, "Replicate weights for variance created")   # variance card present (not the "not created" cross)
  expect_false(grepl("<td[^>]*>[0-9.]+ <span class='muted'>\\(", html))  # plain transition -> no per-cell SE
  # longitudinal given -> full weighting report of the longitudinal weight + panel section
  expect_match(html, "Panel / longitudinal")     # the injected panel section
  expect_match(html, "Per-stage summary|Resumen")# the base report's cascade is present
  expect_match(html, "Panel structure")          # card 1
  expect_match(html, "Net change variance")      # card 2
  expect_match(html, "retention|Retained")       # card 3
  expect_match(html, "Gross flows")              # card 4
  expect_match(html, "<svg")                     # inline visualisations rendered
  expect_match(html, "<path")                    # the Sankey ribbons
})

test_that("report_panel adapts to whichever objects are given (and needs at least one)", {
  pd <- panel_design(panel_cl, unit = c("id_hogar", "nper"), wave = "ola",
                     rotation_group = "grupo_rotacion")
  f <- report_panel(design = pd, file = tempfile(fileext = ".html"), open = FALSE)
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_match(html, "Panel structure")
  expect_false(grepl("Net change variance", html))   # change card skipped
  expect_error(report_panel(open = FALSE), "at least one")
})

test_that("report_panel valida la clase de cada argumento (no reporte vacio silencioso, auditoria A5)", {
  pd <- panel_design(panel_cl, unit = c("id_hogar", "nper"), wave = "ola",
                     rotation_group = "grupo_rotacion")
  # el bug historico: pasar un objeto de clase equivocada como `design` -> tarjeta "" ->
  # HTML vacio pero "valido". Ahora falla fuerte, sin escribir nada.
  expect_error(report_panel(design = data.frame(x = 1), file = tempfile(fileext = ".html"),
                            open = FALSE), "`design` must be")
  # cada slot rechaza la clase equivocada (pd es un design, no un change ni un coordinated)
  expect_error(report_panel(change = pd, file = tempfile(fileext = ".html"), open = FALSE),
               "`change` must be")
  # `coordinated` es suplementario: hay que darle un primario valido para pasar el guard
  # de "al menos uno" y llegar a la validacion de clase de `coordinated`.
  expect_error(report_panel(design = pd, coordinated = pd, file = tempfile(fileext = ".html"),
                            open = FALSE), "`coordinated` must be")
  # y el objeto correcto sigue funcionando
  expect_true(file.exists(
    report_panel(design = pd, file = tempfile(fileext = ".html"), open = FALSE)))
})
