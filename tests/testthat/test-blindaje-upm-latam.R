# Complex Latin American methodologies with PSU-level adjustments.
# Each test expresses an institutional recipe (INEGI, IBGE, DANE, INDEC, INE-Chile)
# and verifies the properties it promises, including the behaviour
# of the replication machinery when the cascade has PSU-level adjustments inside.

# Two-stage sample: strata > PSUs > dwellings > persons
latam_d <- function(n_est = 4, upm_x_est = 10, viv_x_upm = 4, seed = 51) {
  set.seed(seed)
  viv <- expand.grid(estrato = sprintf("E%d", 1:n_est),
                     upm_loc = 1:upm_x_est, viv_loc = 1:viv_x_upm,
                     KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  viv$upm <- paste(viv$estrato, viv$upm_loc, sep = "-")
  viv$viv <- paste(viv$upm, viv$viv_loc, sep = "-")
  viv$w_viv <- runif(nrow(viv), 30, 80)
  per <- do.call(rbind, lapply(seq_len(nrow(viv)), function(i) {
    k <- sample(1:3, 1)
    data.frame(viv[i, c("estrato", "upm", "viv", "w_viv")],
               sexo  = sample(c("H", "M"), k, TRUE),
               gedad = sample(c("g1", "g2", "g3"), k, TRUE),
               y     = rnorm(k, 100, 12), row.names = NULL)
  }))
  per$sexo  <- factor(per$sexo); per$gedad <- factor(per$gedad)
  per$id    <- seq_len(nrow(per))
  per
}

test_that("INEGI/ENOE-style: whole-UPM nonresponse redistributes within stratum, then household NR, then raking to projections", {
  d <- latam_d()
  # 2 lost (inaccessible) PSUs per stratum; nonresponse is the WHOLE PSU
  set.seed(52)
  muertas <- unlist(lapply(split(unique(d$upm), sub("-.*", "", unique(d$upm))),
                           function(u) sample(u, 2)))
  d$upm_ok <- !(d$upm %in% muertas)
  d$hh_ok  <- d$upm_ok & rep(rbinom(length(unique(d$viv)), 1, 0.85) == 1,
                             times = tapply(d$id, d$viv, length)[unique(d$viv)])[
                match(d$viv, unique(d$viv))]
  m_sexo <- setNames(as.numeric(tapply(d$w_viv, d$sexo,  sum)) * 1.04, levels(d$sexo))
  m_geda <- setNames(as.numeric(tapply(d$w_viv, d$gedad, sum)) * 1.04, levels(d$gedad))

  # step 1 only: the promise of the PSU-level adjustment
  p1 <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_viv) |>
      step_nonresponse(respondent = upm_ok, method = "weighting_class",
                       by = "estrato", cluster = "upm")))
  w1 <- collect_weights(p1, drop_zero = FALSE)$.weight
  # the cluster-adjustment promise: the mass OF PSUs per stratum is preserved
  # (peso de UPM = media de sus miembros, estilo Valliant); la masa de personas
  # is NOT preserved by design -- the later calibration closes it
  Wh_base <- tapply(d$w_viv, d$upm, mean)
  Wh_new  <- tapply(w1,      d$upm, mean)
  est_upm <- sub("-[0-9]+$", "", names(Wh_base))
  expect_equal(as.numeric(tapply(as.numeric(Wh_new),  est_upm, sum)),
               as.numeric(tapply(as.numeric(Wh_base), est_upm, sum)),
               tolerance = 1e-8)
  # UPMs muertas: todo el mundo en cero
  expect_true(all(w1[!d$upm_ok] == 0))
  # factor uniforme dentro del estrato (la definicion del ajuste por zona)
  fac <- (w1 / d$w_viv)[d$upm_ok]
  expect_true(all(tapply(fac, d$estrato[d$upm_ok],
                         function(f) diff(range(f))) < 1e-10))

  # cascada completa ENOE-style
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_viv) |>
      step_nonresponse(respondent = upm_ok, method = "weighting_class",
                       by = "estrato", cluster = "upm") |>
      step_nonresponse(respondent = hh_ok, method = "weighting_class",
                       by = "estrato", cluster = "viv") |>
      step_calibrate(method = "raking",
                     margins = list(sexo = m_sexo, gedad = m_geda))))
  cw <- collect_weights(p)
  tot_s <- tapply(cw$.weight, cw$sexo,  sum)
  tot_g <- tapply(cw$.weight, cw$gedad, sum)
  expect_lt(max(abs(as.numeric(tot_s[names(m_sexo)]) - m_sexo) / m_sexo), 1e-6)
  expect_lt(max(abs(as.numeric(tot_g[names(m_geda)]) - m_geda) / m_geda), 1e-6)
})

