## ===========================================================================
## Generates the nonprobability-inference example datasets for weightflow:
##   nps_sample        - a nonprobability (convenience) sample of ~1500 units
##                       drawn with a self-selection mechanism that depends on
##                       covariates correlated with the outcome, so the naive
##                       NPS mean is clearly biased. No design weights.
##   reference_sample  - a large probability reference sample (~30000 units)
##                       from the SAME population, with design weights (pw_ref)
##                       that sum to the population size (~1,000,000).
##
## Both carry the common covariates region, sex, age and the outcome income.
## These datasets use their own large synthetic population (independent of the
## small `population` used elsewhere in the package).
##
## Run from the package root:  source("data-raw/nonprob_data.R")
## ===========================================================================

set.seed(2025)

## ---- 0. Large synthetic finite population (1,000,000) ----------------------
N      <- 1e6
regs   <- c("North", "South", "East", "West")
region <- factor(sample(regs, N, replace = TRUE, prob = c(.32, .28, .22, .18)),
                 levels = regs)
sex    <- factor(sample(c("F", "M"), N, replace = TRUE), levels = c("F", "M"))
age    <- round(pmin(pmax(rnorm(N, 44, 17), 18), 95))

base_r <- c(North = 10.05, South = 9.75, East = 9.60, West = 9.85)[as.character(region)]
income <- round(exp(base_r + 0.006 * (age - 44) +
                    ifelse(sex == "M", 0.15, 0) + rnorm(N, 0, 0.40)))

pop_big <- data.frame(person_id = seq_len(N), region, sex, age, income)
true_mean <- mean(pop_big$income)

## ---- 1. Nonprobability sample (~1500), strong self-selection ----------------
lin <- -7.4 +
  1.30 * (log(income) - mean(log(income))) +
  -0.015 * (age - 44) +
  0.40 * (sex == "M") +
  0.50 * (region %in% c("North", "East"))
p_part <- plogis(lin)
in_nps <- rbinom(N, 1, p_part) == 1

nps_sample <- pop_big[in_nps, c("person_id", "region", "sex", "age", "income")]
rownames(nps_sample) <- NULL

## ---- 2. Reference probability sample (~30000) with design weights -----------
n_ref_total <- 30000
reg_n  <- table(pop_big$region)
effort <- c(North = 1.0, South = 1.1, East = 1.6, West = 1.8)
raw    <- reg_n[names(effort)] * effort
frac   <- as.numeric(raw / sum(raw) * n_ref_total) / as.numeric(reg_n[names(effort)])
names(frac) <- names(effort)
frac   <- pmin(frac, 0.99)

sel <- logical(N)
for (rg in names(frac)) {
  idx <- which(pop_big$region == rg)
  sel[sample(idx, round(length(idx) * frac[rg]))] <- TRUE
}
reference_sample <- pop_big[sel, c("person_id", "region", "sex", "age", "income")]
reference_sample$pw_ref <- 1 / frac[as.character(reference_sample$region)]
rownames(reference_sample) <- NULL

## ---- report -----------------------------------------------------------------
cat(sprintf("population (synthetic): %8d   true mean income = %.0f\n", N, true_mean))
cat(sprintf("nps_sample:             %8d   naive mean income = %.0f  (bias %+.0f)\n",
            nrow(nps_sample), mean(nps_sample$income),
            mean(nps_sample$income) - true_mean))
cat(sprintf("reference_sample:       %8d   sum(pw_ref) = %s\n",
            nrow(reference_sample), format(round(sum(reference_sample$pw_ref)), big.mark = ",")))
cat(sprintf("weighted reference mean income = %.0f\n",
            sum(reference_sample$pw_ref * reference_sample$income) /
            sum(reference_sample$pw_ref)))

usethis::use_data(nps_sample, reference_sample, overwrite = TRUE)
