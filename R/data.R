#' Synthetic target population (sampling frame)
#'
#' The simulated frame every weightflow example draws from: 4,495 persons nested
#' in 1,882 households, in 120 primary sampling units, in 4 regions used as
#' strata. Because the whole population is observed, it supplies the known
#' population totals a calibration step needs, and the true values against which a
#' weighted estimate can be checked.
#'
#' @format A data frame with one row per person:
#' \describe{
#'   \item{person_id}{individual identifier}
#'   \item{household_id}{household identifier (cluster)}
#'   \item{psu}{primary sampling unit (segment) within the stratum}
#'   \item{region}{stratum: North, South, East or West}
#'   \item{sex}{F or M}
#'   \item{age}{age in years (18-95)}
#'   \item{income}{annual income}
#'   \item{employed}{employment indicator (0/1)}
#' }
"population"

#' Synthetic person sample with a take-all household roster
#'
#' A stratified two-stage sample of 467 persons drawn from [population]: PSUs
#' within region, then households within PSU, then **every** adult of the selected
#' household (take-all roster). It carries unequal design base weights, an
#' unknown-eligibility flag and a person-level response indicator, and it is the
#' dataset the short examples in this package use.
#'
#' @format A data frame with one row per sampled person:
#' \describe{
#'   \item{person_id, household_id, psu}{identifiers}
#'   \item{region, sex, age}{frame auxiliaries, known for all units}
#'   \item{pw}{design base weight (inverse sampling fraction)}
#'   \item{unknown_elig}{1 if eligibility is unknown}
#'   \item{responded}{1 if the person responded}
#'   \item{income, employed}{survey outcomes; NA for nonrespondents}
#' }
"sample_survey"

#' Synthetic address sample with one selected person per household
#'
#' A multistage sample of 417 addresses (stratum, then PSU, then household, then
#' one person inside the reached household) carrying every complication a
#' household survey meets: unresolved eligibility, out-of-scope addresses,
#' household nonresponse, unequal within-household selection and person
#' nonresponse. It is the dataset that exercises the complete weighting cascade.
#'
#' @format A data frame with one row per sampled household (the selected person,
#'   or a single placeholder row for non-roster cases):
#' \describe{
#'   \item{person_id, household_id, psu}{identifiers}
#'   \item{region}{stratum}
#'   \item{sex, age}{selected person's attributes (NA on non-roster rows)}
#'   \item{pw}{design base weight (product of the stage selection probabilities)}
#'   \item{status}{"eligible", "ineligible" or "unknown"}
#'   \item{disposition}{full field disposition as a single factor (a recode of
#'     the indicator columns): "eligible respondent", "eligible nonrespondent",
#'     "household nonresponse", "ineligible" or "unknown eligibility"}
#'   \item{unknown_elig}{1 if eligibility is unknown (no roster)}
#'   \item{ineligible}{1 if the address is out of scope (no roster)}
#'   \item{hh_responded}{1 reached, 0 household nonresponse, NA for non-eligible}
#'   \item{responded}{1 if the selected person responded (NA on non-roster rows)}
#'   \item{n_elig}{number of eligible persons in the household (NA on non-roster rows)}
#'   \item{p_within}{within-household selection probability of the selected person}
#'   \item{income, employed}{survey outcomes; NA unless the person responded}
#' }
"sample_one"
