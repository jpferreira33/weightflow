# Preparing the sample: eligibility and response before weighting

> **Development version.** The `disposition` example column used
> throughout this article is in the development version of weightflow
> (GitHub) and not yet on CRAN; the same goes for the R-indicator line
> that [`summary()`](https://rdrr.io/r/base/summary.html) prints.
> Install with `remotes::install_github("jpferreira33/weightflow")`. The
> adjustment steps and the indicator columns (`unknown_elig`,
> `ineligible`, `hh_responded`, `responded`) are on CRAN and unchanged.

Weighting starts before any factor is computed: with a clean
classification of **what each sampled case is**. Every record drawn from
the frame has to be placed in one of a few mutually exclusive
dispositions, because each disposition is handled by a different
weighting adjustment (and some are not weighted at all). Getting this
classification right, and encoding it in the right columns, is what
makes the rest of the cascade correct. This article shows the standard
disposition tree, explains when each branch arises in practice, lists
the columns `weightflow` expects, and runs a full pipeline on the
bundled multistage sample.

The framework follows the survey-methodology standard: the eligibility
and response outcomes of Valliant, Dever and Kreuter (2018) and the
final-disposition categories of the AAPOR *Standard Definitions* (2016).

## The disposition tree

Every sampled case is first resolved for **eligibility**: it is either
of **known** eligibility (resolved) or of **unknown** eligibility (never
resolved). Known cases are in turn either **eligible** (in scope) or
**ineligible** (out of scope), and only the eligible cases are finally
split into **respondents** and **nonrespondents**. Each split is handled
by a different adjustment. The colours below are reused throughout
`weightflow`’s plots and reports.

![Survey disposition tree: sampled cases split into known and unknown
eligibility; known into eligible and ineligible; eligible into
respondents and
nonrespondents.](data:image/svg+xml;base64,PHN2ZyB2aWV3Qm94PSIwIDAgNzYwIDQ3MCIgd2lkdGg9IjEwMCUiIHN0eWxlPSJtYXgtd2lkdGg6NzYwcHg7IGZvbnQtZmFtaWx5OiBJbnRlciwgc3lzdGVtLXVpLCBzYW5zLXNlcmlmOyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiByb2xlPSJpbWciIGFyaWEtbGFiZWw9IlN1cnZleSBkaXNwb3NpdGlvbiB0cmVlLiI+CiAgPGcgc3Ryb2tlPSIjYzdjOWQ2IiBzdHJva2Utd2lkdGg9IjEuNiIgZmlsbD0ibm9uZSI+CiAgICA8cGF0aCBkPSJNMzgwIDcyIEwyMjAgMTQwIi8+CiAgICA8cGF0aCBkPSJNMzgwIDcyIEw1NjAgMTQwIi8+CiAgICA8cGF0aCBkPSJNMjIwIDE5MCBMMTUwIDI1MiIvPgogICAgPHBhdGggZD0iTTIyMCAxOTAgTDM0MCAyNTIiLz4KICAgIDxwYXRoIGQ9Ik0xNTAgMzAyIEw5NSAzNzIiLz4KICAgIDxwYXRoIGQ9Ik0xNTAgMzAyIEwyNTUgMzcyIi8+CiAgPC9nPgoKICA8cmVjdCB4PSIyOTAiIHk9IjI0IiB3aWR0aD0iMTgwIiBoZWlnaHQ9IjQ4IiByeD0iOSIgZmlsbD0iIzNkMzU4MCIvPgogIDx0ZXh0IHg9IjM4MCIgeT0iNDUiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZpbGw9IiNmZmYiIGZvbnQtc2l6ZT0iMTUiIGZvbnQtd2VpZ2h0PSI2MDAiPlNhbXBsZWQgY2FzZXM8L3RleHQ+CiAgPHRleHQgeD0iMzgwIiB5PSI2MiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZmlsbD0iI2Q3ZDNmMCIgZm9udC1zaXplPSIxMC41Ij5jYXJyeSB0aGUgZGVzaWduIGJhc2Ugd2VpZ2h0PC90ZXh0PgoKICA8cmVjdCB4PSIxMjUiIHk9IjE0MCIgd2lkdGg9IjE5MCIgaGVpZ2h0PSI1MCIgcng9IjkiIGZpbGw9IiM0ZjU3YTYiLz4KICA8dGV4dCB4PSIyMjAiIHk9IjE2MiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZmlsbD0iI2ZmZiIgZm9udC1zaXplPSIxNCIgZm9udC13ZWlnaHQ9IjYwMCI+S25vd24gZWxpZ2liaWxpdHk8L3RleHQ+CiAgPHRleHQgeD0iMjIwIiB5PSIxNzkiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZpbGw9IiNkY2Q5ZjQiIGZvbnQtc2l6ZT0iMTAuNSI+cmVzb2x2ZWQ8L3RleHQ+CgogIDxyZWN0IHg9IjQ2MCIgeT0iMTQwIiB3aWR0aD0iMjAwIiBoZWlnaHQ9IjUwIiByeD0iOSIgZmlsbD0iIzdhNmFkMCIvPgogIDx0ZXh0IHg9IjU2MCIgeT0iMTYyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmaWxsPSIjZmZmIiBmb250LXNpemU9IjE0IiBmb250LXdlaWdodD0iNjAwIj5Vbmtub3duIGVsaWdpYmlsaXR5PC90ZXh0PgogIDx0ZXh0IHg9IjU2MCIgeT0iMTc5IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmaWxsPSIjZWFlN2Y4IiBmb250LXNpemU9IjEwLjUiPm5ldmVyIHJlc29sdmVkPC90ZXh0PgoKICA8cmVjdCB4PSI3NSIgeT0iMjUyIiB3aWR0aD0iMTUwIiBoZWlnaHQ9IjUwIiByeD0iOSIgZmlsbD0iIzUzNGFiNyIvPgogIDx0ZXh0IHg9IjE1MCIgeT0iMjc0IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmaWxsPSIjZmZmIiBmb250LXNpemU9IjE0IiBmb250LXdlaWdodD0iNjAwIj5FbGlnaWJsZTwvdGV4dD4KICA8dGV4dCB4PSIxNTAiIHk9IjI5MSIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZmlsbD0iI2RjZDlmNCIgZm9udC1zaXplPSIxMC41Ij5pbiBzY29wZTwvdGV4dD4KCiAgPHJlY3QgeD0iMjYwIiB5PSIyNTIiIHdpZHRoPSIxNjAiIGhlaWdodD0iNTAiIHJ4PSI5IiBmaWxsPSIjOGE5MGEwIi8+CiAgPHRleHQgeD0iMzQwIiB5PSIyNzQiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZpbGw9IiNmZmYiIGZvbnQtc2l6ZT0iMTQiIGZvbnQtd2VpZ2h0PSI2MDAiPkluZWxpZ2libGU8L3RleHQ+CiAgPHRleHQgeD0iMzQwIiB5PSIyOTEiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZpbGw9IiNlZWYwZjQiIGZvbnQtc2l6ZT0iMTAuNSI+b3V0IG9mIHNjb3BlPC90ZXh0PgoKICA8cmVjdCB4PSIyNSIgeT0iMzcyIiB3aWR0aD0iMTQwIiBoZWlnaHQ9IjQ4IiByeD0iOSIgZmlsbD0iIzFkOWU3NSIvPgogIDx0ZXh0IHg9Ijk1IiB5PSIzOTMiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZpbGw9IiNmZmYiIGZvbnQtc2l6ZT0iMTMuNSIgZm9udC13ZWlnaHQ9IjYwMCI+UmVzcG9uZGVudDwvdGV4dD4KICA8dGV4dCB4PSI5NSIgeT0iNDA5IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmaWxsPSIjZGNmM2VhIiBmb250LXNpemU9IjEwLjUiPnByb3ZpZGVzIGRhdGE8L3RleHQ+CgogIDxyZWN0IHg9IjE3NSIgeT0iMzcyIiB3aWR0aD0iMTYwIiBoZWlnaHQ9IjQ4IiByeD0iOSIgZmlsbD0iI2NmN2EzMyIvPgogIDx0ZXh0IHg9IjI1NSIgeT0iMzkzIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmaWxsPSIjZmZmIiBmb250LXNpemU9IjEzLjUiIGZvbnQtd2VpZ2h0PSI2MDAiPk5vbnJlc3BvbmRlbnQ8L3RleHQ+CiAgPHRleHQgeD0iMjU1IiB5PSI0MDkiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZpbGw9IiNmN2U2ZDUiIGZvbnQtc2l6ZT0iMTAuNSI+bm8gZGF0YTwvdGV4dD4KCiAgPHRleHQgeD0iNTYwIiB5PSIyMTAiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZpbGw9IiM1MzRhYjciIGZvbnQtc2l6ZT0iMTEiIGZvbnQtd2VpZ2h0PSI2MDAiPnN0ZXBfdW5rbm93bl9lbGlnaWJpbGl0eSgpPC90ZXh0PgogIDx0ZXh0IHg9IjU2MCIgeT0iMjI1IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmaWxsPSIjNmI3MjgwIiBmb250LXNpemU9IjEwLjUiPndlaWdodCByZWRpc3RyaWJ1dGVkIHRvIHRoZSBrbm93biBjYXNlczwvdGV4dD4KCiAgPHRleHQgeD0iMzQwIiB5PSIzMjIiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZpbGw9IiM1MzRhYjciIGZvbnQtc2l6ZT0iMTEiIGZvbnQtd2VpZ2h0PSI2MDAiPnN0ZXBfZHJvcF9pbmVsaWdpYmxlKCk8L3RleHQ+CiAgPHRleHQgeD0iMzQwIiB5PSIzMzciIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZpbGw9IiM2YjcyODAiIGZvbnQtc2l6ZT0iMTAuNSI+d2VpZ2h0IHNldCB0byAwIChyZW1vdmVkKTwvdGV4dD4KCiAgPHRleHQgeD0iMTUwIiB5PSIzMzMiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZpbGw9IiM1MzRhYjciIGZvbnQtc2l6ZT0iMTEiIGZvbnQtd2VpZ2h0PSI2MDAiPnN0ZXBfc2VsZWN0X3dpdGhpbigpPC90ZXh0PgogIDx0ZXh0IHg9IjE1MCIgeT0iMzQ4IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmaWxsPSIjNmI3MjgwIiBmb250LXNpemU9IjEwLjUiPmlmIG9uZSBwZXJzb24gcGVyIGhvdXNlaG9sZDwvdGV4dD4KCiAgPHRleHQgeD0iOTUiIHk9IjQ0MCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZmlsbD0iIzZiNzI4MCIgZm9udC1zaXplPSIxMC41Ij5rZXB0IGFzIGlzPC90ZXh0PgogIDx0ZXh0IHg9IjI1NSIgeT0iNDQwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmaWxsPSIjNTM0YWI3IiBmb250LXNpemU9IjExIiBmb250LXdlaWdodD0iNjAwIj5zdGVwX25vbnJlc3BvbnNlKCk8L3RleHQ+CiAgPHRleHQgeD0iMjU1IiB5PSI0NTUiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZpbGw9IiM2YjcyODAiIGZvbnQtc2l6ZT0iMTAuNSI+cmVzcG9uZGVudHMgaW5mbGF0ZWQgdG8gcmVwcmVzZW50IHRoZW08L3RleHQ+Cjwvc3ZnPg==)

## What each branch means, and when it happens

**Ineligible (out of scope).** Resolved cases that do not belong to the
target population: a business or fax number in a survey of households, a
vacant or demolished dwelling, an address outside the geographic scope,
a person outside the age range. They are known with certainty not to be
part of $`U`$, so they get weight zero. Crucially they are *kept* in the
data until after the unknown adjustment, so they can absorb their share
of the unresolved cases first (see the ordering below).

**Unknown eligibility (unresolved).** Cases you cannot classify as
eligible or ineligible. Two situations feed this branch, and both belong
here:

- *No evidence of eligibility.* The case was worked but never resolved:
  a phone that never answers, a questionnaire returned undelivered, an
  address where no contact was ever made and no roster obtained.
- *Released but not worked.* Sample that was fielded but never
  attempted, because the target number of interviews was already
  reached, globally or for a specific domain (a region, an age group, a
  quota that closed early). There was no chance to observe whether these
  cases are in scope, so they too are of unknown eligibility. AAPOR
  treats released sample that is not worked as unknown eligibility; only
  sample that was never *released* is excluded from the base altogether.

Discarding the unknowns assumes they represent nobody; treating them all
as eligible overstates the population. The standard fix redistributes
their weight to the resolved cases within adjustment cells, so the
resolved units stand in for the unresolved share. The implicit
assumption is that the eligible fraction among the unknowns matches that
of the resolved cases in the cell (the “e” factor in AAPOR response-rate
formulas).

**Eligible.** In scope and resolved. These split into respondents and
nonrespondents.

**Respondent.** Provided usable data. The survey outcomes ($`y`$) are
observed only here. Respondents are kept and later inflated to also
represent the nonrespondents.

**Nonrespondent.** Eligible but no usable data: refusal, noncontact
after eligibility was established, break-off. Under the assumption that
response is ignorable given the auxiliaries used, respondents are
inflated to cover them
([`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md),
by weighting classes or a response-propensity model).

In a multistage household design the response branch happens twice:
first at the household level (was the household reached and a roster
obtained?), then at the person level (did the selected person respond?).
Between them sits
[`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md),
which restores the within-household selection probabilities when a
subsample of persons is chosen.

## Why there is unused and out-of-scope sample: sizing the design

These dispositions are not accidents; they are anticipated when the
sample is sized. You never field only the number of interviews you want,
because not every released case will be eligible and not every eligible
case will respond. Starting from a target number of completed interviews
$`n_C`$, the released sample is inflated by the expected eligibility and
response rates, plus a contingency cushion for a worse-than-expected
field:

``` math
n_{\text{released}} \;=\; \frac{n_C}{\widehat{E}\times\widehat{R}}\;(1+c),
```

where $`\widehat{E}`$ is the expected eligibility rate, $`\widehat{R}`$
the expected response rate, and $`c`$ a cushion (a design margin for the
pessimistic scenario, and to protect the sample sizes needed for each
domain or breakdown). Valliant, Dever and Kreuter (2018) develop this
sizing in detail.

Two consequences show up in the delivered dataset. Because
$`\widehat{E}<1`$, part of the released sample turns out **ineligible**.
Because the cushion and the per-domain targets are deliberately
generous, some released sample ends up **not worked** once the targets
are met, and that portion is **unknown eligibility**. Both are expected
products of the design, and both must be represented in the data so the
weighting can account for them, rather than silently dropped.

## What your input data needs

The starting point is a **disposition column**: the field outcome (the
“causal”) recorded for every case in the theoretical sample. This is
where the AAPOR final disposition of each unit lives (complete, refusal,
noncontact, ineligible, undelivered, not worked, and so on). Every case
in the released sample must have one, including the ineligible, the
unresolved and the not-worked cases; they are part of the sample and
cannot be missing rows. From that single column you derive the 0/1 flags
each step reads.

`weightflow` never guesses dispositions; you encode them as columns and
point each step at the relevant one. For the disposition stages the
recipe expects:

| Disposition column | Type | Used by |
|----|----|----|
| disposition / reason | code or factor (source of the flags) | you, to build the flags below |
| design base weight | numeric, \> 0 | `weighting_spec(base_weights = )` |
| unknown eligibility | 0/1 flag (1 = unresolved or not worked) | `step_unknown_eligibility(unknown = )` |
| ineligible | 0/1 flag (1 = out of scope) | `step_drop_ineligible(ineligible = )` |
| within-household prob. | numeric in (0, 1\] | `step_select_within(prob = )` |
| respondent | 0/1 flag (1 = responded) | `step_nonresponse(respondent = )` |

Deriving the flags from the disposition code is a direct recode, for
example:

``` r

dat$unknown_elig <- as.integer(dat$disposition %in%
                                 c("noncontact", "undelivered", "not_worked"))
dat$ineligible   <- as.integer(dat$disposition %in%
                                 c("out_of_scope", "vacant", "business"))
dat$responded    <- as.integer(dat$disposition == "complete")
```

Two conventions matter. First, the flags are 0/1 indicators (or an
unquoted logical condition), so a case that is neither unknown nor
ineligible is treated as resolved and eligible. Second, the survey
outcomes are `NA` for nonrespondents; that is expected, because the
nonresponse step drops them from the active set before any outcome is
used.

Adjustment cells (`by =`) and, for roster-less cases, the household id
(`cluster =`) are the other inputs: the unknown and nonresponse
adjustments are computed within these cells.

## Order of operations

The sequence is not interchangeable, and it follows directly from the
tree:

1.  **Unknown eligibility first**, while ineligibles are still present,
    so the unresolved weight is spread over *all* resolved cases
    (eligible and ineligible), not only the eligible ones.
    Redistributing only to eligibles would overstate the population.
2.  **Drop ineligibles next**: once they have absorbed their share of
    the unresolved weight, the out-of-scope units are removed (weight
    zero).
3.  **Within-household selection**, to undo the subsampling of persons.
4.  **Nonresponse last**, inflating respondents to represent
    nonrespondents among the eligible, resolved cases.
5.  Calibration then aligns the eligible respondents with external
    population totals (covered in the calibration articles).

## A full pipeline on the multistage sample

`sample_one` is a multistage select-one design that carries every
disposition: unknown-eligibility and ineligible addresses arrive as
single rows with no roster; resolved eligible households are either
reached or are household nonresponse; in reached households one person
is selected and may or may not respond.

``` r

dat <- sample_one

# the whole field disposition in a single column, matching the tree above
table(disposition = dat$disposition)
#> disposition
#>    eligible respondent eligible nonrespondent  household nonresponse 
#>                    209                    106                     50 
#>             ineligible    unknown eligibility 
#>                     29                     23
```

`sample_one` ships the dispositions in two equivalent forms: the
ready-made 0/1 indicator columns (`unknown_elig`, `ineligible`,
`responded`, `hh_responded`) and the single `disposition` factor they
were recoded from. Every step accepts either a 0/1 column or an unquoted
logical condition, so you can point a step at the indicator column or
write the condition on `disposition` directly; the two give the same
flag.

``` r

# the indicator column and the equivalent condition on `disposition` agree
identical(dat$ineligible == 1L, dat$disposition == "ineligible")
#> [1] TRUE

# so these two calls are interchangeable:
#   step_drop_ineligible(ineligible = ineligible)
#   step_drop_ineligible(ineligible = disposition == "ineligible")
```

We add an age grouping for the person-level nonresponse cells, then run
the disposition stages in order, pointing each step at a condition on
the `disposition` column, the single field-outcome variable the sample
carries.

``` r

dat$age_grp <- cut(dat$age, c(0, 30, 45, 60, Inf),
                   labels = c("18-30", "31-45", "46-60", "60+"))

fitted <- weighting_spec(dat, base_weights = pw) |>
  # 1. unresolved cases: redistribute their weight within region (no roster,
  #    so at the household level via cluster)
  step_unknown_eligibility(unknown = disposition == "unknown eligibility",
                           by = "region", cluster = "household_id") |>
  # 2. out-of-scope cases: remove after they absorbed the unknown share
  step_drop_ineligible(ineligible = disposition == "ineligible") |>
  # 3. household nonresponse: reached households vs not, within region
  #    (whole-household outcome, so at the household level via cluster)
  step_nonresponse(respondent = disposition != "household nonresponse",
                   method = "weighting_class", by = "region",
                   cluster = "household_id") |>
  # 4. within-household selection of one person
  step_select_within(prob = p_within) |>
  # 5. person nonresponse, within demographic cells
  step_nonresponse(respondent = disposition == "eligible respondent",
                   method = "weighting_class", by = c("region", "sex", "age_grp")) |>
  prep()

fitted
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 417 cases
#> Base wts: pw
#> Steps   :
#>   1. unknown eligibility (by household_id)
#>   2. drop ineligible
#>   3. nonresponse (weighting class, by household_id)
#>   4. within-household selection
#>   5. nonresponse (weighting class)
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                             stage n_active sum_wts cv_wts deff_kish n_eff
#>                              base      417    2182  0.238     1.057   395
#>  stage_1_step_unknown_eligibility      394    2182  0.234     1.055   374
#>      stage_2_step_drop_ineligible      365    2023  0.232     1.054   346
#>          stage_3_step_nonresponse      315    2023  0.197     1.039   303
#>        stage_4_step_select_within      315    4611  0.678     1.460   216
#>          stage_5_step_nonresponse      209    4611  0.714     1.510   138
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
```

The stage summary shows how the active sample and the weight total
change as each disposition is handled: unresolved weight is moved onto
resolved cases, ineligibles drop out, and respondents are inflated to
carry the nonrespondents.

``` r

summary(fitted)
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 417 cases
#> Base wts: pw
#> Steps   :
#>   1. unknown eligibility (by household_id)
#>   2. drop ineligible
#>   3. nonresponse (weighting class, by household_id)
#>   4. within-household selection
#>   5. nonresponse (weighting class)
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                             stage n_active sum_wts cv_wts deff_kish n_eff
#>                              base      417    2182  0.238     1.057   395
#>  stage_1_step_unknown_eligibility      394    2182  0.234     1.055   374
#>      stage_2_step_drop_ineligible      365    2023  0.232     1.054   346
#>          stage_3_step_nonresponse      315    2023  0.197     1.039   303
#>        stage_4_step_select_within      315    4611  0.678     1.460   216
#>          stage_5_step_nonresponse      209    4611  0.714     1.510   138
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
#> --- Step 1: unknown eligibility (by household_id) ---
#>   cell     level n_known n_unknown   factor
#>   East household      56         7 1.125000
#>  North household     127         8 1.062992
#>  South household      97         2 1.020619
#>   West household     114         6 1.052632
#> Kish deff: 1.057 -> 1.055   |   n_eff: 395 -> 374
#> 
#> --- Step 2: drop ineligible ---
#>  n_dropped weight_dropped n_remaining
#>         29         159.22         365
#> Kish deff: 1.055 -> 1.054   |   n_eff: 374 -> 346
#> 
#> --- Step 3: nonresponse (weighting class, by household_id) ---
#>   cell n_resp_hh n_nr_hh   factor
#>  North       105      11 1.104762
#>  South        79      13 1.164557
#>   East        46       8 1.173913
#>   West        85      18 1.211765
#> Kish deff: 1.054 -> 1.039   |   n_eff: 346 -> 303
#> 
#> --- Step 4: within-household selection ---
#>   using mean_factor min_factor max_factor
#>  1/prob        2.26          1      9.052
#> Kish deff: 1.039 -> 1.460   |   n_eff: 303 -> 216
#> 
#> --- Step 5: nonresponse (weighting class) ---
#>               cell n_respondents n_nonresponse   factor
#>   East | F | 18-30             2             6 4.824394
#>   East | F | 31-45             5             0 1.000000
#>   East | F | 46-60             9             0 1.000000
#>     East | F | 60+             2             1 2.006549
#>   East | M | 18-30             2             2 3.308144
#>   East | M | 31-45             2             3 2.279092
#>   East | M | 46-60             6             1 1.167901
#>     East | M | 60+             4             1 1.114621
#>  North | F | 18-30             7             2 1.219400
#>  North | F | 31-45            12             7 1.436311
#>  North | F | 46-60            12             6 1.524781
#>    North | F | 60+             5             1 1.076659
#>  North | M | 18-30            12             4 1.253068
#>  North | M | 31-45             8             6 1.900951
#>  North | M | 46-60            10             4 1.230544
#>    North | M | 60+             9             0 1.000000
#>  South | F | 18-30             4             3 1.447426
#>  South | F | 31-45             4             4 2.076124
#>  South | F | 46-60             7             6 1.823142
#>    South | F | 60+             4             9 2.808928
#>  South | M | 18-30             4             4 1.848702
#>  South | M | 31-45             9             4 1.444650
#>  South | M | 46-60            12             3 1.360523
#>    South | M | 60+             2             0 1.000000
#>   West | F | 18-30             5             3 2.847808
#>   West | F | 31-45            14             7 1.547330
#>   West | F | 46-60             4             3 1.965820
#>     West | F | 60+             9             4 1.245591
#>   West | M | 18-30             5             5 2.197804
#>   West | M | 31-45            12             2 1.192805
#>   West | M | 46-60             3             3 2.005306
#>     West | M | 60+             4             2 1.499946
#> Kish deff: 1.460 -> 1.510   |   n_eff: 216 -> 138
#> 
#> R-indicator (representativity of response): 0.802  (on region, sex, age_grp)
```

### The same recipe with the ready-made indicator columns

`sample_one` also ships the dispositions as 0/1 indicator columns
(`unknown_elig`, `ineligible`, `hh_responded`, `responded`), and every
step accepts either form. Pointing the steps at those columns is exactly
equivalent, and it is the style the other articles use, so the recipes
there look like this:

``` r

fitted2 <- weighting_spec(dat, base_weights = pw) |>
  step_unknown_eligibility(unknown = unknown_elig, by = "region",
                           cluster = "household_id") |>
  step_drop_ineligible(ineligible = ineligible) |>
  step_nonresponse(respondent = hh_responded, method = "weighting_class",
                   by = "region", cluster = "household_id") |>
  step_select_within(prob = p_within) |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = c("region", "sex", "age_grp")) |>
  prep()

# same weights as the disposition-based version
all.equal(fitted$final_weight, fitted2$final_weight)
#> [1] TRUE
```

From here the recipe would continue with calibration and, optionally,
trimming; those stages are covered in the calibration and
getting-started articles. The point of this article is upstream of them:
if the dispositions are classified and encoded correctly, every later
factor is applied to the right set of cases.

## References

Valliant, R., Dever, J. A., & Kreuter, F. (2018). *Practical Tools for
Designing and Weighting Survey Samples* (2nd ed.). Springer. Chapters on
nonresponse and unknown-eligibility adjustments and weighting classes.

The American Association for Public Opinion Research (2016). *Standard
Definitions: Final Dispositions of Case Codes and Outcome Rates for
Surveys* (9th ed.). AAPOR. Definitions of eligible, ineligible and
unknown-eligibility cases, and the treatment of released-but-not-worked
sample as unknown eligibility.

Kish, L. (1965). *Survey Sampling.* Wiley. Within-household selection
and the design effect of unequal weights.

Särndal, C.-E., Swensson, B., & Wretman, J. (1992). *Model Assisted
Survey Sampling.* Springer. Design-based nonresponse and calibration
adjustments.
