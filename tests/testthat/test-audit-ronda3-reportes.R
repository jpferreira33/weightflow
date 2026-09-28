# Round-3 audit, the HTML reports: the weight-distribution card (REP-04), a column
# name that took the whole report down (REP-05), and two sentences of the same report
# claiming opposite directions (REP-06). All three are against 1.2.0 as published.

test_that("REP-04: the weight table describes the ACTIVE weights, negatives included", {
  set.seed(1)
  fin <- c(stats::rnorm(79, -12, 8), stats::rlnorm(221, 1.5, 0.8))
  h   <- .weight_distribution_html(fin, "en", plots = FALSE)
  val <- function(k) {
    m <- regmatches(h, regexpr(sprintf("<td class='k'>%s</td><td class='numc'>[^<]*</td>", k), h))
    as.numeric(gsub("[^0-9.eE+-]", "", sub(".*numc'>", "", m)))
  }
  # the card used to publish the minimum and median of fin[fin > 0]: 0.094 and 4.23
  expect_equal(val("min"), min(fin), tolerance = 1e-3)
  expect_equal(val("median"), stats::median(fin), tolerance = 1e-3)
  expect_true(val("min") < 0)
  # a max/min ratio across a sign change is meaningless, so it is not printed
  expect_match(h, "raz|max/min ratio</td><td class='numc'>&ndash;")
  # the extreme count uses the real median, so it no longer undercounts
  n_ext <- val("extreme \\(&gt; 4&times; median\\)")
  w <- fin[is.finite(fin) & fin != 0]
  expect_equal(n_ext, sum(w > 4 * stats::median(w)))

  # an all-positive recipe -- the ordinary case -- is unchanged
  set.seed(2); fp <- stats::rlnorm(300, 1.5, 0.8)
  hp <- .weight_distribution_html(fp, "en", plots = FALSE)
  vp <- function(k) {
    m <- regmatches(hp, regexpr(sprintf("<td class='k'>%s</td><td class='numc'>[^<]*</td>", k), hp))
    as.numeric(gsub("[^0-9.eE+-]", "", sub(".*numc'>", "", m)))
  }
  expect_equal(vp("min"), min(fp), tolerance = 1e-3)
  expect_equal(vp("median"), stats::median(fp), tolerance = 1e-3)
  expect_equal(vp("max/min ratio"), max(fp) / min(fp), tolerance = 1e-2)
})

test_that("REP-05: a column name with a space does not take the report down", {
  set.seed(2); n <- 200
  d <- data.frame(w0 = 10, resp = stats::rbinom(n, 1, 0.7))
  d[["region code"]] <- sample(c("a", "b"), n, TRUE)      # an ordinary CSV import
  p <- prep(weighting_spec(d, base_weights = w0) |>
              step_nonresponse(respondent = resp == 1, method = "propensity",
                               formula = ~ `region code`, engine = "logit"), warn = FALSE)
  # .r_indicator() itself must cope, not merely be caught
  ri <- .r_indicator(p)
  expect_false(is.null(ri))
  expect_true(is.finite(ri$R))

  f <- tempfile(fileext = ".html")
  expect_error(report_weighting(p, file = f, open = FALSE), NA)
  expect_true(file.exists(f))
  expect_true(any(grepl("R-indicator", readLines(f, warn = FALSE))))
})

test_that("REP-06: the trimming narrative names the direction the total moved", {
  mk <- function(sb, sa) structure(
    list(lower = 1, upper = 5, method = "tukey",
         diagnostics = data.frame(sum_before = sb, sum_after = sa)),
    class = c("step_trim_weights", "weighting_step"))
  say <- function(st, lang) gsub("<[^>]+>", "",
    .step_narrative(st, list(deff = 1, n_eff = 100), list(deff = 1.1, n_eff = 90),
                    NULL, FALSE, lang))

  # the total ROSE: this used to read "the weight total fell by -399.5%", while the
  # Points of attention block of the same report said it increased by 399.5%
  up <- say(mk(1201, 6000), "en")
  expect_match(up, "weight total rose by")
  expect_false(grepl("-[0-9]", sub(".*weight total", "", up)))
  expect_match(say(mk(1201, 6000), "es"), "total de pesos subi")

  down <- say(mk(1201, 400), "en")
  expect_match(down, "weight total fell by 66\\.")
  expect_match(say(mk(1201, 400), "es"), "total de pesos baj")

  # preserved is unchanged
  expect_match(say(mk(1000, 1000), "en"), "preserving the weight total")
  # and a degenerate before-total does not print NaN%
  expect_false(grepl("NaN", say(mk(0, 500), "en")))
})
