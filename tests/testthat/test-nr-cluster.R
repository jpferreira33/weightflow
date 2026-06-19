test_that("household-level weighting-class nonresponse adjusts per household", {
  # 3 households (weight 10); hh1, hh2 respond; hh3 (3 members) does not.
  # Household factor = (3 hh * 10) / (2 resp hh * 10) = 1.5 -> responders 15.
  # (A person-level adjustment would give 50/20 = 2.5 -> 25 instead.)
  hid  <- c(1, 2, 3, 3, 3)
  resp <- c(1, 1, 0, 0, 0)
  pw   <- rep(10, 5)
  dat  <- data.frame(hid, resp, pw)
  w <- prep(weighting_spec(dat, base_weights = pw) |>
              step_nonresponse(respondent = resp, method = "weighting_class",
                               cluster = "hid"))$final_weight
  expect_equal(w[1], 15)
  expect_equal(w[2], 15)
  expect_true(all(w[3:5] == 0))
  expect_equal(sum(w), 30)        # household total weight preserved
})

test_that("household-level propensity nonresponse runs and zeroes nonrespondents", {
  set.seed(21)
  nh  <- 40
  hid <- rep(seq_len(nh), each = 2)
  x   <- rep(rnorm(nh), each = 2)                 # household-level covariate
  rsp <- rep(rbinom(nh, 1, plogis(0.5 + x)), each = 2)
  pw  <- rep(5, length(hid))
  dat <- data.frame(hid, x, resp = rsp, pw)
  w <- prep(weighting_spec(dat, base_weights = pw) |>
              step_nonresponse(respondent = resp, method = "propensity",
                               formula = ~ x, engine = "logit",
                               num_classes = NULL, cluster = "hid"))$final_weight
  expect_true(all(w[dat$resp == 0] == 0))
  expect_true(all(w[dat$resp == 1] > 0))
})
