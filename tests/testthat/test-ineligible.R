test_that("step_drop_ineligible zeroes ineligibles without redistributing", {
  dat <- data.frame(pw = c(10, 10, 10, 10), inelig = c(0, 0, 1, 1))
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_drop_ineligible(ineligible = inelig) |>
    prep()
  w <- fitted$final_weight
  expect_equal(w, c(10, 10, 0, 0))      # ineligibles zeroed
  expect_equal(sum(w), 20)              # their weight discarded, not redistributed
})

test_that("unknown-eligibility then drop-ineligible gives the correct eligible total", {
  # eligible W_e = 20 (2x10), ineligible W_i = 10, unknown W_u = 10
  # factor = (20+10+10)/(20+10) = 40/30; eligible total after = 20 * 40/30
  dat <- data.frame(
    pw   = c(10, 10, 10, 10),
    unk  = c(0, 0, 0, 1),
    inel = c(0, 0, 1, 0)
  )
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_unknown_eligibility(unknown = unk) |>
    step_drop_ineligible(ineligible = inel) |>
    prep()
  w <- fitted$final_weight
  expect_equal(sum(w), 20 * (40 / 30), tolerance = 1e-8)  # eligible population total
  expect_equal(w[3], 0)   # ineligible dropped (after absorbing its share)
  expect_equal(w[4], 0)   # unknown dropped by the eligibility step
})
