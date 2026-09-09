# step_panel_overlap() divides the base weight by Pr(panel selection); panel_pr()
# derives that probability from a panel_design() with a rotation group.

test_that("panel_pr returns the group-continuity probability", {
  d <- rbind(data.frame(id = c(1, 2, 3, 4), mes = "T1", grp = c(1, 2, 3, 4)),
             data.frame(id = c(2, 3, 4, 5), mes = "T2", grp = c(2, 3, 4, 1)))
  pd <- panel_design(d, unit = "id", wave = "mes", rotation_group = "grp")
  expect_equal(panel_pr(pd, c("T1", "T2")), 0.75)   # 3 of 4 group cohorts persist
  expect_equal(panel_pr(pd), 0.75)                  # default = all waves
})

test_that("step_panel_overlap divides by a constant probability", {
  dat <- data.frame(pw = c(10, 20, 30), x = 1:3)
  fit <- weighting_spec(dat, base_weights = pw) |>
    step_panel_overlap(prob = 0.75) |>
    prep()
  expect_equal(fit$final_weight, c(10, 20, 30) / 0.75)
})

test_that("step_panel_overlap accepts a per-unit probability column", {
  dat <- data.frame(pw = c(10, 20, 30), p = c(0.5, 0.75, 1))
  fit <- weighting_spec(dat, base_weights = pw) |>
    step_panel_overlap(prob = p) |>
    prep()
  expect_equal(fit$final_weight, c(10, 20, 30) / c(0.5, 0.75, 1))
})

test_that("panel_pr feeds step_panel_overlap end to end", {
  d <- rbind(data.frame(id = c(1, 2, 3, 4), mes = "T1", grp = c(1, 2, 3, 4)),
             data.frame(id = c(2, 3, 4, 5), mes = "T2", grp = c(2, 3, 4, 1)))
  pd <- panel_design(d, unit = "id", wave = "mes", rotation_group = "grp")
  dat <- data.frame(pw = c(100, 100, 100))
  fit <- weighting_spec(dat, base_weights = pw) |>
    step_panel_overlap(prob = panel_pr(pd, c("T1", "T2"))) |>
    prep()
  expect_equal(fit$final_weight, rep(100 / 0.75, 3))   # factor 4/3
})

test_that("step_panel_overlap and panel_pr validate inputs", {
  dat <- data.frame(pw = c(10, 20), p = c(0, 1.5))
  expect_error(
    weighting_spec(dat, base_weights = pw) |> step_panel_overlap(prob = p) |> prep(),
    "in \\(0, 1\\]")
  d <- rbind(data.frame(id = 1:2, mes = "T1"), data.frame(id = 1:2, mes = "T2"))
  pd <- panel_design(d, unit = "id", wave = "mes")           # no rotation_group
  expect_error(panel_pr(pd), "rotation_group")
})
