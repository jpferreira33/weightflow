# Recursive period-to-period chaining (wave_step / wave_carry). The coordination transfers
# PSU multiplicities (StatCan LFS 7.2.2), so the invariants are sharp: an unchanged PSU set
# reproduces the previous resampling exactly (two identical periods -> zero change variance),
# and a rotation that leaves n_h alone is a permutation, so no replicate needs the sum
# adjustment. The cross-sectional weights must never be touched by any of it.

mkp <- function(npsu = 24, per = 10, offset = 0, drift = 0, seed = 1) {
  set.seed(1000)
  eff <- stats::setNames(stats::rnorm(400, 0, 1.2), as.character(1:400))
  set.seed(seed)
  psu <- rep(seq_len(npsu) + offset, each = per)
  str <- rep(rep(1:4, length.out = npsu), each = per)
  data.frame(psu = psu, str = str, pw = 10,
             sexo = factor(sample(c("M", "F"), npsu * per, TRUE)),
             desoc = stats::rbinom(npsu * per, 1,
                                   stats::plogis(-2.4 + 0.9 * eff[as.character(psu)] + drift)),
             resp = 1)
}
spc <- function(d) weighting_spec(d, base_weights = pw) |>
  step_nonresponse(respondent = resp, by = "sexo")
EST <- list(desoc = function(w, d) stats::weighted.mean(d$desoc, w, na.rm = TRUE))

test_that("the cross-sectional weights are exactly prep()'s", {
  skip_on_cran()
  d <- mkp(seed = 1)
  s <- wave_step(spc(d), estimands = EST, replicates = 60, strata = "str", psu = "psu",
                 period = "p1", seed = 1, progress = FALSE)
  expect_equal(s$weights, prep(spc(d))$final_weight)
  expect_null(s$change)                       # first period of a chain has nothing to compare
})

test_that("two identical periods give zero change and zero change variance", {
  skip_on_cran()
  d <- mkp(seed = 1)
  a <- wave_step(spc(d), estimands = EST, replicates = 150, strata = "str", psu = "psu",
                 period = "p1", seed = 7, progress = FALSE)
  b <- wave_step(spc(d), previous = wave_carry(a), estimands = EST, replicates = 150,
                 strata = "str", psu = "psu", period = "p2", seed = 8, progress = FALSE)
  expect_equal(b$change$estimate, 0)
  expect_lt(b$change$se, 1e-10)               # the transfer reproduces the resampling exactly
  expect_equal(b$change$rho, 1)
  expect_true(all(b$strata$case == "i"))
})

test_that("rotation with n_h unchanged is a permutation: no replicate is adjusted", {
  skip_on_cran()
  a <- wave_step(spc(mkp(seed = 1)), estimands = EST, replicates = 200, strata = "str",
                 psu = "psu", period = "q1", seed = 3, progress = FALSE)
  b <- wave_step(spc(mkp(seed = 2, offset = 4, drift = 0.15)), previous = wave_carry(a),
                 estimands = EST, replicates = 200, strata = "str", psu = "psu",
                 period = "q2", seed = 4, progress = FALSE)
  expect_true(all(b$strata$case == "ii"))
  expect_true(all(b$strata$coordinated == 1))
  expect_gt(b$change$rho, 0.5)                          # the overlap shows up as covariance
  expect_lt(b$change$V, b$change$V1 + b$change$V2)      # and lowers the change variance
})

test_that("a stratum that loses a PSU is case iii and coordinates only partly", {
  skip_on_cran()
  a <- wave_step(spc(mkp(seed = 1)), estimands = EST, replicates = 200, strata = "str",
                 psu = "psu", period = "q1", seed = 3, progress = FALSE)
  d <- subset(mkp(seed = 2, offset = 4, drift = 0.1), psu != 5)
  b <- wave_step(spc(d), previous = wave_carry(a), estimands = EST, replicates = 200,
                 strata = "str", psu = "psu", period = "q2", seed = 8, progress = FALSE)
  expect_equal(sum(b$strata$case == "iii"), 1L)
  expect_lt(b$strata$coordinated[b$strata$case == "iii"], 1)
  expect_true(all(b$strata$coordinated[b$strata$case == "ii"] == 1))
})

test_that("a returning cohort inherits from the carry that holds it, not the latest one", {
  skip_on_cran()
  g1 <- wave_step(spc(mkp(seed = 1)), estimands = EST, replicates = 150, strata = "str",
                  psu = "psu", period = "m1", seed = 5, progress = FALSE)
  g2 <- wave_step(spc(mkp(seed = 9, offset = 100)), previous = wave_carry(g1),
                  estimands = EST, replicates = 150, strata = "str", psu = "psu",
                  period = "m2", seed = 6, progress = FALSE)
  expect_true(all(g2$strata$case == "fresh"))           # no PSU in common with m1
  g3 <- wave_step(spc(mkp(seed = 3, drift = 0.1)),
                  previous = list(wave_carry(g1), wave_carry(g2)), estimands = EST,
                  replicates = 150, strata = "str", psu = "psu", period = "m3",
                  seed = 7, progress = FALSE)
  expect_true(all(g3$strata$case == "i"))               # same PSU set as m1
  r <- g3$change
  expect_gt(r$rho[r$from == "m1"], 0.5)                 # coordinated with the period it shares
  expect_lt(abs(r$rho[r$from == "m2"]), 0.3)            # and not with the disjoint one
})

