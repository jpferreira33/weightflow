# Gross flows: transition_matrix() (point) and boot_transition() (per-cell bootstrap SE) on
# the longitudinal weight of the wide file. Labour state is derived from the employment items.

estado <- function(oc) ifelse(is.na(oc), "inactivo", ifelse(oc == 1, "ocupado", "desocupado"))
LEV <- c("ocupado", "desocupado", "inactivo")

long_fit <- function() {
  wide <- panel_merge(list(T1 = panel_ine[panel_ine$ola == 1, ],
                           T2 = panel_ine[panel_ine$ola == 2, ]),
                      by = c("id_hogar", "nper"), require = "all")
  wide$estado_T1 <- estado(wide$ocupado_T1)
  wide$estado_T2 <- estado(wide$ocupado_T2)
  spec <- weighting_spec(wide, base_weights = w_base_T1) |>
    step_panel_overlap(prob = 5 / 6) |>
    step_drop_ineligible(disp_T2 == "OS") |>
    step_attrition(respondent = disp_T2 == "R", method = "weighting_class", by = "region_T1")
  list(spec = spec, fit = prep(spec))
}

test_that("transition_matrix returns a valid conditional flow matrix", {
  tm <- transition_matrix(long_fit()$fit, from = "estado_T1", to = "estado_T2",
                          states = LEV, format = "row")
  expect_s3_class(tm, "weightflow_transition")
  expect_equal(dim(tm$matrix), c(3L, 3L))
  expect_true(all(tm$matrix >= 0 & tm$matrix <= 1 + 1e-8))
  rs <- rowSums(tm$matrix)                         # row format: each non-empty row is a distribution
  expect_true(all(abs(rs - 1) < 1e-8 | rs < 1e-8))
})

test_that("counts and joint formats are consistent", {
  fit <- long_fit()$fit
  cnt <- transition_matrix(fit, "estado_T1", "estado_T2", states = LEV, format = "counts")$matrix
  jnt <- transition_matrix(fit, "estado_T1", "estado_T2", states = LEV, format = "joint")$matrix
  expect_equal(sum(jnt), 1, tolerance = 1e-8)
  expect_equal(jnt, cnt / sum(cnt), tolerance = 1e-8)
})

test_that("boot_flows gives gross-flow TOTALS, net flows and margins, all with SE", {
  skip_on_cran()
  L <- long_fit()
  boot <- bootstrap_weights(L$spec, replicates = 80, strata = "estrato_T1",
                            psu = "psu_T1", seed = 1, progress = FALSE)
  fl <- boot_flows(boot, "estado_T1", "estado_T2", states = LEV)
  expect_s3_class(fl, "weightflow_flows")
  expect_equal(dim(fl$counts), c(3L, 3L))
  expect_true(all(is.finite(fl$counts_se) & fl$counts_se >= 0))
  expect_equal(as.numeric(fl$net), as.numeric(-t(fl$net)), tolerance = 1e-8)   # net is antisymmetric
  expect_equal(unname(fl$origin), unname(rowSums(fl$counts)), tolerance = 1e-6)   # margins consistent
  expect_equal(unname(fl$dest),   unname(colSums(fl$counts)), tolerance = 1e-6)
  expect_true(is.finite(fl$stayers_se) && is.finite(fl$movers_se))
  expect_output(print(fl), "gross flows")
})

test_that("boot_transition adds a per-cell standard error from the replicates", {
  skip_on_cran()
  L <- long_fit()
  boot <- bootstrap_weights(L$spec, replicates = 60, strata = "estrato_T1",
                            psu = "psu_T1", seed = 1, progress = FALSE)
  bt <- boot_transition(boot, "estado_T1", "estado_T2", states = LEV, format = "row")
  expect_s3_class(bt, "weightflow_transition_boot")
  expect_equal(dim(bt$se), c(3L, 3L))
  expect_true(all(is.finite(bt$se) & bt$se >= 0))
  # point estimate matches transition_matrix() on the same weights
  tm <- transition_matrix(L$fit, "estado_T1", "estado_T2", states = LEV, format = "row")
  expect_equal(bt$estimate, tm$matrix, tolerance = 1e-8)
  expect_output(print(bt), "transition")
})
