# Unit tests for R/report-helpers.R. These are pure string/SVG builders, so they
# are tested directly on their inputs rather than by rendering a whole report.

# ---------------------------------------------------------------------------
# .html_escape(), %||%
# ---------------------------------------------------------------------------

test_that(".html_escape escapes every special character", {
  expect_equal(.html_escape("a & b"), "a &amp; b")
  expect_equal(.html_escape("<i>"), "&lt;i&gt;")
  expect_equal(.html_escape('say "hi"'), "say &quot;hi&quot;")
  expect_equal(.html_escape("it's"), "it&#39;s")
  expect_equal(.html_escape("&<"), "&amp;&lt;")     # ampersand first, no double-escape
})

test_that("%||% falls back on NULL and on a single NA", {
  expect_equal("a" %||% "b", "a")
  expect_equal(NULL %||% "b", "b")
  expect_equal(NA %||% "b", "b")
  expect_equal(c(NA, 1) %||% "b", c(NA, 1))         # length > 1 is kept
})

# ---------------------------------------------------------------------------
# .fmt_val()
# ---------------------------------------------------------------------------

test_that(".fmt_val renders every kind of step parameter", {
  expect_equal(.fmt_val(NULL), "&mdash;")
  expect_match(.fmt_val(~ region + sex), "region \\+ sex")
  expect_match(.fmt_val(quote(responded == 1)), "responded == 1")
  expect_equal(.fmt_val(data.frame(a = 1:2, b = 3:4)), "data.frame [2 &times; 2]")
  expect_equal(.fmt_val("plain"), "plain")
  expect_equal(.fmt_val(c(a = 1000, b = 2000)), "a=1,000, b=2,000")
})

test_that(".fmt_val walks a named list recursively", {
  out <- .fmt_val(list(region = c(N = 10), sex = "M"))
  expect_match(out, "<i>region</i>")
  expect_match(out, "<i>sex</i>: M")
  expect_match(out, "<br>")
})

# ---------------------------------------------------------------------------
# .fmt_num()
# ---------------------------------------------------------------------------

test_that(".fmt_num uses one convention per quantity type", {
  expect_equal(.fmt_num(1234.5678, "weight"), "1,234.568")
  expect_equal(.fmt_num(1234.6, "count"), "1,235")
  expect_equal(.fmt_num(0.5, "prop"), "0.500")
  expect_equal(.fmt_num(1.23456, "factor"), "1.2346")
  expect_equal(.fmt_num(1.23, "pct"), "+1.2%")
  expect_equal(.fmt_num(-1.23, "pct"), "-1.2%")
  expect_equal(.fmt_num(0, "pct"), "0.0%")          # exact zero, no "+0.0%"
})

test_that(".fmt_num returns a dash for anything it cannot format", {
  expect_equal(.fmt_num(NA_real_, "weight"), "&ndash;")
  expect_equal(.fmt_num(Inf, "count"), "&ndash;")
  expect_equal(.fmt_num(c(1, 2), "prop"), "&ndash;")
  expect_equal(.fmt_num(numeric(0), "prop"), "&ndash;")
})

# ---------------------------------------------------------------------------
# .uniq_ticks() and .fmt_ax()
# ---------------------------------------------------------------------------

test_that(".uniq_ticks drops non-finite values and handles the empty case", {
  expect_equal(.uniq_ticks(numeric(0)), character(0))
  expect_equal(.uniq_ticks(c(NA, NaN, Inf)), character(0))
})

test_that(".uniq_ticks prints integers without decimals", {
  expect_equal(.uniq_ticks(c(1, 2, 3)), c("1", "2", "3"))
})

test_that(".uniq_ticks rounds large values to one decimal with a separator", {
  out <- .uniq_ticks(c(1000.12, 2000.55))
  expect_true(all(grepl(",", out, fixed = TRUE)))
  expect_length(out, 2L)
})

