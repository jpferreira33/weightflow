# Regressions for the 1.3.0 audit findings E9-E13, E15 and E16. Each test states the
# measurement that showed the bug, so a future change that reintroduces it fails here
# rather than in production.

# --- CRE-06 (E9): delta must count the units that carry a t-1 value ----------

test_that("delta counts linked non-births, not every non-birth", {
  t1 <- subset(panel_ine, wave == 1 & disposition == "R")
  t2 <- subset(panel_ine, wave == 2 & disposition == "R")
  t1$sex <- factor(t1$sex); t2$sex <- factor(t2$sex)
  Xtot <- function(d) colSums(d$pw * stats::model.matrix(~ sex, data = d))
  seed <- weighting_spec(t1, base_weights = pw) |>
    step_cre(previous = NULL, status = lf_status, formula = ~ sex,
             totals = Xtot(t1), status_ref = "inact") |> prep()

  key <- function(d) paste(d$household_id, d$person_no)
  t2$birth <- !(key(t2) %in% key(t1))
  fit <- function(d) weighting_spec(d, base_weights = pw) |>
    step_cre(previous = seed, rescale_previous = TRUE, status = lf_status, composite = list(NULL),
             id_unit = c("household_id", "person_no"), birth = birth,
             formula = ~ sex, totals = Xtot(t2), alpha = 2/3, status_ref = "inact") |> prep()
  lk <- function(f) attr(f$steps[[1]]$diagnostics, "cre_link")

  ok   <- lk(fit(t2))
  expect_identical(ok$n_missing_prev, 0L)
  expect_equal(ok$delta, ok$w_linked)

  # break the link of half the overlap: those units are NOT births, they simply fail
  # to link, so with carry_backward they carry z_{t-1} = z_t and contribute nothing.
  broken <- t2
  set.seed(1)
  ov  <- which(!broken$birth)
  brk <- sample(ov, length(ov) %/% 2L)
  broken$household_id[brk] <- paste0("X", broken$household_id[brk])
  b <- lk(suppressWarnings(fit(broken)))

  expect_gt(b$n_missing_prev, 0L)
  expect_equal(b$n_linked + b$n_missing_prev + b$n_birth, b$n_active)
  # delta must FALL with the broken links; counting them would leave it unchanged
  expect_lt(b$delta, ok$delta * 0.75)
  # and the user has to be told
  expect_warning(fit(broken), "no t-1 link")
})

# --- CRE-05 (E10): the link is against the ACTIVE previous rows --------------

test_that("a unit linked to a zero-weight previous row is not counted as overlap", {
  w1 <- subset(panel_ine, wave == 1)                 # includes the nonrespondents
  t2 <- subset(panel_ine, wave == 2 & disposition == "R")
  w1$sex <- factor(w1$sex); t2$sex <- factor(t2$sex)
  Xtot <- function(d) colSums(d$pw * stats::model.matrix(~ sex, data = d))
  prev <- weighting_spec(w1, base_weights = pw) |>
    step_nonresponse(respondent = disposition == "R", by = "sex") |>
    step_cre(previous = NULL, status = lf_status, formula = ~ sex,
             totals = Xtot(subset(w1, disposition == "R")), status_ref = "inact") |> prep()
  n_all    <- nrow(prev$data)
  n_active <- sum(weightflow:::.wf_active(prev$final_weight))
  expect_lt(n_active, n_all)                          # there ARE inactive previous rows

  f2 <- suppressWarnings(weighting_spec(t2, base_weights = pw) |>
    step_cre(previous = prev, rescale_previous = TRUE, status = lf_status, composite = list(NULL),
             id_unit = c("household_id", "person_no"), formula = ~ sex,
             totals = Xtot(t2), alpha = 2/3, status_ref = "inact") |> prep())
  lk <- attr(f2$steps[[1]]$diagnostics, "cre_link")
  # Zhat is built from the active rows only, so the linked set must be too: an upper
  # bound is the number of active previous rows.
  expect_lte(lk$n_linked, n_active)
})

