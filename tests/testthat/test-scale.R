# Scale / performance smoke test: a full recipe + 200-replicate bootstrap on a
# large synthetic sample, to catch blow-ups before they show up in production.
# Skipped by default (it is slow); enable with WEIGHTFLOW_SCALE=1.

test_that("a full recipe + bootstrap scales to tens of thousands of units", {
  skip_on_cran()
  skip_if(Sys.getenv("WEIGHTFLOW_SCALE") != "1",
          "set WEIGHTFLOW_SCALE=1 to run the scale test")

  set.seed(1)
  n <- 20000L
  d <- data.frame(
    region    = sample(c("N", "S", "E", "W"), n, TRUE),
    sex       = sample(c("M", "F"), n, TRUE),
    age       = sample(18:90, n, TRUE),
    strata    = sample(1:5, n, TRUE),
    responded = rbinom(n, 1, 0.8),
    y         = rnorm(n, 100, 20))
  d$psu <- paste0(d$strata, "-", sample(1:120, n, TRUE))
  d$w0  <- runif(n, 50, 150)
  N     <- sum(d$w0)
  tgt_region <- prop.table(table(d$region)) * N     # consistent targets (sum to N)
  tgt_sex    <- prop.table(table(d$sex))    * N

  spec <- weighting_spec(d, base_weights = w0) |>
    step_nonresponse(respondent = responded == 1, method = "weighting_class",
                     by = c("region", "sex")) |>
    step_calibrate(method = "raking",
                   margins = list(region = tgt_region, sex = tgt_sex))

  t0   <- Sys.time()
  rec  <- prep(spec)
  boot <- bootstrap_weights(spec, replicates = 200, strata = "strata", psu = "psu",
                            seed = 1, progress = FALSE)
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  expect_true(all(is.finite(rec$final_weight)))
  expect_equal(ncol(boot$replicates), 200L)
  expect_true(is.finite(boot_mean(boot, "y")$se))
  message(sprintf("scale test: %d units, 200 replicates in %.1fs", n, secs))
})
