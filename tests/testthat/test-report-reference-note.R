# When a calibration step calibrates to totals ESTIMATED from a reference_sample(),
# the HTML report must say so: in the step narrative and in the replication card.
# Fixed totals (no reference replicates) -> a caveat; propagated (replicates
# supplied) -> the Opsomer-Erciulescu note.

mk_rs <- function(n, seed, wcol = FALSE) {
  set.seed(seed)
  d <- data.frame(
    region = factor(sample(c("A", "B", "C"), n, TRUE), levels = c("A", "B", "C")),
    psu    = sample(paste0("p", seq_len(20)), n, TRUE),
    pw     = 10)
  if (wcol) d$w <- stats::runif(n, 5, 15)
  d
}

test_that("report flags estimated control totals and, without replicates, the fixed-totals caveat", {
  samp <- mk_rs(200, 1); ref <- mk_rs(800, 2, wcol = TRUE)
  fit <- weighting_spec(samp, base_weights = pw) |>
    step_calibrate(method = "raking", formula = ~ region,
                   population = reference_sample(ref, "w")) |>
    prep()
  f <- tempfile(fileext = ".html")
  expect_no_error(report_weighting(fit, file = f, open = FALSE, lang = "en"))
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_match(html, "estimated from a reference survey", fixed = TRUE)
  expect_match(html, "treated as fixed", fixed = TRUE)
})

test_that("with reference replicates the report shows the propagated (Opsomer-Erciulescu) note", {
  samp <- mk_rs(200, 3); ref <- mk_rs(800, 4, wcol = TRUE)
  reps <- matrix(rep(ref$w, 4L), ncol = 4L)          # >= 2 finite non-negative cols
  spec <- weighting_spec(samp, base_weights = pw) |>
    step_calibrate(method = "raking", formula = ~ region,
                   population = reference_sample(ref, "w", replicates = reps))
  fit  <- prep(spec)
  boot <- suppressWarnings(bootstrap_weights(spec, replicates = 30, psu = "psu",
                                             seed = 1, progress = FALSE))
  f <- tempfile(fileext = ".html")
  expect_no_error(report_weighting(fit, file = f, open = FALSE, lang = "en", replicates = boot))
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_match(html, "estimated from a reference survey", fixed = TRUE)
  expect_match(html, "propagated", fixed = TRUE)
  expect_match(html, "Opsomer", fixed = TRUE)
})

test_that("a plain (census-frame) calibration shows no reference-sample note", {
  samp <- mk_rs(200, 5)
  fit <- weighting_spec(samp, base_weights = pw) |>
    step_calibrate(method = "raking",
                   margins = list(region = c(A = 700, B = 700, C = 600))) |>
    prep()
  f <- tempfile(fileext = ".html")
  report_weighting(fit, file = f, open = FALSE, lang = "en")
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_false(grepl("estimated from a reference survey", html, fixed = TRUE))
})
