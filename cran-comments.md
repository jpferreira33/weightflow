## R CMD check results

0 errors | 0 warnings | 0 notes

## Submission

This is an update (0.2.0) of an existing CRAN package (weightflow 0.1.0). It adds
new features and fixes two bugs: `report_weighting()` now flags calibration
steps that did not converge, and `step_calibrate(equal_within_cluster = TRUE)`
now implements the standard Lemaitre-Dufour integrative method (one weight per
household). There are no changes to the published API; existing code runs
unchanged, though integrative-calibration weights differ from 0.1.0, as
documented in NEWS.

## Test environments

* local macOS, R 4.5
* win-builder: R-devel, R-release and R-oldrelease
* R-hub: linux, macos, macos-arm64, m1-san and windows (all R-devel)
* GitHub Actions: ubuntu / macOS / windows (R-oldrel, R-release, R-devel)

## Notes

* All examples run. Two examples are wrapped in \donttest{} because they open a
  browser / write a report (`report_weighting`) or use a suggested package
  (`collect_replicate_weights`); none use \dontrun{}.
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