# --- CRE-08 (E11): the MR1 denominator is the PREVIOUS wave's total ----------

test_that("the level estimate does not move with the scale of the incoming weights", {
  t1 <- subset(panel_ine, wave == 1 & disposition == "R")
  t2 <- subset(panel_ine, wave == 2 & disposition == "R")
  t1$sex <- factor(t1$sex); t2$sex <- factor(t2$sex)
  Xtot <- function(d) colSums(d$pw * stats::model.matrix(~ sex, data = d))
  seed <- weighting_spec(t1, base_weights = pw) |>
    step_cre(previous = NULL, status = lf_status, formula = ~ sex,
             totals = Xtot(t1), status_ref = "inact") |> prep()
  emp <- function(k) {
    d <- t2; d$pw2 <- d$pw * k                       # same design, different units
    f <- suppressWarnings(weighting_spec(d, base_weights = pw2) |>
      step_cre(previous = seed, rescale_previous = TRUE, status = lf_status, composite = list(NULL),
               id_unit = c("household_id", "person_no"), formula = ~ sex,
               totals = Xtot(t2), alpha = 0, status_ref = "inact") |> prep())
    sum(collect_weights(f)$.weight * (d$lf_status == "emp"), na.rm = TRUE)
  }
  # alpha = 0 is the MR1 branch, the one that imputes Zhat / N to the births. With N
  # taken from the CURRENT wave the answer used to depend on an arbitrary rescaling
  # of the base weights (+0.4% at 0.85x, +6.3% at 1.2x in simulation).
  expect_equal(emp(0.85), emp(1), tolerance = 1e-6)
  expect_equal(emp(1.20), emp(1), tolerance = 1e-6)
})

# --- CRE-07 (E12): a birth vector of the wrong length is an error ------------

test_that("`birth` must be a scalar or one value per unit", {
  t1 <- subset(panel_ine, wave == 1 & disposition == "R")
  t2 <- subset(panel_ine, wave == 2 & disposition == "R")
  t1$sex <- factor(t1$sex); t2$sex <- factor(t2$sex)
  Xtot <- function(d) colSums(d$pw * stats::model.matrix(~ sex, data = d))
  seed <- weighting_spec(t1, base_weights = pw) |>
    step_cre(previous = NULL, status = lf_status, formula = ~ sex,
             totals = Xtot(t1), status_ref = "inact") |> prep()
  mk <- function(b) weighting_spec(t2, base_weights = pw) |>
    step_cre(previous = seed, rescale_previous = TRUE, status = lf_status, composite = list(NULL),
             id_unit = c("household_id", "person_no"), birth = b, formula = ~ sex,
             totals = Xtot(t2), alpha = 2/3, status_ref = "inact") |> prep()
  expect_error(mk(c(TRUE, FALSE, TRUE)), "one value per unit")
  expect_no_error(suppressWarnings(mk(FALSE)))        # a scalar is still recycled
})

# --- VAR-11 (E13): lonely strata in the coordinated engines ------------------

test_that("single-PSU strata are flagged, and collapse restores a variance", {
  mkw <- function(seed, k) {
    set.seed(seed)
    d <- data.frame(stratum = rep(1:20, each = 20), pw = 10, y = stats::rnorm(400))
    d$psu <- paste0(d$stratum, "_", rep(1:2, each = 10))
    if (k > 0) {
      sel <- d$stratum %in% seq_len(k)
      d$psu[sel] <- paste0(d$stratum[sel], "_solo")
    }
    weighting_spec(d, base_weights = pw)
  }
  wb <- function(k, lp) wave_bootstrap(list(T1 = mkw(1, k), T2 = mkw(2, k)), replicates = 60,
                                       strata = "stratum", psu = "psu", seed = 1,
                                       lonely_psu = lp, progress = FALSE)
  clean <- change_mean(wb(0, "certainty"), "y")$se
  expect_gt(clean, 0)

  expect_warning(wb(20, "certainty"), "single PSU")
  degenerate <- change_mean(suppressWarnings(wb(20, "certainty")), "y")$se
  expect_equal(degenerate, 0)                          # this is what used to be silent

  fixed <- change_mean(wb(20, "collapse"), "y")$se
  expect_gt(fixed, 0)
  expect_true(is.finite(fixed))

  expect_warning(wave_jackknife(list(T1 = mkw(1, 20), T2 = mkw(2, 20)), strata = "stratum",
                                psu = "psu", progress = FALSE), "single PSU")
})

