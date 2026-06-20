# Collect replicate weights into a data frame ready for srvyr

Returns the data with the point weight and the bootstrap replicate
weights as columns, so it can be fed directly to
[`srvyr::as_survey_rep()`](http://gdfe.co/srvyr/reference/as_survey_rep.md)
(or
[`survey::svrepdesign()`](https://rdrr.io/pkg/survey/man/svrepdesign.html)).
Replicate columns are full weights, so use `combined.weights = TRUE`,
`scale = 1 / R`, `rscales = 1`, `mse = TRUE`.

## Usage

``` r
collect_replicate_weights(
  boot,
  weight_name = ".weight",
  prefix = "rep_",
  drop_zero = TRUE
)
```

## Arguments

- boot:

  a `weightflow_boot` object.

- weight_name:

  name of the point-weight column to add.

- prefix:

  prefix for the replicate-weight columns (`rep_1`, `rep_2`, ...).

- drop_zero:

  keep only active units (point weight \> 0).

## Value

A data frame: the original columns, `weight_name`, and one column per
replicate. The number of replicates is stored in attribute `"R"`.

## Examples

``` r
spec <- weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region))))
boot <- bootstrap_weights(spec, replicates = 30, strata = "region",
                          psu = "psu", seed = 1, progress = FALSE)
df <- collect_replicate_weights(boot)
if (FALSE) { # \dontrun{
srvyr::as_survey_rep(df, weights = .weight,
                     repweights = dplyr::starts_with("rep_"),
                     type = "bootstrap", combined.weights = TRUE,
                     scale = 1 / attr(df, "R"), rscales = 1, mse = TRUE)
} # }
```
