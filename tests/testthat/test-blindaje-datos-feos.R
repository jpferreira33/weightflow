# Hardening: ugly and missing data in the sample and in the totals. Regressions
# for guards the package now enforces (non-finite base weights, unmatched margin
# levels, empty/dead cells, inconsistent totals) plus healthy-behaviour checks.

feo_d <- function(n = 200, seed = 1) {
  set.seed(seed)
  data.frame(id = 1:n, x = factor(sample(c("A", "B"), n, TRUE)),
             w = runif(n, 1, 3), resp = rbinom(n, 1, 0.7) == 1,
             y = rnorm(n))
}
feo_marg <- function(d, f = 1.05)
  setNames(as.numeric(tapply(d$w, d$x, sum)) * f, levels(d$x))

test_that("NA and negative base weights are rejected loudly at prep", {
  d1 <- feo_d(); d1$w[5] <- NA
  expect_error(suppressMessages(prep(weighting_spec(d1, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x"))),
    "NA")
  d2 <- feo_d(); d2$w[7] <- -2
  expect_error(suppressMessages(prep(weighting_spec(d2, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x"))),
    "negative")
})

test_that("an infinite base weight is rejected at construction", {
  d <- feo_d(); d$w[3] <- Inf
  expect_error(weighting_spec(d, base_weights = w), "finite")
})

test_that("a raking margin level that matches nothing errors, naming it", {
  d  <- feo_d()
  m2 <- c(feo_marg(d), Zona99 = 50)   # a level that does not exist in the data
  expect_error(suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_calibrate(method = "raking", margins = list(x = m2)))),
    "match no active unit")
})

test_that("NA in the raking margin variable errors (raking needs a cell for every unit)", {
  # Design decision (2026-08): raking / post-stratification requires a cell for
  # every unit, so an NA in a margin variable is an error instead of a silent
  # pass-through where the NA units keep their base weight and the total drifts.
  d <- feo_d(); d$x[c(2, 4, 6)] <- NA
  marg <- feo_marg(feo_d())
  expect_error(suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_calibrate(method = "raking", margins = list(x = marg)))),
    "missing values")
})

test_that("an NA inside the totals vector errors (loudly, though the message could name the margin)", {
  d <- feo_d()
  m4 <- feo_marg(d); m4["B"] <- NA
  expect_error(suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_calibrate(method = "raking", margins = list(x = m4)))))
})

test_that("a continuous numeric `by` (raw age) runs, raises the small/dead-cell alerts, and the mass accounting closes", {
  d <- feo_d(); set.seed(11); d$edad <- sample(18:75, nrow(d), TRUE)
  # deterministic dead cell: an age that exists only among nonrespondents
  d$edad[which(!d$resp)[1:3]] <- 99L
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "edad")))
  expect_true(any(grepl("no units to adjust to", p$alerts)))
  expect_true(any(grepl("fewer than 30 cases", p$alerts)))
  cw <- collect_weights(p, drop_zero = FALSE)
  # the mass lost is EXACTLY that of the cells with no respondents
  dead <- names(which(tapply(d$resp, d$edad, sum) == 0))
  lost <- sum(d$w[as.character(d$edad) %in% dead])
  expect_equal(sum(cw$.weight), sum(d$w) - lost, tolerance = 1e-8)
  # and every respondent in live cells keeps a positive weight
  vivos <- d$resp & !(as.character(d$edad) %in% dead)
  expect_true(all(cw$.weight[vivos] > 0))
})

test_that("a whole stratum with zero responding UPMs: alert raised, surviving strata untouched, lost stratum zeroed", {
  set.seed(3); nn <- 200
  d <- data.frame(id = 1:nn, w = runif(nn, 1, 3),
                  estrato = rep(c("E1", "E2"), each = 100),
                  upm = rep(1:20, each = 10))
  d$upm_ok <- d$estrato != "E2"        # E2: zona perdida completa
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = upm_ok, method = "weighting_class",
                     by = "estrato", cluster = "upm")))
  expect_true(any(grepl("no units to adjust to", p$alerts)))
  cw <- collect_weights(p, drop_zero = FALSE)
  expect_equal(sum(cw$.weight[d$estrato == "E1"]), sum(d$w[d$estrato == "E1"]),
               tolerance = 1e-8)
  expect_true(all(cw$.weight[d$estrato == "E2"] == 0))
})

test_that("inconsistent margin totals: classic margins warn about non-convergence, tidy totals reconcile with a message", {
  d <- feo_d(); set.seed(21); d$z <- factor(sample(c("u", "v"), nrow(d), TRUE))
  m_x <- feo_marg(d, 1.05)                                        # suma N*1.05
  m_z <- setNames(as.numeric(tapply(d$w, d$z, sum)), levels(d$z)) # suma N
  # classic path (margins): raking oscillates and WARNS that the totals
  # son mutuamente inconsistentes -- loud ok
  expect_warning(
    suppressMessages(prep(weighting_spec(d, base_weights = w) |>
      step_calibrate(method = "raking",
                     margins = list(x = m_x, z = m_z)))),
    "mutually consistent|did not converge")
  # camino tidy (totals): reconciliacion automatica con mensaje, cierra en el
  # largest N and preserves the internal distribution of each margin
  tx <- data.frame(x = names(m_x), Freq = as.numeric(m_x))
  tz <- data.frame(z = names(m_z), Freq = as.numeric(m_z))
  expect_message(
    p <- prep(weighting_spec(d, base_weights = w) |>
      step_calibrate(method = "raking", totals = list(tx, tz), count = "Freq")),
    "did not all sum")
  cw <- collect_weights(p)
  expect_equal(sum(cw$.weight), sum(m_x), tolerance = 1e-6 * sum(m_x))
  tt <- tapply(cw$.weight, cw$z, sum)
  expect_equal(as.numeric(tt / sum(tt)), as.numeric(m_z / sum(m_z)),
               tolerance = 1e-6)
})
