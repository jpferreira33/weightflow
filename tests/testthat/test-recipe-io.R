# write_recipe() / read_recipe(): serialize a recipe to YAML and rebuild it.

test_that("a recipe round-trips through YAML and reproduces the weights", {
  skip_if_not_installed("yaml")
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_unknown_eligibility(unknown = unknown_elig, by = "region") |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    step_calibrate(method = "raking",
                   margins = list(region = c(table(population$region)))) |>
    step_trim_weights(upper = 8)

  f <- tempfile(fileext = ".yml")
  write_recipe(spec, f)
  expect_true(file.exists(f))

  # manifest read (no data): inspectable, right number of steps and ids
  man <- read_recipe(f)
  expect_s3_class(man, "weightflow_recipe")
  expect_equal(length(man$steps), 4L)
  expect_equal(man$base_weights, "pw")
  expect_output(print(man), "weightflow recipe")

  # executable read (with data): rebuilds a spec that preps to the SAME weights
  spec2 <- read_recipe(f, data = sample_survey)
  expect_s3_class(spec2, "weighting_spec")
  # (this recipe's trim step loses a little mass -> a step_trim_weights warning; not the
  # subject here, so suppress it and just check the round-trip reproduces the weights)
  w1 <- suppressWarnings(prep(spec)$final_weight)
  w2 <- suppressWarnings(prep(spec2)$final_weight)
  expect_equal(w2, w1, tolerance = 1e-9)
})

test_that("a non-probability recipe round-trips and asks for its reference back", {
  skip_if_not_installed("yaml")
  set.seed(1)
  N   <- nrow(population)
  vol <- population[rbinom(N, 1, plogis(-2 + 0.9 * (population$sex == "M"))) == 1,
                    c("region", "sex", "income")]
  ref <- population[sample(N, 600), c("region", "sex")]; ref$d <- N / 600
  refs <- reference_sample(ref, "d")
  spec <- weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
    step_pseudoweight(reference = refs, formula = ~ region + sex, engine = "logit")

  f <- tempfile(fileext = ".yml")
  write_recipe(spec, f)
  man <- read_recipe(f)
  expect_true(isTRUE(man$nonprob))
  expect_null(man$base_weights)                      # NULL base -> non-probability

  # without the reference, reconstruction errors clearly, naming the step id
  sid <- man$steps[[1]]$id
  expect_error(read_recipe(f, data = vol), "reference_sample")
  # with the reference supplied by step id, it rebuilds and reproduces the weights
  spec2 <- read_recipe(f, data = vol, references = stats::setNames(list(refs), sid))
  w1 <- suppressWarnings(prep(spec)$final_weight)
  w2 <- suppressWarnings(prep(spec2)$final_weight)
  expect_equal(w2, w1, tolerance = 1e-6)
})

test_that("a recipe with a tidy totals table round-trips (the flagged gap)", {
  skip_if_not_installed("yaml")
  tot <- data.frame(region = names(table(population$region)),
                    Freq   = as.numeric(table(population$region)),
                    stringsAsFactors = FALSE)
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    step_calibrate(method = "poststratify", totals = tot, count = "Freq")

  f <- tempfile(fileext = ".yml")
  write_recipe(spec, f)                              # used to crash on the data frame
  spec2 <- read_recipe(f, data = sample_survey)
  expect_equal(prep(spec2)$final_weight, prep(spec)$final_weight, tolerance = 1e-9)
})

test_that("ordered factor and Date survive the totals_table round-trip (M-6)", {
  skip_if_not_installed("yaml")
  tot <- data.frame(
    grade = factor(c("low", "high"), levels = c("low", "high"), ordered = TRUE),
    day   = as.Date(c("2020-01-01", "2020-06-15")),
    Freq  = c(10, 20),
    stringsAsFactors = FALSE)
  rt <- weightflow:::.wf_decode(weightflow:::.wf_encode(tot), NULL, NULL)
  expect_true(is.ordered(rt$grade))
  expect_identical(levels(rt$grade), c("low", "high"))
  expect_s3_class(rt$day, "Date")
  expect_equal(rt$day, tot$day)
})