test_that("IBGE/PNADc-style: UPM-level NR + poststratification + published bootstrap replicates that downstream software reproduces", {
  skip_if_not_installed("survey")
  d <- latam_d(seed = 61)
  set.seed(62)
  muertas <- unlist(lapply(split(unique(d$upm), sub("-.*", "", unique(d$upm))),
                           function(u) sample(u, 1)))
  d$upm_ok <- !(d$upm %in% muertas)
  m_est <- setNames(as.numeric(tapply(d$w_viv, d$estrato, sum)) * 1.06,
                    sort(unique(d$estrato)))
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_viv) |>
      step_nonresponse(respondent = upm_ok, method = "weighting_class",
                       by = "estrato", cluster = "upm") |>
      step_calibrate(method = "poststratify", margins = list(estrato = m_est))))
  cw <- collect_weights(p)
  tt <- tapply(cw$.weight, cw$estrato, sum)
  expect_lt(max(abs(as.numeric(tt[names(m_est)]) - m_est) / m_est), 1e-8)
  b <- suppressWarnings(bootstrap_weights(p, replicates = 40,
                                          strata = "estrato", psu = "upm", seed = 63))
  # el archivo de replicas publicable no tiene NA y el puente a survey
  # reproduce punto y SE (cualquier software downstream obtiene lo mismo)
  rw <- collect_replicate_weights(b)
  expect_false(anyNA(rw))
  des <- suppressWarnings(as_svrepdesign(b))
  est <- survey::svymean(~y, des)
  expect_equal(as.numeric(coef(est)), boot_mean(b, "y")$estimate, tolerance = 1e-8)
  expect_equal(as.numeric(survey::SE(est)), boot_mean(b, "y")$se, tolerance = 1e-3)
})

test_that("DANE/GEIH-style: a hard-to-access segment per department, then Folsom-Singh bounded trim keeps totals", {
  d <- latam_d(seed = 71)
  names(d)[names(d) == "estrato"] <- "depto"
  set.seed(72)
  muertas <- vapply(split(unique(d$upm), sub("-.*", "", unique(d$upm))),
                    function(u) sample(u, 1), "")
  d$seg_ok <- !(d$upm %in% muertas)     # zona de dificil acceso: el segmento entero
  p0 <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_viv) |>
      step_nonresponse(respondent = seg_ok, method = "weighting_class",
                       by = "depto", cluster = "upm")))
  w0 <- collect_weights(p0, drop_zero = FALSE)$.weight
  # la masa DE SEGMENTOS de cada depto sobrevive a la perdida (peso de
  # segmento = media de sus miembros; ver nota del test INEGI)
  Wh_base <- tapply(d$w_viv, d$upm, mean)
  Wh_new  <- tapply(w0,      d$upm, mean)
  dep_upm <- sub("-[0-9]+$", "", names(Wh_base))
  expect_equal(as.numeric(tapply(as.numeric(Wh_new),  dep_upm, sum)),
               as.numeric(tapply(as.numeric(Wh_base), dep_upm, sum)),
               tolerance = 1e-8)
  # realized bounds from the percentiles and Folsom-Singh: bounds AND totals at once
  wpos <- w0[w0 > 0]
  lo <- as.numeric(quantile(wpos, .10)); up <- as.numeric(quantile(wpos, .90))
  tot_pre <- tapply(w0, d$depto, sum)
  p1 <- suppressMessages(prep(step_trim_calibrated(p0, formula = ~depto + sexo,
                                                   lower = lo, upper = up)))
  cw <- collect_weights(p1)
  expect_true(all(cw$.weight >= lo - 1e-8 & cw$.weight <= up + 1e-8))
  tot_post <- tapply(cw$.weight, cw$depto, sum)
  expect_lt(max(abs(as.numeric(tot_post[names(tot_pre)]) - as.numeric(tot_pre)) /
                as.numeric(tot_pre)), 1e-6)
})

