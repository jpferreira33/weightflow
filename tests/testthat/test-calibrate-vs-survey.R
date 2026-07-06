# step_calibrate() must reproduce survey's calibrated weights, for the three
# methods (post-stratification, raking, linear/GREG). We build the full cascade
# on sample_one (unknown eligibility -> drop ineligible -> household nonresponse
# -> within-household selection -> person nonresponse), hand survey the
# nonresponse-adjusted weights (all cascade, pre-calibration), and calibrate the
# same way on both sides. weightflow uses the tidy totals format throughout.

# ---- build the cascade once and return the pre-calibration state ----------
cascade <- function() {
  dat <- sample_one
  dat$age_grp <- cut(dat$age, c(0, 30, 45, 60, Inf),
                     labels = c("18-30", "31-45", "46-60", "60+"))

  # cascade WITHOUT calibration -> nonresponse-adjusted weights
  nr_spec <- weighting_spec(dat, base_weights = pw) |>
    step_unknown_eligibility(unknown = unknown_elig, by = "region") |>
    step_drop_ineligible(ineligible = ineligible) |>
    step_nonresponse(respondent = hh_responded, method = "weighting_class",
                     by = "region") |>
    step_select_within(prob = p_within) |>
    step_nonresponse(respondent = responded, method = "weighting_class",
                     by = c("region", "sex", "age_grp"))
  nr  <- prep(nr_spec)$final_weight
  act <- which(nr > 0)                       # eligible respondents

  dat$w_nr <- nr
  list(dat = dat, nr_spec = nr_spec, act = act,
       des = survey::svydesign(ids = ~1, weights = ~w_nr, data = dat[act, ]))
}

# population calibration targets (tidy for weightflow)
reg_tab <- as.data.frame(table(region = population$region))
sex_tab <- as.data.frame(table(sex    = population$sex))
inc_tot <- sum(population$income)

test_that("poststratify matches survey::postStratify", {
  skip_if_not_installed("survey")
  cc  <- cascade()
  # weightflow: tidy joint table (region x sex), crossed automatically
  ps_tab <- as.data.frame(table(region = population$region, sex = population$sex))
  wf <- prep(cc$nr_spec |>
               step_calibrate(method = "poststratify", totals = ps_tab,
                              count = "Freq"))$final_weight[cc$act]
  # survey
  des_ps <- survey::postStratify(cc$des, ~ region + sex, ps_tab)
  expect_equal(as.numeric(weights(des_ps)), as.numeric(wf), tolerance = 1e-6)
})

test_that("raking matches survey::rake", {
  skip_if_not_installed("survey")
  cc <- cascade()
  wf <- prep(cc$nr_spec |>
               step_calibrate(method = "raking",
                              totals = list(reg_tab, sex_tab),
                              count = "Freq"))$final_weight[cc$act]
  des_rk <- survey::rake(cc$des,
                         sample.margins     = list(~ region, ~ sex),
                         population.margins = list(reg_tab, sex_tab))
  expect_equal(as.numeric(weights(des_rk)), as.numeric(wf), tolerance = 1e-6)
})

test_that("linear/GREG (categorical + numeric) matches survey::calibrate", {
  skip_if_not_installed("survey")
  cc <- cascade()
  # weightflow: tidy list, data frame per factor + a single number for income
  wf <- prep(cc$nr_spec |>
               step_calibrate(method = "linear", formula = ~ region + sex + income,
                              totals = list(region = reg_tab, sex = sex_tab,
                                            income = inc_tot),
                              count = "Freq"))$final_weight[cc$act]
  # survey: the classic model-matrix totals vector (reference levels dropped)
  rlev <- levels(population$region); slev <- levels(population$sex)
  pop_tot <- c(`(Intercept)` = nrow(population),
    stats::setNames(as.numeric(table(population$region))[-1], paste0("region", rlev[-1])),
    stats::setNames(as.numeric(table(population$sex))[-1],    paste0("sex",    slev[-1])),
    income = inc_tot)
  des_lin <- survey::calibrate(cc$des, ~ region + sex + income,
                               population = pop_tot, calfun = "linear")
  expect_equal(as.numeric(weights(des_lin)), as.numeric(wf), tolerance = 1e-6)
})
