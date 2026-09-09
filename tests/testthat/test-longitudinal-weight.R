# Longitudinal weight (case c): built by REUSING the cascade on the wide file, restricted to
# the units in sample in all waves (the overlapping rotation groups). Its variance is the
# ordinary bootstrap. These tests check the frame selection, the disposition handling
# (OS -> 0, respondents -> > 0) and that reason= is recorded; they apply to pure and rotating.

long_wide <- function(df, waves = 1:2) {
  parts <- lapply(waves, function(t) df[df$ola == t, ])
  names(parts) <- paste0("T", waves)
  panel_merge(parts, by = c("id_hogar", "nper"), require = "all")
}
long_fit <- function(wide, prob = 1) {
  suppressWarnings(prep(
    weighting_spec(wide, base_weights = w_base_T1) |>
      step_panel_overlap(prob = prob) |>
      step_unknown_eligibility(disp_T2 == "UNK", by = "region_T1") |>
      step_drop_ineligible(disp_T2 == "OS", reason = "left universe") |>
      step_nonresponse(respondent = disp_T2 == "R", method = "weighting_class", by = "region_T1")))
}

test_that("require = 'all' keeps only the overlapping frame (in sample in every wave)", {
  wide <- long_wide(panel_ine, 1:2)
  expect_true(all(wide$.wf_in_T1 == 1L & wide$.wf_in_T2 == 1L))
  expect_lte(nrow(wide), min(sum(panel_ine$ola == 1), sum(panel_ine$ola == 2)))
  expect_gt(nrow(wide), 0L)
})

test_that("longitudinal weight: OS drop to 0, respondents stay positive (rotating panel)", {
  wide <- long_wide(panel_ine, 1:2)
  w    <- collect_weights(long_fit(wide, prob = 5 / 6), drop_zero = FALSE)$.weight
  expect_length(w, nrow(wide))
  if (any(wide$disp_T2 == "OS")) expect_true(all(w[wide$disp_T2 == "OS"] == 0))
  expect_true(all(w[wide$disp_T2 == "R"] > 0))
  expect_true(is.finite(sum(w)) && sum(w) > 0)
})

test_that("the same recipe builds a pure-panel longitudinal weight (Pr = 1)", {
  wide <- long_wide(panel_puro, 1:2)
  w    <- collect_weights(long_fit(wide, prob = 1), drop_zero = FALSE)$.weight
  expect_true(all(w[wide$disp_T2 == "R"] > 0))
  if (any(wide$disp_T2 == "OS")) expect_true(all(w[wide$disp_T2 == "OS"] == 0))
})

test_that("its variance is the ordinary bootstrap (case c), not the coordinated one", {
  skip_on_cran()
  wide <- long_wide(panel_ine, 1:2)
  spec <- weighting_spec(wide, base_weights = w_base_T1) |>
    step_panel_overlap(prob = 5 / 6) |>
    step_drop_ineligible(disp_T2 == "OS") |>
    step_nonresponse(respondent = disp_T2 == "R", method = "weighting_class", by = "region_T1")
  boot <- bootstrap_weights(spec, replicates = 100, strata = "estrato_T1",
                            psu = "psu_T1", seed = 1)
  est  <- bootstrap_estimate(boot, function(w, d) stats::weighted.mean(d$ingreso_T2, w, na.rm = TRUE))
  expect_true(is.finite(est$estimate) && est$se > 0)
})

test_that("step_drop_ineligible records the reason for the narrative", {
  sp <- weighting_spec(long_wide(panel_ine, 1:2), base_weights = w_base_T1) |>
    step_drop_ineligible(disp_T2 == "OS", reason = "left target population between waves")
  drop <- sp$steps[[length(sp$steps)]]
  expect_equal(drop$reason, "left target population between waves")
  expect_match(drop$label, "left target population")
})
