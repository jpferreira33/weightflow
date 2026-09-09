# step_cross_sectional() / step_longitudinal() declare the recipe's purpose without
# touching the weights; the panel detail lives in panel_design(), so they take no args.

panel_data <- function() {
  d <- rbind(data.frame(id = 1:3, mes = "T1", gr = 1:3, w = 10),
             data.frame(id = 1:3, mes = "T2", gr = 1:3, w = 10))
  panel_design(d, unit = "id", wave = "mes", rotation_group = "gr")
}

test_that("scope steps declare purpose and leave weights unchanged", {
  pd <- panel_data()
  fit <- weighting_spec(pd, base_weights = w) |> step_longitudinal() |> prep()
  expect_equal(fit$final_weight, rep(10, 6))                       # identity on weights

  specL <- weighting_spec(pd, base_weights = w) |> step_longitudinal()
  specC <- weighting_spec(pd, base_weights = w) |> step_cross_sectional()
  spec0 <- weighting_spec(pd, base_weights = w)                    # no scope step
  expect_identical(weightflow:::.wf_purpose(specL), "longitudinal")
  expect_identical(weightflow:::.wf_purpose(specC), "cross_sectional")
  expect_identical(weightflow:::.wf_purpose(spec0), "cross_sectional")  # default
})

test_that("step_longitudinal warns without a panel_design; reference_wave is carried", {
  plain <- data.frame(id = 1:3, w = 10)
  expect_warning(weighting_spec(plain, base_weights = w) |> step_longitudinal(),
                 "panel_design")
  pd <- panel_data()
  expect_identical(attr(pd, "wf_panel")$reference_wave, "T1")      # default = first wave
})

test_that("step_panel_overlap warns on panel data without step_longitudinal", {
  pd <- panel_data()
  expect_warning(weighting_spec(pd, base_weights = w) |> step_panel_overlap(prob = 0.75),
                 "step_longitudinal")
  # declared -> no warning
  expect_warning(weighting_spec(pd, base_weights = w) |>
                   step_longitudinal() |> step_panel_overlap(prob = 0.75), NA)
  # plain (non-panel) data with an explicit prob -> no warning
  plain <- data.frame(w = c(10, 20))
  expect_warning(weighting_spec(plain, base_weights = w) |> step_panel_overlap(prob = 0.75), NA)
})
