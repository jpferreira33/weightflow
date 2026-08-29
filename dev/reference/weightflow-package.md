# weightflow: declarative survey weighting

Builds analysis weights from design base weights by declaring the
weighting process as an ordered recipe of explicit adjustments – unknown
eligibility, within-cluster selection (e.g. within household),
nonresponse, calibration, trimming, rounding, rescaling, assertions –
and then estimating that recipe in one call. The package also produces
replicate weights and design-based standard errors that carry the
variability of the whole cascade, so a weighting project no longer has
to end at the weights.

## Details

Start with
[`weighting_spec()`](https://jpferreira33.github.io/weightflow/dev/reference/weighting_spec.md),
add `step_*()` adjustments, estimate the cascade with
[`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md),
and extract the weights with
[`collect_weights()`](https://jpferreira33.github.io/weightflow/dev/reference/collect_weights.md).
Inspect with [`summary()`](https://rdrr.io/r/base/summary.html),
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) and
[`report_weighting()`](https://jpferreira33.github.io/weightflow/dev/reference/report_weighting.md).

## See also

Useful links:

- <https://github.com/jpferreira33/weightflow>

- <https://jpferreira33.github.io/weightflow/>

- Report bugs at <https://github.com/jpferreira33/weightflow/issues>

## Author

**Maintainer**: Juan Pablo Ferreira <juanpablo.ferreira@fcea.edu.uy>
([ORCID](https://orcid.org/0000-0002-1884-8187)) \[copyright holder\]

Authors:

- Juan Pablo Ferreira <juanpablo.ferreira@fcea.edu.uy>
  ([ORCID](https://orcid.org/0000-0002-1884-8187)) \[copyright holder\]

- Andrés Gutiérrez ([ORCID](https://orcid.org/0009-0007-2918-1932))
