## R CMD check results

0 errors | 0 warnings | 0 notes

## Submission

This is an update (0.3.0) of an existing CRAN package (weightflow 0.2.0). It adds
new features and fixes one bug:

* `step_nonresponse()` gains `method = "calibration"`, the calibration (two-phase)
  approach to nonresponse adjustment (Sarndal & Lundstrom 2005).
* `step_trim_weights()` gains a `redistribute` argument; the new `"uniform"`
  option reproduces `survey::trimWeights()` exactly.
* Bug fix: `step_trim_weights()` now trims negative weights (a lower floor
  previously left negative weights, which unbounded linear calibration can
  produce, untouched).

There are no changes to the published API; existing code runs unchanged (the
trimming default is `redistribute = "proportional"`, which preserves the previous
behaviour on non-negative weights).

## Test environments

* local macOS, R 4.5
* win-builder: R-devel and R-release
* GitHub Actions: ubuntu / macOS / windows (R-oldrel, R-release, R-devel)

## Notes

* All examples run. A few examples are wrapped in \donttest{} because they open a
  browser / write a report (`report_weighting`) or use a suggested package;
  none use \dontrun{}.
* All exported functions and methods document their return value with \value{}.
* Suggested packages (survey, srvyr, xgboost, ranger, rpart, ...) are only used
  conditionally, via requireNamespace() and testthat::skip_if_not_installed().
* Snapshot, scale and spelling tests are skipped on CRAN.
* A local `R CMD check` occasionally reports a NOTE "checking for future file
  timestamps ... unable to verify current time". This is environmental (the
  check machine could not reach the time server) and is unrelated to the
  package; it does not occur on CRAN.
* Should the incoming check flag possibly misspelled words in DESCRIPTION:
  "Deville", "Rao" and "Sarndal" are author surnames in the cited references;
  "nonresponse" and "pipeable" are standard survey-methodology / R terms. All
  are intentional and spelled correctly.

## Downstream dependencies

There are no reverse dependencies.
