## Submission

This is a maintenance and feature update to weightflow (version 1.1.0).

Since the previous release it adds a diagnostics report suite, honest
recipe-aware variance for machine-learning adjustments, jackknife export in
`collect_replicate_weights()`, per-subgroup trimming, and the accessors
`collect_propensities()`, `collect_step_detail()` and `domain_summary()` for
per-unit and per-domain inspection of the cascade; it also fixes a large
batch of edge-case bugs (bad inputs now error instead of corrupting silently,
honest replicate variance and calibration totals, consistent handling of
negative calibration weights) and reworks the help pages (every function's title
and description, estimator formulas in `@details`, and two new documented
methods). NEWS.md has the full list.

## R CMD check results

0 errors | 0 warnings | 1 note (environment-dependent).

Checked locally and on win-builder (R release and R-devel). One R-devel run
reported, under "checking HTML version of manual":

    Skipping checking math rendering: package 'V8' unavailable

This only reflects that the 'V8' package was not installed on that particular
check machine, so the optional math-rendering check of the help pages was
skipped; it is not a package issue and does not appear when 'V8' is present (an
earlier R-devel run on the same sources reported 0 notes).

* If a spell check flags an author surname (e.g. 'Sarndal') or a standard
  survey-methodology term in DESCRIPTION, these are false positives.

## Test environments

* local: macOS, R release
* win-builder: R release and R-devel (R Under development)

## Downstream dependencies

There are currently no downstream dependencies for this package.
