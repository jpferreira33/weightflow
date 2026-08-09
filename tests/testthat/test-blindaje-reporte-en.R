# Hardening: the English HTML report under extreme scenarios. Checks that the
# report computes correctly (funnel, deff, AAPOR recomputed by hand), that prep
# alerts surface, and that the diagnostics render sanely.

rep_en <- function(p, ...) {
  f <- tempfile(fileext = ".html")
  suppressMessages(report_weighting(p, file = f, open = FALSE, lang = "en", ...))
  paste(readLines(f, warn = FALSE), collapse = "\n")
}
# unescape the basics so alert text can be searched inside the HTML
unesc <- function(h) {
  h <- gsub("&gt;", ">", h, fixed = TRUE); h <- gsub("&lt;", "<", h, fixed = TRUE)
  gsub("&amp;", "&", h, fixed = TRUE)
}
ren_d <- function(n = 500, seed = 7) {
  set.seed(seed)
  d <- data.frame(id = 1:n, x = factor(sample(c("A", "B", "C"), n, TRUE)),
                  reg = factor(sample(c("N", "S"), n, TRUE)),
                  w = runif(n, 2, 9), y = rnorm(n, 40, 6))
  d$inel <- rbinom(n, 1, .04) == 1
  d$unk  <- rbinom(n, 1, .05) == 1 & !d$inel
  d$resp <- rbinom(n, 1, .72) == 1 & !d$inel & !d$unk
  d
}
ren_marg <- function(d, v, f = 1.05)
  setNames(as.numeric(tapply(d$w, d[[v]], sum)) * f, levels(d[[v]]))

test_that("EN report of a full cascade: funnel, deff and AAPOR RR1 match hand recomputation; no NaN/NA leaks; no Spanish", {
  d <- ren_d()
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_unknown_eligibility(unknown = unk, by = "x") |>
    step_drop_ineligible(ineligible = inel) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x") |>
    step_calibrate(method = "raking",
                   margins = list(x = ren_marg(d, "x"), reg = ren_marg(d, "reg"))) |>
    step_trim_weights(lower = 1, upper = 25) |>
    step_round(digits = 0, method = "preserve_total")))
  h <- rep_en(p, metadata = list(operation = "Stress EN", period = "2026"))
  wfin <- collect_weights(p, drop_zero = FALSE)$.weight
  de   <- design_effect(wfin)
  # funnel numbers recomputed by hand
  expect_true(grepl(format(round(de$deff, 3)), h, fixed = TRUE))
  expect_true(grepl(format(round(sum(wfin)), big.mark = ","), h, fixed = TRUE))
  # AAPOR RR1 = R / (R + NR + U) sobre los no-inelegibles
  rr1 <- 100 * sum(d$resp) / (nrow(d) - sum(d$inel))
  expect_true(grepl(sprintf("%.1f%%", rr1), h, fixed = TRUE))
  # sin fugas de indicadores rotos ni de idioma
  for (bad in c("NaN", ">NA<", ">Inf<", "-Inf", "Etapa", "Advertencia", "Resumen ejecutivo"))
    expect_false(grepl(bad, h, fixed = TRUE), label = paste("aparece", bad))
  expect_true(grepl("<html lang='en'", h, fixed = TRUE))
  expect_true(grepl("Stress EN", h, fixed = TRUE))       # metadata
})

test_that("every prep alert appears in the EN report (comparing HTML-unescaped text)", {
  d <- ren_d(seed = 8)
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "propensity",
                     formula = ~ x + reg + y, engine = "forest", num_classes = 5)))
  h <- unesc(rep_en(p))
  expect_gt(length(p$alerts), 0)
  for (a in p$alerts) {
    frag <- substr(gsub("\\[.*?\\] ", "", a), 1, 60)
    expect_true(grepl(frag, h, fixed = TRUE), label = paste("alerta ausente:", frag))
  }
})

test_that("a single-covariate logit propensity does not crash the report", {
  d <- ren_d(seed = 9)
  d$edad <- rnorm(nrow(d), 45, 12)
  d$resp2 <- rbinom(nrow(d), 1, stats::plogis(-2 + 0.05 * d$edad)) == 1
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp2, method = "propensity",
                     formula = ~edad, engine = "logit", num_classes = 5)))
  h <- rep_en(p)
  expect_true(grepl("propensity", h, ignore.case = TRUE))
})

