# ORACULO ANALITICO INDEPENDIENTE: ReGenesees::svyDelta (Berger & Priam 2016).
#
# Hasta este archivo, la SE del cambio neto estaba validada solo CONTRA SI MISMA:
# wave_bootstrap() y wave_jackknife() son dos implementaciones de la MISMA idea
# --replicar y dejar que el solape aparezca como covarianza--, asi que un sesgo
# conceptual del enfoque de replicas las haria fallar juntas sin que nada lo note.
# svyDelta() es de otra familia: linealizacion analitica, la que usan Eurostat y
# la ONS. Aca sus resultados quedan CONGELADOS como numeros: weightflow NO depende
# de ReGenesees, ni siquiera en Suggests.
#
# Procedencia de las constantes: ReGenesees 2.4 (GitHub f92fdb5), R 4.5.1. Se
# reprodujeron identicas en dos maquinas independientes. El script que las genera
# es weightflow_pruebas/oraculo_cambio_vs_regenesees.R.
#
# Convencion: weightflow aparea UPM DENTRO del estrato, asi que una unidad que
# salta de estrato pierde la coordinacion. Eso es rho.STRAT = "noJump".
#
# El mismo archivo se lee de dos maneras, que ejercitan las dos rutas de varianza:
#   - por CONGLOMERADO: la UPM es `id` (20 UPM, 10 por estrato, 50 % de solape);
#   - por ELEMENTO: cada fila es su propia UPM (80 unidades, 50 % de solape).
#
# NOTA sobre muestras chicas. Con 3 UPM por estrato --el tamano del ejemplo
# Delta.clus que ReGenesees distribuye-- el estimador analitico de la covarianza
# se degenera (rho -> 0.97 cuando la correlacion del diseno es ~0.46) y la razon
# de SE se va a 6.5. Desde 5 UPM por estrato las dos familias vuelven a coincidir
# dentro del 2 %. Por eso la referencia se fija en un diseno con 10, no en el
# ejemplo de 3: ahi el que se rompe es el oraculo, no las replicas.

s1 <- structure(list(id = c(149, 149, 149, 149, 33, 33, 33, 33, 86, 
86, 86, 86, 100, 100, 100, 100, 74, 74, 74, 74, 130, 130, 130, 
130, 132, 132, 132, 132, 43, 43, 43, 43, 77, 77, 77, 77, 58, 
58, 58, 58, 394, 394, 394, 394, 364, 364, 364, 364, 345, 345, 
345, 345, 213, 213, 213, 213, 329, 329, 329, 329, 218, 218, 218, 
218, 389, 389, 389, 389, 276, 276, 276, 276, 211, 211, 211, 211, 
224, 224, 224, 224), strata = structure(c(1L, 1L, 1L, 1L, 1L, 
1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 
1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 
1L, 1L, 1L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 
2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 
2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L), levels = c("A", 
"B"), class = "factor"), w = c(20, 20, 20, 20, 20, 20, 20, 20, 
20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 
20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 
20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 
20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 
20, 20, 20, 20, 20, 20, 20, 20), y = c(6.925785, 8.44101, 5.185048, 
8.177433, 16.845831, 16.524624, 16.696886, 18.064488, 4.611558, 
3.434568, 2.482077, 3.775655, 11.237501, 11.959773, 12.505977, 
12.198359, 11.31246, 12.988006, 11.274215, 11.231444, 4.745349, 
4.80387, 4.265145, 4.925246, 8.533461, 6.973744, 8.433065, 7.434271, 
11.720135, 9.262875, 10.51341, 12.126907, 6.816319, 6.93679, 
8.41238, 6.481316, 4.197691, 5.635893, 6.170488, 5.541053, 5.46055, 
6.097991, 5.696695, 5.328911, 6.211015, 7.947981, 6.617979, 8.677886, 
8.881287, 9.605584, 7.776654, 9.109447, 8.871623, 10.537586, 
10.293779, 10.138739, 11.054349, 10.246464, 8.652474, 9.416444, 
14.178967, 13.17384, 11.849003, 11.717474, 13.526137, 14.657619, 
16.016092, 13.861296, 9.084204, 6.775846, 9.22715, 6.852149, 
13.433238, 13.734566, 13.695994, 13.316582, 13.064367, 12.389164, 
13.601856, 13.464508)), row.names = c(NA, -80L), class = "data.frame")