test_that("carry size: thin without CRE, and the replicate count must not drift", {
  skip_on_cran()
  a <- wave_step(spc(mkp(seed = 1)), estimands = EST, replicates = 60, strata = "str",
                 psu = "psu", period = "p1", seed = 1, progress = FALSE)
  cy <- wave_carry(a)
  expect_s3_class(cy, "wf_wave_carry")
  expect_null(cy$reps)                                  # thin: no unit-level weights
  expect_null(cy$data)
  expect_equal(ncol(cy$mult), 60L)
  expect_error(wave_step(spc(mkp(seed = 2)), previous = cy, estimands = EST,
                         replicates = 61, strata = "str", psu = "psu", progress = FALSE),
               "constant along the chain")
})

test_that("domains expand and an estimand added mid-chain is flagged, not dropped silently", {
  skip_on_cran()
  a <- wave_step(spc(mkp(seed = 1)), estimands = EST, by = "sexo", replicates = 150,
                 strata = "str", psu = "psu", period = "q1", seed = 3, progress = FALSE)
  b <- wave_step(spc(mkp(seed = 2, offset = 4, drift = 0.15)), previous = wave_carry(a),
                 estimands = EST, by = "sexo", replicates = 150, strata = "str",
                 psu = "psu", period = "q2", seed = 4, progress = FALSE)
  expect_equal(nrow(b$change), 3L)                      # total + two domains
  expect_true(all(c("desoc", "desoc|sexo=F", "desoc|sexo=M") %in% b$change$estimand))
  expect_warning(
    wave_step(spc(mkp(seed = 2, offset = 4)), previous = wave_carry(a),
              estimands = c(EST, list(ocup = function(w, d) stats::weighted.mean(1 - d$desoc, w))),
              replicates = 150, strata = "str", psu = "psu", seed = 4, progress = FALSE),
    "no replicate values")
})

test_that("a CRE chain injects Zhat* per replicate and needs a fat carry", {
  skip_on_cran()
  w <- lapply(1:2, function(k) {
    d <- subset(panel_ine, ola == k & disp == "R"); d$sexo <- factor(d$sexo); d })
  Xtot <- function(d) colSums(d$w_base * stats::model.matrix(~ sexo, data = d))
  E <- list(desoc = function(w, d) stats::weighted.mean(d$desocupado, w, na.rm = TRUE))
  sp1 <- weighting_spec(w[[1]], base_weights = w_base) |>
    step_cre(previous = NULL, status = condicion, formula = ~ sexo,
             totals = Xtot(w[[1]]), status_ref = "inact")
  s1 <- wave_step(sp1, estimands = E, replicates = 40, strata = "estrato", psu = "psu",
                  period = "ola1", seed = 1, progress = FALSE)
  expect_true(s1$carry$meta$fat)                        # CRE forces the fat carry
  expect_false(is.null(s1$carry$reps))
  expect_equal(s1$n_cre_skipped, 0L)                    # a seed wave must not warn

  sp2 <- weighting_spec(w[[2]], base_weights = w_base) |>
    step_cre(previous = prep(sp1), status = condicion, composite = list(NULL, "sexo"),
             id_unit = c("id_hogar", "nper"), formula = ~ sexo, totals = Xtot(w[[2]]),
             alpha = 2/3, status_ref = "inact")
  s2 <- wave_step(sp2, previous = wave_carry(s1), estimands = E, replicates = 40,
                  strata = "estrato", psu = "psu", period = "ola2", seed = 2, progress = FALSE)
  expect_gte(s2$n_cre_injected, 1L)
  expect_equal(s2$n_cre_skipped, 0L)
  expect_true(is.finite(s2$change$se))
  expect_equal(s2$weights, prep(sp2)$final_weight)

  expect_error(wave_step(sp2, previous = wave_carry(s1), estimands = E, replicates = 40,
                         strata = "estrato", psu = "psu", carry = "thin", progress = FALSE),
               "thin")
  expect_warning(wave_step(sp2, previous = NULL, estimands = E, replicates = 10,
                           strata = "estrato", psu = "psu", progress = FALSE),
                 "FIXED")
})

test_that("wave_step restores the caller's RNG state", {
  skip_on_cran()
  d <- mkp(seed = 1)
  set.seed(99); s0 <- .Random.seed
  invisible(wave_step(spc(d), estimands = EST, replicates = 40, strata = "str",
                      psu = "psu", seed = 1, progress = FALSE))
  expect_identical(s0, get(".Random.seed", envir = .GlobalEnv))
})
