# step_calibrate() with a reference_sample() as `population`: the calibration
# targets are the design-weighted sums over the reference. Point estimate must
# match passing those same targets as numbers; a replicate index re-derives the
# targets from the paired reference replicate (variance propagation).

make_rc <- function(n, seed) {
  set.seed(seed)
  data.frame(region = factor(sample(c("A", "B", "C"), n, TRUE), levels = c("A", "B", "C")),
             w = stats::runif(n, 0.5, 2))
}

test_that("raking to a reference_sample == passing the reference-derived margins", {
  samp <- make_rc(300, 1); samp$pw <- 10
  ref  <- make_rc(2000, 2); ref$w <- stats::runif(nrow(ref), 5, 15)
  m_reg <- tapply(ref$w, ref$region, sum); m_reg <- stats::setNames(as.numeric(m_reg), names(m_reg))

  w_num <- (weighting_spec(samp, base_weights = pw) |>
    step_calibrate(method = "raking", margins = list(region = m_reg)) |> prep())$final_weight
  w_ref <- (weighting_spec(samp, base_weights = pw) |>
    step_calibrate(method = "raking", formula = ~ region,
                   population = reference_sample(ref, "w")) |> prep())$final_weight
  expect_equal(w_ref, w_num, tolerance = 1e-8)
})

test_that("linear calibration to a reference_sample == passing the reference-derived totals", {
  samp <- make_rc(300, 3); samp$pw <- 10
  ref  <- make_rc(2000, 4); ref$w <- stats::runif(nrow(ref), 5, 15)
  X   <- stats::model.matrix(~ region, ref)
  tot <- stats::setNames(as.numeric(colSums(X * ref$w)), colnames(X))

  w_num <- (weighting_spec(samp, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ region, totals = tot) |> prep())$final_weight
  w_ref <- (weighting_spec(samp, base_weights = pw) |>
    step_calibrate(method = "linear", formula = ~ region,
                   population = reference_sample(ref, "w")) |> prep())$final_weight
  expect_equal(w_ref, w_num, tolerance = 1e-8)
})

test_that("poststratify to a reference_sample == passing the reference-derived cell totals", {
  samp <- make_rc(300, 7); samp$pw <- 10
  ref  <- make_rc(2000, 8); ref$w <- stats::runif(nrow(ref), 5, 15)
  agg  <- stats::aggregate(list(Freq = ref$w), by = list(region = ref$region), FUN = sum)

  w_num <- (weighting_spec(samp, base_weights = pw) |>
    step_calibrate(method = "poststratify", totals = agg, count = "Freq") |> prep())$final_weight
  w_ref <- (weighting_spec(samp, base_weights = pw) |>
    step_calibrate(method = "poststratify", formula = ~ region,
                   population = reference_sample(ref, "w")) |> prep())$final_weight
  expect_equal(w_ref, w_num, tolerance = 1e-8)
})

test_that("a replicate index re-derives the targets from the paired reference replicate", {
  samp <- make_rc(300, 5); samp$pw <- 10
  ref  <- make_rc(2000, 6); ref$w <- stats::runif(nrow(ref), 5, 15)
  reps <- cbind(ref$w, ifelse(ref$region == "B", ref$w * 3, ref$w))   # col 2 tilted

  spec <- weighting_spec(samp, base_weights = pw) |>
    step_calibrate(method = "raking", formula = ~ region,
                   population = reference_sample(ref, "w", replicates = reps))
  w_pt <- prep(spec)$final_weight

  sp1 <- spec; attr(sp1$data, "wf_replicate_idx") <- 1L      # col 1 == point weights
  expect_equal(prep(sp1)$final_weight, w_pt, tolerance = 1e-8)
  sp2 <- spec; attr(sp2$data, "wf_replicate_idx") <- 2L      # tilted -> different targets
  expect_false(isTRUE(all.equal(prep(sp2)$final_weight, w_pt)))
})

test_that("step_calibrate + population validates its inputs", {
  samp <- make_rc(60, 9);  samp$pw <- 10
  ref  <- make_rc(120, 10); ref$w <- 1
  expect_error(
    weighting_spec(samp, base_weights = pw) |>
      step_calibrate(method = "raking", population = reference_sample(ref, "w")),
    "formula")
  expect_error(
    weighting_spec(samp, base_weights = pw) |>
      step_calibrate(method = "raking", formula = ~ region,
                     margins = list(region = c(A = 1, B = 1, C = 1)),
                     population = reference_sample(ref, "w")),
    "do not also pass")
})
