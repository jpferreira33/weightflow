# Fidelity to real national statistical office methodologies.
# Each test expresses a documented institutional recipe and verifies the
# properties that methodology promises. Dual use: regression + reference
# examples for the documentation and the book.

nso_d <- function(n_hh = 300, seed = 31) {
  set.seed(seed)
  hh <- data.frame(hh_id = 1:n_hh,
                   region = factor(sample(sprintf("R%d", 1:4), n_hh, TRUE)),
                   psu    = rep(1:30, length.out = n_hh),
                   str    = rep(1:5, length.out = n_hh),
                   w_hh   = runif(n_hh, 20, 60),
                   hh_resp = rbinom(n_hh, 1, 0.8) == 1)
  per <- do.call(rbind, lapply(1:n_hh, function(h) {
    k <- sample(1:4, 1)
    data.frame(hh_id = h, sex = factor(sample(c("M", "F"), k, TRUE)),
               age = factor(sample(c("a1", "a2", "a3"), k, TRUE)),
               p_resp = rbinom(k, 1, 0.85) == 1,
               income = exp(rnorm(k, 7, 0.5)))
  }))
  d <- merge(per, hh, by = "hh_id")
  d$id <- seq_len(nrow(d))
  d$resp <- d$hh_resp & d$p_resp
  d
}

# population margin ("projections"): base totals perturbed smoothly
proy <- function(d, var, f = 1.06) {
  setNames(as.numeric(tapply(d$w_hh, d[[var]], sum)) * f, levels(d[[var]]))
}

test_that("ECH/INE-LatAm recipe: household NR -> person NR -> raking to projections -> integer rounding", {
  d <- nso_d()
  m_reg <- proy(d, "region"); m_sex <- proy(d, "sex")
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_hh) |>
      step_nonresponse(respondent = hh_resp, method = "weighting_class",
                       by = "region", cluster = "hh_id") |>
      step_nonresponse(respondent = resp, method = "weighting_class",
                       by = c("region", "sex")) |>
      step_calibrate(method = "raking", margins = list(region = m_reg, sex = m_sex)) |>
      step_round(digits = 0, method = "preserve_total")))
  cw <- collect_weights(p)
  # integer weights and total preserved to the nearest integer of the margins
  expect_true(all(cw$.weight == floor(cw$.weight)))
  expect_equal(sum(cw$.weight), round(sum(m_reg)), tolerance = 1)
  # the region projections hold up to the rounding effect
  tot <- tapply(cw$.weight, cw$region, sum)
  expect_lt(max(abs(as.numeric(tot[names(m_reg)]) - m_reg) / m_reg), 0.01)
})

test_that("EU-SILC integrative recipe (Lemaitre-Dufour): one weight per household AND person margins hit", {
  d <- nso_d()
  m_sex <- proy(d, "sex")
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_hh) |>
      step_nonresponse(respondent = hh_resp, method = "weighting_class",
                       by = "region", cluster = "hh_id") |>
      step_calibrate(method = "linear", formula = ~sex,
                     totals = c("(Intercept)" = sum(d$w_hh) * 1.06, sexM = m_sex[["M"]]),
                     cluster = "hh_id", equal_within_cluster = TRUE)))
  cw <- collect_weights(p)
  # promise 1: a single weight per household
  rango_hh <- tapply(cw$.weight, cw$hh_id, function(x) diff(range(x)))
  expect_lt(max(rango_hh), 1e-8)
  # promise 2: the PERSON margins are reproduced as well
  expect_equal(sum(cw$.weight[cw$sex == "M"]), m_sex[["M"]], tolerance = 1e-6 * m_sex[["M"]])
  expect_equal(sum(cw$.weight), sum(d$w_hh) * 1.06, tolerance = 1)
})

