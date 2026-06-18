# Build a nice HTML report of the weighting recipe

Writes a self-contained HTML file (no dependencies, no server) showing
the pipeline, the parameters requested at each step, the per-stage
summary (n, sum, CV, Kish deff, effective n) and per-step diagnostics,
and opens it in the browser.

## Usage

``` r
report_weighting(object, file = NULL, open = TRUE, plots = TRUE)
```

## Arguments

- object:

  a prepped object (output of prep()).

- file:

  output path; if NULL, a temporary .html file.

- open:

  logical; open the file in the browser.

- plots:

  logical; add per-step plots (weight before-vs-after scatter and
  adjustment-factor histogram). Uses ggplot2 if installed, else base
  graphics.

## Value

(invisibly) the path to the HTML file.