# --- EST-01 (E15): the estimand is evaluated, not looked up by name ----------

test_that("an estimand can be an expression, and a typo is an error", {
  t1 <- subset(panel_ine, wave == 1 & disposition == "R")
  t2 <- subset(panel_ine, wave == 2 & disposition == "R")
  wb <- wave_bootstrap(list(T1 = weighting_spec(t1, base_weights = pw),
                            T2 = weighting_spec(t2, base_weights = pw)),
                       replicates = 30, strata = "stratum", psu = "psu",
                       seed = 1, progress = FALSE)
  r  <- collect_estimates(wb |> step_estimate(total(income / 1000), over = "level"))$table
  truth <- sum(t1$pw * t1$income / 1000, na.rm = TRUE)
  expect_equal(r$estimate[1], truth, tolerance = 1e-6)  # used to be exactly 0
  expect_gt(r$se[1], 0)                                 # ... with an SE of 0

  expect_warning(
    expect_error(collect_estimates(wb |> step_estimate(total(no_such_column), over = "level"))),
    "no_such_column")
})

# --- TR-01 (E16): the flow table validates its inputs and reports coverage ---

test_that("gross flows refuse a missing column and report the weight they drop", {
  t1  <- subset(panel_ine, wave == 1 & disposition == "R")
  fit <- prep(weighting_spec(t1, base_weights = pw))
  expect_error(transition_matrix(fit, from = "lf_status", to = "no_existe"), "not in the data")
  expect_error(transition_matrix(t1, from = "lf_status", to = "lf_status",
                                 weights = c(10, 20)), "one weight per row")

  d <- t1
  set.seed(1)
  d$lf2 <- as.character(d$lf_status)
  d$lf2[sample(nrow(d), round(0.35 * nrow(d)))] <- NA
  f2 <- prep(weighting_spec(d, base_weights = pw))
  expect_warning(transition_matrix(f2, from = "lf_status", to = "lf2", format = "counts"),
                 "covers")
  m <- suppressWarnings(transition_matrix(f2, from = "lf_status", to = "lf2",
                                          format = "counts"))
  expect_lt(sum(m$matrix), 0.7 * sum(f2$final_weight))
})

test_that("a non-positive margin gives NA, not a ratio of 1e16", {
  d <- data.frame(a = c("x", "y"), b = c("x", "y"), w = c(5, -5))
  m <- transition_matrix(d, from = "a", to = "b", weights = "w", format = "row")
  expect_true(is.na(m$matrix["y", "y"]))
  expect_equal(unname(m$matrix["x", "x"]), 1)
})

# --- WC-03 (E6): removing a draw is proportional to the count ----------------

test_that("closing a multiplicity column downwards preserves the multinomial law", {
  # Removing k draws at random from a Multinomial(m, 1/n) must give Multinomial(m-k, 1/n).
  # Picking uniformly among the PSUs with a positive count instead inflated the per-PSU
  # variance by 13-22%, which fed straight into the chained variance.
  set.seed(2)
  R <- 8000; n <- 6L; m0 <- 5L
  for (k in 1:3) {
    m1 <- m0 - k
    M  <- matrix(as.integer(stats::rmultinom(R, m0, rep(1 / n, n))), n, R)
    got <- mean(apply(weightflow:::.wf_close_mult(M, m1)$mult, 1L, stats::var))
    ref <- m1 * (1 / n) * (1 - 1 / n)
    expect_equal(got, ref, tolerance = 0.05)
    expect_true(all(colSums(weightflow:::.wf_close_mult(M, m1)$mult) == m1))
  }
})

