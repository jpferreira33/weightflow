# Invariant / property tests: things that must ALWAYS hold, regardless of the
# particular numbers. These guard the core behaviour against silent regressions.
# (Run and adjust tolerances / column names to your data if any needs it.)

# ---- Calibration reproduces its targets ------------------------------------

test_that("linear (GREG) calibration reproduces the model-matrix totals and N", {
  X   <- model.matrix(~ region + sex, sample_survey)
  tot <- colSums(model.matrix(~ region + sex, population))
  w   <- prep(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ region + sex, totals = tot)
  )$final_weight
  expect_equal(as.numeric(colSums(w * X)), as.numeric(tot), tolerance = 1e-6)
  expect_equal(sum(w), nrow(population), tolerance = 1e-6)   # intercept constraint
})

test_that("post-stratification matches the population count in every cell", {
  rt <- as.data.frame(table(region = population$region))
  w  <- prep(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_calibrate(method = "poststratify", totals = rt, count = "Freq")
  )$final_weight
  got <- tapply(w, sample_survey$region, sum)
  expect_equal(as.numeric(got), as.numeric(table(sample_survey$region) * 0 +
                                           table(population$region)), tolerance = 1e-6)
})

test_that("raking reproduces every margin", {
  w <- prep(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_calibrate(method = "raking",
                     margins = list(region = c(table(population$region)),
                                    sex    = c(table(population$sex))))
  )$final_weight
  expect_equal(as.numeric(tapply(w, sample_survey$region, sum)),
               as.numeric(table(population$region)), tolerance = 1e-4)
  expect_equal(as.numeric(tapply(w, sample_survey$sex, sum)),
               as.numeric(table(population$sex)), tolerance = 1e-4)
})

# ---- Weight-conserving / defining identities -------------------------------

test_that("within-household selection multiplies the base weight by 1/prob", {
  # applied on rows with a valid selection probability (as it is in the cascade,
  # after the drops); the identity is w_after = w_before / prob.
  d   <- data.frame(pw = c(10, 20, 30, 40), p_within = c(0.5, 0.25, 1, 0.1))
  rec <- prep(weighting_spec(d, base_weights = pw) |> step_select_within(prob = p_within))
  expect_equal(rec$final_weight, d$pw / d$p_within, tolerance = 1e-10)
})

test_that("weighting-class nonresponse preserves the total weight in each cell", {
  w <- prep(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_nonresponse(respondent = responded, method = "weighting_class", by = "region")
  )$final_weight
  before <- tapply(sample_survey$pw, sample_survey$region, sum)
  after  <- tapply(w, sample_survey$region, sum)
  expect_equal(as.numeric(after), as.numeric(before), tolerance = 1e-6)
})

test_that("unknown-eligibility redistribution conserves the total weight", {
  w <- prep(
    weighting_spec(sample_one, base_weights = pw) |>
      step_unknown_eligibility(unknown = unknown_elig, by = "region")
  )$final_weight
  expect_equal(sum(w), sum(sample_one$pw), tolerance = 1e-6)
})

test_that("rescale hits its target sum", {
  wn <- prep(weighting_spec(sample_survey, base_weights = pw) |>
               step_rescale(to = "n"))$final_weight
  expect_equal(sum(wn), sum(wn > 0), tolerance = 1e-8)          # sum == active n
  wt <- prep(weighting_spec(sample_survey, base_weights = pw) |>
               step_rescale(to = "total", total = 10000))$final_weight
  expect_equal(sum(wt), 10000, tolerance = 1e-6)
})

test_that("trimming with redistribution preserves the total weight", {
  base <- weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
  w0 <- sum(prep(base)$final_weight)
  w1 <- sum(prep(base |> step_trim(max_ratio = 3, reference = "median",
                                   redistribute = TRUE))$final_weight)
  expect_equal(w1, w0, tolerance = 1e-6)
})

# ---- Diagnostics sanity ----------------------------------------------------

test_that("design_effect obeys its bounds", {
  de <- design_effect(c(1, 2, 3, 4, 0, 5))
  expect_gte(de$deff, 1)
  expect_lte(de$n_eff, de$n)
  expect_equal(de$cv, sqrt(de$deff - 1), tolerance = 1e-10)
})

# ---- Determinism and permutation invariance --------------------------------

test_that("prep is deterministic for the weighting steps", {
  f <- function()
    prep(weighting_spec(sample_survey, base_weights = pw) |>
           step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
           step_calibrate(method = "raking", margins = list(region = c(table(population$region)))))
  expect_equal(f()$final_weight, f()$final_weight)
})

test_that("weights do not depend on the row order of the input", {
  mk <- function(d) prep(weighting_spec(d, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(region = c(table(population$region)),
                                  sex    = c(table(population$sex)))))$final_weight
  w1  <- mk(sample_survey)
  set.seed(1); ord <- sample(nrow(sample_survey))
  w2  <- mk(sample_survey[ord, ])
  expect_equal(w2, w1[ord], tolerance = 1e-4)
})

# ---- Variance sanity -------------------------------------------------------

test_that("the bootstrap yields finite estimates and a positive SE", {
  spec <- weighting_spec(sample_one, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
  boot <- bootstrap_weights(spec, replicates = 40, strata = "region", psu = "psu",
                            seed = 1, progress = FALSE)
  est <- boot_total(boot, "responded")
  expect_equal(ncol(boot$replicates), 40L)
  expect_true(is.finite(est$estimate))
  expect_gt(est$se, 0)
})

# ---- Error / edge paths (fail loudly and clearly) --------------------------

test_that("NA base weights are rejected", {
  d <- sample_survey; d$pw[1] <- NA
  expect_error(weighting_spec(d, base_weights = pw), "NA")
})

test_that("a missing base-weight column is rejected", {
  expect_error(weighting_spec(sample_survey, base_weights = no_such_col), "not found")
})

test_that("equal_within_cluster without cluster is rejected", {
  expect_error(
    weighting_spec(sample_survey, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ region,
                     totals = c("(Intercept)" = 1), equal_within_cluster = TRUE),
    "cluster")
})

test_that("a sample cell absent from the post-stratification totals errors", {
  rt   <- as.data.frame(table(region = population$region))
  drop <- as.character(sample_survey$region[1])
  rt   <- rt[as.character(rt$region) != drop, , drop = FALSE]     # a region that IS in the sample
  expect_error(
    prep(weighting_spec(sample_survey, base_weights = pw) |>
           step_calibrate(method = "poststratify", totals = rt, count = "Freq"))
  )
})
