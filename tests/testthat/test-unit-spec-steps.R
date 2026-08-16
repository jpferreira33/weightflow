# Validation branches of the step constructors (spec.R, spec-steps-cascade.R,
# spec-steps-calibrate.R). These are pure argument checks: they never run the
# cascade, so they are fast and exercise the messages a user actually hits.

sp <- function() weighting_spec(sample_survey, base_weights = pw)

lin_tot <- c("(Intercept)" = 1000, regionSouth = 300)
ps_df   <- data.frame(region = c("North", "South"), Freq = c(700, 300),
                      stringsAsFactors = FALSE)
ps_df2  <- data.frame(sex = c("M", "F"), N = c(500, 500),
                      stringsAsFactors = FALSE)

# ---------------------------------------------------------------------------
# weighting_spec() and .add_step()
# ---------------------------------------------------------------------------

test_that("weighting_spec validates the data and the base-weight column", {
  expect_error(weighting_spec(1:10, base_weights = pw), "must be a data.frame")
  expect_error(weighting_spec(sample_survey[0, ], base_weights = pw), "0 rows")
  expect_error(weighting_spec(sample_survey, base_weights = nope), "not found")
})

test_that("weighting_spec rejects unusable base weights", {
  d <- sample_survey
  d$pw[1] <- NA
  expect_error(weighting_spec(d, base_weights = pw), "cannot contain NA")
  d$pw <- sample_survey$pw; d$pw[1] <- Inf
  expect_error(weighting_spec(d, base_weights = pw), "finite")
  d$pw <- sample_survey$pw; d$pw[1] <- -1
  expect_error(weighting_spec(d, base_weights = pw), "negative")
})

test_that("weighting_spec warns about zero base weights", {
  d <- sample_survey; d$pw[1] <- 0
  expect_warning(s <- weighting_spec(d, base_weights = pw), "start inactive")
  expect_s3_class(s, "weighting_spec")
  expect_length(s$steps, 0L)
})

test_that(".add_step refuses anything that is not a weighting_spec", {
  expect_error(step_round(list(a = 1)), "must be a weighting_spec")
})

test_that("adding a step to a prepped recipe clears the previous results", {
  p <- prep(sp() |> step_rescale(to = "n"))
  expect_message(s2 <- step_round(p, digits = 0), "results cleared")
  expect_false(inherits(s2, "prepped_weighting_spec"))
  expect_length(s2$steps, 2L)
})

# ---------------------------------------------------------------------------
# step_select_within()
# ---------------------------------------------------------------------------

test_that("step_select_within requires exactly one of prob / n_eligible", {
  expect_error(step_select_within(sp()), "either `prob` or `n_eligible`")
  expect_error(step_select_within(sp(), prob = pw, n_eligible = age),
               "only one of")
  expect_error(step_select_within(sp(), n_selected = 2),
               "only applies together with")
})

test_that("step_select_within records the captured expressions", {
  s <- step_select_within(sp(), n_eligible = age, n_selected = 2)
  st <- s$steps[[1]]
  expect_equal(st$label, "within-cluster selection")
  expect_null(st$prob)
  expect_equal(deparse(st$n_eligible), "age")
})

# ---------------------------------------------------------------------------
# step_nonresponse()
# ---------------------------------------------------------------------------

test_that("step_nonresponse validates crossfit and num_classes", {
  expect_error(step_nonresponse(sp(), respondent = responded,
                                method = "propensity", formula = ~ region,
                                crossfit = 1),
               "integer >= 2")
  expect_error(step_nonresponse(sp(), respondent = responded,
                                method = "propensity", formula = ~ region,
                                num_classes = 1),
               "single integer >= 2")
})

test_that("step_nonresponse warns about arguments the method ignores", {
  expect_warning(step_nonresponse(sp(), respondent = responded,
                                  method = "weighting_class", by = "region",
                                  engine = "forest"),
                 "ignored: engine")
  expect_warning(step_nonresponse(sp(), respondent = responded,
                                  method = "weighting_class", by = "region",
                                  formula = ~ region),
                 "ignored: formula")
  expect_warning(step_nonresponse(sp(), respondent = responded,
                                  method = "propensity", formula = ~ region,
                                  bounds = c(0.5, 2)),
                 "ignored: bounds")
})

