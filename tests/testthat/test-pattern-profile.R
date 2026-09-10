# El perfil de solape se deriva de un CALENDARIO de rotacion, no de leer el primer bloque.
# El parser anterior devolvia (n1-1)/n1, lo que fallaba de tres formas: los patrones con mas de
# tres bloques no parseaban (NULL, y entonces PN-01 no existia para ellos), (n_i-1)/n_i no es el
# solape adyacente cuando hay mas de un bloque, y n_groups confundia "grupos en muestra" con
# "largo del ciclo". Estos tests fijan las tres correcciones y la alerta que habilitan.

test_that("las dos notaciones describen el mismo diseno", {
  eq <- function(a, b) {
    ra <- weightflow:::.wf_pattern_overlap(a); rb <- weightflow:::.wf_pattern_overlap(b)
    expect_equal(ra$profile, rb$profile, info = paste(a, "vs", b))
    expect_equal(ra$periods, rb$periods); expect_equal(ra$cycle, rb$cycle)
  }
  eq("2-(2)-2", "2-2-2")                     # los parentesis son notacion, no semantica
  eq("4-(8)-4", "4-8-4")
  eq("2(2)2",   "2-(2)-2")                   # CEPAL n(m)k  ==  EU-LFS por bloques
  eq("4(8)2",   "4-(8)-4")
  eq("1(2)5",   "1-(2)-1-(2)-1-(2)-1-(2)-1") # PNAD Continua
})

test_that("el perfil reproduce los valores publicados de cada esquema", {
  p <- function(x, n = 6L) unname(weightflow:::.wf_pattern_overlap(x)$profile[seq_len(n)])
  expect_equal(p("6"),       c(5, 4, 3, 2, 1, 0) / 6)          # LFS Canada / ECH del INE
  expect_equal(p("8"),       c(7, 6, 5, 4, 3, 2) / 8)
  expect_equal(p("2-(2)-2"), c(0.50, 0.00, 0.25, 0.50, 0.25, 0.00))  # hueco en L=2
  expect_equal(p("4-(8)-4"), c(0.75, 0.50, 0.25, 0.00, 0.00, 0.00))  # CPS
  # el interanual puede pesar tanto como el adyacente: en 2-(2)-2, L=4 == L=1
  pr <- weightflow:::.wf_pattern_overlap("2-(2)-2")$profile
  expect_equal(unname(pr[["4"]]), unname(pr[["1"]]))
})

test_that("(n-1)/n NO es el solape adyacente cuando hay mas de un bloque", {
  # 3-(1)-2: cinco periodos en muestra (0,1,2,4,5) y tres pares consecutivos -> 3/5, no 2/3.
  # El parser viejo devolvia 0.667 y sobreestimaba un 11 %.
  r <- weightflow:::.wf_pattern_overlap("3-(1)-2")
  expect_equal(r$overlap, 0.60)
  expect_false(isTRUE(all.equal(r$overlap, 2 / 3)))
  expect_equal(weightflow:::.wf_pattern_overlap("3-(2)-2")$overlap, 0.60)
  expect_equal(r$periods, c(0L, 1L, 2L, 4L, 5L))
})

test_that("los patrones no contiguos parsean, y su solape adyacente es CERO", {
  # Aca es donde el parser viejo devolvia NULL y PN-01 no se disparaba nunca -- justo el caso
  # en que mas falta hace, porque con solape teorico 0 en el rezago 1 no hay forma de
  # distinguir "el diseno es asi" de "la clave de enlace esta rota".
  a <- weightflow:::.wf_pattern_overlap("1-(3)-1-(3)-1-(3)-1")
  expect_false(is.null(a))
  expect_equal(a$overlap, 0)
  expect_equal(unname(a$profile[["4"]]), 0.75)
  expect_equal(a$lags, c(4L, 8L, 12L))                   # solo los rezagos multiplo de 4
  b <- weightflow:::.wf_pattern_overlap("1(2)5")         # PNAD
  expect_equal(b$overlap, 0)
  expect_equal(unname(b$profile[["3"]]), 0.80)
  expect_equal(b$lags, c(3L, 6L, 9L, 12L))
})

