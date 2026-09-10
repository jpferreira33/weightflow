# Linear combinations over a chain of carries. The point of wave_contrast() is that a rolling
# quarter, an annual average or a semester contrast can be estimated from the .rds files the
# chain already wrote, without holding the waves together. The sharp invariant is that
# contrast = c(-1, 1) must reproduce wave_step()'s own $change exactly: same replicates, same
# pairing, so the same covariance -- if it does not, the two paths disagree about V(change).

mkc <- function(npsu = 24, per = 10, offset = 0, drift = 0, seed = 1) {
  set.seed(2000)
  eff <- stats::setNames(stats::rnorm(600, 0, 1.1), as.character(1:600))
  set.seed(seed)
  psu <- rep(seq_len(npsu) + offset, each = per)
  # El estrato es funcion del ID de UPM, no de su posicion: una UPM que rota tiene que
  # conservar su estrato entre periodos, o la transferencia de multiplicidades -- que opera
  # dentro de estrato -- no la puede emparejar y la coordinacion se pierde en silencio.
  data.frame(psu = psu, str = ((psu - 1L) %% 4L) + 1L, pw = 12,
             sexo = factor(sample(c("M", "F"), npsu * per, TRUE)),
             desoc = stats::rbinom(npsu * per, 1,
                                   stats::plogis(-2.2 + 0.8 * eff[as.character(psu)] + drift)),
             resp = 1)
}
spc2 <- function(d) weighting_spec(d, base_weights = pw) |>
  step_nonresponse(respondent = resp, by = "sexo")
EST2 <- list(desoc = function(w, d) stats::weighted.mean(d$desoc, w, na.rm = TRUE))

chain3 <- function(R = 200L) {
  out <- list(); prev <- NULL
  for (k in 1:3) {
    s <- wave_step(spc2(mkc(seed = k, offset = 2 * (k - 1), drift = 0.12 * (k - 1))),
                   previous = prev, estimands = EST2, replicates = R, strata = "str",
                   psu = "psu", period = paste0("t", k), seed = 40 + k, progress = FALSE)
    out[[k]] <- list(step = s, carry = wave_carry(s))
    prev <- rev(lapply(out, `[[`, "carry"))
  }
  out
}

test_that("contrast c(-1, 1) reproduces wave_step()'s own net change exactly", {
  skip_on_cran()
  ch <- chain3()
  cy <- lapply(ch, `[[`, "carry")
  got <- wave_contrast(list(cy[[1]], cy[[2]]), "desoc", contrast = c(-1, 1))
  ref <- ch[[2]]$step$change
  ref <- ref[ref$from == "t1" & ref$estimand == "desoc", ]
  expect_equal(got$estimate, ref$estimate, tolerance = 1e-12)
  expect_equal(got$se,       ref$se,       tolerance = 1e-12)
  expect_equal(got$V,        ref$V,        tolerance = 1e-12)
})

test_that("the covariance matrix is symmetric, PSD, and decays with the lag", {
  skip_on_cran()
  cy <- lapply(chain3(), `[[`, "carry")
  r <- wave_contrast(cy, "desoc")
  S <- attr(r, "Sigma")
  expect_equal(dim(S), c(3L, 3L))
  expect_equal(S, t(S), tolerance = 1e-14)                 # simetrica
  expect_true(all(eigen(S, only.values = TRUE)$values > -1e-12))   # semidefinida positiva
  expect_true(all(diag(S) > 0))
  # las UPM compartidas hacen positiva la covarianza, y Cauchy-Schwarz la acota
  expect_true(all(S[upper.tri(S)] > 0))
  expect_lt(abs(S[1, 2]), sqrt(S[1, 1] * S[2, 2]))
  expect_lt(abs(S[1, 3]), sqrt(S[1, 1] * S[3, 3]))
  expect_equal(rownames(S), c("t1", "t2", "t3"))
})

test_that("the rolling average beats the typical period, and never the impossible", {
  skip_on_cran()
  cy <- lapply(chain3(), `[[`, "carry")
  avg <- wave_contrast(cy, "desoc")                        # default rep(1/3, 3)
  S   <- attr(avg, "Sigma")
  expect_equal(avg$estimate, mean(attr(avg, "theta")), tolerance = 1e-12)
  # Promediar W periodos positivamente correlacionados da V = (1/W^2)(sum diag + 2 sum offdiag),
  # menor que la varianza MEDIA de un periodo siempre que rho < 1. NO tiene por que ser menor
  # que la del periodo mas preciso: con la diagonal heterogenea, el promedio arrastra a los
  # periodos ruidosos. Esa es la version verdadera del enunciado.
  expect_lt(avg$V, mean(diag(S)))
  expect_lt(avg$V, max(diag(S)))
  expect_true(avg$lo < avg$estimate && avg$estimate < avg$hi)
})

test_that("a contrast that cancels the level has smaller variance than the sum", {
  skip_on_cran()
  cy <- lapply(chain3(), `[[`, "carry")
  dif <- wave_contrast(cy, "desoc", contrast = c(-1, 0, 1))
  sum3 <- wave_contrast(cy, "desoc", contrast = c(1, 0, 1))
  # la covarianza positiva resta en la diferencia y suma en el total
  expect_lt(dif$V, sum3$V)
})

test_that("it refuses mismatched inputs instead of returning something plausible", {
  skip_on_cran()
  cy <- lapply(chain3(), `[[`, "carry")
  expect_error(wave_contrast(cy, "desoc", contrast = c(1, -1)), "length 2 but 3 carries")
  expect_error(wave_contrast(cy, "no_existe"), "missing from carr")
  expect_error(wave_contrast(list(1, 2), "desoc"), "list of wave_carry")
  short <- wave_step(spc2(mkc(seed = 9)), estimands = EST2, replicates = 50, strata = "str",
                     psu = "psu", period = "otro", seed = 7, progress = FALSE)
  expect_error(wave_contrast(list(cy[[1]], wave_carry(short)), "desoc"),
               "replicate count must be constant")
})

test_that("a single carry with contrast 1 returns that period's level", {
  skip_on_cran()
  ch <- chain3()
  r <- wave_contrast(ch[[1]]$carry, "desoc", contrast = 1)
  lv <- ch[[1]]$step$level
  lv <- lv[lv$estimand == "desoc", ]
  expect_equal(r$estimate, lv$estimate, tolerance = 1e-12)
  expect_equal(r$se, lv$se, tolerance = 1e-10)
})
