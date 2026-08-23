# Print a bootstrap replicate-weight object

Compact one-screen summary of a `weightflow_boot` object: how many
replicates were requested, how many units are in the data, how many of
them are still active (final weight above zero), and which columns
defined the resampling design.

## Usage

``` r
# S3 method for class 'weightflow_boot'
print(x, ...)
```

## Arguments

- x:

  a `weightflow_boot` object.

- ...:

  ignored.

## Value

(invisibly) the object.
