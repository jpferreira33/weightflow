test_that("household-level unknown eligibility uses one weight per household", {
  # 3 households (weight 10 each); hh3 unknown with 5 members.
  # Household factor = (3 hh * 10) / (2 known hh * 10) = 1.5  -> known weights 15.
  # (A person-level adjustment would instead give 70/20 = 3.5.)
  hid <- c(1, 2, 3, 3, 3, 3, 3)
  unk <- c(0, 0, 1, 1, 1, 1, 1)
  pw  <- rep(10, 7)
  dat <- data.frame(hid, unk, pw)
  fitted <- weighting_spec(dat, base_weights = pw) |>
    step_unknown_eligibility(unknown = unk, cluster = "hid") |>
    prep()
  w <- fitted$final_weight
  expect_equal(w[1], 15)
  expect_equal(w[2], 15)
  expect_true(all(w[3:7] == 0))
})

test_that("household-level adjustment keeps weights uniform within household", {
  hid <- c(1, 1, 1, 2, 2, 3)
  unk <- c(0, 0, 0, 0, 0, 1)
  pw  <- rep(8, 6)
  dat <- data.frame(hid, unk, pw)
  w <- prep(weighting_spec(dat, base_weights = pw) |>
              step_unknown_eligibility(unknown = unk, cluster = "hid"))$final_weight
  expect_equal(length(unique(w[hid == 1])), 1L)
  expect_equal(length(unique(w[hid == 2])), 1L)
  expect_equal(w[6], 0)
})

test_that("step_select_within multiplies by the inverse selection probability", {
  dat <- data.frame(pw = c(10, 10, 10), n_elig = c(2, 4, 1), p = c(0.5, 0.25, 1))
  w_k <- prep(weighting_spec(dat, base_weights = pw) |>
                step_select_within(n_eligible = n_elig))$final_weight
  w_p <- prep(weighting_spec(dat, base_weights = pw) |>
                step_select_within(prob = p))$final_weight
  expect_equal(w_k, c(20, 40, 10))
  expect_equal(w_p, c(20, 40, 10))   # 1/p == n_elig in this example
})

test_that("step_select_within rejects invalid probabilities", {
  dat <- data.frame(pw = c(10, 10), p = c(0, 1.2))
  expect_error(
    prep(weighting_spec(dat, base_weights = pw) |> step_select_within(prob = p)))
})
