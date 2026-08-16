# Hardening: African and European NSO methodologies.
# DHS (normalized weights), Stats SA QLFS (bounded calibration), Mikrozensus
# (integrative AND bounded at once), ESS (poststrat + trim at 4x), and the
# general integrative promise when base weights vary within the household.

afr_d <- function(n_cl = 40, seed = 301) {
  set.seed(seed)
  cl <- data.frame(cluster = 1:n_cl,
                   region  = factor(rep(c("Norte", "Centro", "Sur", "Este"),
                                        each = n_cl / 4)),
                   w_cl    = runif(n_cl, 15, 45))
  d <- do.call(rbind, lapply(seq_len(n_cl), function(i) {
    k <- sample(18:26, 1)                       # ~22 hogares por conglomerado (DHS)
    data.frame(cl[i, ], hogar = paste(i, 1:k, sep = "_"),
               sexo = factor(sample(c("H", "M"), k, TRUE)),
               edad = factor(sample(c("15-29", "30-49", "50+"), k, TRUE)),
               y = rnorm(k, 55, 9), row.names = NULL)
  }))
  d$id   <- seq_len(nrow(d))
  d$resp <- rbinom(nrow(d), 1, 0.88) == 1
  d
}

test_that("DHS-style recipe: cluster design + NR + NORMALIZED weights (mean 1), and estimates are invariant to the normalization", {
  d <- afr_d()
  p_raw <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_cl) |>
      step_nonresponse(respondent = resp, method = "weighting_class",
                       by = "region")))
  p_dhs <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_cl) |>
      step_nonresponse(respondent = resp, method = "weighting_class",
                       by = "region") |>
      step_rescale(to = "n")))
  cw <- collect_weights(p_dhs)
  # the DHS signature: mean exactly 1, sum = number of respondents
  expect_equal(mean(cw$.weight), 1, tolerance = 1e-10)
  expect_equal(sum(cw$.weight), nrow(cw), tolerance = 1e-8)
  # la normalizacion NO cambia nada relativo: mismas medias ponderadas
  cwr <- collect_weights(p_raw)
  expect_equal(sum(cw$.weight * cw$y) / sum(cw$.weight),
               sum(cwr$.weight * cwr$y) / sum(cwr$.weight), tolerance = 1e-10)
  # y el deff es invariante a la escala
  expect_equal(design_effect(cw$.weight)$deff,
               design_effect(cwr$.weight)$deff, tolerance = 1e-10)
})

test_that("Stats-SA/QLFS-style: two-stage NR then BOUNDED calibration to province x sex, bounds and totals both hold", {
  d <- afr_d(seed = 311)
  names(d)[names(d) == "region"] <- "prov"
  d$resp_h <- rbinom(nrow(d), 1, 0.9) == 1        # segunda fase (individuo)
  X  <- stats::model.matrix(~ prov + sexo, d)
  tt <- colSums(X * d$w_cl) * 1.04
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_cl) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = "prov") |>
      step_nonresponse(respondent = resp_h, method = "weighting_class",
                       by = c("prov", "sexo")) |>
      step_calibrate(method = "linear", formula = ~ prov + sexo, totals = tt,
                     calfun = "logit", bounds = c(0.6, 1.9))))
  cw <- collect_weights(p)
  hw <- collect_weights(p, keep_intermediate = TRUE)
  nrcols <- grep("nonresponse", names(hw), value = TRUE)
  g <- cw$.weight / hw[[nrcols[length(nrcols)]]][hw$.weight > 0]
  expect_true(all(g >= 0.6 - 1e-6 & g <= 1.9 + 1e-6))
  ach <- colSums(cw$.weight * X[collect_weights(p, drop_zero = FALSE)$.weight > 0, , drop = FALSE])
  expect_lt(max(abs(ach - tt) / abs(tt)), 1e-4)   # tolerancia del solver logit
})

