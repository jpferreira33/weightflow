# Read a weighting recipe from a YAML file

Reads a recipe written by
[`write_recipe()`](https://jpferreira33.github.io/weightflow/reference/write_recipe.md).
With `data = NULL` (the default) it returns an inspectable recipe
manifest (for review or archival); pass `data` to reconstruct an
executable `weighting_spec` bound to that data, ready for
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md).

## Usage

``` r
read_recipe(file, data = NULL, references = NULL, allow_code = FALSE)
```

## Arguments

- file:

  path to the recipe `.yml`/`.yaml` file.

- data:

  optional data frame. When supplied, the recipe is rebuilt into a
  `weighting_spec` on this data. The columns the steps reference
  (weights, auxiliaries, disposition flags) must exist in `data`.

- references:

  optional named list, named by the id of the step that needs each
  object, restoring what the recipe stores only as a descriptor because
  it is microdata rather than metadata: a
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
  for a step that calibrates or pseudo-weights against a reference, and
  the `population` data frame of
  [`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
  /
  [`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md).

- allow_code:

  single logical, the gate on **every** executable thing a recipe file
  can carry: the conditions and formulas it stores as text, and a step
  that stores an R function as source. With `FALSE` (the default) a
  stored expression is accepted only if every call in it is on a fixed
  whitelist of data-manipulation functions (comparisons, arithmetic,
  [`is.na()`](https://rdrr.io/r/base/NA.html),
  [`factor()`](https://rdrr.io/r/base/factor.html),
  [`cut()`](https://rdrr.io/r/base/cut.html), string and `apply`-free
  helpers), and a function node is refused outright. That matters
  because a recipe is meant to be exchanged between organizations: an
  expression like `{ system("...") ; responded }` runs at the first
  [`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md),
  not at read time. Set `TRUE` only for a file you trust, exactly as you
  would [`source()`](https://rdrr.io/r/base/source.html) it.

## Value

With `data = NULL`, a `weightflow_recipe` manifest (a list with a print
method). With `data`, a `weighting_spec`.

## Details

A reconstructed recipe is validated only when you call
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md):
a hand-edited recipe with an out-of-range or mistyped value surfaces its
error there, not at `read_recipe()` time. And because reading a recipe
evaluates the stored expressions, only read recipes you trust, as you
would [`source()`](https://rdrr.io/r/base/source.html) an R script.

## See also

[`write_recipe()`](https://jpferreira33.github.io/weightflow/reference/write_recipe.md)

Other recipe serialization:
[`write_recipe()`](https://jpferreira33.github.io/weightflow/reference/write_recipe.md)

## Examples

``` r
spec <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region")
f <- tempfile(fileext = ".yml"); write_recipe(spec, f)
read_recipe(f)                       # inspect the manifest
#> weightflow recipe (written by version 1.3.1, 2026-09-28T18:27:26Z)
#>   base weights: pw
#>   1 step(s):
#>     - nonresponse    nonresponse_1
#>   Pass `data =` to read_recipe() to rebuild an executable recipe.
spec2 <- read_recipe(f, data = sample_survey)   # rebuild an executable recipe
```