test_that(".uniq_ticks adds decimals until the labels are distinct", {
  expect_equal(.uniq_ticks(c(1.001, 1.002)), c("1.001", "1.002"))
  expect_equal(.uniq_ticks(c(1.05, 1.06, 1.07)), c("1.05", "1.06", "1.07"))
})

test_that(".uniq_ticks gives up at six decimals", {
  out <- .uniq_ticks(c(1.00000001, 1.00000002))
  expect_length(out, 2L)
  expect_true(all(out == "1.000000"))
})

test_that(".fmt_ax formats an axis value by magnitude", {
  expect_equal(.fmt_ax(NA_real_), "")
  expect_equal(.fmt_ax(Inf), "")
  expect_equal(.fmt_ax(1500.7), "1,501")
  expect_equal(.fmt_ax(1.23456), "1.23")
})

# ---------------------------------------------------------------------------
# .step_params()
# ---------------------------------------------------------------------------

test_that(".step_params drops internals, defaults and 'off' flags", {
  st <- structure(list(
    label = "x", method = "raking", margins = list(region = c(N = 10)),
    calfun = "linear", equal_within_cluster = FALSE, penalty = NULL,
    maxit = 50L, tol = 1e-6, env = globalenv(), fn = function(z) z,
    diagnostics = data.frame(a = 1), alerts = "boom"),
    class = c("step_calibrate", "weighting_step"))
  out <- .step_params(st)
  expect_named(out, c("method", "margins"))
})

test_that(".step_params hides the arguments a nonresponse method ignores", {
  base <- list(label = "x", by = "region", engine = "forest", formula = ~ a,
               num_classes = 5L, weight_model = TRUE, calfun = "raking",
               bounds = c(0.5, 2), maxit = 50L, tol = 1e-6, env = globalenv())

  wc <- structure(c(list(method = "weighting_class"), base),
                  class = c("step_nonresponse", "weighting_step"))
  expect_named(.step_params(wc), c("method", "by"))

  pr <- structure(c(list(method = "propensity"), base),
                  class = c("step_nonresponse", "weighting_step"))
  out <- .step_params(pr)
  expect_true(all(c("engine", "formula", "num_classes") %in% names(out)))
  expect_false(any(c("calfun", "bounds") %in% names(out)))
})

test_that(".step_params keeps a logical only when it is TRUE", {
  mk <- function(v) structure(list(label = "x", method = "linear",
                                   equal_within_cluster = v),
                              class = c("step_calibrate", "weighting_step"))
  expect_true("equal_within_cluster" %in% names(.step_params(mk(TRUE))))
  expect_false("equal_within_cluster" %in% names(.step_params(mk(FALSE))))
})

# ---------------------------------------------------------------------------
# .with_reldiff() and .df_to_html()
# ---------------------------------------------------------------------------

test_that(".with_reldiff passes through anything without target/achieved", {
  expect_null(.with_reldiff(NULL, "en"))
  df <- data.frame(a = 1, b = 2)
  expect_identical(.with_reldiff(df, "en"), df)
})

test_that(".with_reldiff inserts the relative difference right after achieved", {
  df  <- data.frame(variable = "g", target = 100, achieved = 110,
                    stringsAsFactors = FALSE)
  out <- .with_reldiff(df, "en")
  expect_equal(names(out), c("variable", "target", "achieved", "rel. diff (%)"))
  expect_equal(out[["rel. diff (%)"]], "+10.00%")
})

test_that(".with_reldiff prints an exact match as 0.00% and a bad ratio as a dash", {
  out0 <- .with_reldiff(data.frame(target = 100, achieved = 100), "en")
  expect_equal(out0[["rel. diff (%)"]], "0.00%")
  outNA <- .with_reldiff(data.frame(target = 0, achieved = 5), "en")
  expect_equal(outNA[["rel. diff (%)"]], "-")
})

test_that(".with_reldiff localises the column name", {
  out <- .with_reldiff(data.frame(target = 100, achieved = 110), "es")
  expect_true("dif. rel. (%)" %in% names(out))
})