test_that("Pew/AAPOR rake-trim-rake loop runs via the iterative workflow, and Folsom-Singh does it in one step", {
  d <- nso_d()
  m_reg <- proy(d, "region"); m_sex <- proy(d, "sex")
  base <- weighting_spec(d, base_weights = w_hh) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "region") |>
    step_calibrate(method = "raking", margins = list(region = m_reg, sex = m_sex))
  rec1 <- suppressMessages(prep(base))
  w1 <- collect_weights(rec1)$.weight
  lo <- as.numeric(quantile(w1, .05)); up <- as.numeric(quantile(w1, .95))
  # classic loop: trim -> re-rake (2 rounds), reusing the prepped recipe
  rec2 <- rec1
  for (k in 1:2) {
    rec2 <- suppressMessages(step_trim_weights(rec2, lower = lo, upper = up)) |>
      step_calibrate(method = "raking", margins = list(region = m_reg, sex = m_sex))
    rec2 <- suppressMessages(prep(rec2))
  }
  w2 <- collect_weights(rec2)$.weight
  tot2 <- tapply(collect_weights(rec2)$.weight, collect_weights(rec2)$region, sum)
  expect_lt(max(abs(as.numeric(tot2[names(m_reg)]) - m_reg) / m_reg), 1e-6)  # margenes exactos
  expect_lt(max(w2) / max(w1), 1.0)                                          # colas reducidas
  # Folsom-Singh: bounds AND margins exact in ONE step
  rec3 <- suppressMessages(prep(step_trim_calibrated(rec1, formula = ~region + sex,
                                                     lower = lo, upper = up)))
  w3 <- collect_weights(rec3)$.weight
  expect_true(all(w3 >= lo - 1e-8 & w3 <= up + 1e-8))
  tot3 <- tapply(collect_weights(rec3)$.weight, collect_weights(rec3)$region, sum)
  expect_lt(max(abs(as.numeric(tot3[names(m_reg)]) - m_reg) / m_reg), 1e-6)
})

test_that("INSEE/CALMAR recipe: propensity classes (homogeneous response groups) + bounded logit calibration", {
  d <- nso_d()
  m_reg <- proy(d, "region")
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_hh) |>
      step_nonresponse(respondent = resp, method = "propensity",
                       formula = ~ region + sex + age, engine = "logit",
                       num_classes = 5) |>
      step_calibrate(method = "linear", formula = ~region,
                     totals = c("(Intercept)" = sum(m_reg),
                                structure(as.numeric(m_reg[-1]),
                                          names = paste0("region", names(m_reg)[-1]))),
                     calfun = "logit", bounds = c(0.4, 2.5))))
  cw <- collect_weights(p)
  # CALMAR promise: g-weights within bounds and totals exact
  hist_w <- collect_weights(p, keep_intermediate = TRUE)
  nrcol <- grep("nonresponse", names(hist_w), value = TRUE)[1]
  g <- cw$.weight / hist_w[[nrcol]][hist_w$.weight > 0]
  expect_true(all(g >= 0.4 - 1e-6 & g <= 2.5 + 1e-6))
  tot <- tapply(cw$.weight, cw$region, sum)
  expect_lt(max(abs(as.numeric(tot[names(m_reg)]) - m_reg) / m_reg), 1e-6)
})

test_that("StatCan-style deliverable: recipe + JKn replicate weights export and reproduce the SEs downstream", {
  skip_if_not_installed("survey")
  d <- nso_d()
  m_reg <- proy(d, "region")
  p <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_hh) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = "region") |>
      step_calibrate(method = "raking", margins = list(region = m_reg))))
  j <- suppressWarnings(jackknife_weights(p, strata = "str", psu = "psu"))
  # the survey bridge reproduces point and SE (the dissemination flow: any
  # downstream software consuming the replicates gets the same)
  des <- suppressWarnings(as_svrepdesign(j))
  est <- survey::svymean(~income, des)
  expect_equal(as.numeric(coef(est)), jack_mean(j, "income")$estimate, tolerance = 1e-8)
  expect_equal(as.numeric(survey::SE(est)), jack_mean(j, "income")$se, tolerance = 1e-3)
  # the publishable replicate file: available via bootstrap
  # (collect_replicate_weights now also accepts jackknife objects)
  b <- bootstrap_weights(p, replicates = 30, strata = "str", psu = "psu", seed = 9)
  rw <- collect_replicate_weights(b)
  expect_false(anyNA(rw))
})

test_that("NCES/Tukey rule: fence-based trimming preserves the total and caps the tail", {
  d <- nso_d()
  p0 <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_hh) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = "region")))
  w0 <- collect_weights(p0)$.weight
  p1 <- suppressMessages(prep(
    weighting_spec(d, base_weights = w_hh) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = "region") |>
      step_trim_weights(method = "tukey")))
  w1 <- collect_weights(p1)$.weight
  expect_equal(sum(w1), sum(w0), tolerance = 1e-6)   # masa preservada
  expect_lte(max(w1), max(w0))                       # cola capada (o igual si no habia far-out)
})
