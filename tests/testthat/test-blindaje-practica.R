# Real production-practice situations.
# Data as it really arrives (tibbles, characters, NA in cells),
# composite cascades, and the replication machinery under awkward data.

prac_d <- function(n = 400, seed = 3) {
  set.seed(seed)
  data.frame(id = 1:n,
             x = factor(sample(c("A", "B"), n, TRUE)),
             hh = rep(1:(n / 2), each = 2),
             w = runif(n, 1, 3),
             resp = rbinom(n, 1, 0.7) == 1, y = rnorm(n, 10))
}

test_that("a dplyr tibble works end-to-end like a data.frame", {
  skip_if_not_installed("dplyr")
  d  <- prac_d()
  td <- dplyr::as_tibble(d)
  wd <- collect_weights(suppressMessages(prep(weighting_spec(d,  base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x"))),
    drop_zero = FALSE)$.weight
  wt <- collect_weights(suppressMessages(prep(weighting_spec(td, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x"))),
    drop_zero = FALSE)$.weight
  expect_equal(wd, wt)
})

test_that("`by` on a character column behaves like the factor version", {
  d <- prac_d(); d$xc <- as.character(d$x)
  wf_ <- collect_weights(suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x"))),
    drop_zero = FALSE)$.weight
  wc <- collect_weights(suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "xc"))),
    drop_zero = FALSE)$.weight
  expect_equal(wf_, wc)
})

test_that("NA in the cell variable forms a '(missing)' cell (with a warning); respondents there keep positive weight", {
  d <- prac_d(); d$x[c(5, 9, 13, 17)] <- NA; d$resp[c(5, 9)] <- TRUE
  expect_warning(
    p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
      step_nonresponse(respondent = resp, method = "weighting_class", by = "x"))),
    "missing")
  ww <- collect_weights(p, drop_zero = FALSE)$.weight
  expect_true(all(ww[c(5, 9)] > 0))                        # respondentes (missing)-cell adjusted
  expect_equal(sum(ww), sum(d$w), tolerance = 1e-8)        # masa conservada
})

test_that("a two-level nonresponse cascade (household then person) runs and zeroes correctly", {
  d <- prac_d()
  d$hh_resp <- rep(rbinom(nrow(d) / 2, 1, 0.8) == 1, each = 2)
  d$hhgrp   <- rep(sample(c("g1", "g2"), nrow(d) / 2, TRUE), each = 2)  # household-level group
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = hh_resp, method = "weighting_class",
                     by = "hhgrp", cluster = "hh") |>       # by constant within household
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  ww <- collect_weights(p, drop_zero = FALSE)$.weight
  expect_true(all(ww[!d$hh_resp] == 0))                    # hogares no respondentes: fuera
  expect_true(all(ww[d$hh_resp & !d$resp] == 0))           # personas no respondentes: fuera
  expect_true(all(ww[d$hh_resp & d$resp] > 0))
})

test_that("pre- and post-calibration in the same recipe hit the final margins", {
  d <- prac_d()
  marg <- setNames(as.numeric(tapply(d$w, d$x, sum)) * 1.05, levels(d$x))
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_calibrate(method = "raking", margins = list(x = marg)) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x") |>
    step_calibrate(method = "raking", margins = list(x = marg))))
  cw <- collect_weights(p)
  tot <- tapply(cw$.weight, cw$x, sum)
  expect_lt(max(abs(as.numeric(tot[names(marg)]) - marg) / marg), 1e-6)
})

test_that("bootstrap survives a rare calibration cell and returns a finite SE", {
  d <- prac_d()
  d$cel <- factor(c(rep("rara", 6), rep(c("c1", "c2"), length.out = nrow(d) - 6)))
  d$psu <- rep(1:20, each = 20); d$str <- rep(1:4, each = 100)
  marg <- setNames(as.numeric(tapply(d$w, d$cel, sum)) * 1.05, levels(d$cel))
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_calibrate(method = "raking", margins = list(cel = marg))))
  b <- suppressWarnings(bootstrap_weights(p, replicates = 40, strata = "str",
                                          psu = "psu", seed = 7))
  # dropping non-finite replicates from a rare cell must warn loudly, not fail
  expect_warning(se <- boot_mean(b, "y")$se, "non-finite replicate")
  expect_true(is.finite(se) && se > 0)
})

test_that("recipe-aware bootstrap works with domain-partitioned calibration inside", {
  d <- prac_d()
  d$dom <- factor(rep(c("d1", "d2"), each = nrow(d) / 2))
  d$psu <- rep(1:20, each = 20); d$str <- rep(1:2, each = 200)
  tot <- aggregate(d$w, by = list(dom = d$dom, x = d$x), sum)
  names(tot)[3] <- "Freq"; tot$Freq <- tot$Freq * 1.04
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_calibrate(method = "raking", totals = list(tot), count = "Freq", by = "dom")))
  b <- suppressWarnings(bootstrap_weights(p, replicates = 30, strata = "str",
                                          psu = "psu", seed = 5))
  expect_true(is.finite(boot_mean(b, "y")$se))
})

test_that("tiny inputs do not crash: a 1-row sample preps; a stepless prep summarises and plots", {
  d <- prac_d()
  expect_s3_class(suppressMessages(prep(weighting_spec(d[1, ], base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x"))),
    "prepped_weighting_spec")
  p0 <- suppressMessages(prep(weighting_spec(d, base_weights = w)))
  expect_no_error({ invisible(capture.output(summary(p0))); pdf(NULL); plot(p0); dev.off() })
})

test_that("step_assert(on_fail = 'error') stops the cascade with an informative message", {
  d <- prac_d()
  sp <- weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x") |>
    step_assert(max_weight_ratio = 1.0001, on_fail = "error")
  expect_error(suppressMessages(prep(sp)), "Assertion")
})

test_that("design_effect on an equal-weight vector is exactly 1", {
  de <- design_effect(rep(2, 100))
  expect_equal(de$deff, 1); expect_equal(de$n_eff, 100)
})

test_that("the full 6-step cascade renders a report with trim and AAPOR content", {
  d <- prac_d()
  d$inel <- rbinom(nrow(d), 1, .05) == 1
  d$unk  <- rbinom(nrow(d), 1, .05) == 1 & !d$inel
  marg <- setNames(as.numeric(tapply(d$w, d$x, sum)) * 1.05, levels(d$x))
  p <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_unknown_eligibility(unknown = unk, by = "x") |>
    step_drop_ineligible(ineligible = inel) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x") |>
    step_calibrate(method = "raking", margins = list(x = marg)) |>
    step_trim_weights(lower = 0.5, upper = 15) |>
    step_round(digits = 0, method = "preserve_total")))
  f <- tempfile(fileext = ".html")
  suppressMessages(report_weighting(p, file = f, open = FALSE,
                                    metadata = list(operation = "Prueba", period = "2026")))
  h <- paste(readLines(f, warn = FALSE), collapse = "")
  expect_true(grepl("trim", h, ignore.case = TRUE))
  expect_true(grepl("AAPOR", h))
  expect_true(grepl("Prueba", h))
})
