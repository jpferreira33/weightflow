## Submission

This is a feature update to weightflow (version 1.3.0).

The main addition is support for rotating and pure panels: the panel structure
layer (`panel_design()`, `panel_merge()`, `panel_pr()`,
`step_panel_overlap()`), attrition and longitudinal weights, gross flows
(`transition_matrix()`, `boot_flows()`), composite regression estimation
(`step_cre()`), and a variance layer that coordinates the replicate draws
across waves (`wave_bootstrap()`, `wave_jackknife()`, `wave_step()`,
`change_estimate()`) so that the sample overlap enters the variance of a net
change as covariance. It also adds a declarative estimation grammar
(`step_domain()`, `step_estimate()`, `collect_estimates()`) and a panel quality
report (`report_panel()`).

The release also fixes a correctness bug in the response-propensity models
(binomial GLM prior weights are the number of trials, so large design weights
could drive the fitted propensities to the boundary; model weights are now
normalized to mean 1, which leaves the estimates invariant). NEWS.md has the
full list.

All examples now run: there is no `\dontrun{}` or `\donttest{}` in the package.
The 50 examples take about 3 seconds in total.

## R CMD check results

0 errors | 0 warnings | 0 notes

## Note on the DOI

DESCRIPTION and README cite the article describing the package,
<doi:10.1177/18747655261484262> (Statistical Journal of the IAOS, advance
online publication, 2026-09-09). The DOI resolves correctly in a browser, but
the publisher (SAGE) returns HTTP 403 to automated requests, so a URL or DOI
checker may report it as unreachable. This is a false positive from the
publisher's bot protection, not a broken reference.

A spell check may also flag author surnames ('Sarndal', 'Feinberg', 'Stasny')
and standard survey-methodology terms; these are in inst/WORDLIST where
appropriate and are false positives otherwise.

## Test environments

* local: macOS (R release)
* win-builder: R release and R-devel

## Downstream dependencies

There are currently no downstream dependencies for this package.
