library(weightflow)
set.seed(2024)
H   <- 800                                          # number of households
sz  <- sample(1:5, H, replace = TRUE, prob = c(.25, .35, .22, .12, .06))
n   <- sum(sz)

region_h <- sample(c("North", "South"), H, replace = TRUE, prob = c(.4, .6))
pw_h     <- ifelse(region_h == "North", 30, 70)     # design weight per household
u1 <- runif(H); u2 <- runif(H)
unknown_h   <- as.integer(u1 < .08)                 # 1 = eligibility unknown
responded_h <- as.integer(unknown_h == 0 & u2 < .70) # 1 = responded (among known)

survey <- data.frame(
  id           = seq_len(n),
  household    = rep(seq_len(H), sz),
  region       = rep(region_h, sz),                 # constant within household
  pw           = rep(pw_h, sz),                      # constant within household
  unknown_elig = rep(unknown_h, sz),                 # 0/1 dummy (household level)
  responded    = rep(responded_h, sz),               # 0/1 dummy (household level)
  sex          = sample(c("M", "F"), n, replace = TRUE),         # varies per person
  age_g        = sample(c("18-34", "35-54", "55+"), n, replace = TRUE),
  stringsAsFactors = FALSE
)
survey$income <- round(rlnorm(n, meanlog = 9.2, sdlog = 0.5))    # continuous, per person

# Target population totals (for linear/GREG calibration).
# We use design-implied totals so the g factor stays ~1.
N      <- sum(survey$pw)
totals <- c("(Intercept)" = N,
            sexM          = round(N * 0.49),
            income        = round(sum(survey$pw * survey$income)))

# --- 2. Recipe: HOUSEHOLD-level adjustments -> uniform weights per household -
# Eligibility and nonresponse use 0/1 dummies and adjust by region (a
# household-level variable), so weights stay uniform within a household. The
# final integrative calibration preserves that uniformity.
recipe <- weighting_spec(survey, base_weights = pw) |>
  step_unknown_eligibility(
    unknown = unknown_elig,                # 0/1 dummy: 1 = eligibility unknown
    by = c("region")
  ) |>
  step_nonresponse(respondent = responded, method = "propensity",# 0/1 dummy: 1 = responded
                   engine = "forest", 
                   formula = ~ region + sex + age_g,
                   num_classes = 10) |> 
  step_calibrate(
    method  = "linear",                    # GREG: handles income (continuous)
    formula = ~ sex + income,
    totals  = totals,
    cluster = "household",
    equal_within_cluster = TRUE            # equal weights within household
  ) |>
  step_round(digits = 0, method = "preserve_total")   # integers; "nearest" keeps household equality

print(recipe)

# --- 3. Estimate the cascade -----------------------------------------------
fitted <- prep(recipe)
print(fitted)

# --- 4. Detailed per-step diagnostics --------------------------------------
summary(fitted)

report_weighting(fitted)   


# --- 5. Result and within-household equality check -------------------------
wts <- collect_weights(fitted, drop_zero = TRUE, keep_intermediate = TRUE)

chk <- tapply(wts$.weight, wts$household, function(z) diff(range(z)))
cat(sprintf("\nActive households                    : %d\n", length(chk)))
cat(sprintf("Households with NON-uniform wts (>1e-6): %d\n", sum(chk > 1e-6, na.rm = TRUE)))
cat(sprintf("Sum of final weights                 : %.0f (target N = %.0f)\n",
            sum(wts$.weight), N))
cat(sprintf("Final design effect (Kish)           : %.3f\n",
            design_effect(wts$.weight)$deff))

# --- 5b. Diagnostic plots --------------------------------------------------
plot(fitted)                       # per-step factor histograms + summary panel
# plot(fitted, type = "factors")   # only per-step factor histograms
# plot(fitted, type = "summary")   # only the summary 2x2 panel
# wf <- weight_factors(fitted); head(wf)   # per-unit/per-step factors
report_weighting(fitted)           # nice self-contained HTML report (opens in browser)

# --- 6. Note: PERSON-level nonresponse -------------------------------------
# If instead of 'by = region' (household level) you adjusted by 'age_g' (which
# varies within the household), weights would no longer be uniform per household
# before calibration. With equal_within_cluster = TRUE the summary would show
# "one weight per household" but the input would not be uniform. Unequal weights
# per person are perfectly valid; it just means you did not get the equality
# property you explicitly requested.

# --- 7. Other calibrations (alternatives to step 2) ------------------------
# (a) Classic categorical raking:
#   step_calibrate(margins = list(sex = c(M = 50000, F = 52000)), method = "raking")
# (b) Propensity nonresponse with random forest (needs 'ranger'):
#   step_nonresponse(respondent = responded, method = "propensity",
#                    engine = "forest", formula = ~ region + sex + age_g,
#                    num_classes = 10)

# --- 8. New steps: bounded calibration, assert, auto-trim, rescale ---------
# (a) Bounded calibration (logit calfun keeps g within bounds; no negative or
#     extreme weights). Also works as `calfun = "linear"` + `bounds`:
#   step_calibrate(method = "linear", formula = ~ sex + income, totals = totals,
#                  calfun = "logit", bounds = c(0.3, 3))
#
# (b) Checkpoint that fails the pipeline if quality drops:
#   step_assert(max_deff = 1.5, max_weight_ratio = 5, min_n_eff = 1000,
#               on_fail = "warning")
#
# (c) Automatic survey-style trimming (no weight < 1; auto upper cap; strict):
#   step_trim_weights(lower = 1, upper = NULL, strict = TRUE)
#
# (d) Rescale so weights sum to the sample size (mean weight 1):
#   step_rescale(to = "n")
#   step_rescale(to = "total", total = 100000)