test_that(".df_to_html renders a table and escapes its contents", {
  expect_match(.df_to_html(NULL), "no diagnostics")
  expect_match(.df_to_html(data.frame(a = character(0))), "no diagnostics")
  out <- .df_to_html(data.frame(a = "<b>", b = 1.23456789,
                                stringsAsFactors = FALSE))
  expect_match(out, "<table>")
  expect_match(out, "&lt;b&gt;")
  expect_match(out, "1.2346")                        # numerics rounded to 4 dp
})

# ---------------------------------------------------------------------------
# .thin_scatter()
# ---------------------------------------------------------------------------

test_that(".thin_scatter keeps everything below the cap", {
  expect_equal(.thin_scatter(1:100, 1:100, cap = 3000L), 1:100)
})

test_that(".thin_scatter respects the cap but never drops the extremes", {
  set.seed(21)
  x <- stats::runif(5000); y <- x + stats::rnorm(5000, 0, 0.01)
  i <- .thin_scatter(x, y, cap = 1000L)
  expect_true(length(i) <= 1000L)
  expect_true(which.max(x) %in% i)
  expect_true(which.min(x) %in% i)
  expect_true(which.max(abs(y - x)) %in% i)
  expect_false(anyDuplicated(i) > 0)
})

# ---------------------------------------------------------------------------
# the SVG builders
# ---------------------------------------------------------------------------

test_that(".svg_evolution needs at least two stages", {
  expect_equal(.svg_evolution("base", 1), "")
})

test_that(".svg_evolution draws a line with one tick per stage", {
  out <- .svg_evolution(c("base", "1", "2"), c(1.0, 1.3, 1.2))
  expect_match(out, "<svg")
  expect_match(out, "deff_K by stage")
  expect_match(out, "&#9650;")                       # rise marker
  expect_match(out, "&#9660;")                       # fall marker
})

test_that(".svg_evolution survives a flat series", {
  out <- .svg_evolution(c("base", "1"), c(1, 1))
  expect_match(out, "<svg")
  expect_false(grepl("&#9650;", out, fixed = TRUE))
})

test_that(".svg_hist returns nothing without finite data", {
  expect_equal(.svg_hist(numeric(0)), "")
  expect_equal(.svg_hist(c(NA, NaN)), "")
})

test_that(".svg_hist draws bars and the reference line when it is in range", {
  set.seed(22)
  out <- .svg_hist(stats::rnorm(200, 1, 0.2))
  expect_match(out, "<rect")
  expect_match(out, "factor = 1")
  far <- .svg_hist(stats::rnorm(200, 50, 1), refline = 1)
  expect_false(grepl("factor = 1", far, fixed = TRUE))
})

test_that(".svg_scatter draws points and a y = x reference", {
  set.seed(23)
  x <- stats::runif(100, 1, 5)
  out <- .svg_scatter(x, x * 1.2)
  expect_match(out, "<circle")
  expect_match(out, "y = x")
  expect_match(out, "weight before")
})

test_that(".svg_scatter survives a degenerate range", {
  out <- .svg_scatter(rep(2, 20), rep(2, 20))
  expect_match(out, "<svg")
})

test_that(".svg_overlap needs enough data and both response groups", {
  expect_equal(.svg_overlap(c(0.1, 0.2), c(1, 0), c(1, 1)), "")
  expect_equal(.svg_overlap(stats::runif(50), rep(1, 50), rep(1, 50)), "")
})

test_that(".svg_overlap draws the two weighted histograms", {
  set.seed(24)
  p <- stats::runif(200); r <- stats::rbinom(200, 1, 0.6)
  out <- .svg_overlap(p, r, rep(1, 200))
  expect_match(out, "<svg")
  expect_match(out, "respondents")
  expect_match(out, "nonrespondents")
  expect_match(.svg_overlap(p, r, rep(1, 200), lang = "es"), "respondentes")
})