test_that("a census-sized frame is still rejected, and timestamp = FALSE is stable", {
  skip_if_not_installed("yaml")
  expect_error(weightflow:::.wf_encode(data.frame(x = 1:10001)), "microdata")
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_trim_weights(upper = 8)
  f1 <- tempfile(fileext = ".yml"); f2 <- tempfile(fileext = ".yml")
  write_recipe(spec, f1, timestamp = FALSE)
  Sys.sleep(1)
  write_recipe(spec, f2, timestamp = FALSE)
  expect_identical(readLines(f1), readLines(f2))     # byte-identical, clean git diffs
})

test_that("a recipe with step_nr_sensitivity round-trips (newest step)", {
  skip_if_not_installed("yaml")
  spec <- weighting_spec(sample_survey, base_weights = pw) |>
    step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
    step_nr_sensitivity(y = income, formula = ~ region + sex + age, phi = c(0, 0.5, 1))
  f <- tempfile(fileext = ".yml")
  write_recipe(spec, f)
  spec2 <- read_recipe(f, data = sample_survey)
  expect_equal(prep(spec2)$final_weight, prep(spec)$final_weight, tolerance = 1e-9)
  s <- nr_sensitivity(prep(spec2))                 # y / respondent decoded from expr
  expect_s3_class(s, "weightflow_nr_sensitivity")
  expect_true(all(c(0, 0.5, 1) %in% s$table$phi))
})

test_that("read_recipe rejects a non-recipe file", {
  skip_if_not_installed("yaml")
  f <- tempfile(fileext = ".yml")
  writeLines("something: else", f)
  expect_error(read_recipe(f), "not a weightflow recipe")
})

test_that("write_recipe does not serialize the previous wave's microdata for step_cre (IO-02)", {
  skip_if_not_installed("yaml")
  d <- data.frame(id = 1:6, sexo = factor(rep(c("F", "M"), 3)),
                  cond = rep(c("emp", "unemp", "inact"), 2), w = 10)
  Xt <- function(z) colSums(z$w * stats::model.matrix(~ sexo, z))
  seed <- prep(weighting_spec(d, base_weights = w) |>
                 step_cre(previous = NULL, status = cond, formula = ~ sexo,
                          totals = Xt(d), status_ref = "inact"))
  spec2 <- weighting_spec(d, base_weights = w) |>
    step_cre(previous = seed, status = cond, id_unit = "id", formula = ~ sexo,
             totals = Xt(d), status_ref = "inact")
  f <- tempfile(fileext = ".yml")
  write_recipe(spec2, f)                          # must not abort, must not dump the wave
  txt <- paste(readLines(f), collapse = "\n")
  expect_true(grepl("previous_wave", txt))        # the marker replaced the fitted wave
  expect_false(grepl("final_weight|history", txt))# no prepped-wave internals leaked
  # a CRE recipe cannot be rebuilt from YAML alone -> clear error, not a silent seed
  expect_error(read_recipe(f, data = d), "cannot be rebuilt")
})

test_that("read_recipe does not execute stored code by default (CRIT-1)", {
  node <- list(.wf = "function", value = "stop('code executed')")
  # default (allow_code = FALSE): refused with the security message, NEVER evaluated
  # (if it ran, the error message would be 'code executed', not the guard).
  expect_error(.wf_decode(node, NULL, "s1"), "allow_code")
  # explicit opt-in evaluates the source (here the stored stop() runs)
  expect_error(.wf_decode(node, NULL, "s1", allow_code = TRUE), "code executed")
  # a benign function round-trips only under allow_code = TRUE
  fn <- .wf_decode(list(.wf = "function", value = "function(x) x + 1"),
                   NULL, "s1", allow_code = TRUE)
  expect_true(is.function(fn))
  expect_equal(fn(1), 2)
})
