# Ways to specify calibration totals

> **Development version.** The tidy data-frame format described here is
> available in the development version of weightflow. The classic
> `margins`/`totals` inputs work in every version and are unchanged.

Calibration adjusts the weights so that the weighted sample reproduces
known population totals of auxiliary variables. In practice those totals
almost always arrive as a **table**: a census cross-tabulation, a
projection, a spreadsheet read into R.
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
accepts totals in two shapes:

- the **classic** shape, kept for backward compatibility (`margins` as a
  named list, or a `totals` vector aligned with the model matrix); and
- the **tidy** shape (recommended): a data frame with the category
  columns and a counts column, whose name you pass through `count`. Any
  column that is not the counts column is treated as a
  post-stratification variable.

This vignette shows both, side by side, for the three calibration
methods, so you can pick whichever matches the data you already have.

We use the bundled example data throughout.

``` r

data(population)
data(sample_survey)
```

## Post-stratification

Post-stratification calibrates to the **joint** distribution of one or
more categorical variables (the cells of their cross-classification).

### One variable

The tidy way: a data frame with the category column and a counts column.
Here we build the population counts with
[`table()`](https://rdrr.io/r/base/table.html) (its data-frame form has
a `Freq` column), then pass `count = "Freq"`.

``` r

region_totals <- as.data.frame(table(region = population$region))
region_totals
#>   region Freq
#> 1  North 1570
#> 2  South 1250
#> 3   East  927
#> 4   West  748

ps <- weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "poststratify", totals = region_totals, count = "Freq") |>
  prep()

sum(collect_weights(ps)$.weight)   # sums to the population size N
#> [1] 4495
```

The classic equivalent uses `margins`, a named list of named vectors:

``` r

ps_classic <- weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "poststratify",
                 margins = list(region = c(table(population$region)))) |>
  prep()

sum(collect_weights(ps_classic)$.weight)
#> [1] 4495
```

Both produce the same weights.

### Several variables crossed

This is where the tidy format helps most. If your table has **several**
category columns, weightflow crosses them automatically to form the
post-strata. You do **not** need to build a single collapsed cell
variable by hand.

``` r

rs_totals <- as.data.frame(table(region = population$region,
                                 sex    = population$sex))
head(rs_totals)
#>   region sex Freq
#> 1  North   F  825
#> 2  South   F  643
#> 3   East   F  467
#> 4   West   F  376
#> 5  North   M  745
#> 6  South   M  607

ps_cross <- weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "poststratify", totals = rs_totals, count = "Freq") |>
  prep()

sum(collect_weights(ps_cross)$.weight)
#> [1] 4495
```

If you had pre-combined the categories into a single column (for example
a `"North-F"` cell label), that is simply the one-column case above, so
it is handled by the same rule with no extra work.

## Raking

Raking calibrates to several **independent margins** (each variable
separately, iterated), which is what you use when you do not have the
full cross-tabulation, only the marginal totals. In the tidy format you
pass a **list** of data frames, one per margin.

``` r

m_region <- as.data.frame(table(region = population$region))
m_sex    <- as.data.frame(table(sex    = population$sex))

rk <- weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "raking",
                 totals = list(m_region, m_sex), count = "Freq") |>
  prep()

sum(collect_weights(rk)$.weight)
#> [1] 4495
```

The classic equivalent uses `margins`:

``` r

rk_classic <- weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "raking",
                 margins = list(region = c(table(population$region)),
                                sex    = c(table(population$sex)))) |>
  prep()

sum(collect_weights(rk_classic)$.weight)
#> [1] 4495
```

Because raking is iterative, weightflow warns you if the margins are
mutually inconsistent (they do not all sum to the same population size)
or if the iteration does not converge, rather than silently returning
weights that do not satisfy the margins.

## Linear / GREG calibration

Linear (GREG) calibration handles categorical **and** continuous
auxiliaries together, through a model formula.