test_that("n_in y cycle son numeros distintos y estan nombrados por lo que son", {
  r <- weightflow:::.wf_pattern_overlap("2-(2)-2")
  expect_equal(r$n_in, 4L)      # grupos simultaneamente EN MUESTRA
  expect_equal(r$cycle, 6L)     # largo del ciclo: los grupos distintos que existen
  s <- weightflow:::.wf_pattern_overlap("6")
  expect_equal(s$n_in, 6L); expect_equal(s$cycle, 6L)    # contiguo: coinciden
  expect_equal(weightflow:::.wf_pattern_overlap("4(0)1")$n_in, 4L)  # CEPAL: k es repeticiones
  expect_equal(weightflow:::.wf_pattern_overlap("4(0)1")$cycle, 4L)
})

test_that("una entrada que no es un patron devuelve NULL en vez de un numero inventado", {
  for (x in list(NULL, NA_character_, "", "abc", c("6", "8"), 6))
    expect_null(weightflow:::.wf_pattern_overlap(x))
})

test_that("PN-01 se evalua sobre el perfil completo, no solo sobre el rezago 1", {
  skip_on_cran()
  # El caso que el parser viejo no podia ni mirar: "1-(3)-1-(3)-1-(3)-1" tiene solape CERO en
  # los rezagos 1 a 3 y 0.75 en el 4. Un chequeo solo-adyacente no dice absolutamente nada de
  # este diseno; el perfil completo si.
  W <- 5L
  # enlace sano: las unidades vuelven en el rezago 4 (olas 1 y 5), como manda el patron
  bien <- rbind(data.frame(id = 1:200, ola = 1L), data.frame(id = 201:400, ola = 2L),
                data.frame(id = 401:600, ola = 3L), data.frame(id = 601:800, ola = 4L),
                data.frame(id = 1:200,   ola = 5L))
  al_ok <- attr(panel_design(bien, unit = "id", wave = "ola",
                             pattern = "1-(3)-1-(3)-1-(3)-1"), "wf_panel")$alerts
  expect_false(any(grepl("PN-01", al_ok)))

  # clave rota: nadie vuelve en el rezago 4 (ids todos distintos)
  roto <- do.call(rbind, lapply(seq_len(W), function(k)
    data.frame(id = (k - 1L) * 1000L + 1:200, ola = k)))
  al_bad <- attr(panel_design(roto, unit = "id", wave = "ola",
                              pattern = "1-(3)-1-(3)-1-(3)-1"), "wf_panel")$alerts
  expect_true(any(grepl("PN-01", al_bad)))
  expect_true(any(grepl("lag 4", al_bad)))   # reporta el rezago culpable, que no es el 1
})

test_that("PN-07 marca el solape que el patron prohibe, y solo con un ciclo observado", {
  skip_on_cran()
  # ciclo 6, ventana de 8 olas: la contradiccion es verificable
  d8 <- do.call(rbind, lapply(1:8, function(k) data.frame(id = 1:200, ola = k, g = rep(1:4, 50))))
  a8 <- attr(panel_design(d8, unit = "id", wave = "ola", rotation_group = "g",
                          pattern = "2-2-2"), "wf_panel")$alerts
  expect_true(any(grepl("PN-07", a8)))
  expect_true(any(grepl("lag 2", a8)))
  # la misma contradiccion con una ventana MAS CORTA que el ciclo no se puede afirmar: el perfil
  # describe un regimen estacionario al que el panel no llego. panel_cl es ese caso.
  d3 <- do.call(rbind, lapply(1:3, function(k) data.frame(id = 1:200, ola = k, g = rep(1:4, 50))))
  a3 <- attr(panel_design(d3, unit = "id", wave = "ola", rotation_group = "g",
                          pattern = "2-2-2"), "wf_panel")$alerts
  expect_false(any(grepl("PN-07", a3)))
  expect_false(any(grepl("PN-07", attr(panel_design(
    panel_cl, unit = c("id_hogar", "nper"), wave = "ola",
    rotation_group = "grupo_rotacion", pattern = "2-2-2"), "wf_panel")$alerts)))
})

test_that("el objeto expone el perfil y los rezagos utiles", {
  skip_on_cran()
  p <- attr(panel_design(panel_ine, unit = c("id_hogar", "nper"), wave = "ola",
                         rotation_group = "grupo_rotacion", pattern = "6"), "wf_panel")
  expect_equal(unname(p$overlap_profile[1:5]), c(5, 4, 3, 2, 1) / 6)
  expect_equal(p$pattern_n_in, 6L)
  expect_equal(p$pattern_cycle, 6L)
  expect_equal(p$pattern_lags, 1:5)
  expect_equal(length(p$pr_lag), length(p$waves) - 1L)
  expect_equal(length(p$obs_lag), length(p$waves) - 1L)
})
