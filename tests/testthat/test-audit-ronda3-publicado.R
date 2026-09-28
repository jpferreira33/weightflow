# Round-3 audit, the findings that are against 1.2.0 as published: the adjustment-cell
# key (CELL-01), the confidentiality screen (SDC-01), the SAE publication gate
# (SAE-01/SAE-02) and largest-remainder rounding (ROUND-01). Every one of them was
# silent: no error, no warning, and a diagnostics table that looked right.

test_that("CELL-01: a separator inside a `by` value does not merge two cells", {
  g1 <- rep(c("a | b", "a", "x"), each = 40)
  g2 <- rep(c("c", "b | c", "y"), each = 40)
  d  <- data.frame(w0 = 10, g1 = g1, g2 = g2, resp = rep(c(1, 0), 60))
  d$resp[d$g1 == "a"] <- 0                       # the cell ("a", "b | c") has no respondent
  p <- suppressWarnings(prep(
    weighting_spec(d, base_weights = w0) |>
      step_nonresponse(respondent = resp == 1, by = c("g1", "g2")), warn = FALSE))

  # three cells, not two: ("a | b","c") and ("a","b | c") used to paste to the same string
  expect_equal(nrow(p$steps[[1]]$diagnostics), 3L)
  cw <- collect_weights(p, drop_zero = FALSE)
  got <- tapply(cw$.weight, paste0(cw$g1, "//", cw$g2), sum)
  expect_equal(unname(got[["a | b//c"]]), 400)   # was 800: the merged cell doubled it
  expect_equal(unname(got[["a//b | c"]]), 0)

  # and the alert the merge used to swallow is back
  expect_true(any(grepl("no units to adjust to", weighting_alerts(p))))

  # a control run with the pipes removed from the values must agree exactly
  d2 <- d; d2$g1 <- gsub(" \\| ", "_", d2$g1); d2$g2 <- gsub(" \\| ", "_", d2$g2)
  p2 <- suppressWarnings(prep(
    weighting_spec(d2, base_weights = w0) |>
      step_nonresponse(respondent = resp == 1, by = c("g1", "g2")), warn = FALSE))
  expect_equal(sort(collect_weights(p2, drop_zero = FALSE)$.weight),
               sort(cw$.weight))

  # a genuine "(missing)" value stays distinct from an NA
  d3 <- data.frame(w0 = 10, g = c(rep("(missing)", 30), rep(NA, 30), rep("z", 30)),
                   resp = rep(c(1, 0), 45))
  p3 <- suppressWarnings(prep(
    weighting_spec(d3, base_weights = w0) |>
      step_nonresponse(respondent = resp == 1, by = "g"), warn = FALSE))
  expect_equal(nrow(p3$steps[[1]]$diagnostics), 3L)

  # ordinary values are untouched: no label changes for data without pipes
  expect_identical(.wf_cell_escape(c("Montevideo", "25-34", NA)),
                   c("Montevideo", "25-34", NA))
})

test_that("SDC-01: disclosure_risk() screens the missing cell instead of skipping it", {
  set.seed(2); n <- 300
  d <- data.frame(w0 = runif(n, 5, 20), reg = sample(c("N", "S"), n, TRUE))
  d$reg[seq_len(40)] <- NA
  p <- prep(weighting_spec(d, base_weights = w0), warn = FALSE)
  p$final_weight[5] <- 1e6                       # unit 5 is in the NA cell
  dr <- disclosure_risk(p, by = "reg", ratio = 3)
  expect_true(5L %in% dr$.row)                   # used to return zero rows
  expect_equal(dr$cell[dr$.row == 5L], "(missing)")

  # a cell whose median is <= 0 is screened on its positive weights, and says so
  d2 <- data.frame(w0 = runif(n, 5, 20), reg = rep(c("N", "S"), length.out = n))
  p2 <- prep(weighting_spec(d2, base_weights = w0), warn = FALSE)
  neg <- which(d2$reg == "S")
  p2$final_weight[neg] <- -abs(p2$final_weight[neg])
  p2$final_weight[neg[1]] <- 5000
  expect_warning(disclosure_risk(p2, by = "reg", ratio = 3), "non-positive median")

  # a share of a non-positive total is NA, not 1000%
  dr2 <- suppressWarnings(disclosure_risk(p2, by = "reg", ratio = 3))
  expect_true(all(is.na(dr2$cell_share[dr2$cell == "S"]) |
                  dr2$cell_share[dr2$cell == "S"] <= 1))
})

test_that("SAE-01/02: as_sae_input() does not publish a phantom area or a degenerate one", {
  set.seed(2); n <- 400
  d <- data.frame(w0 = runif(n, 5, 20), str = 1, psu = rep(1:40, each = 10),
                  y = rlnorm(n, 8, 0.5))
  d$dom <- sample(c("A1", "A2", "A3"), n, TRUE)
  d$dom[seq_len(60)] <- NA
  b <- bootstrap_weights(prep(weighting_spec(d, base_weights = w0), warn = FALSE),
                         replicates = 40, strata = "str", psu = "psu",
                         progress = FALSE, seed = 1)
  expect_warning(as_sae_input(b, variable = "y", by = "dom"), "not a small area")
  s <- suppressWarnings(as_sae_input(b, variable = "y", by = "dom"))
  expect_false("NA" %in% s$domain)                # the phantom area is gone
  expect_setequal(s$domain, c("A1", "A2", "A3"))

  # a degenerate domain (se == 0) is not publishable, nor is an unrated one
  d2 <- d; d2$dom[is.na(d2$dom)] <- "A0"; d2$bin <- 0
  tiny <- which(d2$dom == "A3")[1:4]
  d2$dom[tiny] <- "TINY"; d2$bin[tiny] <- 1
  b2 <- bootstrap_weights(prep(weighting_spec(d2, base_weights = w0), warn = FALSE),
                          replicates = 40, strata = "str", psu = "psu",
                          progress = FALSE, seed = 1)
  s2 <- suppressWarnings(as_sae_input(b2, variable = "bin", by = "dom"))
  expect_equal(s2$se[s2$domain == "TINY"], 0)
  expect_equal(as.character(s2$rating[s2$domain == "TINY"]), "not publishable")
  expect_false(any(is.na(s2$rating)))             # estimate == 0 left rating NA before
})

