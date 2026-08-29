# Write a weighting recipe to a YAML file

Serializes the recipe (the weighting *method*, not the data) to a
human-readable YAML file: the base-weight column, the non-probability
flag, and every step's id, type and parameters. The file is a
versionable metadata artifact you can review in a pull request, archive
next to the quality report, or reference from a metadata system. Read it
back with
[`read_recipe()`](https://jpferreira33.github.io/weightflow/dev/reference/read_recipe.md).

## Usage

``` r
write_recipe(object, file, timestamp = TRUE)
```

## Arguments

- object:

  a `weighting_spec` (or a prepped one; only the recipe is written,
  never the weights or the data).

- file:

  path to the `.yml`/`.yaml` file to write.

- timestamp:

  whether to record the write time (UTC) in the file. Default `TRUE`;
  set `FALSE` for byte-identical output across writes of the same recipe
  (cleaner version-control diffs).

## Value

the `file` path, invisibly.

## Details

Formulas and captured column expressions are stored as text. A
[`reference_sample()`](https://jpferreira33.github.io/weightflow/dev/reference/reference_sample.md)
is stored as a descriptor only (its microdata is not metadata), so a
step that calibrates or pseudo-weights against a reference must be given
that reference again when the recipe is reconstructed. Small
control-totals tables (for example a tidy poststratification total) are
serialized in full; a data frame larger than 10,000 rows is treated as
microdata and rejected (route it through
[`reference_sample()`](https://jpferreira33.github.io/weightflow/dev/reference/reference_sample.md)).

A recipe is portable only if its captured expressions reference columns
of the data (for example `respondent = responded`). An expression that
referenced objects from your R session (say
`respondent = id %in% ids_resp`) is stored as text but cannot be
reconstructed elsewhere, and will error at
[`prep()`](https://jpferreira33.github.io/weightflow/dev/reference/prep.md).

## See also

[`read_recipe()`](https://jpferreira33.github.io/weightflow/dev/reference/read_recipe.md)

Other recipe serialization:
[`read_recipe()`](https://jpferreira33.github.io/weightflow/dev/reference/read_recipe.md)

## Examples

``` r
spec <- weighting_spec(sample_survey, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
f <- tempfile(fileext = ".yml")
write_recipe(spec, f)
```
