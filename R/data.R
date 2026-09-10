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

#' Synthetic rotating- and pure-panel datasets
#'
#' Four small, reproducible household-panel datasets that ship with weightflow to test and
#' illustrate the panel tools. They share one structure and differ only in the **rotation
#' system**, so the same code runs on a pure panel and on each rotating design. All are in
#' **long format**: one row per person and per wave the person is in sample. Continuing units
#' keep the same `id_hogar` / `id_persona` across waves, so they link the panel; the household
#' is the natural cluster and `c(id_hogar, nper)` the person-level key.
#'
#' The between-wave disposition `disp` follows the four-state taxonomy the longitudinal
#' cascade needs: `"R"` responded, `"NR"` eligible nonresponse (reweight), `"OS"` out of scope
#' -- left the target population between waves, so the household exits permanently and is not
#' reweighted -- and `"UNK"` unknown eligibility. The variables of interest (`ocupado`,
#' `desocupado`, `ingreso`) are observed only when `disp == "R"` (and, for the labour-force
#' items, when the person is in the labour force), otherwise `NA`; they repeat across waves for
#' continuing persons, with within-person persistence, so net change and gross flows are
#' meaningful.
#'
#' @format A `data.frame` with one row per person-wave and the columns:
#' \describe{
#'   \item{id_hogar}{household id, persistent across waves (the panel link / cluster).}
#'   \item{id_persona, nper}{person id and person-number within household; `c(id_hogar, nper)`
#'     is the person key.}
#'   \item{estrato, psu}{design stratum and primary sampling unit (PSU nested in stratum, at
#'     least two PSUs per stratum), for the coordinated bootstrap / jackknife.}
#'   \item{region, sexo, edad}{covariates usable as estimation domains.}
#'   \item{ola}{wave (month) index.}
#'   \item{grupo_rotacion, mes_en_muestra}{rotation group and order-in-sample.}
#'   \item{w_base}{design (base) weight.}
#'   \item{disp}{between-wave disposition: `"R"`, `"NR"`, `"OS"`, `"UNK"`.}
#'   \item{condicion}{labour status within the working-age population, a factor with levels
#'     `"emp"` / `"unemp"` / `"inact"`; `NA` for non-respondents. This is the `status`
#'     argument of [step_cre()] (the previous-wave composite auxiliary).}
#'   \item{ocupado, desocupado}{employed / unemployed indicators (labour force; `NA` if not
#'     `"R"` or not in the labour force).}
#'   \item{ingreso}{labour income (`NA` if not `"R"`).}
#' }
#'
#' @details
#' The datasets differ only in the rotation calendar (which waves each rotation group is in
#' sample), giving different overlap structures:
#' \describe{
#'   \item{`panel_puro`}{**Pure panel**, no rotation: every unit is followed across all 4
#'     waves; the sample shrinks only through attrition. Style of EU-SILC / SLID pure panels.}
#'   \item{`panel_cl`}{**Chile ENE, 2-2-2** (in-out-in): 3 waves, consecutive overlap ~1/2,
#'     and units that **return** (in sample in waves 1 and 3 but not 2). The real ENE has no
#'     public rotation group; `grupo_rotacion` is included for teaching, but the panel also
#'     links through the persistent ids alone.}
#'   \item{`panel_ine`}{**INE Uruguay ECH / StatCan LFS, 6-month rotation**: 6 groups in
#'     sample each wave, one sixth rotating out per wave, so consecutive overlap ~5/6.}
#'   \item{`panel_us`}{**US CPS, 4-8-4**: 3 waves, consecutive overlap ~3/4, with a cohort that
#'     leaves and **returns** after the 8-month gap.}
#' }
#'
#' @examples
#' # rotation structure of the 6-month panel
#' panel_design(panel_ine, unit = c("id_hogar", "nper"), wave = "ola",
#'              rotation_group = "grupo_rotacion", pattern = "6")
#' # coordinated change of the unemployment rate between two waves
#' t1 <- subset(panel_ine, ola == 1 & disp == "R")
#' t2 <- subset(panel_ine, ola == 2 & disp == "R")
#' wb <- wave_bootstrap(
#'   list(T1 = weighting_spec(t1, base_weights = w_base),
#'        T2 = weighting_spec(t2, base_weights = w_base)),
#'   replicates = 100, strata = "estrato", psu = "psu", seed = 1, progress = FALSE)
#' change_mean(wb, "desocupado")
#' @name panel_datasets
"panel_puro"

#' @rdname panel_datasets
#' @format NULL
"panel_cl"

#' @rdname panel_datasets
#' @format NULL
"panel_ine"

#' @rdname panel_datasets
#' @format NULL
"panel_us"