test_that("ROUND-01: preserve_total breaks ties at random, not by row order", {
  d <- data.frame(w0 = 12.5, reg = rep(c("North", "South"), each = 50))
  r <- t(replicate(120, {
    p  <- prep(weighting_spec(d, base_weights = w0) |>
                 step_round(method = "preserve_total", digits = 0))
    cw <- collect_weights(p, drop_zero = FALSE)
    c(sum(cw$.weight), sum(cw$.weight[cw$reg == "North"]))
  }))
  expect_true(all(r[, 1] == 1250))                # the promise is kept exactly
  # row order used to give North 650 and South 600 on every single run
  expect_lt(abs(mean(r[, 2]) - 625), 3)
  expect_gt(stats::sd(r[, 2]), 0)

  # reproducible given a seed, and untouched where the fractions are distinct
  set.seed(4); a <- prep(weighting_spec(d, base_weights = w0) |>
                           step_round(method = "preserve_total"))$final_weight
  set.seed(4); b <- prep(weighting_spec(d, base_weights = w0) |>
                           step_round(method = "preserve_total"))$final_weight
  expect_identical(a, b)
  set.seed(1); d2 <- data.frame(w0 = stats::runif(100, 10, 20))
  set.seed(9); x1 <- prep(weighting_spec(d2, base_weights = w0) |>
                            step_round(method = "preserve_total"))$final_weight
  set.seed(8); x2 <- prep(weighting_spec(d2, base_weights = w0) |>
                            step_round(method = "preserve_total"))$final_weight
  expect_identical(x1, x2)
})

test_that("TRIM-01: `kappa` prices bias against variance in the Potter cutoff", {
  set.seed(11); wv <- stats::rlnorm(300, 3, 0.8)
  cuts <- vapply(c(0.25, 0.5, 1, 2, 4),
                 function(k) as.numeric(.potter_threshold(wv, kappa = k)), numeric(1))
  expect_true(all(diff(cuts) > 0))               # more weight on bias -> cap later
  # the default is exactly what it always was
  expect_equal(as.numeric(.potter_threshold(wv)),
               as.numeric(.potter_threshold(wv, kappa = 1)))

  d <- data.frame(w0 = wv)
  up <- function(k) prep(weighting_spec(d, base_weights = w0) |>
                           step_trim_weights(method = "potter", kappa = k),
                         warn = FALSE)$steps[[1]]$diagnostics$upper
  expect_equal(up(1), as.numeric(.potter_threshold(wv)), tolerance = 1e-4)
  expect_lt(up(0.25), up(1))

  expect_error(step_trim_weights(weighting_spec(d, base_weights = w0),
                                 method = "potter", kappa = -1), "single positive number")
  expect_warning(step_trim_weights(weighting_spec(d, base_weights = w0), kappa = 2),
                 "only affects method")
})

test_that("IO-03: a y_model node in a recipe cannot smuggle code past the whitelist", {
  # The `formula` and `expr` branches were checked; `y_model` built its formula on its
  # own and handed it to step_model_calibration(), where it runs on the first prep().
  # all.vars() on I(system("...")) is character(0), so the NA guard never saw it either.
  bad <- list(.wf = "y_model", engine = "glm", family = NULL,
              formula = 'income ~ age + I(system("echo PWNED"))')
  expect_error(.wf_decode(bad, references = NULL, step_id = "mc_1", allow_code = FALSE),
               "only a fixed set of data-manipulation functions")
  # an explicit trust flag still reads it, as for every other node
  expect_error(.wf_decode(bad, references = NULL, step_id = "mc_1", allow_code = TRUE), NA)
  # an ordinary formula is untouched
  ok <- list(.wf = "y_model", engine = "glm", family = "gaussian",
             formula = "income ~ age + sex")
  m <- .wf_decode(ok, references = NULL, step_id = "mc_1", allow_code = FALSE)
  expect_s3_class(m, "wf_y_model")
  expect_equal(all.vars(m$formula), c("income", "age", "sex"))
  # engine and family come from closed catalogues, as the constructor enforces
  expect_error(.wf_decode(list(.wf = "y_model", formula = "y ~ x", engine = "rm -rf"),
                          references = NULL, step_id = "s", allow_code = FALSE),
               "not one of glm, tree, forest, boost")
  expect_error(.wf_decode(list(.wf = "y_model", formula = "y ~ x", engine = "glm",
                               family = "bogus"),
                          references = NULL, step_id = "s", allow_code = FALSE),
               "not one of gaussian, binomial, poisson")
})
