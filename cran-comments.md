## Submission

This is a maintenance and documentation update to weightflow (version 1.3.0 is
currently on CRAN).

It adds domain-level fitting to two steps (`step_model_calibration()` and
`step_pseudoweight()` take `by`, fitting and calibrating one domain at a time),
a delete-a-group jackknife with a replicate budget
(`jackknife_weights(groups =, seed =, max_replicates =)`), balanced rounding on
a calibration design (`step_round(method = "balanced", formula =)`), two new
arguments to `step_cre()` (`n_groups`, `rescale_previous`), Student t confidence
intervals on the estimation entry points (`ci_type`, `df`) for designs with few
degrees of freedom, and the Monte Carlo error of the bootstrap standard errors
in `print()`.

It fixes one correctness bug: a `reference_sample()` kept its design weights in
positional order, so reordering or subsetting its rows misaligned the weights
silently. They now travel with the rows.

The rest of the release is an audit of the warnings and diagnostics across the
pseudo-weighting, panel, trimming and calibration steps: they now fire where
they were silent, stop firing on sound models, and state what a variance assumes
about the reference survey. In particular, a non-probability recipe is no longer
accepted in silence when it adjusts nothing, pseudo-weights twice, or is
exported to `survey` as if it had a sampling design. Values interpolated into
the HTML report are escaped. NEWS.md has the full list.

Five vignettes were rewritten, and vignette figures now ship as standalone
`.svg` files embedded as data URIs rather than as inline SVG, which did not
survive the HTML post-processing of the rendered articles.

## R CMD check results

0 errors | 0 warnings | 0 notes

A local run without network access reports one additional NOTE, "unable to
verify current time". It comes from the check being unable to reach a time
service to validate file timestamps, not from the package, and does not appear
when the check runs with network access.

## Examples

All examples run: there is no `\dontrun{}` or `\donttest{}` in the package. The
50 examples take about 5 seconds in total, the slowest one under a second.

## Note on the DOI

DESCRIPTION, README and inst/CITATION cite the article describing the package,
<doi:10.1177/18747655261484262> (Statistical Journal of the IAOS, advance
online publication, 2026-09-09). The DOI resolves correctly in a browser, but
the publisher (SAGE) returns HTTP 403 to automated requests, so a URL or DOI
checker may report it as unreachable. This is a false positive from the
publisher's bot protection, not a broken reference. The same note accompanied
the 1.3.0 submission.

## Note on spelling

A spell check may flag author surnames ('Sarndal', 'Feinberg', 'Stasny') and
standard survey-methodology terms; these are in inst/WORDLIST where appropriate
and are false positives otherwise.

## Test environments

* local: macOS (R release)
* win-builder: R release and R-devel

## Downstream dependencies

There are currently no downstream dependencies for this package.
