# Read a weighting recipe from a YAML file

Reads a recipe written by
[`write_recipe()`](https://jpferreira33.github.io/weightflow/reference/write_recipe.md).
With `data = NULL` (the default) it returns an inspectable recipe
manifest (for review or archival); pass `data` to reconstruct an
executable `weighting_spec` bound to that data, ready for
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md).

## Usage

``` r
read_recipe(file, data = NULL, references = NULL)
```

## Arguments

- file:

  path to the recipe `.yml`/`.yaml` file.

- data:

  optional data frame. When supplied, the recipe is rebuilt into a
  `weighting_spec` on this data. The columns the steps reference
  (weights, auxiliaries, disposition flags) must exist in `data`.

- references:

  optional named list of
  [`reference_sample()`](https://jpferreira33.github.io/weightflow/reference/reference_sample.md)
  objects, named by the id of the step that uses each one, to restore
  the steps that calibrate or pseudo-weight against a reference (whose
  microdata the recipe does not store).

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
#> weightflow recipe (written by version 1.2.0, 2026-09-04T02:43:32Z)
#>   base weights: pw
#>   1 step(s):
#>     - nonresponse    nonresponse_1
#>   Pass `data =` to read_recipe() to rebuild an executable recipe.
spec2 <- read_recipe(f, data = sample_survey)   # rebuild an executable recipe
```
