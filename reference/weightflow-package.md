# weightflow: declarative survey weighting

Build survey weights from design base weights by chaining hierarchical
adjustments (unknown eligibility, nonresponse, trimming, calibration,
rounding, rescaling, assertions) through a declarative, pipeable,
tidymodels-style API. Computes weights only; for variance/inference,
export the weights and use them with the 'survey' package.

## Details

Start with
[`weighting_spec()`](https://jpferreira33.github.io/weightflow/reference/weighting_spec.md),
add `step_*()` adjustments, estimate the cascade with
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md),
and extract the weights with
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md).
Inspect with [`summary()`](https://rdrr.io/r/base/summary.html),
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) and
[`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md).

## Author

**Maintainer**: Your Name <you@example.com>

Authors:

- Your Name <you@example.com>
