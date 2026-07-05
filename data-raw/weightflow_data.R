## ===========================================================================
## Generates the example datasets bundled with weightflow:
##   population     - the target population (frame): stratum (region) -> PSU ->
##                    household -> person, with auxiliaries and outcomes.
##   sample_survey  - simple take-all-roster sample (back-compatible) + psu.
##   sample_one     - realistic SELECT-ONE-PERSON multistage design: unknown
##                    eligibility and ineligible addresses come as single rows
##                    (no roster); resolved eligible households are reached or
##                    not (household nonresponse); one person is selected per
##                    reached household with an unequal within-household
##                    probability (p_within), and may respond or not.
##
## Run once (from the package root):  source("data-raw/weightflow_data.R")
## Writes data/population.rda, data/sample_survey.rda, data/sample_one.rda
## ===========================================================================

set.seed(2024)
regs <- c("North", "South", "East", "West")

## ---- Household frame: stratum (region) -> PSU -> household -----------------
n_psu      <- c(North = 40, South = 35, East = 25, West = 20)   # PSUs per stratum
psu_region <- rep(regs, n_psu[regs])
P          <- length(psu_region)
psu_id     <- seq_len(P)
hh_per_psu <- sample(10:24, P, replace = TRUE)
hh_psu     <- rep(psu_id, hh_per_psu)
hh_region  <- rep(psu_region, hh_per_psu)
H          <- length(hh_psu)
hh_id      <- seq_len(H)
hh_status  <- ifelse(runif(H) < 0.06, "ineligible", "eligible")   # ~6% out of scope
hh_size    <- ifelse(hh_status == "eligible",
                     sample(1:5, H, replace = TRUE, prob = c(.30, .30, .20, .12, .08)),
                     0L)

## ---- Population: all persons in eligible households (the frame) ------------
elig_hh   <- hh_id[hh_status == "eligible"]
pe_hh     <- rep(elig_hh, hh_size[elig_hh])
Np        <- length(pe_hh)
pe_region <- hh_region[pe_hh]
pe_psu    <- hh_psu[pe_hh]
pe_sex    <- sample(c("F", "M"), Np, replace = TRUE)
pe_age    <- round(pmin(pmax(rnorm(Np, 42, 18), 18), 95))
pe_base   <- c(North = 9.9, South = 9.6, East = 9.4, West = 9.7)[pe_region]
pe_income <- round(exp(pe_base + 0.004 * (pe_age - 42) +
                       ifelse(pe_sex == "M", 0.12, 0) + rnorm(Np, 0, 0.45)))
pe_emp    <- rbinom(Np, 1, plogis(-0.5 + 0.03 * (pe_age - 42) -
                                  0.0004 * (pe_age - 42)^2 + ifelse(pe_sex == "M", 0.3, 0)))

population <- data.frame(
  person_id    = seq_len(Np),
  household_id = pe_hh,
  psu          = pe_psu,
  region       = factor(pe_region, levels = regs),
  sex          = factor(pe_sex, levels = c("F", "M")),
  age          = pe_age,
  income       = pe_income,
  employed     = pe_emp
)

## ---- sample_survey: simple take-all-roster sample (back-compatible) --------
fr      <- c(North = .08, South = .10, East = .12, West = .15)
hh_all  <- unique(population$household_id)
hh_reg  <- as.character(population$region[match(hh_all, population$household_id)])
take_hh <- hh_all[runif(length(hh_all)) < fr[hh_reg]]
ss      <- population[population$household_id %in% take_hh, ]
ss$pw   <- as.numeric(1 / fr[as.character(ss$region)])
m       <- nrow(ss)
ss$unknown_elig <- rbinom(m, 1, 0.04)
ss$responded    <- rbinom(m, 1, plogis(0.6 + 0.01 * (ss$age - 42) - 0.4 * (ss$region == "West")))
ss$responded[ss$unknown_elig == 1] <- 0

sample_survey <- data.frame(
  person_id = ss$person_id, household_id = ss$household_id, psu = ss$psu,
  region = ss$region, sex = ss$sex, age = ss$age, pw = ss$pw,
  unknown_elig = ss$unknown_elig, responded = ss$responded,
  income   = ifelse(ss$responded == 1, ss$income,   NA),
  employed = ifelse(ss$responded == 1, ss$employed, NA),
  row.names = NULL
)

## ---- sample_one: multistage SELECT-ONE-PERSON design ----------------------
# Stage 1: sample PSUs within each stratum (unequal fractions -> design effect)
f1       <- c(North = .30, South = .35, East = .45, West = .55)
samp_psu <- psu_id[runif(P) < f1[psu_region]]
# Stage 2: sample households within sampled PSUs
f2       <- 0.5
samp_hh  <- hh_id[(hh_psu %in% samp_psu) & (runif(H) < f2)]
m        <- length(samp_hh)
pw_hh    <- as.numeric(1 / (f1[hh_region[samp_hh]] * f2))   # design weight per household

