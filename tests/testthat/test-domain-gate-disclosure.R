# domain_summary(min_n_eff=) publication gate, collect_replicate_weights(scramble=)
# and disclosure_risk(): the domain / confidentiality tools.

test_that("domain_summary min_n_eff adds publishable and warns on small domains", {
  fit <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    prep()
  # a huge threshold makes every domain fall below -> warning + all not publishable
  expect_warning(d <- domain_summary(fit, by = "region", min_n_eff = 1e6),
                 "publication threshold")
  expect_true("publishable" %in% names(d))
  expect_false(any(d$publishable))
  # a tiny threshold: everyone passes, no warning, no NA
  d2 <- domain_summary(fit, by = "region", min_n_eff = 1)
  expect_true(all(d2$publishable))
  expect_error(domain_summary(fit, by = "region", min_n_eff = -5), "positive")
})

test_that("collect_replicate_weights(scramble=) preserves the variance and hides the design", {
  skip_if_not_installed("survey")
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
  boot <- suppressWarnings(bootstrap_weights(spec, replicates = 40, strata = "region",
                                             psu = "psu", seed = 1, progress = FALSE))
  plain <- collect_replicate_weights(boot)
  set.seed(7)
  scr   <- collect_replicate_weights(boot, scramble = TRUE)
  # design identifier columns are dropped from the scrambled export
  expect_true(all(c("region", "psu") %in% names(plain)))
  expect_false(any(c("region", "psu") %in% names(scr)))
  expect_true(isTRUE(attr(scr, "scrambled")))
  # same replicate design metadata, same number of replicates
  expect_equal(attr(scr, "R"), attr(plain, "R"))
  # variance is invariant: the set of replicate columns is a permutation
  rp <- as.matrix(plain[, grep("^rep_", names(plain))])
  rs <- as.matrix(scr[,   grep("^rep_", names(scr))])
  expect_equal(sort(unname(colSums(rp))), sort(unname(colSums(rs))))
})

test_that("disclosure_risk flags an outlier weight within its cell", {
  fit <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    prep()
  # inject a large weight into one unit and check it is flagged within its cell
  fake <- fit
  fake$final_weight[1] <- 50 * max(fit$final_weight)   # a lone dominant weight
  dr <- disclosure_risk(fake, by = "region", ratio = 10)
  expect_true(nrow(dr) >= 1L)
  expect_true(1L %in% dr$.row)
  expect_true(all(dr$weight > dr$cell_median * 10))
  # a calm recipe flags nothing at a high ratio
  expect_equal(nrow(disclosure_risk(fit, by = "region", ratio = 500)), 0L)
  expect_error(disclosure_risk(fit, by = "region", ratio = 0.5), "greater than 1")
})
