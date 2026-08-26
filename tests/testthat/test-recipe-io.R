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
  w1 <- prep(spec)$final_weight
  w2 <- prep(spec2)$final_weight
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

test_that("read_recipe rejects a non-recipe file", {
  skip_if_not_installed("yaml")
  f <- tempfile(fileext = ".yml")
  writeLines("something: else", f)
  expect_error(read_recipe(f), "not a weightflow recipe")
})
