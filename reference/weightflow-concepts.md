# Conventions shared by every weightflow step

Five things behave the same way in all twelve `step_*()` functions and
are easier to learn once than twelve times: what the *active set* is and
how a unit leaves it, why the order of the cascade is not arbitrary, the
three different scales on which weight bounds are expressed, which
arguments take a bare column name and which take a string, and how to
read the diagnostics that
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
stores.

## Details

**The active set.** A unit is *active* when its weight is finite and
non-zero (`is.finite(w) & w != 0`). A weight of exactly `0` is the
"dropped" marker:
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md)
sets out-of-scope units to zero, an empty adjustment cell collapses to
zero, and a unit that leaves the active set takes no part in any later
step and is not returned by
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md).
A *negative* weight, by contrast, is a valid (if unusual) output of
unbounded linear/GREG calibration and stays active: it is counted by
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md),
the stage funnel and
[`design_effect()`](https://jpferreira33.github.io/weightflow/reference/design_effect.md),
so the reported totals match the weights actually returned. (One caveat:
the Kish design effect assumes non-negative weights, so with negatives
present its value is inflated – see
[`design_effect()`](https://jpferreira33.github.io/weightflow/reference/design_effect.md).)

**Why the order is not arbitrary.** Each step multiplies the *current*
weight, i.e. the weight leaving the previous step, so the cascade is
read top to bottom. The methodological order of a household survey is:
resolve unknown eligibility
([`step_unknown_eligibility()`](https://jpferreira33.github.io/weightflow/reference/step_unknown_eligibility.md))
while the ineligible units are still present, then drop the ineligible
([`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md)),
undo any within-cluster subsampling
([`step_select_within()`](https://jpferreira33.github.io/weightflow/reference/step_select_within.md)),
adjust for nonresponse
([`step_nonresponse()`](https://jpferreira33.github.io/weightflow/reference/step_nonresponse.md)),
calibrate to population totals
([`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)),
and finally trim, round or rescale for delivery. Putting calibration
before a trim, or a trim before the nonresponse adjustment, changes the
estimator, which is why the steps are explicit rather than inferred.

**Three scales for weight bounds.** Bounds are expressed on three
different scales, and mixing them up is the most common mistake for
users coming from `survey`:

- [`step_trim()`](https://jpferreira33.github.io/weightflow/reference/step_trim.md)
  `max_ratio` / `min_ratio` are a **ratio** to a reference (each unit's
  base weight, the group median, or an absolute value): `max_ratio = 3`
  caps a weight at three times its reference.

- [`step_trim_weights()`](https://jpferreira33.github.io/weightflow/reference/step_trim_weights.md)
  and
  [`step_trim_calibrated()`](https://jpferreira33.github.io/weightflow/reference/step_trim_calibrated.md)
  `lower` / `upper` are **absolute weights**: `upper = 400` caps the
  weight itself at 400.

- [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  `bounds = c(L, U)` bound the calibration **g-factor** `w_new / d` (the
  multiplicative adjustment), not the weight.

**Bare column name vs string.** Arguments that name a single variable to
be *evaluated on the data* take an unquoted (bare) column name or
condition: `base_weights` in
[`weighting_spec()`](https://jpferreira33.github.io/weightflow/reference/weighting_spec.md),
and `respondent`, `unknown`, `ineligible`, `prob`, `n_eligible`,
`n_selected` in the steps. Arguments that name *grouping or design
structure* take character strings: `by`, `cluster`, and `strata` / `psu`
in the variance functions. So it is
`step_nonresponse(respondent = responded, by = "region")` – `responded`
bare, `"region"` quoted.

**Reading the diagnostics.**
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
returns an object that carries the weight at every stage (`$history`, a
named list of vectors), one entry per step (`$steps`, each with its own
`$diagnostics` table and `$alerts`), and the recipe-level `$alerts`.
Rather than read those directly, use
[`summary()`](https://rdrr.io/r/base/summary.html) for the
stage-by-stage audit,
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) for the visual
cascade,
[`weight_factors()`](https://jpferreira33.github.io/weightflow/reference/weight_factors.md)
for the per-unit factor table,
[`design_effect()`](https://jpferreira33.github.io/weightflow/reference/design_effect.md)
for the Kish design effect, and
[`report_weighting()`](https://jpferreira33.github.io/weightflow/reference/report_weighting.md)
for the full self-contained HTML report.