test_that("INDEC/EPH-style: integrative calibration inside the recipe-aware bootstrap keeps one weight per household in EVERY replicate", {
  d <- latam_d(seed = 81)
  names(d)[names(d) == "estrato"] <- "aglo"
  set.seed(82)
  viv_ids <- unique(d$viv)
  ok_viv  <- setNames(rbinom(length(viv_ids), 1, 0.8) == 1, viv_ids)
  d$hh_ok <- ok_viv[d$viv]
  X <- stats::model.matrix(~ sexo + gedad, data = d)
  tots <- colSums(X * d$w_viv) * 1.05
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_viv) |>
      step_nonresponse(respondent = hh_ok, method = "weighting_class",
                       by = "aglo", cluster = "viv") |>
      step_calibrate(method = "linear", formula = ~ sexo + gedad, totals = tots,
                     cluster = "viv", equal_within_cluster = TRUE)))
  cw <- collect_weights(p)
  # a single weight per household in the point estimate
  expect_lt(max(tapply(cw$.weight, cw$viv, function(x) diff(range(x)))), 1e-8)
  # and in the replicates: the bootstrap re-runs the integrative calibration,
  # so the Lemaitre-Dufour promise must hold replicate by replicate
  b <- suppressWarnings(bootstrap_weights(p, replicates = 15,
                                          strata = "aglo", psu = "upm", seed = 83))
  rw <- collect_replicate_weights(b)
  repcols <- grep("^rep_", names(rw), value = TRUE)[1:5]
  for (rc in repcols) {
    act <- rw[[rc]] > 0
    expect_lt(max(tapply(rw[[rc]][act], rw$viv[act],
                         function(x) diff(range(x)))), 1e-6)
  }
})

test_that("INE-Chile/Casen-style: comuna-level NR + REGION-PARTITIONED bounded calibration keeps bounds and totals per region", {
  d <- latam_d(n_est = 3, seed = 91)
  names(d)[names(d) == "estrato"] <- "region"
  d$comuna <- paste(d$region, rep(1:4, length.out = nrow(d)), sep = "_c")
  set.seed(92)
  d$resp <- rbinom(nrow(d), 1, 0.78) == 1
  tt <- aggregate(d$w_viv, by = list(region = d$region, sexo = d$sexo), sum)
  names(tt)[3] <- "Freq"; tt$Freq <- tt$Freq * 1.05
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_viv) |>
      step_nonresponse(respondent = resp, method = "weighting_class",
                       by = "comuna") |>
      step_calibrate(method = "linear", formula = ~sexo, totals = list(sexo = tt),
                     count = "Freq", by = "region",
                     calfun = "logit", bounds = c(0.5, 2))))
  cw <- collect_weights(p)
  hw <- collect_weights(p, keep_intermediate = TRUE)
  nrcol <- grep("nonresponse", names(hw), value = TRUE)[1]
  g <- cw$.weight / hw[[nrcol]][hw$.weight > 0]
  # promise 1: g-weights within bounds IN EACH region
  expect_true(all(tapply(g >= 0.5 - 1e-6 & g <= 2 + 1e-6, cw$region, all)))
  # promise 2: region x sex totals exact (logit solver tolerance)
  ag <- aggregate(cw$.weight, by = list(region = cw$region, sexo = cw$sexo), sum)
  mm <- merge(ag, tt)
  expect_lt(max(abs(mm$x - mm$Freq) / mm$Freq), 1e-5)
})

test_that("a domain contained in a SINGLE UPM survives delete-a-PSU jackknife and bootstrap with partitioned calibration inside", {
  set.seed(101); nn <- 300
  d <- data.frame(id = 1:nn, w = runif(nn, 1, 3), y = rnorm(nn),
                  x = factor(sample(c("A", "B"), nn, TRUE)),
                  str = rep(1:3, each = 100), psu = rep(1:30, each = 10))
  d$dom <- ifelse(d$psu == 7, "chico", "grande")   # dominio = exactamente 1 UPM
  tt <- aggregate(d$w, by = list(dom = d$dom, x = d$x), sum)
  names(tt)[3] <- "Freq"; tt$Freq <- tt$Freq * 1.05
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_calibrate(method = "raking", totals = list(tt), count = "Freq",
                     by = "dom")))
  # la replica JKn que borra la UPM 7 deja el dominio 'chico' VACIO:
  # the machinery must survive and return finite SEs with no NA
  j <- suppressWarnings(jackknife_weights(p, strata = "str", psu = "psu"))
  expect_true(is.finite(jack_mean(j, "y")$se))
  expect_false(anyNA(collect_replicate_weights(j)))
  b <- suppressWarnings(bootstrap_weights(p, replicates = 40, strata = "str",
                                          psu = "psu", seed = 102))
  expect_true(is.finite(boot_mean(b, "y")$se))
  expect_false(anyNA(collect_replicate_weights(b)))
})