# --- WC-02 (E5): a fresh PSU draws from the CURRENT period's marginal --------

test_that("a PSU with no partner is drawn with the current m_h and n_h", {
  set.seed(3)
  R <- 8000; nh <- 5L; mh <- 4L
  ph <- c("a", "b", "c", "d", "e")
  Mreg <- matrix(NA_integer_, 5, R, dimnames = list(ph, NULL))
  Mreg[c("a", "b", "c"), ] <- matrix(as.integer(stats::rmultinom(R, 2L, rep(1 / 3, 3))), 3)
  out <- weightflow:::.wf_transfer_stratum(Mreg, ph, retired = character(0),
                                           mh = mh, nh = nh, R = R)
  # every column closes on m_h, and the fresh PSUs are far from the OLD law
  # Binomial(n_prev - 1, 1/n_prev) = Binomial(2, 1/3), whose variance is 0.444
  expect_true(all(colSums(out$mult) == mh))
  v_fresh <- mean(c(stats::var(out$mult["d", ]), stats::var(out$mult["e", ])))
  expect_gt(v_fresh, 0.48)
  expect_identical(out$n_fresh, 2L)
})

# --- WC-01 (E8): an all-NA multiplicity row must not claim a registry slot ---

test_that("a poisoned multiplicity row does not block an older carry", {
  R <- 5L
  good <- list(period = "t1", mult = matrix(1L, 1, R, dimnames = list("A", NULL)),
               psu_stratum = stats::setNames("h1", "A"))
  poisoned <- list(period = "t2",
                   mult = matrix(NA_integer_, 1, R, dimnames = list("A", NULL)),
                   psu_stratum = stats::setNames("h1", "A"))
  # most recent first: the poisoned carry must be passed over for the one that has it
  reg <- weightflow:::.wf_mult_registry(list(poisoned, good), "A", "h1", R)
  expect_false(anyNA(reg$mult["A", ]))
  expect_identical(unname(reg$source[["A"]]), "t1")
})

# --- WC-04 (E7): wave_contrast() checks the carries are one chain ------------

test_that("wave_contrast() refuses repeated periods and flags uncoordinated carries", {
  mk <- function(seed) {
    set.seed(seed)
    d <- do.call(rbind, lapply(1:4, function(h)
      data.frame(stratum = h, psu = paste0(h, "_", rep(1:5, each = 8)), pw = 10,
                 y = stats::rnorm(40, mean = h))))
    weighting_spec(d, base_weights = pw)
  }
  EST <- list(m = function(w, d) stats::weighted.mean(d$y, w))
  st <- function(sp, prev, per, sd)
    wave_step(sp, previous = prev, estimands = EST, replicates = 80, strata = "stratum",
              psu = "psu", period = per, seed = sd, progress = FALSE)
  a1 <- st(mk(1), NULL, "t1", 1)
  a2 <- st(mk(2), wave_carry(a1), "t2", 2)
  chain <- list(wave_carry(a1), wave_carry(a2))
  expect_no_warning(wave_contrast(chain, "m"))

  b1 <- st(mk(1), NULL, "t1", 1)
  b2 <- st(mk(2), NULL, "t2", 2)
  expect_warning(wave_contrast(list(wave_carry(b1), wave_carry(b2)), "m"),
                 "FIRST period of a chain")
  # two chains sharing a label are two different chains
  expect_error(wave_contrast(list(chain[[1]], wave_carry(b1)), "m"), "repeat the period")
})

# --- VAR-12 (E3): the previous wave is identified by content, not by size ----

