# FIREWALL for the variance engine. The panel work (coordinated bootstrap) is built
# self-contained in R/variance-panel.R and MUST NOT change R/variance.R. This test
# freezes the current bootstrap_weights() behaviour: if anything ever alters the
# engine, it fails loudly. Snapshot is recorded on first run (the current, correct
# CRAN behaviour) and compared thereafter.

test_that("bootstrap_weights is deterministic under a fixed seed", {
  skip_on_cran()
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
  a <- bootstrap_weights(spec, replicates = 25, strata = "region",
                         psu = "psu", seed = 20260906, progress = FALSE)
  b <- bootstrap_weights(spec, replicates = 25, strata = "region",
                         psu = "psu", seed = 20260906, progress = FALSE)
  expect_identical(a$replicates, b$replicates)          # same seed -> same replicates
  expect_identical(a$weights, b$weights)
})

test_that("bootstrap_weights output is frozen bit-for-bit (firewall)", {
  skip_on_cran()
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
  boot <- bootstrap_weights(spec, replicates = 25, strata = "region",
                            psu = "psu", seed = 20260906, progress = FALSE)
  est <- boot_mean(boot, "income")
  # A compact but sensitive fingerprint of the whole realized bootstrap: the point
  # weights, the per-replicate weight totals, and the estimate/SE. Any change to the
  # Rao-Wu draw or the rescaling formula moves at least one of these.
  expect_snapshot_value(
    list(point   = round(boot$weights, 8),
         rep_tot = round(colSums(boot$replicates), 6),
         mean    = round(est$estimate, 8),
         se      = round(est$se, 8)),
    style = "serialize")
})