# Field outcome per sampled household
st            <- hh_status[samp_hh]
unk           <- runif(m) < 0.05                      # unknown eligibility (no roster)
resolved_elig <- !unk & st == "eligible"
reached       <- resolved_elig & (runif(m) < 0.85)    # household reached (roster)
hhnr          <- resolved_elig & !reached             # eligible, household nonresponse
inelig        <- !unk & st == "ineligible"            # resolved out of scope

cols <- c("person_id", "household_id", "psu", "region", "sex", "age", "pw",
          "status", "unknown_elig", "ineligible", "hh_responded", "responded",
          "n_elig", "p_within", "income", "employed")

# Reached households: select ONE person with unequal within-household probability
reach_pos <- which(reached)
sel_list <- lapply(reach_pos, function(i) {
  h  <- samp_hh[i]; ne <- hh_size[h]
  sx <- sample(c("F", "M"), ne, replace = TRUE)
  ag <- round(pmin(pmax(rnorm(ne, 42, 18), 18), 95))
  pr <- runif(ne, 0.5, 1.5); pr <- pr / sum(pr)       # unequal selection probs
  j  <- sample.int(ne, 1, prob = pr)
  resp <- rbinom(1, 1, plogis(0.7 + 0.01 * (ag[j] - 42) - 0.4 * (hh_region[h] == "West")))
  bse  <- c(North = 9.9, South = 9.6, East = 9.4, West = 9.7)[hh_region[h]]
  inc  <- round(exp(bse + 0.004 * (ag[j] - 42) + ifelse(sx[j] == "M", 0.12, 0) + rnorm(1, 0, 0.45)))
  emp  <- rbinom(1, 1, plogis(-0.5 + 0.03 * (ag[j] - 42) + ifelse(sx[j] == "M", 0.3, 0)))
  data.frame(person_id = NA_integer_, household_id = h, psu = hh_psu[h],
             region = hh_region[h], sex = sx[j], age = ag[j], pw = pw_hh[i],
             status = "eligible", unknown_elig = 0L, ineligible = 0L,
             hh_responded = 1L, responded = resp, n_elig = ne, p_within = pr[j],
             income = ifelse(resp == 1, inc, NA), employed = ifelse(resp == 1, emp, NA),
             stringsAsFactors = FALSE)
})
sel <- if (length(sel_list)) do.call(rbind, sel_list) else NULL

# Single placeholder rows (no roster) for unknown / ineligible / household-NR
placeholder <- function(pos, status, ue, inelg, hhr) {
  if (!length(pos)) return(NULL)
  h <- samp_hh[pos]
  data.frame(person_id = NA_integer_, household_id = h, psu = hh_psu[h],
             region = hh_region[h], sex = NA, age = NA, pw = pw_hh[pos],
             status = status, unknown_elig = ue, ineligible = inelg,
             hh_responded = hhr, responded = NA, n_elig = NA, p_within = NA,
             income = NA, employed = NA, stringsAsFactors = FALSE)
}
ph_unk <- placeholder(which(unk),    "unknown",    1L, 0L, NA)
ph_ine <- placeholder(which(inelig), "ineligible", 0L, 1L, NA)
ph_nr  <- placeholder(which(hhnr),   "eligible",   0L, 0L, 0L)

sample_one <- rbind(sel[, cols], ph_unk[, cols], ph_ine[, cols], ph_nr[, cols])
sample_one$region <- factor(sample_one$region, levels = regs)
sample_one$sex    <- factor(sample_one$sex,    levels = c("F", "M"))
sample_one <- sample_one[order(sample_one$psu, sample_one$household_id), ]
sample_one$person_id <- seq_len(nrow(sample_one))
rownames(sample_one) <- NULL

# Full field disposition as a single "reason" column, recoded from the
# eligibility and response components above. It matches the survey disposition
# tree (eligible respondent / eligible nonrespondent / household nonresponse /
# ineligible / unknown eligibility). The 0/1 indicator columns are kept for
# backward compatibility; `disposition` is the tidy single-column view of them.
sample_one$disposition <- factor(
  with(sample_one, ifelse(
    status == "unknown",         "unknown eligibility",
    ifelse(status == "ineligible",   "ineligible",
    ifelse(hh_responded %in% 0L,     "household nonresponse",
    ifelse(responded == 1,           "eligible respondent",
                                     "eligible nonrespondent"))))),
  levels = c("eligible respondent", "eligible nonrespondent",
             "household nonresponse", "ineligible", "unknown eligibility"))

usethis::use_data(population, sample_survey, sample_one, overwrite = TRUE)