### Why the totals are usually awkward

Linear calibration is built on
[`model.matrix()`](https://rdrr.io/r/stats/model.matrix.html), and
traditionally the totals must be supplied in exactly that internal
shape: a vector that includes the intercept (the population size $`N`$)
and, for each factor, drops one *reference* category absorbed into the
intercept, using treatment-contrast column names.

Knowing that a category is silently omitted, and reproducing the exact
model-matrix names, is a common source of mistakes. Providing totals
this way is the norm in established survey-calibration tools, and it is
precisely the part that trips people up.

``` r

# The classic model-matrix vector: intercept = N, and region *without* its
# reference level (the first, "North"), with model.matrix column names.
pop_tot <- c("(Intercept)" = nrow(population),
             regionSouth = sum(population$region == "South"),
             regionEast  = sum(population$region == "East"),
             regionWest  = sum(population$region == "West"),
             sexM        = sum(population$sex == "M"))

lin_classic <- weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "linear", formula = ~ region + sex, totals = pop_tot) |>
  prep()

sum(collect_weights(lin_classic)$.weight)
#> [1] 4495
```

### The tidy way

In the tidy format you give the **complete** categories (no reference
dropped) and a single number for each continuous total, as a named list
matching the formula terms. weightflow builds the model-matrix totals
internally, including the intercept and the omitted reference category,
so you never handle them.

``` r

lin_tidy <- weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "linear", formula = ~ region + sex,
                 totals = list(region = m_region, sex = m_sex),
                 count = "Freq") |>
  prep()

sum(collect_weights(lin_tidy)$.weight)
#> [1] 4495
```

This yields the same weights as the model-matrix vector above, but you
supplied the totals in the natural, complete form.

### Mixing categorical and continuous auxiliaries

For a continuous auxiliary, give its population total as a single
number. Here we add `income`; because `income` is observed only for
respondents in this example, we calibrate the respondent subsample.

``` r

resp <- subset(sample_survey, responded == 1)

lin_mixed <- weighting_spec(resp, base_weights = pw) |>
  step_calibrate(method = "linear", formula = ~ region + sex + income,
                 totals = list(region = m_region, sex = m_sex,
                               income = sum(population$income)),
                 count = "Freq") |>
  prep()

# the calibrated weights reproduce every target
X <- model.matrix(~ region + sex + income, data = resp)
colSums(collect_weights(lin_mixed)$.weight * X)
#> (Intercept) regionSouth  regionEast  regionWest        sexM      income 
#>        4495        1250         927         748        2184    86745007
```

Ridge (penalized) calibration works with the tidy format too: add
`penalty` as usual. Under ridge the achieved totals are deliberately not
exact, so weightflow reports the deviation instead of warning about it.

## Validation and messages

The tidy format is not only more convenient; it checks the totals
against the sample and explains problems in survey terms.

- **A cell in the sample with no population total is an error.** Every
  sampled unit belongs to the population, so every cell present in the
  sample must have a known total. weightflow stops and lists the
  offending cells.
- **A cell in the totals with no sample units is a warning, not an
  error.** It can happen by sampling chance. Calibration proceeds on the
  cells that are present, and weightflow reports that the calibrated
  weights will fall short of $`N`$ by the total of the absent cells.
- **A calibration variable with missing values (`NA`) is an error.**
  Calibration requires every unit to have a value for each auxiliary;
  impute first, or use a complete frame variable.

## Which one should I use?

- Reach for the **tidy** format when your totals live in a data frame (a
  census table, a projection, a spreadsheet), when you post-stratify on
  several variables at once, or when you calibrate linearly on
  categorical auxiliaries and would rather not manage the intercept and
  reference category.
- The **classic** `margins`/`totals` inputs remain fully supported;
  existing code keeps working unchanged.

In all cases the calibration itself is identical: the two shapes are
just different ways to hand weightflow the same population totals.
