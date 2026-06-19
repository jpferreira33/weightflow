## ===========================================================================
## Generates the example datasets bundled with weightflow:
##   population     - the full target population (frame), one row per person
##   sample_survey  - a household sample drawn from it
## Run once:  source("data-raw/weightflow_data.R")
## ===========================================================================

set.seed(2024)

## ---- Population (sampling frame) ------------------------------------------
N_hh    <- 6000
hh_size <- sample(1:5, N_hh, replace = TRUE, prob = c(.30, .30, .20, .12, .08))
N       <- sum(hh_size)

household_id <- rep(seq_len(N_hh), hh_size)
region <- rep(sample(c("North", "South", "East", "West"), N_hh, replace = TRUE,
                     prob = c(.35, .30, .20, .15)), hh_size)
sex    <- sample(c("F", "M"), N, replace = TRUE)
age    <- round(pmin(pmax(rnorm(N, 42, 18), 18), 95))

base_inc <- c(North = 9.9, South = 9.6, East = 9.4, West = 9.7)[region]
income   <- round(exp(base_inc + 0.004 * (age - 42) +
                      ifelse(sex == "M", 0.12, 0) + rnorm(N, 0, 0.45)))

p_emp    <- plogis(-0.5 + 0.03 * (age - 42) - 0.0004 * (age - 42)^2 +
                   ifelse(sex == "M", 0.3, 0))
employed <- rbinom(N, 1, p_emp)

population <- data.frame(
  person_id    = seq_len(N),
  household_id = household_id,
  region       = factor(region, levels = c("North", "South", "East", "West")),
  sex          = factor(sex, levels = c("F", "M")),
  age          = age,
  income       = income,
  employed     = employed
)

## ---- Sample ---------------------------------------------------------------
f_region  <- c(North = 0.08, South = 0.10, East = 0.12, West = 0.15)
hh_region <- tapply(as.character(population$region), population$household_id,
                    function(z) z[1])
hh_ids    <- as.integer(names(hh_region))
sampled   <- hh_ids[runif(length(hh_ids)) < f_region[hh_region]]
samp      <- population[population$household_id %in% sampled, ]
n         <- nrow(samp)

pw <- 1 / f_region[as.character(samp$region)]

unknown_elig <- rbinom(n, 1, 0.04)
responded    <- rbinom(n, 1, plogis(0.6 + 0.01 * (samp$age - 42) -
                                    0.4 * (samp$region == "West")))
responded[unknown_elig == 1] <- 0

sample_survey <- data.frame(
  person_id    = samp$person_id,
  household_id = samp$household_id,
  region       = samp$region,
  sex          = samp$sex,
  age          = samp$age,
  pw           = as.numeric(pw),
  unknown_elig = unknown_elig,
  responded    = responded,
  income       = ifelse(responded == 1, samp$income,   NA),
  employed     = ifelse(responded == 1, samp$employed, NA),
  row.names    = NULL
)

usethis::use_data(population, sample_survey, overwrite = TRUE)