test_that("Mikrozensus-style: integrative AND bounded at once -- one weight per household, g in bounds, totals hit", {
  d <- afr_d(seed = 321)
  # base weights CONSTANT within household (household weight, as in practice);
  # here each row is a household, so we build persons within the household
  per <- do.call(rbind, lapply(seq_len(nrow(d)), function(i) {
    k <- sample(1:4, 1)
    data.frame(d[i, c("hogar", "region", "w_cl")],
               sexo = factor(sample(c("H", "M"), k, TRUE)), row.names = NULL)
  }))
  per$id <- seq_len(nrow(per))
  X  <- stats::model.matrix(~ region + sexo, per)
  tt <- colSums(X * per$w_cl) * 1.05
  p <- suppressMessages(prep(
    weighting_spec(per, base_weights = w_cl) |>
      step_calibrate(method = "linear", formula = ~ region + sexo, totals = tt,
                     cluster = "hogar", equal_within_cluster = TRUE,
                     calfun = "logit", bounds = c(0.5, 2))))
  cw <- collect_weights(p)
  # promise 1: one weight per household (base weights were constant within it)
  expect_lt(max(tapply(cw$.weight, cw$hogar, function(x) diff(range(x)))), 1e-8)
  # promise 2: the household g-factor respects the bounds
  g_h <- tapply(cw$.weight / cw$w_cl, cw$hogar, function(x) x[1])
  expect_true(all(g_h >= 0.5 - 1e-6 & g_h <= 2 + 1e-6))
  # promise 3: person totals are reproduced (logit tolerance)
  ach <- colSums(cw$.weight * X[match(cw$id, per$id), , drop = FALSE])
  expect_lt(max(abs(ach - tt) / abs(tt)), 1e-4)
})

test_that("person-varying base weights with equal_within_cluster now ERROR (2026-08 decision)", {
  # Previously this ran, producing one g-FACTOR per household (members kept
  # DIFFERENT weights) with an inexactness warning. Design decision 2026-08:
  # `equal_within_cluster` promises ONE WEIGHT per cluster, which is undefined
  # when the incoming base weights already differ within a cluster -> hard error
  # pointing at the upstream step, instead of silently per-member-varying weights.
  set.seed(331); n <- 400
  d <- data.frame(id = 1:n, sexo = factor(sample(c("H", "M"), n, TRUE)),
                  hogar = rep(1:(n / 2), each = 2), w = runif(n, 5, 20))
  X  <- stats::model.matrix(~sexo, d)
  tt <- colSums(X * d$w) * 1.04
  expect_error(suppressMessages(prep(
    weighting_spec(d, base_weights = w) |>
      step_calibrate(method = "linear", formula = ~sexo, totals = tt,
                     cluster = "hogar", equal_within_cluster = TRUE))),
    "constant within|one weight per cluster")
})

test_that("ESS-style: design weights + poststratification + trim at 4x the mean, mass preserved and cap held", {
  d <- afr_d(seed = 341)
  m_reg <- setNames(as.numeric(tapply(d$w_cl, d$region, sum)) * 1.06,
                    levels(d$region))
  p0 <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_cl) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = "region") |>
      step_calibrate(method = "poststratify", margins = list(region = m_reg))))
  w0  <- collect_weights(p0, drop_zero = FALSE)$.weight
  cap <- 4 * mean(w0[w0 > 0])
  p1 <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_cl) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = "region") |>
      step_calibrate(method = "poststratify", margins = list(region = m_reg)) |>
      step_trim_weights(lower = min(w0[w0 > 0]) / 2, upper = cap)))
  w1 <- collect_weights(p1, drop_zero = FALSE)$.weight
  expect_equal(sum(w1), sum(w0), tolerance = 1e-6)
  expect_lte(max(w1), cap + 1e-8)
  # the poststrat totals shift a little from the trim: the accounting
  # del funnel debe reflejar el mismo Sigma-w (coherencia interna)
  expect_equal(sum(w1), sum(m_reg), tolerance = 1e-6 * sum(m_reg))
})
