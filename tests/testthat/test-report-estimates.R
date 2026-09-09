# The estimation grammar and the composite regression estimator are the two things a
# panel report exists to explain, so both have to survive into the HTML: the estimates
# section with its results tables, and the parsed composite block inside the step card.
# These tests pin the contract between collect_estimates() and report_panel(), not the
# styling: the row-aligned `detail` frame, the anchors, and the translation.

mk_ola <- function(t) {
  d <- panel_ine[panel_ine$ola == t & panel_ine$disp == "R", ]
  d$sexo <- factor(d$sexo)
  d
}
xtot <- function(d) colSums(d$w_base * stats::model.matrix(~ sexo, data = d))

cre_pair <- function() {
  m1 <- mk_ola(1); m2 <- mk_ola(2)
  s1 <- weighting_spec(m1, base_weights = w_base) |>
    step_cre(previous = NULL, status = condicion, formula = ~ sexo,
             totals = xtot(m1), status_ref = "inact")
  s2 <- weighting_spec(m2, base_weights = w_base) |>
    step_cre(previous = prep(s1), status = condicion, composite = list(NULL, "sexo"),
             id_unit = c("id_hogar", "nper"), formula = ~ sexo, totals = xtot(m2),
             alpha = 2/3, status_ref = "inact")
  list(s1 = s1, s2 = s2)
}

test_that("collect_estimates() carries a detail frame aligned with the tidy table", {
  skip_on_cran()
  sp <- cre_pair()
  wb <- wave_bootstrap(list(T1 = sp$s1, T2 = sp$s2), replicates = 20, strata = "estrato",
                       psu = "psu", seed = 1, refit_steps = "calibration", progress = FALSE)
  res <- collect_estimates(wb |> step_domain(region) |>
                             step_estimate(mean(desocupado), over = "change"))
  # the documented tidy shape is unchanged
  expect_true(all(c("estimand", "over", "type", "estimate", "se",
                    "ci_lower", "ci_upper", "rho") %in% names(res$table)))
  expect_s3_class(res$detail, "data.frame")
  expect_equal(nrow(res$detail), nrow(res$table))
  expect_true(all(c("level", "R", "wave_1", "wave_2", "deff", "se_indep") %in%
                    names(res$detail)))
  # the wave levels are the ones the change is built from
  expect_equal(res$table$estimate, res$detail$wave_2 - res$detail$wave_1)
  expect_true(all(res$detail$level == 0.95))
})

test_that("a step_filter() is recorded on the result so the report can name the subpopulation", {
  skip_on_cran()
  sp <- cre_pair()
  wb <- wave_bootstrap(list(T1 = sp$s1, T2 = sp$s2), replicates = 20, strata = "estrato",
                       psu = "psu", seed = 1, refit_steps = "calibration", progress = FALSE)
  res <- collect_estimates(wb |> step_filter(edad >= 25 & edad <= 54) |>
                             step_estimate(mean(desocupado), over = "change"))
  expect_equal(res$filters, "edad >= 25 & edad <= 54")
  expect_equal(res$replicates, 20L)
  plain <- collect_estimates(wb |> step_estimate(mean(desocupado), over = "change"))
  expect_length(plain$filters, 0L)
})

test_that("change_estimate() reports the two wave levels behind the change", {
  skip_on_cran()
  sp <- cre_pair()
  wb <- wave_bootstrap(list(T1 = sp$s1, T2 = sp$s2), replicates = 20, strata = "estrato",
                       psu = "psu", seed = 1, refit_steps = "calibration", progress = FALSE)
  ch <- change_mean(wb, "desocupado")
  expect_length(ch$point, 2L)
  expect_named(ch$point, c("T1", "T2"))
  expect_equal(unname(ch$point[2] - ch$point[1]), ch$estimate)
})

test_that("report_panel(estimates=) writes the estimates section", {
  skip_on_cran()
  sp <- cre_pair()
  wb <- wave_bootstrap(list(T1 = sp$s1, T2 = sp$s2), replicates = 20, strata = "estrato",
                       psu = "psu", seed = 1, refit_steps = "calibration", progress = FALSE)
  res <- collect_estimates(wb |> step_domain(region) |>
                             step_estimate(mean(desocupado), over = "change",
                                           label = "desempleo"))
  f <- tempfile(fileext = ".html")
  report_panel(coordinated = wb, estimates = list("By region" = res),
               file = f, open = FALSE)
  h <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_true(grepl("id='estimates'", h, fixed = TRUE))
  expect_true(grepl("class='est'", h, fixed = TRUE))     # the results table
  expect_true(grepl("wf-dot", h, fixed = TRUE))          # the dot-and-whisker chart
  expect_true(grepl("By region", h, fixed = TRUE))       # the list name is the card title
  expect_true(grepl("desempleo", h, fixed = TRUE))
  # every domain cell reaches the table
  for (r in unique(res$table$region)) expect_true(grepl(r, h, fixed = TRUE))
})

test_that("report_panel() accepts an uncollected pipeline and rejects a wrong class", {
  skip_on_cran()
  sp <- cre_pair()
  wb <- wave_bootstrap(list(T1 = sp$s1, T2 = sp$s2), replicates = 20, strata = "estrato",
                       psu = "psu", seed = 1, refit_steps = "calibration", progress = FALSE)
  f <- tempfile(fileext = ".html")
  expect_silent(report_panel(estimates = wb |> step_estimate(mean(desocupado), over = "change"),
                             file = f, open = FALSE))
  expect_true(file.exists(f))
  # a weighting fit is not an estimation result: fail loudly, do not render an empty card
  expect_error(report_panel(estimates = prep(sp$s1), file = tempfile(), open = FALSE),
               "weightflow_estimation_result")
})

test_that("the composite block is parsed into its own card and left out of the flat table", {
  skip_on_cran()
  sp <- cre_pair()
  fit2 <- prep(sp$s2)
  f <- tempfile(fileext = ".html")
  report_weighting(fit2, file = f, open = FALSE)
  h <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_true(grepl("Composite regression estimator", h, fixed = TRUE))
  # parsed into block / cell / status, so the raw constraint names are gone
  expect_false(grepl("z1.all.emp", h, fixed = TRUE))
  expect_true(grepl(">emp<", h, fixed = TRUE))
  # the demographic block still shows in the step's own diagnostics table
  expect_true(grepl("(Intercept)", h, fixed = TRUE))
  # a Greek letter inside an uppercased label is opted out of the transform
  expect_true(grepl("<span class='gk'>&alpha;</span>", h, fixed = TRUE))
})

test_that("the estimates section is fully translated", {
  skip_on_cran()
  sp <- cre_pair()
  wb <- wave_bootstrap(list(T1 = sp$s1, T2 = sp$s2), replicates = 20, strata = "estrato",
                       psu = "psu", seed = 1, refit_steps = "calibration", progress = FALSE)
  res <- collect_estimates(wb |> step_filter(edad >= 25) |> step_domain(region) |>
                             step_estimate(mean(desocupado), over = "change"))
  f <- tempfile(fileext = ".html")
  report_panel(longitudinal = prep(sp$s2), coordinated = wb, estimates = res,
               file = f, open = FALSE, lang = "es")
  h <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_true(grepl("id='estimates'", h, fixed = TRUE))
  expect_true(grepl("href='#estimates'", h, fixed = TRUE))
  for (en in c(">Estimates<", "net change", "Subpopulation:", "Composite weight",
               ">Change<", ">Confidence<", ">Replicates<", "Constraints met",
               "previous wave", "Achieved", "Deviation"))
    expect_false(grepl(en, h, fixed = TRUE), label = en)
})
