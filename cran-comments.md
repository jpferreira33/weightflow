## Submission

This is a maintenance and feature update to weightflow (version 1.1.0).

Since the previous release it adds a diagnostics report suite, honest
recipe-aware variance for machine-learning adjustments, jackknife export in
`collect_replicate_weights()`, and per-subgroup trimming; it also fixes a large
batch of edge-case bugs (bad inputs now error instead of corrupting silently,
honest replicate variance and calibration totals, consistent handling of
negative calibration weights) and reworks the help pages (every function's title
and description, estimator formulas in `@details`, and two new documented
methods). NEWS.md has the full list.

## R CMD check results

0 errors | 0 warnings | 0 notes.

Checked clean locally and on win-builder (R release and R-devel).

* If a spell check flags an author surname (e.g. 'Sarndal') or a standard
  survey-methodology term in DESCRIPTION, these are false positives.

## Test environments

* local: macOS, R release
* win-builder: R release and R-devel (R Under development)

## Downstream dependencies

There are currently no downstream dependencies for this package.
