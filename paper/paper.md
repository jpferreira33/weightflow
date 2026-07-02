---
title: 'weightflow: A Declarative Pipeline for Survey Weighting in R'
tags:
  - R
  - survey statistics
  - survey weighting
  - calibration
  - nonresponse
  - official statistics
authors:
  - name: Juan Pablo Ferreira
    orcid: 0000-0002-1884-8187
    affiliation: "1, 2"
affiliations:
  - name: Instituto Nacional de Estadística (INE), Uruguay
    index: 1
  - name: Facultad de Ciencias Económicas y de Administración, Universidad de la República (UdelaR), Uruguay
    index: 2
date: 2 July 2026
bibliography: paper.bib
---

# Summary

Survey estimates of population quantities rely on weights that correct the
realized sample for departures from the ideal probability design. Building
these weights is a multi-step process: design (base) weights derived from the
inclusion probabilities are successively adjusted for unknown eligibility,
ineligible units, within-household selection, and nonresponse, and are then
calibrated to known population totals before optional trimming and rounding.
Each step trades bias reduction against variance inflation, and the order in
which the steps are applied matters.

`weightflow` expresses this whole process as a single, explicit, pipeable
recipe. Following the separation between specification and execution familiar
from the `recipes`/`tidymodels` ecosystem [@kuhn2022], a weighting recipe is
inert: building it computes nothing. A call to `prep()` walks the steps in
order and estimates the cascade of multiplicative adjustment factors, and
`collect_weights()` returns the final analysis weights. Because the recipe is a
declarative object, it can be read top to bottom, audited step by step, and
re-executed on demand, which is precisely what enables the package's
recipe-aware variance estimation: a rescaling bootstrap [@rao1988] that
resamples primary sampling units within strata and re-applies the entire
recipe on each replicate, so the resulting standard errors reflect both the
sampling design and every weighting adjustment. The replicate weights and the
final design object bridge directly to the `survey` [@lumley2010] and `srvyr`
packages for design-based inference.

The package covers the standard toolkit of official-statistics weighting:
weighting-class and response-propensity nonresponse adjustments, calibration
by raking, post-stratification and generalized regression (GREG) following
@deville1992, model-assisted (Wu-Sitter) calibration [@wu2001], integrated
household calibration that assigns a single weight per dwelling [@lemaitre1987],
and design-effect and effective-sample-size diagnostics [@kish1965]. Response
propensities and model-calibration outcomes can be fitted with logistic
regression, classification trees, random forests or gradient boosting, with
optional k-fold cross-fitting, and calibration can be ridge-penalised to keep
weights stable when many auxiliary margins are used. The methodological
framework follows @valliant2018. `weightflow` has no hard dependencies beyond
base R and ships with synthetic survey datasets so that the full pipeline and
the variance methods run out of the box.

# Statement of need

National statistical offices and survey researchers routinely build analysis
weights, but in practice this work often lives in long, fragmented scripts that
are hard to review, hard to reproduce, and hard to defend. Existing R tools
address parts of the problem well: `survey` and `srvyr` are the standard tools
for *analysing* already-weighted data and for calibration, and other packages
implement specific adjustments. What has been missing is a single, coherent
grammar that assembles the *entire* weighting cascade, from design weights
through eligibility, nonresponse, calibration, trimming and rounding, as one
auditable object, and that propagates the variability of every one of those
adjustments into the variance estimates.

`weightflow` fills that gap. Its declarative recipe mirrors the way weighting is
documented in official statistics methodology, where each adjustment must be
stated, justified, and reproducible; this aligns with the weighting workflow
described in international guidance such as the United Nations *Handbook of
Surveys on Individuals and Households*. By separating the specification of the
weighting plan from its execution, the package makes the plan itself the primary artefact: it can be
inspected before any computation, reused across survey waves, and re-run in full
on each bootstrap replicate. This last property is the package's main
methodological contribution in software form. Rather than requiring the analyst
to re-orchestrate nonresponse and calibration adjustments by hand on top of a
set of replicate weights, `weightflow` re-estimates the complete cascade
automatically on every replicate, so the reported standard errors carry the
variability of the sampling design and of each weighting step at once.

The package is documented with a set of vignettes covering the adjustment logic,
calibration, nonresponse modelling, model-assisted calibration, machine-learning
propensities with cross-fitting, variance estimation, and validation against the
`survey` package, together with a fully worked case study that weights real open
microdata from the Uruguayan continuous household survey (ECH) and validates the
resulting poverty-rate estimate against a known population value. `weightflow` is
available on CRAN, with development versions on GitHub.

# Acknowledgements

The author thanks the community of survey methodologists and national
statistical office colleagues whose feedback shaped the package.

# References