test_that("step_nonresponse validates the calibration flavour", {
  nr <- function(...) step_nonresponse(sp(), respondent = responded,
                                       method = "calibration", ...)
  expect_error(nr(), "requires `formula`")
  expect_error(nr(formula = ~ region, calfun = "logit"), "requires `bounds`")
  expect_error(nr(formula = ~ region, bounds = c(1.5, 2)), "L < 1 < U")
  expect_error(nr(formula = ~ region, bounds = c(0.5, 2), penalty = 1),
               "cannot be combined")
  expect_error(nr(formula = ~ region, penalty = -1), "positive scalar")
  expect_error(nr(formula = ~ region, equal_within_cluster = TRUE),
               "requires `cluster`")
})

test_that("step_nonresponse builds an informative label", {
  s1 <- step_nonresponse(sp(), respondent = responded, method = "propensity",
                         formula = ~ region, weight_model = FALSE)
  expect_match(s1$steps[[1]]$label, "unweighted model")

  s2 <- step_nonresponse(sp(), respondent = responded, method = "calibration",
                         formula = ~ region, calfun = "raking")
  expect_match(s2$steps[[1]]$label, "raking")
  expect_match(s2$steps[[1]]$label, "sample-level")

  s3 <- step_nonresponse(sp(), respondent = responded, method = "weighting_class",
                         by = "region", cluster = "household_id")
  expect_match(s3$steps[[1]]$label, "weighting class")
  expect_match(s3$steps[[1]]$label, "household_id")
})

# ---------------------------------------------------------------------------
# step_calibrate() -- raking / poststratify
# ---------------------------------------------------------------------------

test_that("step_calibrate needs margins or tidy totals for raking", {
  expect_error(step_calibrate(sp(), method = "raking"),
               "requires either `margins`")
})

test_that("step_calibrate checks that margin names are columns of the data", {
  expect_error(step_calibrate(sp(), method = "raking",
                              margins = list(nope = c(a = 1))),
               "not columns of the data")
})

test_that("step_calibrate requires `count` with tidy totals", {
  expect_error(step_calibrate(sp(), method = "poststratify", totals = ps_df),
               "must be a single string")
  expect_error(step_calibrate(sp(), method = "raking",
                              totals = list(ps_df, ps_df2), count = "Freq"),
               "not a column of every")
})

# ---------------------------------------------------------------------------
# step_calibrate() -- linear
# ---------------------------------------------------------------------------

test_that("step_calibrate linear requires a formula and totals", {
  expect_error(step_calibrate(sp(), method = "linear"),
               "requires `formula` and `totals`")
  expect_error(step_calibrate(sp(), method = "linear", formula = ~ region,
                              totals = ps_df),
               "must name the counts column")
})

test_that("step_calibrate linear validates the tidy totals list", {
  expect_error(step_calibrate(sp(), method = "linear", formula = ~ region,
                              totals = list(ps_df, ps_df2), count = "Freq"),
               "NAMED list")
  expect_error(step_calibrate(sp(), method = "linear", formula = ~ region,
                              totals = list(region = ps_df)),
               "must name their counts column")
})

# ---------------------------------------------------------------------------
# step_calibrate() -- domain (`by`), bounds, penalty, cluster
# ---------------------------------------------------------------------------

test_that("step_calibrate validates the domain argument", {
  expect_error(step_calibrate(sp(), method = "poststratify", totals = ps_df,
                              count = "Freq", by = 1),
               "single string")
  expect_error(step_calibrate(sp(), method = "raking",
                              margins = list(region = c(North = 700)),
                              by = "region"),
               "requires the tidy `totals` format")
  expect_error(step_calibrate(sp(), method = "linear", formula = ~ region,
                              totals = list(region = ps_df), count = "Freq",
                              by = "region"),
               "must not appear in `formula`")
})

