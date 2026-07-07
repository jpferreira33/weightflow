# Domain (partitioned) calibration: `by =` calibrates independently within each
# domain, each to its own totals. It must reproduce running the same calibration
# on each domain subset by hand.

pop_ag <- transform(population,
  age_grp = cut(age, c(0, 30, 45, 60, Inf), labels = c("18-30","31-45","46-60","60+")))
samp_ag <- transform(sample_survey,
  age_grp = cut(age, c(0, 30, 45, 60, Inf), labels = c("18-30","31-45","46-60","60+")))
resp_ag <- samp_ag[samp_ag$responded == 1, ]        # income observed here

sex_by_region <- as.data.frame(table(region = pop_ag$region, sex = pop_ag$sex))
age_by_region <- as.data.frame(table(region = pop_ag$region, age_grp = pop_ag$age_grp))
inc_by_region <- aggregate(income ~ region, pop_ag, sum)     # region, income

test_that("domain raking equals per-domain raking by hand", {
  w_by <- prep(
    weighting_spec(samp_ag, base_weights = pw) |>
      step_calibrate(method = "raking",
                     totals = list(sex_by_region, age_by_region),
                     count = "Freq", by = "region")
  )$final_weight

  w_man <- samp_ag$pw
  for (rg in levels(samp_ag$region)) {
    idx <- which(samp_ag$region == rg)
    sx  <- sex_by_region[sex_by_region$region == rg, c("sex", "Freq")]
    ag  <- age_by_region[age_by_region$region == rg, c("age_grp", "Freq")]
    w_man[idx] <- prep(
      weighting_spec(samp_ag[idx, ], base_weights = pw) |>
        step_calibrate(method = "raking", totals = list(sx, ag), count = "Freq")
    )$final_weight
  }
  expect_equal(w_by, w_man, tolerance = 1e-8)
})

test_that("domain linear (categorical + continuous) equals per-domain linear", {
  w_by <- prep(
    weighting_spec(resp_ag, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ sex + income,
                     totals = list(sex = sex_by_region, income = inc_by_region),
                     count = "Freq", by = "region")
  )$final_weight

  w_man <- resp_ag$pw
  for (rg in levels(resp_ag$region)) {
    idx <- which(resp_ag$region == rg)
    sx  <- sex_by_region[sex_by_region$region == rg, c("sex", "Freq")]
    inc <- inc_by_region$income[inc_by_region$region == rg]
    w_man[idx] <- prep(
      weighting_spec(resp_ag[idx, ], base_weights = pw) |>
        step_calibrate(method = "linear", formula = ~ sex + income,
                       totals = list(sex = sx, income = inc), count = "Freq")
    )$final_weight
  }
  expect_equal(w_by, w_man, tolerance = 1e-6)
})

test_that("ridge composes with domain calibration", {
  w_by <- prep(
    weighting_spec(resp_ag, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ sex + income,
                     totals = list(sex = sex_by_region, income = inc_by_region),
                     count = "Freq", by = "region", penalty = 1)
  )$final_weight

  w_man <- resp_ag$pw
  for (rg in levels(resp_ag$region)) {
    idx <- which(resp_ag$region == rg)
    sx  <- sex_by_region[sex_by_region$region == rg, c("sex", "Freq")]
    inc <- inc_by_region$income[inc_by_region$region == rg]
    w_man[idx] <- prep(
      weighting_spec(resp_ag[idx, ], base_weights = pw) |>
        step_calibrate(method = "linear", formula = ~ sex + income,
                       totals = list(sex = sx, income = inc), count = "Freq",
                       penalty = 1)
    )$final_weight
  }
  expect_equal(w_by, w_man, tolerance = 1e-6)
})

test_that("the raking distance composes with domain calibration (positive weights)", {
  w_by <- prep(
    weighting_spec(resp_ag, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ sex + income,
                     totals = list(sex = sex_by_region, income = inc_by_region),
                     count = "Freq", calfun = "raking", by = "region")
  )$final_weight

  w_man <- resp_ag$pw
  for (rg in levels(resp_ag$region)) {
    idx <- which(resp_ag$region == rg)
    sx  <- sex_by_region[sex_by_region$region == rg, c("sex", "Freq")]
    inc <- inc_by_region$income[inc_by_region$region == rg]
    w_man[idx] <- prep(
      weighting_spec(resp_ag[idx, ], base_weights = pw) |>
        step_calibrate(method = "linear", formula = ~ sex + income,
                       totals = list(sex = sx, income = inc), count = "Freq",
                       calfun = "raking")
    )$final_weight
  }
  expect_equal(w_by, w_man, tolerance = 1e-6)
  expect_true(all(w_by[w_by != 0] > 0))                       # exponential -> positive
  got <- tapply(w_by * resp_ag$income, resp_ag$region, sum)   # income reproduced per domain
  expect_equal(as.numeric(got),
               inc_by_region$income[match(names(got), inc_by_region$region)],
               tolerance = 1e-3)
})

test_that("domain calibration reproduces each domain's margins", {
  w <- prep(
    weighting_spec(samp_ag, base_weights = pw) |>
      step_calibrate(method = "raking",
                     totals = list(sex_by_region, age_by_region),
                     count = "Freq", by = "region")
  )$final_weight

  got <- as.data.frame(xtabs(w ~ region + sex,
                             data = data.frame(region = samp_ag$region,
                                               sex = samp_ag$sex, w = w)))
  m <- merge(got, sex_by_region, by = c("region", "sex"))
  expect_equal(m$Freq.x, m$Freq.y, tolerance = 1e-6)     # weighted totals == benchmarks
})

test_that("the domain variable in the formula errors", {
  expect_error(
    weighting_spec(resp_ag, base_weights = pw) |>
      step_calibrate(method = "linear", formula = ~ region + sex,
                     totals = list(region = sex_by_region), count = "Freq",
                     by = "region"),
    "must not appear"
  )
})
