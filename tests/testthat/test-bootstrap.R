test_that("bootstrap_weights returns a replicate matrix of the right shape", {
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(region = c(table(population$region))))
  boot <- bootstrap_weights(spec, replicates = 15, strata = "region",
                            psu = "psu", seed = 7, progress = FALSE)
  expect_s3_class(boot, "weightflow_boot")
  expect_equal(dim(boot$replicates), c(nrow(sample_survey), 15))
  expect_equal(length(boot$weights), nrow(sample_survey))
})

test_that("bootstrap estimates have positive standard errors", {
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class",
                     by = "region") |>
    step_calibrate(method = "raking",
                   margins = list(region = c(table(population$region))))
  boot <- bootstrap_weights(spec, replicates = 20, strata = "region",
                            psu = "psu", seed = 11, progress = FALSE)
  # Use a continuous outcome: its weighted mean is not pinned by the margins,
  # so it genuinely varies across replicates (unlike a calibration-implied total).
  est <- boot_mean(boot, "income")
  expect_true(est$se > 0)
  expect_true(est$ci_lower < est$estimate && est$estimate < est$ci_upper)
})

test_that("a single-PSU stratum is handled with a warning, not an error", {
  d <- sample_survey
  d$region <- as.character(d$region)
  d$region[1] <- "Solo"; d$psu[1] <- -999          # a lone PSU in its own stratum
  spec <- weighting_spec(d, base_weights = pw)
  expect_warning(
    bootstrap_weights(spec, replicates = 5, strata = "region", psu = "psu",
                      seed = 3, progress = FALSE),
    "single PSU")
})

test_that("lonely_psu = 'collapse' resamples single-PSU strata without warning", {
  set.seed(9)
  strata <- c(rep("A", 100), rep("B", 100), "C")            # C is a lone-PSU stratum
  psu    <- c(paste0("A", rep(1:4, each = 25)),
              paste0("B", rep(1:4, each = 25)), "C1")
  dat <- data.frame(stratum = strata, psu = psu,
                    y = rnorm(201), w = runif(201, 1, 3))
  spec <- weighting_spec(dat, base_weights = w)

  expect_warning(                                            # default: certainty warns
    bootstrap_weights(spec, replicates = 10, strata = "stratum", psu = "psu",
                      seed = 1, progress = FALSE),
    "single PSU")
  expect_warning(                                            # collapse: no lonely warning
    boot <- bootstrap_weights(spec, replicates = 10, strata = "stratum", psu = "psu",
                              lonely_psu = "collapse", seed = 1, progress = FALSE),
    regexp = NA)
  expect_true(boot_total(boot, "y")$se > 0)
})

test_that("bootstrap is bit-identical serial vs parallel (same seed)", {
  skip_on_cran()
  skip_on_os("windows")
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(region = c(table(population$region))))
  b1 <- bootstrap_weights(spec, replicates = 8, strata = "region", psu = "psu",
                          seed = 42, cores = 1, progress = FALSE)
  b2 <- bootstrap_weights(spec, replicates = 8, strata = "region", psu = "psu",
                          seed = 42, cores = 2, progress = FALSE)
  expect_equal(b1$replicates, b2$replicates, tolerance = 1e-12)
})

test_that("collect_replicate_weights returns point + replicate columns", {
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(region = c(table(population$region))))
  boot <- bootstrap_weights(spec, replicates = 12, strata = "region",
                            psu = "psu", seed = 5, progress = FALSE)
  df <- collect_replicate_weights(boot)
  expect_true(all(df$.weight > 0))
  expect_equal(sum(grepl("^rep_", names(df))), 12)
  expect_equal(attr(df, "R"), 12)
  expect_equal(nrow(df), sum(boot$weights > 0))
})
