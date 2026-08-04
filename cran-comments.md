## Submission

This is an update to weightflow (0.2.0 is currently on CRAN, published
2026-07-22).

It is the 1.0.0 milestone: the package is now feature-complete for its intended
scope (the full weighting cascade, machine-learning response propensities,
range-restricted / trimmed calibration, recipe-aware bootstrap and jackknife
variance, and the self-contained HTML quality report). I brought this milestone
forward so that a version reference in upcoming teaching material and
documentation points to a stable, feature-complete release. From here on updates
will be infrequent and limited to bug fixes and minor improvements, in line with
the CRAN policy on release frequency. I apologise for the short interval since
0.2.0 and am happy to wait if you would prefer.

## R CMD check results

0 errors | 0 warnings | 0-1 note.

* Any "checking for future file timestamps ... unable to verify current time"
  NOTE is transient: it appears only when the check machine cannot reach the
  online time server, and is unrelated to the package.
* Any "possibly misspelled words in DESCRIPTION" (e.g. 'Ferreira',
  'Nonresponse') are false positives: an author surname and a standard
  survey-methodology term.
* Any "invalid URL" message for github.com is a transient network timeout on the
  check machine; the repository is public and the URLs resolve.

## Test environments

* local: macOS, R release
* win-builder: R release and R-devel

## Downstream dependencies

There are currently no downstream dependencies for this package.