s2 <- structure(list(id = c(130, 130, 130, 130, 100, 100, 100, 100, 
77, 77, 77, 77, 86, 86, 86, 86, 149, 149, 149, 149, 211, 211, 
211, 211, 394, 394, 394, 394, 218, 218, 218, 218, 213, 213, 213, 
213, 276, 276, 276, 276, 53, 53, 53, 53, 59, 59, 59, 59, 94, 
94, 94, 94, 126, 126, 126, 126, 66, 66, 66, 66, 372, 372, 372, 
372, 309, 309, 309, 309, 234, 234, 234, 234, 359, 359, 359, 359, 
256, 256, 256, 256), strata = structure(c(1L, 1L, 1L, 1L, 1L, 
1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 2L, 
2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 
2L, 2L, 2L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 
1L, 1L, 1L, 1L, 1L, 1L, 1L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 
2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L), levels = c("A", 
"B"), class = "factor"), w = c(20, 20, 20, 20, 20, 20, 20, 20, 
20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 
20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 
20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 
20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 
20, 20, 20, 20, 20, 20, 20, 20), y = c(6.331681, 4.512372, 3.528795, 
4.720029, 12.379563, 12.582979, 12.019926, 12.22704, 7.037427, 
7.496422, 7.515287, 8.976979, 5.193369, 3.367137, 4.194803, 3.553399, 
6.893453, 6.80018, 7.680272, 4.851886, 12.379269, 12.817421, 
12.36834, 13.703478, 4.896785, 2.899149, 4.068609, 3.396293, 
12.224299, 9.698684, 13.613346, 14.243916, 11.877182, 12.025353, 
11.748518, 13.816111, 7.850471, 7.833941, 7.742122, 7.31436, 
9.309456, 8.934295, 10.577203, 8.455455, 9.305615, 8.018222, 
9.346139, 9.678077, 13.12563, 13.551469, 14.355504, 14.468481, 
8.183569, 8.298828, 9.486414, 7.052616, 5.671922, 6.156442, 6.81308, 
8.687648, 10.419253, 8.971241, 10.142185, 8.11032, 13.612287, 
11.145122, 12.430115, 11.800696, 14.773059, 16.004247, 15.34799, 
15.76711, 13.130983, 13.688839, 12.642851, 16.073742, 10.523274, 
10.07848, 8.517758, 8.376518)), row.names = c(NA, -80L), class = "data.frame")


# ReGenesees 2.4, rho.STRAT = "noJump", vartype = "se"
ORACULO <- list(
  clus = list(Delta = 107.3437, SE = 1228.6927378016, V1 = 1657245.30104,
              V2 = 1346953.34882, CoV = 747256.402966, rho = 0.500149650553),
  elem = list(Delta = 107.3437, SE = 636.7941813667,  V1 = 402992.57786,
              V2 = 336695.717005, CoV = 167090.732721, rho = 0.453612531366))

con_uid <- function(d) {
  d$uid <- d$id * 100L + stats::ave(seq_len(nrow(d)), d$id, FUN = seq_along)
  d
}
cambio <- function(a, b, psu) {
  sp <- function(z) weighting_spec(z, base_weights = w)
  change_total(wave_jackknife(list(T1 = sp(a), T2 = sp(b)), strata = "strata",
                              psu = psu, progress = FALSE), "y")
}

test_that("el punto del cambio coincide con svyDelta a precision de maquina", {
  skip_on_cran()
  for (caso in list(list(cambio(s1, s2, "id"), ORACULO$clus),
                    list(cambio(con_uid(s1), con_uid(s2), "uid"), ORACULO$elem)))
    expect_equal(caso[[1]]$estimate, caso[[2]]$Delta, tolerance = 1e-9)
})

test_that("V1 y V2 coinciden con la linealizacion analitica", {
  skip_on_cran()
  # Las varianzas de NIVEL no dependen de la coordinacion: si estas no dieran
  # iguales el problema seria del bootstrap de un periodo, no del panel.
  cj <- cambio(s1, s2, "id")
  expect_equal(cj$V1, ORACULO$clus$V1, tolerance = 1e-8)
  expect_equal(cj$V2, ORACULO$clus$V2, tolerance = 1e-8)
  ce <- cambio(con_uid(s1), con_uid(s2), "uid")
  expect_equal(ce$V1, ORACULO$elem$V1, tolerance = 1e-8)
  expect_equal(ce$V2, ORACULO$elem$V2, tolerance = 1e-8)
})

test_that("la covarianza inducida por el solape coincide dentro del 3 %", {
  skip_on_cran()
  # Aca esta lo que el test existe para probar: la covarianza NO sale de una
  # formula sino de que la misma UPM se borra en las dos olas a la vez.
  cj <- cambio(s1, s2, "id")
  expect_equal(cj$cov / ORACULO$clus$CoV, 1, tolerance = 0.03)
  expect_equal(cj$rho, ORACULO$clus$rho, tolerance = 0.03)
  ce <- cambio(con_uid(s1), con_uid(s2), "uid")
  expect_equal(ce$cov / ORACULO$elem$CoV, 1, tolerance = 0.03)
  expect_equal(ce$rho, ORACULO$elem$rho, tolerance = 0.03)
})

test_that("la SE del jackknife coordinado queda a menos del 2 % de la analitica", {
  skip_on_cran()
  cj <- cambio(s1, s2, "id")
  expect_lt(abs(cj$se / ORACULO$clus$SE - 1), 0.02)
  ce <- cambio(con_uid(s1), con_uid(s2), "uid")
  expect_lt(abs(ce$se / ORACULO$elem$SE - 1), 0.02)
  # y el solape efectivamente ahorra varianza en los dos casos
  expect_lt(cj$V, cj$V1 + cj$V2)
  expect_lt(ce$V, ce$V1 + ce$V2)
})

test_that("el bootstrap coordinado no contradice al oraculo", {
  skip_on_cran()
  # Con 20 UPM el bootstrap de reescalamiento es ruidoso: la exigencia es de
  # orden de magnitud y signo de la correlacion, no de segundo decimal.
  sp <- function(z) weighting_spec(z, base_weights = w)
  wb <- wave_bootstrap(list(T1 = sp(s1), T2 = sp(s2)), replicates = 400L,
                       strata = "strata", psu = "id", seed = 7L, progress = FALSE)
  cb <- change_total(wb, "y")
  expect_equal(cb$estimate, ORACULO$clus$Delta, tolerance = 1e-9)
  expect_gt(cb$se / ORACULO$clus$SE, 0.6)
  expect_lt(cb$se / ORACULO$clus$SE, 1.6)
})
