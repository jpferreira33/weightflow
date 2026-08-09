# Blindaje: seguridad e integridad estructural del reporte HTML.
# User data (factor levels, column names) is interpolated
# en el HTML: nada de eso puede llegar crudo.

rep_d <- function(n = 300, seed = 5) {
  set.seed(seed)
  data.frame(id = 1:n,
             x = factor(sample(c("A", "B"), n, TRUE)),
             w = runif(n, 1, 3),
             resp = rbinom(n, 1, 0.7) == 1, y = rnorm(n, 10))
}

html_de <- function(sp) {
  f <- tempfile(fileext = ".html")
  suppressMessages(report_weighting(sp, file = f, open = FALSE))
  paste(readLines(f, warn = FALSE), collapse = "\n")
}

test_that("hostile factor levels are escaped everywhere (no raw <script>, & escaped)", {
  d <- rep_d()
  levels(d$x) <- c("<script>alert(1)</script>", "B&B")
  sp <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  h <- html_de(sp)
  expect_false(grepl("<script>alert", h, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;", h, fixed = TRUE))
  expect_true(grepl("B&amp;B", h, fixed = TRUE))
})

test_that("hostile levels in calibration margins are escaped too", {
  d <- rep_d()
  levels(d$x) <- c("<img src=x onerror=alert(1)>", "ok")
  marg <- setNames(as.numeric(tapply(d$w, d$x, sum)) * 1.05, levels(d$x))
  sp <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_calibrate(method = "raking", margins = list(x = marg))))
  h <- html_de(sp)
  expect_false(grepl("<img src=x", h, fixed = TRUE))
})

test_that("the report declares its language and carries accessibility attributes", {
  d <- rep_d()
  sp <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  h <- html_de(sp)
  expect_true(grepl("<html lang=", h))
  expect_true(grepl("role=\"img\"|role='img'", h))
})

test_that("the pipeline funnel shows the surviving n on the arrows", {
  d <- rep_d()
  sp <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  h <- html_de(sp)
  expect_true(grepl("n = ", h, fixed = TRUE))
})

test_that("no internal environment addresses leak into the report", {
  d <- rep_d()
  sp <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  h <- html_de(sp)
  expect_false(grepl("environment: 0x", h, fixed = TRUE))
})

test_that("the Spanish report has no signed-zero or stage_N_step internals", {
  d <- rep_d()
  sp <- suppressMessages(prep(weighting_spec(d, base_weights = w) |>
    step_nonresponse(respondent = resp, method = "weighting_class", by = "x")))
  f <- tempfile(fileext = ".html")
  suppressMessages(report_weighting(sp, file = f, open = FALSE, lang = "es"))
  h <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_false(grepl("stage_[0-9]_step_", h))
  expect_false(grepl(">[+-]0\\.00%<", h))
})
