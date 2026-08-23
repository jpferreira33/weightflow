# weightflow roadmap (deferred work)

Internal notes, not shipped with the package (this folder is in `.Rbuildignore`).
Everything below was consciously left for a later release; the reasons are recorded
so nothing is lost.

## Vignettes to refresh next release

The vignettes exist in the repo; they only need narrative updates for the API
added in 1.1.0 / 1.2.0.

- `calibration.Rmd`, `calibration-totals.Rmd`, `model-calibration.Rmd`: add a
  pointer to `vignette("reference-survey")`. `model-calibration.Rmd` is the
  oldest file and should mention that the step now accepts `reference_sample()`.
- `nonresponse-propensities.Rmd`: link `collect_propensities()` and the new
  `vignette("inspecting-auditing")`.
- New vignette "weightflow in production": GSBPM framing, fixing seeds and a
  lockfile, versioning the recipe object, disseminating replicate weights
  (`collect_replicate_weights()` to CSV plus the attributes to keep), comparing
  waves, and which alerts should block a publication.
- Consolidation, not addition: `trimming.Rmd` and `advanced-methods.Rmd`
  duplicate Potter and Folsom-Singh; merge trimming into one and leave
  advanced-methods for ML and cross-fitting.
- Add the new features to the tour in `quickstart.Rmd` / `weightflow.Rmd`.

Done for 1.2.0: `inspecting-auditing.Rmd` (new), `reference-survey.Rmd` (new),
`variance-estimation.Rmd` (extended with FPC, df, `ci_type`), and the FPC / df
note plus QC pointer in `quality-report.Rmd`.

## Audit findings not yet fixed

- BUG-17 (medium): `bootstrap_weights()` without a seed reuses part of the RNG
  stream. With an explicit seed the handling is exact; niche.
- BUG-19 (medium): cross-fitting with rare factor levels raises the raw engine
  error instead of a weightflow message; niche.
- BUG-25 (minor): fixed arguments that clash with `...` in the survey bridges,
  dead code, typos, duplicate `.Rbuildignore` entries, and the DESCRIPTION vs
  CITATION authorship (CITATION lists one author, DESCRIPTION two: a decision to
  make before the SJIAOS paper is in production).
- CR-1 to CR-23: design behaviours, not bugs. The only one flagged as worth a
  warning was CR-2, which is now done.

## Design-doc features (proposed API for 1.3+)

- Priority A: structured alerts as a data frame (`weighting_alerts(as = "data.frame")`
  with a stable `type` enum and severity) plus `prep(on_alert = ...)`. The step
  `id` half is already shipped.
- Priority B: `check(spec)`, a dry run that validates the recipe without
  estimating (extract `.validate_step.<class>` from each `apply_step`).
- Priority D: `step_collapse_cells()`, collapse re-decided per replicate.
- Programmable API: accept a column-name string in the NSE arguments, plus
  `update_step(spec, id, ...)` (CR-12).
- q-weights in `step_calibrate()` (Deville-Sarndal cost weights); touches the
  core solver, left out of the low-risk batch.
- `logit` in `step_trim_calibrated()`: needs the solver to honour per-unit
  matrix bounds under the logit distance (reverted in 1.2.0 for that reason).
- Report: `report_weighting(compare = old_fit)` wave-to-wave diff (uses step
  ids); configurable `thresholds =` and an embedded JSON block.
- F-11: `by` (per-domain) calibration with a `reference_sample()` (currently
  errors "not supported yet").

## Administrative

- When the SJIAOS paper is online-first, update `inst/CITATION` from the arXiv
  reference to the SJIAOS DOI.
- The FPC / variance and step-id work is on the 1.2.0 branch; DESCRIPTION is at
  1.1.0.9000.