test_that(".svg_potter needs at least three finite grid points", {
  expect_equal(.svg_potter(c(1, 2), c(1, 1), c(1, 1), c(2, 2), 1), "")
})

test_that(".svg_potter draws the three curves and marks the chosen cutoff", {
  g <- seq(1, 10, length.out = 20)
  out <- .svg_potter(g, (10 - g)^2, g^2, (10 - g)^2 + g^2, 5)
  expect_match(out, "Potter MSE curve")
  expect_match(out, "chosen")
  expect_match(out, "MSE")
  expect_match(.svg_potter(g, (10 - g)^2, g^2, (10 - g)^2 + g^2, 5, lang = "es"),
               "elegido")
})

# ---------------------------------------------------------------------------
# .step_visual()
# ---------------------------------------------------------------------------

test_that(".step_visual is empty for steps with nothing to show", {
  for (cls in c("step_drop_ineligible", "step_round", "step_rescale",
                "step_assert")) {
    st <- structure(list(label = cls), class = c(cls, "weighting_step"))
    expect_equal(.step_visual(st, c(1, 2), c(1, 2)), "")
  }
})

test_that(".step_visual is empty when no unit survives the step", {
  st <- structure(list(label = "t"), class = c("step_trim", "weighting_step"))
  expect_equal(.step_visual(st, c(1, 1), c(0, 0)), "")
})

test_that(".step_visual pairs a scatter with a factor histogram", {
  set.seed(25)
  st  <- structure(list(label = "t"), class = c("step_trim", "weighting_step"))
  prev <- stats::runif(200, 1, 5)
  out <- .step_visual(st, prev, prev * stats::runif(200, 0.8, 1.2))
  expect_match(out, "<div class='viz'>")
  expect_match(out, "adjustment factor")
})

test_that(".step_visual relabels the histogram for within-household selection", {
  set.seed(26)
  st   <- structure(list(label = "s"),
                    class = c("step_select_within", "weighting_step"))
  prev <- rep(1, 100)
  out  <- .step_visual(st, prev, prev * sample(1:4, 100, TRUE))
  expect_match(out, "persons represented")
})

test_that(".step_visual notes the thinning when there are many points", {
  set.seed(27)
  st   <- structure(list(label = "t"), class = c("step_trim", "weighting_step"))
  prev <- stats::runif(3200, 1, 5)
  out  <- .step_visual(st, prev, prev * 1.1)
  expect_match(out, "Showing 3,000 of 3,200 points")
})

# ---------------------------------------------------------------------------
# .ri_block()
# ---------------------------------------------------------------------------

test_that(".ri_block renders the indicator with its partials", {
  ri <- list(aux = c("region", "sex"), n_eligible = 1500, R = 0.873,
             partials = data.frame(variable = c("region", "sex"),
                                   partial_R = c(0.021, 0.058),
                                   stringsAsFactors = FALSE),
             num_aux = "age")
  out <- .ri_block(ri)
  expect_match(out, "R-indicator")
  expect_match(out, "R = 0.873")
  expect_match(out, "Partial R-indicators")
  expect_match(out, "1,500")
  expect_match(out, "age")
  expect_match(.ri_block(ri, lang = "es"), "R-indicadores parciales")
})