test_that("the trim narrative does not claim preservation when redistribution was infeasible", {
  d <- ren_d(seed = 10); d$w[1] <- 5000
  # infeasible upper bound: n * 6 < sum(w) -> the mass cannot be preserved
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_trim_weights(lower = 3, upper = 6)))
  wfin <- collect_weights(p, drop_zero = FALSE)$.weight
  loss <- abs(sum(wfin) - sum(d$w)) / sum(d$w)
  expect_gt(loss, 0.5)
  h <- unesc(rep_en(p))
  expect_false(grepl("to preserve the total", h, fixed = TRUE))
  expect_true(grepl("fell by", h, ignore.case = TRUE) ||
              any(grepl("weight total", p$alerts, ignore.case = TRUE)))
})

test_that("degenerate-but-valid extremes render sanely: equal weights (deff=1), n=8, huge outlier deff", {
  # equal weights and 100% response: deff exactly 1, cv 0, RR1 100.0%
  d9 <- ren_d(seed = 11); d9$w <- 5; d9$resp <- TRUE; d9$inel <- FALSE; d9$unk <- FALSE
  p9 <- suppressMessages(prep(weighting_spec(d9, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  h9 <- rep_en(p9)
  expect_true(grepl("100.0%", h9, fixed = TRUE))
  expect_false(grepl("NaN", h9, fixed = TRUE))
  # n = 8 with calibration: renders
  d4 <- ren_d(seed = 12)[1:8, ]
  d4$resp <- c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, FALSE, TRUE)
  p4 <- suppressMessages(prep(weighting_spec(d4, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class") |>
    step_calibrate(method = "raking", margins = list(reg = ren_marg(d4, "reg", 1.1)))))
  expect_gt(nchar(rep_en(p4)), 10000)
  # outlier brutal: el deff gigante se reporta y se marca el peso extremo
  db <- ren_d(seed = 13); db$w[1] <- 5000
  pb <- suppressMessages(prep(weighting_spec(db, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  hb <- unesc(rep_en(pb))
  deb <- design_effect(collect_weights(pb, drop_zero = FALSE)$.weight)
  expect_true(grepl(format(round(deb$deff, 2)), hb, fixed = TRUE) ||
              grepl(format(round(deb$deff, 3)), hb, fixed = TRUE))
  expect_true(grepl("extreme weight", hb, ignore.case = TRUE))
})

test_that("wild linear calibration surfaces its own alarms: under-weighting, Deville-Sarndal g bounds, collinearity", {
  d <- ren_d(seed = 14)
  X <- stats::model.matrix(~x, d); tt <- colSums(X * d$w)
  tt["xB"] <- tt["xB"] * 0.05          # total absurdo -> g minusculos
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_calibrate(method = "linear", formula = ~x, totals = tt)))
  h <- unesc(rep_en(p))
  expect_true(any(grepl("Deville-Sarndal|Deville", p$alerts)))
  expect_true(grepl("under-weighting", h, fixed = TRUE))
  expect_true(grepl("Deville", h, fixed = TRUE))
  expect_true(grepl("collinearity", h, ignore.case = TRUE))   # the plain-language kappa row
  # the diagnostics table reports the targets as achieved (the solver closed)
  expect_true(grepl("achieved", h, fixed = TRUE))
})

test_that("the EN report narrates the tidy-totals reconciliation and the S-L information level", {
  d <- ren_d(seed = 15)
  tx <- data.frame(x = levels(d$x), Freq = as.numeric(ren_marg(d, "x", 1.08)))
  tr <- data.frame(reg = levels(d$reg), Freq = as.numeric(ren_marg(d, "reg", 1.0)))
  p8 <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_calibrate(method = "raking", totals = list(tx, tr), count = "Freq")))
  expect_true(grepl("did not all sum|rescal", rep_en(p8), ignore.case = TRUE))
  p7 <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "calibration", formula = ~ x + reg)))
  expect_true(grepl("information level|InfoS", rep_en(p7), ignore.case = TRUE))
})

test_that("ML propensity (2+ covariates) shows the full diagnostics battery in English", {
  d <- ren_d(seed = 16)
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "propensity",
                     formula = ~ x + reg + y, engine = "forest", num_classes = 5)))
  h <- rep_en(p)
  for (card in c("decile", "AUC", "Brier", "Importance", "verlap"))
    expect_true(grepl(card, h, ignore.case = (card == "decile")),
                label = paste("falta tarjeta", card))
  # y logit con 2+ covariables NO se cae (el crash es solo con 1)
  p2 <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "propensity",
                     formula = ~ x + y, engine = "logit", num_classes = 5)))
  expect_no_error(rep_en(p2))
})
