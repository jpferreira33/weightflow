# ===========================================================================
# DEMO: Model calibration (model-assisted, Wu & Sitter 2001)
#
# Generates a full POPULATION, samples from it, and tests step_model_calibration.
# Since we know the y variables for the whole population, we can verify whether
# model calibration brings the estimates closer to the true values.
#
#   setwd("path/to/weightflow"); source("demo_model.R")
# ===========================================================================

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

# --- 1. Full population ----------------------------------------------------
set.seed(7)
Npop <- 50000
pop <- data.frame(
  sex    = sample(c("M", "F"),                Npop, replace = TRUE, prob = c(.48, .52)),
  region = sample(c("North", "South"),        Npop, replace = TRUE, prob = c(.40, .60)),
  age_g  = sample(c("18-34", "35-54", "55+"), Npop, replace = TRUE, prob = c(.40, .35, .25)),
  stringsAsFactors = FALSE
)
pop$age <- round(runif(Npop, 18, 85))          # continuous age (extra predictor)

# Income depends on the auxiliaries AND on continuous age (+ noise). Continuous
# age carries information the age groups (X) do not: that is where model
# calibration gains over calibrating to X alone.
mu <- 6000 +
      1500 * (pop$sex    == "M")    +
      2000 * (pop$region == "South") +
      90   *  pop$age +
      ifelse(pop$age_g == "35-54", 1500, ifelse(pop$age_g == "55+", 800, 0))
pop$income <- round(pmax(0, rnorm(Npop, mu, 2500)))
pop$poor   <- as.integer(pop$income < 9000)

# TRUE population totals (for verification)
T_income_true <- sum(pop$income)
T_poor_true   <- sum(pop$poor)

# --- 2. Sample (simple random sampling) ------------------------------------
n      <- 2000
idx    <- sample(Npop, n)
sample_df    <- pop[idx, ]
sample_df$pw <- Npop / n                        # design weight (SRS)

# Population frame for calibration: auxiliaries/predictors only (no y).
frame <- pop[, c("sex", "region", "age_g", "age")]

# --- 3. Model calibration --------------------------------------------------
# Consistency: totals of sex, region and age groups (categorical X).
# Efficiency : models for income (continuous) and poor (binary), using
#              continuous age as an extra predictor.
recipe_mc <- weighting_spec(sample_df, base_weights = pw) |>
  step_model_calibration(
    x_formula = ~ sex + region + age_g,
    models = list(
      income = y_model(income ~ sex + region + age, engine = "glm", family = "gaussian"),
      poor   = y_model(poor   ~ sex + region + age, engine = "glm", family = "binomial")
    ),
    population = frame
  )

fitted <- prep(recipe_mc)
summary(fitted)                      # target vs achieved per constraint
wts <- collect_weights(fitted)

# --- 4. Verification: total estimator vs the TRUE value --------------------
# Compare the design (Horvitz-Thompson) estimator against the model-calibrated
# one, using the REAL sample y. The true total is known.
est_HT_income <- sum(sample_df$pw  * sample_df$income)
est_MC_income <- sum(wts$.weight   * wts$income)
est_HT_poor   <- sum(sample_df$pw  * sample_df$poor)
est_MC_poor   <- sum(wts$.weight   * wts$poor)

err <- function(est, real) sprintf("%12.0f (error %+.2f%%)", est, 100 * (est / real - 1))

cat("\n================ Total estimation ================\n")
cat("INCOME total\n")
cat("  True             :", sprintf("%12.0f", T_income_true), "\n")
cat("  Design (HT)      :", err(est_HT_income, T_income_true), "\n")
cat("  Model-calibrated :", err(est_MC_income, T_income_true), "\n")
cat("POOR total\n")
cat("  True             :", sprintf("%12.0f", T_poor_true), "\n")
cat("  Design (HT)      :", err(est_HT_poor, T_poor_true), "\n")
cat("  Model-calibrated :", err(est_MC_poor, T_poor_true), "\n")

cat("\nConsistency with X (should be ~0 error by construction):\n")
cat("  Population total :", sprintf("%6.0f vs %6.0f\n", sum(wts$.weight), Npop))
cat("  Males            :", sprintf("%6.0f vs %6.0f\n",
    sum(wts$.weight[wts$sex == "M"]), sum(pop$sex == "M")))
cat("  Region South     :", sprintf("%6.0f vs %6.0f\n",
    sum(wts$.weight[wts$region == "South"]), sum(pop$region == "South")))

# --- 5. Monte Carlo verification: efficiency (RMSE over many samples) -------
# Model calibration reduces the VARIANCE of the estimator, not the error of a
# single sample. To see it, we repeat the sampling B times and compare the RMSE
# of each estimator of the income total against the true value.
cat("\nRunning Monte Carlo verification (may take a moment)...\n")
B  <- 200
ht <- mc <- numeric(B)
for (b in seq_len(B)) {
  ib <- sample(Npop, n)
  mb <- pop[ib, ]; mb$pw <- Npop / n
  ht[b] <- sum(mb$pw * mb$income)
  ajb <- prep(weighting_spec(mb, base_weights = pw) |>
    step_model_calibration(
      x_formula  = ~ sex + region + age_g,
      models     = list(income = y_model(income ~ sex + region + age,
                                          engine = "glm", family = "gaussian")),
      population = frame))
  pb    <- collect_weights(ajb)
  mc[b] <- sum(pb$.weight * pb$income)
}
rmse <- function(e) sqrt(mean((e - T_income_true)^2))
cat(sprintf("\nRMSE of the income total over %d samples:\n", B))
cat(sprintf("  Design (HT)      : %.0f\n", rmse(ht)))
cat(sprintf("  Model-calibrated : %.0f\n", rmse(mc)))
cat(sprintf("  RMSE reduction   : %.1f%%\n", 100 * (1 - rmse(mc) / rmse(ht))))
