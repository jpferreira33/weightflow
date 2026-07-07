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

## Domain (partitioned) calibration

Sometimes the benchmarks are known **by domain** and you want the
weights to reproduce them *within* each domain, not only overall. Pass
`by =` with the domain (partition) column:
[`step_calibrate()`](https://jpferreira33.github.io/weightflow/reference/step_calibrate.md)
then calibrates independently inside each domain, each to its own
totals. The tidy totals carry the domain as an extra column, and the
domain variable does **not** go in the formula or the margins (it is the
partition). This is also called partitioned calibration.

``` r

# sex counts by region: the domain (region) is just another column
sex_by_region <- as.data.frame(table(region = population$region,
                                      sex    = population$sex))

dom <- weighting_spec(sample_survey, base_weights = pw) |>
  step_calibrate(method = "raking", totals = list(sex_by_region),
                 count = "Freq", by = "region") |>
  prep()

# the calibrated weights reproduce the sex counts WITHIN each region
w <- dom$final_weight
round(xtabs(w ~ region + sex,
            data = data.frame(region = sample_survey$region,
                              sex = sample_survey$sex, w = w)))
#>        sex
#> region    F   M
#>   North 825 745
#>   South 643 607
#>   East  467 460
#>   West  376 372
```

Mixing a categorical and a continuous auxiliary by domain works too. The
continuous total is a data frame `domain, value` (one total per domain).
Here we use the exponential (raking) distance so the weights stay
positive:

``` r

inc_by_region <- aggregate(income ~ region, population, sum)   # region, income
resp <- subset(sample_survey, responded == 1)

lin_dom <- weighting_spec(resp, base_weights = pw) |>
  step_calibrate(method = "linear", formula = ~ sex + income,
                 totals = list(sex = sex_by_region, income = inc_by_region),
                 count = "Freq", calfun = "raking", by = "region") |>
  prep()

# the income total is reproduced within each region
w   <- lin_dom$final_weight
got <- tapply(w * resp$income, resp$region, sum)
cbind(calibrated = round(got),
      benchmark  = inc_by_region$income[match(names(got), inc_by_region$region)])
#>       calibrated benchmark
#> North   36939535  36939535
#> South   22331582  22331581
#> East    13076958  13076958
#> West    14396933  14396933
```

`by =` composes with `calfun`, `bounds`, `penalty` and the integrative
option, all applied within each domain. With `by = NULL` (the default)
calibration is global, as in the sections above.

## Model calibration

[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md)
(model-assisted, Wu & Sitter 2001) fits a working model for each study
variable, predicts it over the population, and calibrates so the
weighted sample reproduces two kinds of target at once: the population
total of each prediction (the model-assisted part) and the totals of a
set of *consistency* auxiliaries given by `x_formula` (exactly as in
linear calibration).

By default those consistency totals are read from the `population`
frame. But the control totals of the auxiliaries often come from
**another source**: an official published total, or a variable that is
not even in the frame. For that, `x_totals` accepts the **same two
shapes** as linear calibration (tidy named list, or classic model-matrix
vector), paired with `count` for the tidy form. The model predictors and
the consistency auxiliaries are independent: a variable can drive the
model without being a control total, and a control total need not enter
the model.

``` r

resp <- subset(sample_survey, responded == 1)

mc <- weighting_spec(resp, base_weights = pw) |>
  step_model_calibration(
    x_formula  = ~ region + age,                                # consistency block
    models     = list(income = y_model(income ~ age + sex,      # model block
                                       engine = "glm")),
    population = population,                                     # used for prediction
    x_totals   = list(region = m_region, age = sum(population$age)),
    count      = "Freq") |>
  prep()

# both blocks are reproduced: the X totals and the model prediction total
mc$steps[[1]]$diagnostics
#>              constraint            type   target achieved
#> (Intercept) (Intercept) X (consistency)     4495     4495
#> regionSouth regionSouth X (consistency)     1250     1250
#> regionEast   regionEast X (consistency)      927      927
#> regionWest   regionWest X (consistency)      748      748
#> age                 age X (consistency)   190781   190781
#> income           income       y (model) 93413771 93413771
```

Here `region` is a tidy data frame of category counts and `age` is a
single external number, just like the mixed linear example. `population`
is still required because the model must predict over every population
unit, but the consistency auxiliaries only need to exist in the sample:
when `x_totals` is given, weightflow does not read them from the frame,
so `age` (or a variable absent from `population` altogether) can be
controlled from an outside total. Leaving `x_totals = NULL` keeps the
earlier behaviour, reading the X totals from `population`.

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
