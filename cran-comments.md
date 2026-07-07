## R CMD check results

0 errors | 0 warnings | 0 notes

## Submission

This is a feature update (0.2.0) of an existing CRAN package (weightflow 0.1.0).
All changes are additive and backward-compatible: the previously published API
is unchanged, and existing code keeps working.

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
* Should the incoming check flag possibly misspelled words in DESCRIPTION:
  "Deville", "Rao" and "Sarndal" are author surnames in the cited references;
  "nonresponse" and "pipeable" are standard survey-methodology / R terms. All
  are intentional and spelled correctly.

## Downstream dependencies

There are no reverse dependencies.