test_that("a step_cre whose `previous` is not the preceding wave is not injected", {
  mk <- function(seed) {
    set.seed(seed)
    data.frame(id = 1:240, stratum = rep(1:6, each = 40),
               psu = paste0(rep(1:6, each = 40), "_", rep(1:4, each = 10)), pw = 10,
               sex = factor(sample(c("F", "M"), 240, TRUE)),
               lf = sample(c("emp", "unemp", "inact"), 240, TRUE, prob = c(.6, .1, .3)))
  }
  Xtot <- function(d) colSums(d$pw * stats::model.matrix(~ sex, data = d))
  d1 <- mk(1); d2 <- mk(2); d3 <- mk(3)          # all three have exactly 240 rows
  f1 <- weighting_spec(d1, base_weights = pw) |>
    step_cre(previous = NULL, status = lf, formula = ~ sex,
             totals = Xtot(d1), status_ref = "inact") |> prep()
  cre <- function(d, prev) weighting_spec(d, base_weights = pw) |>
    step_cre(previous = prev, rescale_previous = TRUE, status = lf, composite = list(NULL), id_unit = "id",
             formula = ~ sex, totals = Xtot(d), status_ref = "inact")
  f2 <- prep(cre(d2, f1))
  run <- function(prev3) wave_bootstrap(
    list(t1 = weighting_spec(d1, base_weights = pw), t2 = cre(d2, f1), t3 = cre(d3, prev3)),
    replicates = 40, strata = "stratum", psu = "psu", seed = 1, progress = FALSE)
  expect_no_warning(run(f2))                      # t3's previous IS t2
  expect_warning(run(f1), "not the preceding wave")   # t3 declares t1, same row count
})

# --- VAR-13 (E4): the coordination must not depend on which PSUs rotate ------

test_that("the multinomial coordinates the shared PSUs whichever ids rotate out", {
  # The sequential multinomial draws a stratum in PSU order, so a PSU coordinates exactly
  # only if no rotating PSU is drawn before it. With the shared ids sorting LAST, the
  # between-wave correlation used to come out at 0.78 of the coordinated jackknife's (the
  # deterministic oracle on the same design) instead of 1.00 -- the answer depended on
  # which ids happened to rotate out. Ordering the PSUs that appear in most waves first
  # is distribution-preserving (the multinomial is exchangeable in that order) and gives
  # the overlap units the exactly-coordinated positions.
  H <- 5; PER <- 12
  set.seed(20260911)
  uni <- do.call(rbind, lapply(seq_len(H), function(h) {
    eff <- stats::rnorm(9, 0, 0.6)
    do.call(rbind, lapply(1:9, function(j)
      data.frame(stratum = h, psu = paste0(h, "_", j), pw = 10,
                 y = stats::rnorm(PER, eff[j], 1))))
  }))
  wv <- function(ids) weighting_spec(uni[sub(".*_", "", uni$psu) %in% as.character(ids), ],
                                     base_weights = pw)
  # adverse arrangement: wave 1 holds PSUs 1-6, wave 2 holds 4-9, so the shared ids
  # (4, 5, 6) sort AFTER the three that rotate out.
  a <- wv(1:6); b <- wv(4:9)
  boot <- change_mean(wave_bootstrap(list(t1 = a, t2 = b), replicates = 1500,
                                     strata = "stratum", psu = "psu", seed = 3,
                                     progress = FALSE), "y")$rho
  jack <- change_mean(wave_jackknife(list(t1 = a, t2 = b), strata = "stratum",
                                     psu = "psu", progress = FALSE), "y")$rho
  expect_equal(boot / jack, 1, tolerance = 0.12)     # was 0.78
})

# --- VAR-15: NA in a design identifier collapses rows into one pseudo-PSU ----