test_that("step_calibrate validates calfun and bounds", {
  expect_error(step_calibrate(sp(), method = "linear", formula = ~ region,
                              totals = lin_tot, calfun = "logit"),
               "requires `bounds`")
  expect_error(step_calibrate(sp(), method = "linear", formula = ~ region,
                              totals = lin_tot, bounds = c(0.5, 0.9)),
               "L < 1 < U")
})

test_that("step_calibrate restricts ridge calibration to unbounded linear", {
  expect_error(step_calibrate(sp(), method = "raking",
                              margins = list(region = c(North = 700)),
                              penalty = 1),
               "only available with method")
  expect_error(step_calibrate(sp(), method = "linear", formula = ~ region,
                              totals = lin_tot, bounds = c(0.5, 2), penalty = 1),
               "cannot be combined")
  expect_error(step_calibrate(sp(), method = "linear", formula = ~ region,
                              totals = lin_tot, penalty = 0),
               "positive scalar")
})

test_that("step_calibrate restricts equal_within_cluster to linear + cluster", {
  expect_error(step_calibrate(sp(), method = "raking",
                              margins = list(region = c(North = 700)),
                              equal_within_cluster = TRUE),
               "only available with method")
  expect_error(step_calibrate(sp(), method = "linear", formula = ~ region,
                              totals = lin_tot, equal_within_cluster = TRUE),
               "requires `cluster`")
})

test_that("step_calibrate labels record the calibration flavour", {
  l <- function(...) step_calibrate(sp(), ...)$steps[[1]]$label
  expect_match(l(method = "linear", formula = ~ region, totals = lin_tot,
                 penalty = 1), "ridge")
  expect_match(l(method = "linear", formula = ~ region, totals = lin_tot,
                 bounds = c(0.5, 2)), "bounded")
  expect_match(l(method = "linear", formula = ~ region, totals = lin_tot,
                 equal_within_cluster = TRUE, cluster = "household_id"),
               "equal weights by household_id")
  expect_match(l(method = "raking", margins = list(region = c(North = 700))),
               "raking")
})

# ---------------------------------------------------------------------------
# step_trim(), step_round(), y_model(), design_effect()
# ---------------------------------------------------------------------------

test_that("step_trim requires max_ratio and records the reference", {
  expect_error(step_trim(sp()), "`max_ratio` is required")
  st <- step_trim(sp(), max_ratio = 3, reference = "median")$steps[[1]]
  expect_equal(st$reference, "median")
  expect_match(st$label, "median")
  expect_match(st$label, "cap 3")
})

test_that("step_round records the method and digits in its label", {
  st <- step_round(sp(), digits = 2, method = "preserve_total")$steps[[1]]
  expect_equal(st$digits, 2)
  expect_match(st$label, "preserve_total")
  expect_match(st$label, "2 decimals")
})

test_that("y_model requires a formula and a known engine", {
  expect_error(y_model("income ~ age"), "must be a formula")
  expect_error(y_model(income ~ age, engine = "nope"), "arg")
  m <- y_model(income ~ age, engine = "glm", family = "gaussian")
  expect_equal(m$engine, "glm")
  expect_equal(m$family, "gaussian")
})

test_that("design_effect handles the empty and degenerate cases", {
  de0 <- design_effect(c(0, 0, 0))
  expect_true(is.na(de0$deff))
  expect_equal(de0$n, 0L)
  expect_equal(de0$n_eff, 0)

  de1 <- design_effect(rep(2, 10))            # equal weights -> deff exactly 1
  expect_equal(de1$deff, 1)
  expect_equal(de1$n_eff, 10)
  expect_equal(de1$cv, 0)
  expect_equal(de1$n, 10L)
})

test_that("design_effect accepts a prepped recipe directly", {
  p  <- prep(sp() |> step_rescale(to = "n"))
  de <- design_effect(p)
  expect_equal(de$deff, design_effect(p$final_weight)$deff)
})
