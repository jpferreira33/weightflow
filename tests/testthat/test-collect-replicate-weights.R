# collect_replicate_weights() must work for both replication objects: a
# bootstrap (weightflow_boot) and a delete-a-PSU jackknife (weightflow_jack),
# attaching the correct replication scaling per method.

rw_spec <- function() {
  weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(region = c(table(population$region))))
}

test_that("collect_replicate_weights() accepts a bootstrap object (scale 1/R, unit rscales)", {
  b  <- bootstrap_weights(rw_spec(), replicates = 20, strata = "region",
                          psu = "psu", seed = 1, progress = FALSE)
  df <- collect_replicate_weights(b)
  expect_true(".weight" %in% names(df))
  expect_equal(sum(grepl("^rep_", names(df))), 20L)
  expect_identical(attr(df, "type"), "bootstrap")
  expect_equal(attr(df, "scale"), 1 / 20)
  expect_equal(attr(df, "rscales"), rep(1, 20))
})

test_that("collect_replicate_weights() accepts a jackknife object (scale 1, (n_h-1)/n_h rscales)", {
  j  <- jackknife_weights(rw_spec(), strata = "region", psu = "psu",
                          lonely_psu = "collapse", progress = FALSE)
  df <- collect_replicate_weights(j)
  expect_s3_class(j, "weightflow_jack")
  expect_true(".weight" %in% names(df))
  expect_equal(sum(grepl("^rep_", names(df))), j$R)
  expect_identical(attr(df, "type"), "other")
  expect_equal(attr(df, "scale"), 1)
  expect_equal(attr(df, "rscales"), (j$rep_nh - 1) / j$rep_nh)
})