test_that(".ri_block works without partials or numeric auxiliaries", {
  ri  <- list(aux = "region", n_eligible = 100, R = 0.9,
              partials = NULL, num_aux = character(0))
  out <- .ri_block(ri)
  expect_match(out, "R = 0.900")
  expect_false(grepl("Partial R-indicators", out, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# .calibration_drift()
# ---------------------------------------------------------------------------

mk_cal <- function(diag) structure(list(label = "cal", diagnostics = diag),
                                   class = c("step_calibrate", "weighting_step"))
mk_rnd <- function() structure(list(label = "round"),
                               class = c("step_round", "weighting_step"))
drift_diag <- data.frame(variable = "g", category = c("a", "b"),
                         target = c(10, 20), stringsAsFactors = FALSE)

test_that(".calibration_drift is empty when there is nothing to report", {
  d <- data.frame(g = c("a", "a", "b", "b"), stringsAsFactors = FALSE)

  # no calibration step at all
  expect_equal(.calibration_drift(list(steps = list(mk_rnd()), data = d,
                                       final_weight = rep(1, 4))), "")
  # calibration is the last step
  expect_equal(.calibration_drift(list(steps = list(mk_cal(drift_diag)), data = d,
                                       final_weight = rep(1, 4))), "")
  # diagnostics without the category/target columns (linear/GREG)
  expect_equal(.calibration_drift(
    list(steps = list(mk_cal(data.frame(variable = "g", achieved = 1)), mk_rnd()),
         data = d, final_weight = rep(1, 4))), "")
})

test_that(".calibration_drift recomputes the targets at the final weights", {
  d   <- data.frame(g = c("a", "a", "b", "b"), stringsAsFactors = FALSE)
  obj <- list(steps = list(mk_cal(drift_diag), mk_rnd()), data = d,
              final_weight = c(4, 4, 10, 10))       # a: 8 vs 10, b: 20 vs 20
  out <- .calibration_drift(obj)
  expect_match(out, "Calibration drift")
  expect_match(out, "max deviation 20.00%")
  expect_match(out, "<table>")
  expect_match(.calibration_drift(obj, lang = "es"), "Deriva de calibraci")
})

test_that(".calibration_drift skips rows whose variable is gone from the data", {
  d   <- data.frame(other = c("a", "a"), stringsAsFactors = FALSE)
  obj <- list(steps = list(mk_cal(drift_diag), mk_rnd()), data = d,
              final_weight = c(1, 1))
  expect_equal(.calibration_drift(obj), "")
})

# ---------------------------------------------------------------------------
# .step_vars(), .chips(), .stage_labels(), .pipeline_diagram()
# ---------------------------------------------------------------------------

test_that(".step_vars collects every variable a step refers to", {
  st <- list(respondent = quote(responded == 1), formula = ~ region + sex,
             by = "stratum", cluster = "household_id",
             margins = list(age_grp = c(a = 1)))
  expect_setequal(.step_vars(st),
                  c("responded", "region", "sex", "stratum", "household_id",
                    "age_grp"))
  expect_equal(.step_vars(list()), character(0))
})

test_that(".lang_vars survives an object it cannot parse", {
  expect_equal(.lang_vars(NULL), character(0))
  expect_equal(.lang_vars(~ a + b), c("a", "b"))
})

test_that(".chips renders one chip per variable", {
  expect_equal(.chips(character(0)), "")
  out <- .chips(c("region", "sex"))
  expect_match(out, "class='chips'")
  expect_equal(lengths(regmatches(out, gregexpr("<span", out))), 2L)
})

test_that(".stage_labels numbers the stages after the base weights", {
  obj <- list(steps = list(
    structure(list(label = "r"), class = c("step_round", "weighting_step")),
    structure(list(label = "s"), class = c("step_rescale", "weighting_step"))))
  out <- .stage_labels(obj, "en")
  expect_length(out, 3L)
  expect_equal(out[1], "Base weights")
  expect_match(out[2], "^1 ")
  expect_match(out[3], "rescaling")
  expect_equal(.stage_labels(obj, "es")[1], "Pesos base")
})

test_that(".pipeline_diagram draws base, steps, final and the active counts", {
  obj <- list(
    base_weights = "pw",
    steps = list(structure(list(label = "r", by = "region"),
                           class = c("step_round", "weighting_step"))),
    history = list(rep(1, 10), c(rep(1, 8), 0, 0)))
  out <- .pipeline_diagram(obj, "en")
  expect_match(out, "class='flow'")
  expect_match(out, "Base weights")
  expect_match(out, "Final weights")
  expect_match(out, "n = 10")
  expect_match(out, "n = 8")
  expect_match(out, "class='chip'>region")
})
