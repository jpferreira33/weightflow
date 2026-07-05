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
# \donttest{
if (requireNamespace("srvyr", quietly = TRUE) &&
    requireNamespace("dplyr", quietly = TRUE)) {
  srvyr::as_survey_rep(df, weights = .weight,
                       repweights = dplyr::starts_with("rep_"),
                       type = "bootstrap", combined.weights = TRUE,
                       scale = 1 / attr(df, "R"), rscales = 1, mse = TRUE)
}
#> Call: Called via srvyr
#> Survey bootstrap with 30 replicates and MSE variances.
#> Sampling variables:
#>   - repweights: `rep_1 + rep_2 + rep_3 + rep_4 + rep_5 + rep_6 + rep_7 + rep_8
#>     + rep_9 + rep_10 + rep_11 + rep_12 + rep_13 + rep_14 + rep_15 + rep_16 +
#>     rep_17 + rep_18 + rep_19 + rep_20 + rep_21 + rep_22 + rep_23 + rep_24 +
#>     rep_25 + rep_26 + rep_27 + rep_28 + rep_29 + rep_30` 
#>   - weights: .weight 
#> Data variables: 
#>   - person_id (int), household_id (int), psu (int), region (fct), sex (fct),
#>     age (dbl), pw (dbl), unknown_elig (int), responded (dbl), income (dbl),
#>     employed (int), .weight (dbl), rep_1 (dbl), rep_2 (dbl), rep_3 (dbl), rep_4
#>     (dbl), rep_5 (dbl), rep_6 (dbl), rep_7 (dbl), rep_8 (dbl), rep_9 (dbl),
#>     rep_10 (dbl), rep_11 (dbl), rep_12 (dbl), rep_13 (dbl), rep_14 (dbl),
#>     rep_15 (dbl), rep_16 (dbl), rep_17 (dbl), rep_18 (dbl), rep_19 (dbl),
#>     rep_20 (dbl), rep_21 (dbl), rep_22 (dbl), rep_23 (dbl), rep_24 (dbl),
#>     rep_25 (dbl), rep_26 (dbl), rep_27 (dbl), rep_28 (dbl), rep_29 (dbl),
#>     rep_30 (dbl)
# }
```