test_that("the coordinated engines reject NA in strata or psu", {
  mk <- function(seed, na_psu = FALSE) {
    set.seed(seed)
    d <- data.frame(stratum = rep(1:6, each = 20), pw = 10, y = stats::rnorm(120))
    d$psu <- paste0(d$stratum, "_", rep(1:2, each = 10))
    if (na_psu) d$psu[sample(nrow(d), 12)] <- NA
    weighting_spec(d, base_weights = pw)
  }
  # suppressWarnings: this fixture's strata change PSU count between waves, which now
  # raises the coordination-drift warning (VAR9-07); the assertion here is about NA ids.
  expect_no_error(suppressWarnings(
    wave_bootstrap(list(t1 = mk(1), t2 = mk(2)), replicates = 30,
                   strata = "stratum", psu = "psu", seed = 1, progress = FALSE)))
  # every row with psu = NA pastes into the same key, so they resample as one unit
  expect_error(suppressWarnings(
    wave_bootstrap(list(t1 = mk(1), t2 = mk(2, TRUE)), replicates = 30,
                   strata = "stratum", psu = "psu", seed = 1, progress = FALSE)),
               "missing values")
  expect_error(wave_jackknife(list(t1 = mk(1), t2 = mk(2, TRUE)), strata = "stratum",
                              psu = "psu", progress = FALSE), "missing values")
  expect_error(wave_step(mk(1, TRUE), estimands = list(m = function(w, d) mean(d$y)),
                         replicates = 30, strata = "stratum", psu = "psu",
                         period = "t1", seed = 1, progress = FALSE), "missing values")
})

# --- PN-09: `cluster` in panel_design() has to compute something ------------

test_that("panel_design(cluster =) reports the cluster-level overlap", {
  pd <- panel_design(panel_ine, unit = c("household_id", "person_no"), wave = "wave",
                     rotation_group = "rotation_group", cluster = "household_id")
  p <- attr(pd, "wf_panel")
  expect_false(is.null(p$overlap_cluster))          # used to be computed nowhere
  expect_identical(dim(p$overlap_cluster), dim(p$overlap))
  expect_true(all(diag(p$overlap_cluster) == 1))
  expect_gt(p$n_clusters, 0)
  expect_lte(p$n_linked_clusters, p$n_clusters)
  expect_lt(p$n_clusters, p$n_units)                # households < persons

  # without `cluster` the field is absent, not silently zero
  pd0 <- panel_design(panel_ine, unit = c("household_id", "person_no"), wave = "wave")
  expect_null(attr(pd0, "wf_panel")$overlap_cluster)
})

# --- step_attrition() takes the arguments of step_nonresponse() -------------

test_that("step_attrition() exposes crossfit and the calibration route", {
  expect_length(setdiff(names(formals(step_nonresponse)), names(formals(step_attrition))), 0L)
  w <- subset(panel_ine, wave == 2)
  # crossfit is what the step's own alert recommends; it used not to exist
  f <- weighting_spec(w, base_weights = pw) |>
    step_attrition(respondent = disposition == "R", method = "propensity",
                   formula = ~ age + sex, crossfit = 5, crossfit_seed = 1) |>
    prep()
  expect_equal(f$steps[[1]]$crossfit, 5)
  expect_true(all(is.finite(collect_weights(f)$.weight)))
  # and the Sarndal-Lundstrom calibration route is configurable
  f2 <- weighting_spec(w, base_weights = pw) |>
    step_attrition(respondent = disposition == "R", method = "calibration",
                   formula = ~ sex, calfun = "raking") |>
    prep()
  expect_identical(f2$steps[[1]]$calfun, "raking")
})

# --- EST-02: a domain level that is NA cannot vanish in silence -------------

test_that("units with a missing domain value are reported, not just dropped", {
  t1 <- subset(panel_ine, wave == 1 & disposition == "R")
  t2 <- subset(panel_ine, wave == 2 & disposition == "R")
  set.seed(1)
  t1$region[sample(nrow(t1), round(0.12 * nrow(t1)))] <- NA
  t2$region[sample(nrow(t2), round(0.12 * nrow(t2)))] <- NA
  wb <- wave_bootstrap(list(T1 = weighting_spec(t1, base_weights = pw),
                            T2 = weighting_spec(t2, base_weights = pw)),
                       replicates = 30, strata = "stratum", psu = "psu",
                       seed = 1, progress = FALSE)
  expect_warning(
    collect_estimates(wb |> step_domain(region) |> step_estimate(mean(unemployed), over = "level")),
    "add up to the overall")
  r <- suppressWarnings(
    collect_estimates(wb |> step_domain(region) |> step_estimate(mean(unemployed), over = "level")))
  expect_false(any(is.na(r$table$region)))          # the NA cell is still not a domain
})
