test_that("n_selected defaults to 1 and reproduces the classic n_eligible factor", {
  set.seed(1)
  dat <- data.frame(n_elig = c(3, 3, 5, 5, 2),
                    pw     = c(2, 2, 4, 4, 1))

  w_default <- weighting_spec(dat, base_weights = pw) |>
    step_select_within(n_eligible = n_elig) |>
    prep() |> (\(x) x$final_weight)()

  w_one <- weighting_spec(dat, base_weights = pw) |>
    step_select_within(n_eligible = n_elig, n_selected = 1) |>
    prep() |> (\(x) x$final_weight)()

  expect_equal(w_default, dat$pw * dat$n_elig, tolerance = 1e-8)
  expect_equal(w_default, w_one, tolerance = 1e-8)
})

test_that("n_selected as a single number applies n_eligible / n_selected", {
  # two persons selected per household, 4 eligible each
  dat <- data.frame(hh     = c(1, 1, 2, 2),
                    n_elig = c(4, 4, 4, 4),
                    pw     = c(3, 3, 5, 5))

  w <- weighting_spec(dat, base_weights = pw) |>
    step_select_within(n_eligible = n_elig, n_selected = 2) |>
    prep() |> (\(x) x$final_weight)()

  # each selected weight = pw * 4 / 2
  expect_equal(w, dat$pw * dat$n_elig / 2, tolerance = 1e-8)
  # the 2 selected in a household jointly represent all 4 eligible
  by_hh <- tapply(w, dat$hh, sum)
  expect_equal(as.numeric(by_hh),
               as.numeric(tapply(dat$pw * dat$n_elig, dat$hh, function(z) z[1])),
               tolerance = 1e-8)
})

test_that("n_selected as a column lets the subsample size vary by household", {
  dat <- data.frame(n_elig = c(6, 6, 6, 4, 4),
                    n_sel  = c(3, 3, 3, 2, 2),
                    pw     = c(2, 2, 2, 5, 5))

  w <- weighting_spec(dat, base_weights = pw) |>
    step_select_within(n_eligible = n_elig, n_selected = n_sel) |>
    prep() |> (\(x) x$final_weight)()

  expect_equal(w, dat$pw * dat$n_elig / dat$n_sel, tolerance = 1e-8)
})

test_that("n_eligible/n_selected equals the equivalent explicit prob", {
  dat <- data.frame(n_elig = c(5, 5, 3, 3),
                    n_sel  = c(2, 2, 1, 1),
                    pw     = c(4, 4, 7, 7))
  dat$p <- dat$n_sel / dat$n_elig

  w_k <- weighting_spec(dat, base_weights = pw) |>
    step_select_within(n_eligible = n_elig, n_selected = n_sel) |>
    prep() |> (\(x) x$final_weight)()

  w_p <- weighting_spec(dat, base_weights = pw) |>
    step_select_within(prob = p) |>
    prep() |> (\(x) x$final_weight)()

  expect_equal(w_k, w_p, tolerance = 1e-8)
})

test_that("n_selected greater than n_eligible errors", {
  dat <- data.frame(n_elig = c(2, 2), pw = c(1, 1))
  expect_error(
    weighting_spec(dat, base_weights = pw) |>
      step_select_within(n_eligible = n_elig, n_selected = 3) |>
      prep(),
    "n_selected"
  )
})

test_that("n_selected without n_eligible errors at construction", {
  dat <- data.frame(n_elig = c(2, 2), pw = c(1, 1))
  expect_error(
    weighting_spec(dat, base_weights = pw) |>
      step_select_within(n_selected = 2),
    "only applies together with"
  )
})
