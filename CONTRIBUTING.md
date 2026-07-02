# Contributing to weightflow

Thank you for your interest in contributing to weightflow. Contributions
of all kinds are welcome: bug reports, feature requests, documentation
improvements, and code.

## Reporting bugs and requesting features

Please use the [GitHub issue
tracker](https://github.com/jpferreira33/weightflow/issues).

- For a **bug report**, include a minimal reproducible example (a
  `reprex`), the output of
  [`sessionInfo()`](https://rdrr.io/r/utils/sessionInfo.html), and a
  description of what you expected versus what happened.
- For a **feature request**, describe the use case and, if possible, how
  it fits the staged weighting workflow (which adjustment step it
  belongs to).

## Contributing code

1.  Fork the repository and create a branch for your change.
2.  Follow the existing code style. Each adjustment is a `step_*()`
    constructor (which only records the specification) plus an
    `apply_step()` S3 method (which performs the computation at
    [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
    time); new steps should follow the same pattern.
3.  Add tests under `tests/testthat/` for any new behaviour, and make
    sure `R CMD check` passes with no errors, warnings, or notes.
4.  Update the documentation (roxygen blocks and, where relevant, a
    vignette).
5.  Open a pull request describing the change and the motivation.

## Getting help

If you have questions about using the package, please open an issue with
the “question” label, or start a discussion on the repository. General
usage is documented in the package vignettes and at
<https://jpferreira33.github.io/weightflow/>.

## Code of conduct

Please note that this project is released with a contributor code of
conduct based on mutual respect and constructive collaboration. By
participating in this project you agree to abide by its terms.
