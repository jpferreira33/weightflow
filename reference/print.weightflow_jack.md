# Print a jackknife replicate-weight object

Compact one-screen summary of a `weightflow_jack` object: how many
delete-a-PSU replicates were built, how many units are in the data, how
many of them are still active (final weight above zero), and which
columns defined the deletion design.

## Usage

``` r
# S3 method for class 'weightflow_jack'
print(x, ...)
```

## Arguments

- x:

  a `weightflow_jack` object.

- ...:

  ignored.

## Value

(invisibly) the object.
