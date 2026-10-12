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

# REF-01. The reference's weights used to live only in an attribute, and `[.data.frame`
# carries a classed frame's attributes through unchanged. Reordering the rows therefore
# left the weights in the old order, silently paired with the new rows -- and reordering
# a reference to add the domain column `by =` wants is an ordinary thing to do.

test_that("the reference's weights follow its rows when they are reordered or subset", {
  ref <- data.frame(id = 1:6, age = c(50, 20, 40, 10, 30, 60),
                    d = c(100, 2, 50, 1, 20, 200))
  rs  <- reference_sample(ref, "d")

  r2 <- rs[order(rs$age), ]                      # reordered
  expect_equal(weightflow:::.wf_ref_weights(r2), r2$d)
  expect_equal(weightflow:::.wf_ref_weights(r2), c(1, 2, 20, 50, 100, 200))

  r3 <- rs[rs$age > 15, ]                        # subset
  expect_equal(length(weightflow:::.wf_ref_weights(r3)), nrow(r3))
  expect_equal(weightflow:::.wf_ref_weights(r3), r3$d)

  # replicates travel too
  rep <- matrix(runif(6 * 4, 0.5, 1.5) * ref$d, nrow = 6)
  rsr <- reference_sample(ref, "d", replicates = rep)
  k   <- c(5L, 1L, 3L)
  expect_equal(weightflow:::.wf_ref_reps(rsr[k, ]), rep[k, , drop = FALSE])
})

test_that("a reference built before REF-01 is refused rather than used misaligned", {
  ref <- data.frame(id = 1:6, age = c(50, 20, 40, 10, 30, 60),
                    d = c(100, 2, 50, 1, 20, 200))
  old <- ref                                     # attribute only, as older versions wrote it
  attr(old, "wf_ref_weights") <- ref$d
  class(old) <- c("wf_reference_sample", class(old))
  expect_equal(weightflow:::.wf_ref_weights(old), ref$d)          # untouched: still fine
  expect_error(weightflow:::.wf_ref_weights(old[old$age > 15, ]),
               "carries 6 weights for 5 rows")
})

test_that("reference_sample() refuses data that already uses its reserved column names", {
  ref <- data.frame(id = 1:3, d = c(1, 2, 3), .wf_ref_w = c(9, 9, 9))
  expect_error(reference_sample(ref, "d"), "reserved for the reference weights")
})

test_that("reordering the reference does not move the pseudo-weighted estimate", {
  set.seed(11)
  N   <- 4000
  pop <- data.frame(x = rnorm(N), g = factor(sample(c("a", "b"), N, TRUE)))
  pop$y <- 10 + 2 * pop$x + rnorm(N)
  vol <- pop[runif(N) < stats::plogis(-2 + 1.1 * pop$x), ]
  idx <- sample.int(N, 400)
  ref <- pop[idx, c("x", "g")]; ref$d <- N / 400

  fit <- function(r) suppressWarnings(prep(
    weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
      step_pseudoweight(reference = r, formula = ~ x + g, engine = "logit")))

  rs <- reference_sample(ref, "d")
  a  <- fit(rs)
  b  <- fit(rs[order(rs$x), ])                   # the same reference, rows reordered
  expect_equal(a$final_weight, b$final_weight, tolerance = 1e-10)
})
