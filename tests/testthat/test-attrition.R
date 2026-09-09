# step_attrition(): the panel-facing attrition step. It delegates to step_nonresponse (reusing
# the tested estimators) under a name that reads in a longitudinal cascade, with the correct
# method naming: "propensity" = individual 1/phi (the SLID / ECLAC response-propensity method,
# Naud 2002 / LaRoche 2003), "rhg" = binned propensity classes.

long_wide <- function() {
  panel_merge(list(T1 = panel_ine[panel_ine$ola == 1, ], T2 = panel_ine[panel_ine$ola == 2, ]),
              by = c("id_hogar", "nper"), require = "all")
}

test_that("step_attrition delegates and records the method", {
  wide <- long_wide()
  fit <- weighting_spec(wide, base_weights = w_base_T1) |>
    step_drop_ineligible(disp_T2 == "OS") |>
    step_attrition(respondent = disp_T2 == "R", method = "weighting_class", by = "region_T1") |>
    prep()
  st <- fit$steps[[length(fit$steps)]]
  expect_true(inherits(st, "step_nonresponse"))            # reuses the engine
  expect_equal(st$attrition_method, "weighting_class")
  expect_match(st$label, "attrition")
  w <- collect_weights(fit, drop_zero = FALSE)$.weight
  expect_true(all(w[wide$disp_T2 == "OS"] == 0))
  expect_true(all(w[wide$disp_T2 == "R"] > 0))
})

test_that("method = 'propensity' is individual 1/phi; 'rhg' bins into classes", {
  wide <- long_wide()
  base <- weighting_spec(wide, base_weights = w_base_T1) |>
    step_drop_ineligible(disp_T2 == "OS")
  # the key behaviour is the constructor translation (checked on the unprepped step); the
  # response is independent of the covariates here, so glm() warns about ~degenerate fitted
  # probabilities -- benign, and irrelevant to what we test, so suppress it.
  specp <- base |> step_attrition(respondent = disp_T2 == "R", method = "propensity",
                                  formula = ~ edad_T1 + sexo_T1)
  specr <- base |> step_attrition(respondent = disp_T2 == "R", method = "rhg",
                                  formula = ~ edad_T1 + sexo_T1, num_classes = 5)
  expect_null(specp$steps[[length(specp$steps)]]$num_classes)   # continuous 1/phi
  expect_equal(specr$steps[[length(specr$steps)]]$num_classes, 5L)  # response homogeneity groups
  fp <- suppressWarnings(prep(specp)); fr <- suppressWarnings(prep(specr))
  expect_true(all(collect_weights(fp, drop_zero = FALSE)$.weight[wide$disp_T2 == "R"] > 0))
  expect_true(all(collect_weights(fr, drop_zero = FALSE)$.weight[wide$disp_T2 == "R"] > 0))
})

test_that("chaining step_attrition per wave IS the discrete-time hazard (multiplicative)", {
  # phi_t is fitted only on the ACTIVE units (.wf_active), so chaining conditions each wave
  # on the prior survivors -> the retention product 1/prod(phi_t) emerges from the recipe,
  # monotone (no resurrection): whoever drops at wave 2 stays 0 even if they respond at wave 3.
  wide <- panel_merge(list(T1 = panel_ine[panel_ine$ola == 1, ],
                           T2 = panel_ine[panel_ine$ola == 2, ],
                           T3 = panel_ine[panel_ine$ola == 3, ]),
                      by = c("id_hogar", "nper"), require = "all")
  fit <- weighting_spec(wide, base_weights = w_base_T1) |>
    step_attrition(respondent = disp_T2 == "R", method = "weighting_class", by = "region_T1") |>
    step_attrition(respondent = disp_T3 == "R", method = "weighting_class", by = "region_T1") |>
    prep()
  w <- collect_weights(fit, drop_zero = FALSE)$.weight
  surv <- wide$disp_T2 == "R" & wide$disp_T3 == "R"
  expect_true(all(w[wide$disp_T2 != "R"] == 0))               # dropped at wave 2 (no resurrection)
  expect_true(all(w[wide$disp_T2 == "R" & wide$disp_T3 != "R"] == 0))  # dropped at wave 3
  expect_true(all(w[surv] > 0))                                # survivors carry the product
  expect_equal(sum(w > 0), sum(surv))                          # active set = responded all waves
})

test_that("the longitudinal cascade uses step_attrition end to end", {
  skip_on_cran()
  wide <- long_wide()
  spec <- weighting_spec(wide, base_weights = w_base_T1) |>
    step_panel_overlap(prob = 5 / 6) |>
    step_drop_ineligible(disp_T2 == "OS", reason = "left target population between waves") |>
    step_attrition(respondent = disp_T2 == "R", method = "weighting_class", by = "region_T1")
  w <- collect_weights(prep(spec), drop_zero = FALSE)$.weight
  expect_true(is.finite(sum(w)) && sum(w) > 0)
  boot <- bootstrap_weights(spec, replicates = 60, strata = "estrato_T1", psu = "psu_T1",
                            seed = 1, progress = FALSE)
  est <- bootstrap_estimate(boot, function(w, d) stats::weighted.mean(d$ingreso_T2, w, na.rm = TRUE))
  expect_true(is.finite(est$estimate) && est$se > 0)
})
