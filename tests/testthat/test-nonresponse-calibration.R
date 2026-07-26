# Calibration approach to nonresponse (two-phase), method = "calibration".

test_that("linear nonresponse calibration on the saturated cell equals weighting_class", {
  # Theoretical anchor (Sarndal-Lundstrom): weighting_class is post-stratification
  # to the joint cell; calibrating on the complete cell indicator reproduces it.
  set.seed(11)
  n   <- 400
  dat <- data.frame(
    region = sample(c("N", "S", "E", "W"), n, TRUE),
    resp   = rbinom(n, 1, 0.7) == 1,
    pw     = runif(n, 1, 5)
  )

  wc <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "region") |>
    prep() |> collect_weights()

  cal <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "calibration", formula = ~ region) |>
    prep() |> collect_weights()

  expect_equal(cal, wc, tolerance = 1e-8)
})

test_that("raking distance also reproduces weighting_class on the saturated cell", {
  # Distance-independence: on a single complete categorical the solution is the
  # same for linear / raking / logit.
  set.seed(21)
  n   <- 300
  dat <- data.frame(
    grp  = sample(c("a", "b", "c"), n, TRUE),
    resp = rbinom(n, 1, 0.6) == 1,
    pw   = runif(n, 1, 4)
  )
  wc <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "grp") |>
    prep() |> collect_weights()
  cal <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "calibration", formula = ~ grp,
                     calfun = "raking") |>
    prep() |> collect_weights()
  expect_equal(cal, wc, tolerance = 1e-6)
})

test_that("sample-level calibration reproduces the R+NR estimate of the auxiliaries", {
  # The defining guarantee: over the calibrated respondents, the weighted totals
  # of the auxiliaries equal those over R+NR with the incoming weights.
  set.seed(12)
  n   <- 500
  dat <- data.frame(
    x    = rnorm(n, 10, 3),
    grp  = sample(c("a", "b", "c"), n, TRUE),
    resp = rbinom(n, 1, 0.65) == 1,
    pw   = runif(n, 1, 4)
  )
  fit <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "calibration", formula = ~ grp + x) |>
    prep()
  w <- collect_weights(fit, drop_zero = FALSE)$.weight   # full-length, aligned

  expect_equal(sum(w * dat$x), sum(dat$pw * dat$x), tolerance = 1e-6)  # continuous
  expect_equal(sum(w), sum(dat$pw), tolerance = 1e-6)                  # intercept -> N
  # each group total preserved
  for (g in unique(dat$grp))
    expect_equal(sum(w[dat$grp == g]), sum(dat$pw[dat$grp == g]), tolerance = 1e-6)
  expect_true(all(w[!dat$resp] == 0))                                 # NR dropped
})

test_that("population totals path calibrates respondents to supplied totals", {
  set.seed(14)
  n   <- 400
  dat <- data.frame(
    sex  = sample(c("M", "F"), n, TRUE),
    resp = rbinom(n, 1, 0.7) == 1,
    pw   = runif(n, 1, 5)
  )
  tot <- c("(Intercept)" = 10000, sexM = 4800)   # aligned with model.matrix(~ sex)
  fit <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = resp, method = "calibration", formula = ~ sex,
                     totals = tot) |>
    prep()
  w <- collect_weights(fit, drop_zero = FALSE)$.weight
  expect_equal(sum(w), 10000, tolerance = 1e-6)
  expect_equal(sum(w[dat$sex == "M"]), 4800, tolerance = 1e-6)
})

test_that("missing auxiliaries among nonrespondents raise an informative error", {
  set.seed(13)
  n   <- 200
  dat <- data.frame(
    z    = c(rnorm(n - 5), rep(NA, 5)),
    resp = c(rep(TRUE, n - 5), rep(FALSE, 5)),
    pw   = runif(n, 1, 3)
  )
  expect_error(
    weighting_spec(dat, base_weights = pw) |>
      step_nonresponse(respondent = resp, method = "calibration", formula = ~ z) |>
      prep(),
    "missing values"
  )
})

test_that("sample-level coincidence holds on bundled sample_survey across calfun", {
  # On real bundled data, after unknown-eligibility, the calibrated respondents
  # reproduce the R+NR totals of region/sex/age for linear and raking distances.
  skip_if_not(exists("sample_survey"))
  data(sample_survey, package = "weightflow", envir = environment())
  d    <- sample_survey
  form <- ~ region + sex + age

  base_only <- weighting_spec(d, base_weights = pw) |>
    step_unknown_eligibility(unknown = unknown_elig) |>
    prep()
  w_in  <- collect_weights(base_only, drop_zero = FALSE)$.weight
  X     <- stats::model.matrix(form, data = d)
  elig  <- w_in > 0
  T_RNR <- colSums(w_in[elig] * X[elig, , drop = FALSE])

  for (cf in c("linear", "raking")) {
    f <- weighting_spec(d, base_weights = pw) |>
      step_unknown_eligibility(unknown = unknown_elig) |>
      step_nonresponse(respondent = responded, method = "calibration",
                       formula = form, calfun = cf) |>
      prep()
    w <- collect_weights(f, drop_zero = FALSE)$.weight
    expect_equal(unname(colSums(w * X)), unname(T_RNR),
                 tolerance = 1e-6, info = paste("calfun =", cf))
  }
})

test_that("equal_within_cluster without cluster is rejected at build time", {
  expect_error(
    weighting_spec(data.frame(a = 1, resp = TRUE, pw = 1), base_weights = pw) |>
      step_nonresponse(respondent = resp, method = "calibration", formula = ~ a,
                       equal_within_cluster = TRUE),
    "requires .cluster."
  )
})

test_that("integrative nonresponse calibration keeps weights constant within household", {
  # Household design (constant base weight within household), household-level
  # nonresponse, person-level auxiliaries. Integrative calibration must give one
  # weight per responding household AND still reproduce the R+NR totals.
  set.seed(31)
  n_hh  <- 400
  sizes <- sample(1:4, n_hh, replace = TRUE)
  hh    <- rep(seq_len(n_hh), sizes)
  N     <- length(hh)
  dat   <- data.frame(
    hh  = hh,
    sex = factor(sample(c("F", "M"),      N, replace = TRUE)),
    reg = factor(sample(c("a", "b", "c"), N, replace = TRUE)),
    pw  = 10                                   # equal base weight (household design)
  )
  resp_hh        <- runif(n_hh) < 0.7          # whole household responds or not
  dat$responded  <- resp_hh[dat$hh]

  fit <- weighting_spec(dat, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "calibration",
                     formula = ~ sex + reg, cluster = "hh",
                     equal_within_cluster = TRUE) |>
    prep()
  w <- collect_weights(fit, drop_zero = FALSE)$.weight

  # (a) one weight per responding household (constant within household)
  act <- w > 0
  const <- tapply(w[act], dat$hh[act], function(z) diff(range(z)))
  expect_true(all(const < 1e-6))
  # (b) nonresponding households dropped
  expect_true(all(w[!dat$responded] == 0))
  # (c) R+NR sample totals of the auxiliaries preserved
  X     <- stats::model.matrix(~ sex + reg, dat)
  T_RNR <- colSums(dat$pw * X)
  expect_equal(unname(colSums(w * X)), unname(T_RNR), tolerance = 1e-6)
})
