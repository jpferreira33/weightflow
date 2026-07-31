test_that(".with_reldiff inserts a relative-% column right after 'achieved'", {
  d   <- data.frame(variable = c("a", "b"), target = c(1000, 2000),
                    achieved = c(1010, 1990), stringsAsFactors = FALSE)
  out <- weightflow:::.with_reldiff(d, "en")
  expect_true("rel. diff (%)" %in% names(out))
  expect_equal(which(names(out) == "rel. diff (%)"),
               which(names(out) == "achieved") + 1L)
  expect_match(out[["rel. diff (%)"]][1], "+1.00%", fixed = TRUE)
  expect_match(out[["rel. diff (%)"]][2], "-0.50%", fixed = TRUE)
})

test_that(".with_reldiff is a no-op without target/achieved", {
  d <- data.frame(propensity_class = 1:2, n = c(10, 20))
  expect_identical(weightflow:::.with_reldiff(d, "en"), d)
})

test_that(".attention_panel surfaces non-convergence and alerts, empty when clean", {
  dbad <- data.frame(x = 1); attr(dbad, "converged") <- FALSE
  obj <- list(steps = list(
    list(label = "calibrate (linear)", diagnostics = dbad, alerts = NULL),
    list(label = "trim", diagnostics = data.frame(x = 1),
         alerts = c("final weights capped at 5"))))
  h <- weightflow:::.attention_panel(obj, "en")
  expect_match(h, "Points of attention")
  expect_match(h, "did not converge")
  expect_match(h, "final weights capped at 5")
  # clean recipe -> no panel
  ok <- data.frame(x = 1); attr(ok, "converged") <- TRUE
  clean <- list(steps = list(list(label = "calibrate", diagnostics = ok, alerts = NULL)))
  expect_identical(weightflow:::.attention_panel(clean, "en"), "")
})
