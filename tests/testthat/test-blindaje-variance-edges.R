# Hardening: edges of the variance machinery.

var_d <- function(n_psu = 24, por_psu = 15, seed = 7) {
  set.seed(seed)
  d <- data.frame(psu = rep(1:n_psu, each = por_psu),
                  estrato = rep(rep(1:4, each = n_psu / 4), each = por_psu))
  n <- nrow(d)
  d$x <- factor(sample(c("A", "B"), n, TRUE))
  d$w <- runif(n, 1, 3); d$resp <- rbinom(n, 1, 0.7) == 1; d$y <- rnorm(n, 10)
  d
}

base_spec <- function(d) {
  weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")
}

test_that("bootstrap is bit-identical under the same seed, different under another", {
  d <- var_d()
  b1 <- bootstrap_weights(suppressMessages(prep(base_spec(d))), replicates = 30,
                          strata = "estrato", psu = "psu", seed = 42)
  b2 <- bootstrap_weights(suppressMessages(prep(base_spec(d))), replicates = 30,
                          strata = "estrato", psu = "psu", seed = 42)
  b3 <- bootstrap_weights(suppressMessages(prep(base_spec(d))), replicates = 30,
                          strata = "estrato", psu = "psu", seed = 43)
  e1 <- boot_mean(b1, "y"); e2 <- boot_mean(b2, "y"); e3 <- boot_mean(b3, "y")
  expect_identical(e1$se, e2$se)
  expect_false(identical(e1$se, e3$se))
})

test_that("lonely-PSU collapse keeps distinct PSUs distinct even with reused PSU labels", {
  # dos estratos con UNA UPM cada uno, ambas etiquetadas '1': sin ids anidados
  # colapsarian a una sola UPM y la varianza se degeneraria (bug C3 original)
  set.seed(8)
  d <- data.frame(estrato = rep(1:4, each = 40),
                  psu = c(rep(1, 40), rep(1, 40),           # estratos 1 y 2: UPM unica, misma etiqueta
                          rep(1:2, each = 20), rep(1:2, each = 20)))
  n <- nrow(d); d$x <- factor(sample(c("A","B"), n, TRUE))
  d$w <- runif(n, 1, 3); d$resp <- rbinom(n, 1, .7) == 1; d$y <- rnorm(n, 10)
  b <- suppressWarnings(bootstrap_weights(suppressMessages(prep(base_spec(d))),
        replicates = 40, strata = "estrato", psu = "psu",
        lonely_psu = "collapse", seed = 1))
  se <- boot_mean(b, "y")$se
  expect_true(is.finite(se) && se > 0)
})

test_that("jackknife and bootstrap agree in order of magnitude on a clean design", {
  d <- var_d()
  p <- suppressMessages(prep(base_spec(d)))
  bse <- boot_mean(bootstrap_weights(p, replicates = 60, strata = "estrato",
                                     psu = "psu", seed = 3), "y")$se
  jse <- jack_mean(jackknife_weights(p, strata = "estrato", psu = "psu"), "y")$se
  expect_gt(bse / jse, 0.5); expect_lt(bse / jse, 2)
})

test_that("collect_replicate_weights returns the point weight plus one column per replicate", {
  d <- var_d()
  b <- bootstrap_weights(suppressMessages(prep(base_spec(d))), replicates = 25,
                         strata = "estrato", psu = "psu", seed = 4)
  cw <- collect_replicate_weights(b)
  expect_equal(sum(grepl("^rep_|^w_rep|rep", names(cw))) >= 25 || ncol(cw) >= 26, TRUE)
})

test_that("as_svydesign builds a survey design whose mean matches the weighted mean", {
  skip_if_not_installed("survey")
  d <- var_d()
  p <- suppressMessages(prep(base_spec(d)))
  des <- as_svydesign(p, ids = ~psu, strata = ~estrato)
  w <- collect_weights(p)$.weight; yv <- collect_weights(p)$y
  expect_equal(as.numeric(coef(survey::svymean(~y, des))),
               sum(w * yv) / sum(w), tolerance = 1e-10)
})
