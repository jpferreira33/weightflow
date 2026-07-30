make_df <- function(n = 2500L, seed = 1L) {
  set.seed(seed)
  x  <- rnorm(n)
  pw <- exp(0.8 * x)                       # peso correlacionado con la covariable
  resp <- rbinom(n, 1, plogis(-0.2 + 0.6 * x))
  data.frame(pw = pw, x = x, resp = resp)
}

fin <- function(df, ...) {
  weighting_spec(df, base_weights = pw) |>
    step_nonresponse(resp, method = "propensity", formula = ~ x,
                     num_classes = NULL, ...) |>
    prep() |>
    collect_weights(drop_zero = FALSE)
}

test_that("weight_model = FALSE changes the propensity fit (final weights differ)", {
  df <- make_df()
  w_wt  <- fin(df, weight_model = TRUE)$.weight
  w_unw <- fin(df, weight_model = FALSE)$.weight
  expect_false(isTRUE(all.equal(w_wt, w_unw)))
})

test_that("weight_model default is TRUE (weighted fit)", {
  df <- make_df()
  w_def  <- fin(df)$.weight
  w_true <- fin(df, weight_model = TRUE)$.weight
  expect_equal(w_def, w_true)
})

test_that("weight_model works at household (cluster) level", {
  set.seed(3)
  H <- 1200L
  hh <- data.frame(hid = seq_len(H), x = rnorm(H))
  hh$pw <- exp(0.7 * hh$x)
  hh$resp <- rbinom(H, 1, plogis(-0.1 + 0.5 * hh$x))
  members <- hh[rep(seq_len(H), sample(1:4, H, replace = TRUE)), ]
  f <- function(...) weighting_spec(members, base_weights = pw) |>
    step_nonresponse(resp, method = "propensity", formula = ~ x,
                     cluster = "hid", num_classes = NULL, ...) |>
    prep() |> collect_weights(drop_zero = FALSE)
  w_wt  <- f(weight_model = TRUE)$.weight
  w_unw <- f(weight_model = FALSE)$.weight
  expect_false(isTRUE(all.equal(w_wt, w_unw)))
})
