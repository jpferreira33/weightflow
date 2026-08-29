# as_sae_input(): direct estimate + design SE + n_eff per domain, for SAE input.

test_that("as_sae_input returns per-domain direct estimates with a design SE and rating", {
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(region = c(table(population$region))))
  boot <- suppressWarnings(
    bootstrap_weights(spec, replicates = 40, strata = "region", psu = "psu",
                      seed = 1, progress = FALSE))
  out <- as_sae_input(boot, "responded", by = "region")
  expect_true(all(c("domain", "n", "n_eff", "estimate", "se", "cv",
                    "ci_lower", "ci_upper", "rating") %in% names(out)))
  expect_equal(nrow(out), length(unique(as.character(sample_survey$region))))
  expect_true(all(is.finite(out$se) & out$se >= 0))
  expect_true(all(out$n_eff <= out$n + 1e-6))               # Kish n_eff <= n
  expect_s3_class(out$rating, "factor")
  expect_true(all(as.character(out$rating) %in%
                  c("publishable", "review", "not publishable")))
})

test_that("as_sae_input validates its inputs", {
  spec <- weighting_spec(sample_survey, base_weights = pw)
  boot <- suppressWarnings(
    bootstrap_weights(spec, replicates = 20, strata = "region", psu = "psu",
                      seed = 1, progress = FALSE))
  expect_error(as_sae_input(boot, "responded", by = "nope"), "domain column")
  expect_error(as_sae_input(boot, "nosuchvar", by = "region"), "column name")
  expect_error(as_sae_input(42, "responded", by = "region"), "weightflow_boot")
})
