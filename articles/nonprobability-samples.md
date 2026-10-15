# Non-probability samples

A statistical office publishes **one** weight column. Every indicator,
every domain, every secondary user’s table comes out of the same column:
that is what keeps a published figure internally consistent with the
ones around it, and it is why a user can compute an estimate the office
never published.

The methods that make a non-probability sample usable pull the other
way. Doubly robust and machine-learning adjustments are
*outcome-specific*: the best weight for poverty is not the best weight
for employment, and the literature hands you one weight column per study
variable. An office cannot disseminate that.

This article builds the reconciliation weightflow implements: a single
column, doubly robust, exactly consistent with the known population
control totals, that serves every study variable at once, together with
the replicate weights that let a user attach a standard error to it. It
also shows where the construction stops working, and how the package
tells you.

## The two files

Nothing here is possible without a probability **reference**: a survey
that measures the same auxiliaries as the volunteers and carries real
design weights. The two files are complementary, and neither is
sufficient alone.

![The volunteer file and the probability
reference](data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPHN2ZyB3aWR0aD0iMTAwJSIgdmlld0JveD0iMCAwIDY4MCAzMjAiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwnSW50ZXInLFNlZ29lIFVJLFJvYm90byxzYW5zLXNlcmlmOyI+Cjx0aXRsZT5UaGUgdm9sdW50ZWVyIGZpbGUgYW5kIHRoZSBwcm9iYWJpbGl0eSByZWZlcmVuY2U8L3RpdGxlPgo8ZGVzYz5UaGUgdm9sdW50ZWVyIGZpbGUgcmVjb3JkcyB0aGUgYXV4aWxpYXJpZXMgeCBhbmQgdGhlIHN0dWR5IHZhcmlhYmxlcyB5IGJ1dCBoYXMgbm8gd2VpZ2h0IGNvbHVtbi4gVGhlIHByb2JhYmlsaXR5IHJlZmVyZW5jZSByZWNvcmRzIHRoZSBzYW1lIGF1eGlsaWFyaWVzIHggYW5kIGNhcnJpZXMgZGVzaWduIHdlaWdodHMgZCwgYnV0IG5vdCB0aGUgc3R1ZHkgdmFyaWFibGVzLiBUaGUgY29uc3RydWN0aW9uIGZpbGxzIHRoZSBtaXNzaW5nIHdlaWdodCBjb2x1bW4gb24gdGhlIHZvbHVudGVlciBmaWxlIHdpdGggYSBzaW5nbGUgY29sdW1uIHVzZWQgZm9yIGV2ZXJ5IHN0dWR5IHZhcmlhYmxlLjwvZGVzYz4KPGRlZnM+PG1hcmtlciBpZD0ibnAxIiB2aWV3Qm94PSIwIDAgMTAgMTAiIHJlZlg9IjgiIHJlZlk9IjUiIG1hcmtlcldpZHRoPSI3IiBtYXJrZXJIZWlnaHQ9IjciIG9yaWVudD0iYXV0by1zdGFydC1yZXZlcnNlIj48cGF0aCBkPSJNMiAxTDggNUwyIDkiIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjgiLz48L21hcmtlcj48L2RlZnM+Cgo8dGV4dCB4PSIxNTAiIHk9IjI2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmb250LXdlaWdodD0iNjAwIiBmaWxsPSIjM2QzNTgwIj52b2x1bnRlZXIgZmlsZTwvdGV4dD4KPHJlY3QgeD0iNDAiIHk9IjM4IiB3aWR0aD0iMjIwIiBoZWlnaHQ9IjEwNCIgcng9IjgiIGZpbGw9IiNmNGYyZmIiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjMiLz4KPHJlY3QgeD0iNDAiIHk9IjM4IiB3aWR0aD0iMjIwIiBoZWlnaHQ9IjI2IiByeD0iOCIgZmlsbD0iI2VjZTlmNiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuMyIvPgo8dGV4dCB4PSI3NiIgeT0iNTYiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiMzZDM1ODAiPng8L3RleHQ+Cjx0ZXh0IHg9IjE1MCIgeT0iNTYiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiMzZDM1ODAiPnkxIOKApiB5SzwvdGV4dD4KPHRleHQgeD0iMjI4IiB5PSI1NiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzhhODRhOCI+dzwvdGV4dD4KPGxpbmUgeDE9IjExMyIgeTE9IjM4IiB4Mj0iMTEzIiB5Mj0iMTQyIiBzdHJva2U9IiNjNmJlZjQiIHN0cm9rZS13aWR0aD0iMSIvPgo8bGluZSB4MT0iMTk2IiB5MT0iMzgiIHgyPSIxOTYiIHkyPSIxNDIiIHN0cm9rZT0iI2M2YmVmNCIgc3Ryb2tlLXdpZHRoPSIxIi8+CjxyZWN0IHg9IjE5NiIgeT0iNjQiIHdpZHRoPSI2NCIgaGVpZ2h0PSI3OCIgZmlsbD0iI2ZkZjZlOCIgc3Ryb2tlPSIjYzk5MDJhIiBzdHJva2Utd2lkdGg9IjEuMyIgc3Ryb2tlLWRhc2hhcnJheT0iNCAzIi8+Cjx0ZXh0IHg9IjIyOCIgeT0iMTA4IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjIyIiBmaWxsPSIjYzk5MDJhIj4/PC90ZXh0Pgo8dGV4dCB4PSI3NiIgeT0iODYiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTEiIGZpbGw9IiM2YjZhODYiPmFnZSBzZXg8L3RleHQ+Cjx0ZXh0IHg9Ijc2IiB5PSIxMDQiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTEiIGZpbGw9IiM2YjZhODYiPnJlZ2lvbjwvdGV4dD4KPHRleHQgeD0iMTUwIiB5PSI4NiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzZiNmE4NiI+aW5jb21lPC90ZXh0Pgo8dGV4dCB4PSIxNTAiIHk9IjEwNCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzZiNmE4NiI+ZW1wbG95ZWQ8L3RleHQ+Cjx0ZXh0IHg9IjE1MCIgeT0iMTIyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjNmI2YTg2Ij7igKY8L3RleHQ+Cgo8dGV4dCB4PSI1MzAiIHk9IjI2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmb250LXdlaWdodD0iNjAwIiBmaWxsPSIjM2QzNTgwIj5wcm9iYWJpbGl0eSByZWZlcmVuY2U8L3RleHQ+CjxyZWN0IHg9IjQyMCIgeT0iMzgiIHdpZHRoPSIyMjAiIGhlaWdodD0iMTA0IiByeD0iOCIgZmlsbD0iI2Y0ZjJmYiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuMyIvPgo8cmVjdCB4PSI0MjAiIHk9IjM4IiB3aWR0aD0iMjIwIiBoZWlnaHQ9IjI2IiByeD0iOCIgZmlsbD0iI2VjZTlmNiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuMyIvPgo8dGV4dCB4PSI0NTYiIHk9IjU2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjM2QzNTgwIj54PC90ZXh0Pgo8dGV4dCB4PSI1MzAiIHk9IjU2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjOGE4NGE4Ij55MSDigKYgeUs8L3RleHQ+Cjx0ZXh0IHg9IjYwOCIgeT0iNTYiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiMzZDM1ODAiPmQ8L3RleHQ+CjxsaW5lIHgxPSI0OTMiIHkxPSIzOCIgeDI9IjQ5MyIgeTI9IjE0MiIgc3Ryb2tlPSIjYzZiZWY0IiBzdHJva2Utd2lkdGg9IjEiLz4KPGxpbmUgeDE9IjU3NiIgeTE9IjM4IiB4Mj0iNTc2IiB5Mj0iMTQyIiBzdHJva2U9IiNjNmJlZjQiIHN0cm9rZS13aWR0aD0iMSIvPgo8cmVjdCB4PSI0OTMiIHk9IjY0IiB3aWR0aD0iODMiIGhlaWdodD0iNzgiIGZpbGw9IiNmM2YzZjUiIHN0cm9rZT0iIzlhOTZhOCIgc3Ryb2tlLXdpZHRoPSIxLjMiIHN0cm9rZS1kYXNoYXJyYXk9IjQgMyIvPgo8dGV4dCB4PSI1MzQiIHk9IjEwOSIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxOCIgZmlsbD0iIzlhOTZhOCI+4oCUPC90ZXh0Pgo8dGV4dCB4PSI0NTYiIHk9Ijg2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjNmI2YTg2Ij5hZ2Ugc2V4PC90ZXh0Pgo8dGV4dCB4PSI0NTYiIHk9IjEwNCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzZiNmE4NiI+cmVnaW9uPC90ZXh0Pgo8dGV4dCB4PSI2MDgiIHk9Ijg5IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjNmI2YTg2Ij5rbm93biBieTwvdGV4dD4KPHRleHQgeD0iNjA4IiB5PSIxMDUiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTEiIGZpbGw9IiM2YjZhODYiPmRlc2lnbjwvdGV4dD4KCjxsaW5lIHgxPSIxNTAiIHkxPSIxNTAiIHgyPSIzMDAiIHkyPSIxOTYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjUiIG1hcmtlci1lbmQ9InVybCgjbnAxKSIvPgo8bGluZSB4MT0iNTMwIiB5MT0iMTUwIiB4Mj0iMzgwIiB5Mj0iMTk2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS41IiBtYXJrZXItZW5kPSJ1cmwoI25wMSkiLz4KPHJlY3QgeD0iMjE1IiB5PSIyMDQiIHdpZHRoPSIyNTAiIGhlaWdodD0iNDQiIHJ4PSIxMCIgZmlsbD0iIzNkMzU4MCIvPgo8dGV4dCB4PSIzNDAiIHk9IjIzMSIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxNCIgZmlsbD0iI2ZmZmZmZiI+b25lIHdlaWdodCBjb2x1bW48L3RleHQ+Cjx0ZXh0IHg9IjM0MCIgeT0iMjcyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmaWxsPSIjNGE0NjYwIj5leGFjdCBvbiB0aGUga25vd24gY29udHJvbCB0b3RhbHMsIGRvdWJseSByb2J1c3QsPC90ZXh0Pgo8dGV4dCB4PSIzNDAiIHk9IjI5MCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzRhNDY2MCI+dXNlZCBmb3IgZXZlcnkgc3R1ZHkgdmFyaWFibGU8L3RleHQ+Cjx0ZXh0IHg9IjM0MCIgeT0iMzEyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmb250LXN0eWxlPSJpdGFsaWMiIGZpbGw9IiM4YTg0YTgiPkEgZGFzaGVkIGNlbGwgaXMgbm90IG1lYXN1cmVkIG9uIHRoYXQgZmlsZS48L3RleHQ+Cjwvc3ZnPgo=)

## A volunteer sample that is wrong in four different ways

We draw volunteers from the bundled `population` so that men and the
young over-participate, and we track four indicators of very different
character: a mean, a proportion, a **rare** proportion, and one that the
selection hits head on. None of them is used to decide who volunteers:
participation depends on `sex` and `age` alone, which is what makes the
problem correctable.

``` r

set.seed(1)
pop <- population
pop$poor    <- as.integer(pop$income < quantile(pop$income, 0.12))  # ~12%: the rare one
pop$retired <- as.integer(pop$age >= 65)
N <- nrow(pop)

take <- runif(N) < plogis(-1.9 + 0.9 * (pop$sex == "M") - 0.025 * (pop$age - 45))
vol  <- pop[take, ]                                   # the volunteers: no weights at all
ri   <- sample(which(!take), 800)
ref  <- pop[ri, c("region", "sex", "age")]            # the reference: no study variables
ref$d <- N / 800                                      # its design weights

c(volunteers = nrow(vol), reference = nrow(ref))
#> volunteers  reference 
#>       1026        800
```

``` r

ind   <- c("income", "employed", "poor", "retired")
truth <- vapply(ind, function(v) mean(pop[[v]]), numeric(1))
pct   <- function(w) round(100 * (vapply(ind, function(v)
           weighted.mean(vol[[v]], w), numeric(1)) / truth - 1), 1)

pct(rep(1, nrow(vol)))        # relative bias (%) of the unweighted volunteer file
#>   income employed     poor  retired 
#>      2.3     -4.2     -7.5    -46.3
```

The unweighted file is not uniformly wrong. It is wrong by different
amounts in different directions, which is why a single correction factor
cannot fix it and why the weight has to come from a model.

## The reference is a sample, so give it its replicates

Before anything else: the reference carries sampling error of its own,
and in this construction that error is not a detail. Every reference
unit is a row of the participation model and a row of the projection
that produces the calibration targets, so the whole weight depends on
which reference units were drawn. Pass the reference’s replicate weights
and the bootstrap propagates that; leave them out and the reference is
treated as the population.

In production the replicates come from the reference survey’s own
replicate file. Here the reference is a simple random sample, so they
can be built from its design with the same function:

``` r

rep_ref <- bootstrap_weights(weighting_spec(ref, base_weights = d),
                             replicates = 40, seed = 11,
                             progress = FALSE)$replicates

sr <- reference_sample(ref, weights = "d", replicates = rep_ref)
```

[What it costs to skip this](#what-the-reference-contributes) is
measured below.

## Step one: the pseudo-weight

[`step_pseudoweight()`](https://jpferreira33.github.io/weightflow/reference/step_pseudoweight.md)
stacks the two files internally, fits the probability that a unit
belongs to the volunteer side rather than the reference side, and turns
it into the participation odds `(1 - p)/p`. No manual pooling, no
[`bind_rows()`](https://dplyr.tidyverse.org/reference/bind_rows.html).

``` r

pw_only <- weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
  step_pseudoweight(reference = sr, formula = ~ region + sex + age,
                    engine = "logit") |>
  prep()

c(sum_of_weights = sum(pw_only$final_weight), N = N)
#> sum_of_weights              N 
#>       4519.597       4495.000
```

That check is the one to run before going further, and it is worth
knowing why.

### What the sum of the weights is telling you

Two decisions go into turning one fitted score into a weight, and both
are usually made by default rather than on purpose: whether the
reference enters the stacked file with its **design weights** or at
weight one, and whether the volunteer’s weight is the **odds**
`(1 - p)/p` or the plain inverse `1/p`. Neither is visible afterwards.
The control totals close to numerical precision either way, no weight
looks odd, and the interval looks reasonable.

The sum of the pseudo-weights separates them, because each construction
leaves a different arithmetic trace:

![Three ways to turn one fitted score into a weight, and the trace each
leaves](data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPHN2ZyB3aWR0aD0iMTAwJSIgdmlld0JveD0iMCAwIDY4MCAyMzIiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwnSW50ZXInLFNlZ29lIFVJLFJvYm90byxzYW5zLXNlcmlmOyI+Cjx0aXRsZT5UaHJlZSB3YXlzIHRvIHR1cm4gb25lIGZpdHRlZCBzY29yZSBpbnRvIGEgd2VpZ2h0LCBhbmQgdGhlIHRyYWNlIGVhY2ggbGVhdmVzPC90aXRsZT4KPGRlc2M+VGhlIGNvcnJlY3QgY29uc3RydWN0aW9uIHVzZXMgdGhlIG9kZHMgd2l0aCBhIGRlc2lnbi13ZWlnaHRlZCByZWZlcmVuY2UgYW5kIGl0cyBwc2V1ZG8td2VpZ2h0cyBzdW0gdG8gdGhlIGVzdGltYXRlZCBwb3B1bGF0aW9uIHNpemUuIFVzaW5nIHRoZSBwbGFpbiBpbnZlcnNlIGFkZHMgb25lIHVuaXQgb2Ygd2VpZ2h0IHBlciB2b2x1bnRlZXIsIHNvIHRoZSBzdW0gb3ZlcnNob290cyBieSB0aGUgdm9sdW50ZWVyIHNoYXJlIG9mIHRoZSBwb3B1bGF0aW9uLiBFbnRlcmluZyB0aGUgcmVmZXJlbmNlIGF0IHdlaWdodCBvbmUgcmVzY2FsZXMgdGhlIHdlaWdodHMgYnkgdGhlIHJlZmVyZW5jZSdzIG93biBzYW1wbGluZyBmcmFjdGlvbiwgc28gdGhlIHN1bSBjb2xsYXBzZXMgdG93YXJkcyB0aGF0IGZyYWN0aW9uLjwvZGVzYz4KPHJlY3QgeD0iMTYiIHk9IjIyIiB3aWR0aD0iMjA2IiBoZWlnaHQ9IjE1MCIgcng9IjEwIiBmaWxsPSIjZWFmNWYwIiBzdHJva2U9IiMxZDllNzUiIHN0cm9rZS13aWR0aD0iMS41Ii8+Cjx0ZXh0IHg9IjExOSIgeT0iNDQiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTEiIGZvbnQtd2VpZ2h0PSI2MDAiIGZpbGw9IiMxNTUwM2MiPkNPUlJFQ1Q8L3RleHQ+Cjx0ZXh0IHg9IjExOSIgeT0iNjYiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTMiIGZpbGw9IiMyMDI0MmUiPnRoZSBvZGRzPC90ZXh0Pgo8dGV4dCB4PSIxMTkiIHk9IjkyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjMTU1MDNjIj4oMSAtIHApIC8gcDwvdGV4dD4KPHRleHQgeD0iMTE5IiB5PSIxMTMiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTEiIGZpbGw9IiMzZjdhNjQiPmRlc2lnbi13ZWlnaHRlZCByZWZlcmVuY2U8L3RleHQ+CjxyZWN0IHg9IjM2IiB5PSIxMjgiIHdpZHRoPSIxNjYiIGhlaWdodD0iMzAiIHJ4PSI2IiBmaWxsPSIjZmZmZmZmIiBzdHJva2U9IiMxZDllNzUiIHN0cm9rZS13aWR0aD0iMS4yIi8+Cjx0ZXh0IHg9IjExOSIgeT0iMTQ4IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjMTU1MDNjIj4mIzkzMTt3IC8gTiYjNzcwOyA9IDE8L3RleHQ+Cgo8cmVjdCB4PSIyMzciIHk9IjIyIiB3aWR0aD0iMjA2IiBoZWlnaHQ9IjE1MCIgcng9IjEwIiBmaWxsPSIjZmRmNmU4IiBzdHJva2U9IiNjOTkwMmEiIHN0cm9rZS13aWR0aD0iMS41Ii8+Cjx0ZXh0IHg9IjM0MCIgeT0iNDQiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTEiIGZvbnQtd2VpZ2h0PSI2MDAiIGZpbGw9IiM4YTY0MTQiPlFVSUVUIEVSUk9SPC90ZXh0Pgo8dGV4dCB4PSIzNDAiIHk9IjY2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmaWxsPSIjMjAyNDJlIj50aGUgcGxhaW4gaW52ZXJzZTwvdGV4dD4KPHRleHQgeD0iMzQwIiB5PSI5MiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzhhNjQxNCI+MSAvIHA8L3RleHQ+Cjx0ZXh0IHg9IjM0MCIgeT0iMTEzIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjOGE3YTUwIj5vbmUgZXh0cmEgdW5pdCBvZiB3ZWlnaHQgZWFjaDwvdGV4dD4KPHJlY3QgeD0iMjU3IiB5PSIxMjgiIHdpZHRoPSIxNjYiIGhlaWdodD0iMzAiIHJ4PSI2IiBmaWxsPSIjZmZmZmZmIiBzdHJva2U9IiNjOTkwMmEiIHN0cm9rZS13aWR0aD0iMS4yIi8+Cjx0ZXh0IHg9IjM0MCIgeT0iMTQ4IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjOGE2NDE0Ij4mIzkzMTt3IC8gTiYjNzcwOyA9IDEgKyBuJiM3NTI1Oy9OPC90ZXh0PgoKPHJlY3QgeD0iNDU4IiB5PSIyMiIgd2lkdGg9IjIwNiIgaGVpZ2h0PSIxNTAiIHJ4PSIxMCIgZmlsbD0iI2ZiZWNlYiIgc3Ryb2tlPSIjYzA0OTJmIiBzdHJva2Utd2lkdGg9IjEuNSIvPgo8dGV4dCB4PSI1NjEiIHk9IjQ0IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmb250LXdlaWdodD0iNjAwIiBmaWxsPSIjOGMyZjFjIj5MT1VEIEVSUk9SPC90ZXh0Pgo8dGV4dCB4PSI1NjEiIHk9IjY2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmaWxsPSIjMjAyNDJlIj5yZWZlcmVuY2UgYXQgd2VpZ2h0IG9uZTwvdGV4dD4KPHRleHQgeD0iNTYxIiB5PSI5MiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzhjMmYxYyI+KDEgLSBwKSAvIHA8L3RleHQ+Cjx0ZXh0IHg9IjU2MSIgeT0iMTEzIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjOWE1YTQ4Ij5zY2FsZWQgYnkgdGhlIHJlZmVyZW5jZSdzIG93biBmcmFjdGlvbjwvdGV4dD4KPHJlY3QgeD0iNDc4IiB5PSIxMjgiIHdpZHRoPSIxNjYiIGhlaWdodD0iMzAiIHJ4PSI2IiBmaWxsPSIjZmZmZmZmIiBzdHJva2U9IiNjMDQ5MmYiIHN0cm9rZS13aWR0aD0iMS4yIi8+Cjx0ZXh0IHg9IjU2MSIgeT0iMTQ4IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjOGMyZjFjIj4mIzkzMTt3IC8gTiYjNzcwOyA9IG4mIzc1MjM7L048L3RleHQ+Cgo8dGV4dCB4PSIzNDAiIHk9IjE5NiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzRhNDY2MCI+RWFjaCB0cmFjZSBpcyBhIHByb3BlcnR5IG9mIHRoZSBzdGFja2luZywgbm90IGEgc2ltdWxhdGlvbiByZXN1bHQuPC90ZXh0Pgo8dGV4dCB4PSIzNDAiIHk9IjIxOCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZm9udC1zdHlsZT0iaXRhbGljIiBmaWxsPSIjOGE4NGE4Ij5BbmQgZWFjaCBpcyBnb25lIGFmdGVyIGEgY2FsaWJyYXRpb246IHRoZSBjb250cm9sLXRvdGFsIGJsb2NrIGltcG9zZXMgdGhlIHBvcHVsYXRpb24gdG90YWwgd2hpY2hldmVyIGNvbnN0cnVjdGlvbiBwcm9kdWNlZCB0aGUgd2VpZ2h0cy48L3RleHQ+Cjwvc3ZnPgo=)

The first two are one line apart, because `1/p = (1 - p)/p + 1`:

``` r

ref1 <- ref; ref1$one <- 1          # the reference stacked at weight one
pw_one <- weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
  step_pseudoweight(reference = reference_sample(ref1, weights = "one"),
                    formula = ~ region + sex + age) |>
  prep(warn = FALSE)

round(c(odds           = sum(pw_only$final_weight) / N,
        plain_inverse  = (sum(pw_only$final_weight) + nrow(vol)) / N,
        reference_at_1 = sum(pw_one$final_weight) / N,
        n_vol_over_N   = nrow(vol) / N,
        n_ref_over_N   = nrow(ref) / N), 4)
#>           odds  plain_inverse reference_at_1   n_vol_over_N   n_ref_over_N 
#>         1.0055         1.2337         0.1781         0.2283         0.1780
```

The inverse overshoots by exactly the volunteer share of the population,
and the weight-one reference collapses to exactly the reference’s own
sampling fraction. That is why the check has to be read **to three
significant figures and before any calibration**: afterwards the
control-total block imposes the population total and all three look
identical. weightflow builds the first construction, and the ratio is in
the step’s diagnostics.

The distortion from stacking the reference at weight one disappears when
the reference is self-weighting, or when the calibration’s control
totals happen to span its design strata. So the louder mistake is the
one a later step can absorb, and the quieter one is not.

Flexible learners are available for the participation model
(`engine = "tree"`, `"forest"`, `"boost"`, with `crossfit`), exactly as
for response propensities.

## Step two: one calibration that carries every variable

The pseudo-weight alone is consistent if the participation model is
right. A calibration is consistent if the working model for the outcome
is right. Doing both is doubly robust: correct if **either** holds.

The move that keeps it one column is to put all K study variables into
the *same* linear calibration system. Each gets its own working model,
i.e. its own predictors and its own learner, and the predictions enter
as columns of one stacked matrix alongside the known control totals. One
system, one solution, one weight.

![The multipurpose doubly robust weight as a single
recipe](data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPHN2ZyB3aWR0aD0iMTAwJSIgdmlld0JveD0iMCAwIDY4MCAzNTgiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwnSW50ZXInLFNlZ29lIFVJLFJvYm90byxzYW5zLXNlcmlmOyI+Cjx0aXRsZT5UaGUgbXVsdGlwdXJwb3NlIGRvdWJseSByb2J1c3Qgd2VpZ2h0IGFzIGEgc2luZ2xlIHJlY2lwZTwvdGl0bGU+CjxkZXNjPlRoZSB2b2x1bnRlZXIgYW5kIHJlZmVyZW5jZSBmaWxlcyBmZWVkIGEgcGFydGljaXBhdGlvbiBtb2RlbCB0aGF0IHByb2R1Y2VzIHRoZSBwc2V1ZG8td2VpZ2h0LiBLIHdvcmtpbmcgbW9kZWxzLCBvbmUgcGVyIHN0dWR5IHZhcmlhYmxlLCBwcm9kdWNlIHByZWRpY3Rpb24gY29sdW1ucyB0aGF0IGFyZSBzdGFja2VkIHdpdGggdGhlIGtub3duIHBvcHVsYXRpb24gY29udHJvbCB0b3RhbHMgaW50byBvbmUgbGluZWFyIGNhbGlicmF0aW9uLiBUaGUgY2FsaWJyYXRpb24gcmV0dXJucyBhIHNpbmdsZSB3ZWlnaHQgY29sdW1uIHVzZWQgZm9yIGV2ZXJ5IGluZGljYXRvci4gQSBiYW5kIHVuZGVybmVhdGggc2hvd3MgdGhhdCB0aGUgcmVwbGljYXRpb24gYm9vdHN0cmFwIHJlLWV4ZWN1dGVzIGV2ZXJ5IHN0ZXAgb24gZWFjaCByZXBsaWNhdGUsIGluY2x1ZGluZyB0aGUgcmVmZXJlbmNlIHJlcGxpY2F0ZXMuPC9kZXNjPgo8ZGVmcz48bWFya2VyIGlkPSJucDIiIHZpZXdCb3g9IjAgMCAxMCAxMCIgcmVmWD0iOCIgcmVmWT0iNSIgbWFya2VyV2lkdGg9IjciIG1hcmtlckhlaWdodD0iNyIgb3JpZW50PSJhdXRvLXN0YXJ0LXJldmVyc2UiPjxwYXRoIGQ9Ik0yIDFMOCA1TDIgOSIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuOCIvPjwvbWFya2VyPjwvZGVmcz4KCjxyZWN0IHg9IjI0IiB5PSI0MCIgd2lkdGg9IjEyMCIgaGVpZ2h0PSIzNCIgcng9IjgiIGZpbGw9IiNlY2U5ZjYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjMiLz4KPHRleHQgeD0iODQiIHk9IjYyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmaWxsPSIjMjAyNDJlIj52b2x1bnRlZXJzPC90ZXh0Pgo8cmVjdCB4PSIyNCIgeT0iODYiIHdpZHRoPSIxMjAiIGhlaWdodD0iMzQiIHJ4PSI4IiBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS4zIi8+Cjx0ZXh0IHg9Ijg0IiB5PSIxMDgiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiMyMDI0MmUiPnJlZmVyZW5jZSArIGQ8L3RleHQ+Cgo8bGluZSB4MT0iMTQ4IiB5MT0iNTciIHgyPSIxOTYiIHkyPSI3MCIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNucDIpIi8+CjxsaW5lIHgxPSIxNDgiIHkxPSIxMDMiIHgyPSIxOTYiIHkyPSI4OCIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNucDIpIi8+CjxyZWN0IHg9IjIwMCIgeT0iNTYiIHdpZHRoPSIxNTAiIGhlaWdodD0iNDQiIHJ4PSI4IiBmaWxsPSIjZjRmMmZiIiBzdHJva2U9IiM1MzRhYjciIHN0cm9rZS13aWR0aD0iMS40Ii8+Cjx0ZXh0IHg9IjI3NSIgeT0iNzQiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiMyMDI0MmUiPnBhcnRpY2lwYXRpb24gbW9kZWw8L3RleHQ+Cjx0ZXh0IHg9IjI3NSIgeT0iOTEiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTEiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiM1MzRhYjciPigxIC0gcCkgLyBwPC90ZXh0PgoKPHJlY3QgeD0iMjAwIiB5PSIxMzIiIHdpZHRoPSIxNTAiIGhlaWdodD0iMjYiIHJ4PSI2IiBmaWxsPSIjZWFmNWYwIiBzdHJva2U9IiMxZDllNzUiIHN0cm9rZS13aWR0aD0iMS4yIi8+Cjx0ZXh0IHg9IjI3NSIgeT0iMTUwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjMTU1MDNjIj55MSAmIzg1OTQ7IGxlYXJuZXIgMTwvdGV4dD4KPHJlY3QgeD0iMjAwIiB5PSIxNjQiIHdpZHRoPSIxNTAiIGhlaWdodD0iMjYiIHJ4PSI2IiBmaWxsPSIjZWFmNWYwIiBzdHJva2U9IiMxZDllNzUiIHN0cm9rZS13aWR0aD0iMS4yIi8+Cjx0ZXh0IHg9IjI3NSIgeT0iMTgyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjMTU1MDNjIj55MiAmIzg1OTQ7IGxlYXJuZXIgMjwvdGV4dD4KPHJlY3QgeD0iMjAwIiB5PSIxOTYiIHdpZHRoPSIxNTAiIGhlaWdodD0iMjYiIHJ4PSI2IiBmaWxsPSIjZWFmNWYwIiBzdHJva2U9IiMxZDllNzUiIHN0cm9rZS13aWR0aD0iMS4yIi8+Cjx0ZXh0IHg9IjI3NSIgeT0iMjE0IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjMTU1MDNjIj55SyAmIzg1OTQ7IGxlYXJuZXIgSzwvdGV4dD4KPHJlY3QgeD0iMjAwIiB5PSIyMzIiIHdpZHRoPSIxNTAiIGhlaWdodD0iMjYiIHJ4PSI2IiBmaWxsPSIjZmRmNmU4IiBzdHJva2U9IiNjOTkwMmEiIHN0cm9rZS13aWR0aD0iMS4yIi8+Cjx0ZXh0IHg9IjI3NSIgeT0iMjUwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjNWM0NDEwIj5rbm93biBjb250cm9sIHRvdGFsczwvdGV4dD4KCjxsaW5lIHgxPSIzNTQiIHkxPSI3OCIgeDI9IjQwMiIgeTI9IjE0MCIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNucDIpIi8+CjxsaW5lIHgxPSIzNTQiIHkxPSIxNDUiIHgyPSI0MDIiIHkyPSIxNjYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjUiIG1hcmtlci1lbmQ9InVybCgjbnAyKSIvPgo8bGluZSB4MT0iMzU0IiB5MT0iMTc3IiB4Mj0iNDAyIiB5Mj0iMTgwIiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS41IiBtYXJrZXItZW5kPSJ1cmwoI25wMikiLz4KPGxpbmUgeDE9IjM1NCIgeTE9IjIwOSIgeDI9IjQwMiIgeTI9IjE5NCIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNucDIpIi8+CjxsaW5lIHgxPSIzNTQiIHkxPSIyNDUiIHgyPSI0MDIiIHkyPSIyMDgiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjUiIG1hcmtlci1lbmQ9InVybCgjbnAyKSIvPgoKPHJlY3QgeD0iNDA2IiB5PSIxNDAiIHdpZHRoPSIxMzYiIGhlaWdodD0iNjgiIHJ4PSI4IiBmaWxsPSIjZjRmMmZiIiBzdHJva2U9IiM1MzRhYjciIHN0cm9rZS13aWR0aD0iMS40Ii8+Cjx0ZXh0IHg9IjQ3NCIgeT0iMTY2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmaWxsPSIjMjAyNDJlIj5vbmUgc3RhY2tlZDwvdGV4dD4KPHRleHQgeD0iNDc0IiB5PSIxODQiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiMyMDI0MmUiPmNhbGlicmF0aW9uPC90ZXh0Pgo8dGV4dCB4PSI0NzQiIHk9IjIwMCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMCIgZmlsbD0iIzZiNmE4NiI+c29sdmVkIG9uY2U8L3RleHQ+Cgo8bGluZSB4MT0iNTQ2IiB5MT0iMTc0IiB4Mj0iNTg2IiB5Mj0iMTc0IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS41IiBtYXJrZXItZW5kPSJ1cmwoI25wMikiLz4KPHJlY3QgeD0iNTkwIiB5PSIxMzQiIHdpZHRoPSI2NiIgaGVpZ2h0PSI4MCIgcng9IjgiIGZpbGw9IiMzZDM1ODAiLz4KPHRleHQgeD0iNjIzIiB5PSIxNzAiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTMiIGZpbGw9IiNmZmZmZmYiPm9uZTwvdGV4dD4KPHRleHQgeD0iNjIzIiB5PSIxODgiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTMiIGZpbGw9IiNmZmZmZmYiPndlaWdodDwvdGV4dD4KCjxyZWN0IHg9IjI0IiB5PSIyNzgiIHdpZHRoPSI2MzIiIGhlaWdodD0iNTIiIHJ4PSI4IiBmaWxsPSIjZjdmNmZiIiBzdHJva2U9IiNiMGE2ZWUiIHN0cm9rZS13aWR0aD0iMS4yIiBzdHJva2UtZGFzaGFycmF5PSI1IDMiLz4KPHRleHQgeD0iMzQwIiB5PSIyOTkiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiM0YTQ2NjAiPnJlcGxpY2F0aW9uIGJvb3RzdHJhcDogcmUtZXhlY3V0ZXMgZXZlcnkgc3RlcCBhYm92ZSBvbiBlYWNoIHJlcGxpY2F0ZTwvdGV4dD4KPHRleHQgeD0iMzQwIiB5PSIzMTgiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiM0YTQ2NjAiPnRoYXQgaXMsIHRoZSBwYXJ0aWNpcGF0aW9uIG1vZGVsLCB0aGUgSyB3b3JraW5nIG1vZGVscywgYW5kIHRoZSByZWZlcmVuY2U8L3RleHQ+Cjx0ZXh0IHg9IjM0MCIgeT0iMzQ0IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmb250LXN0eWxlPSJpdGFsaWMiIGZpbGw9IiM4YTg0YTgiPkVhY2ggc3R1ZHkgdmFyaWFibGUga2VlcHMgaXRzIG93biBtb2RlbDsgdGhlIGZpbGUga2VlcHMgb25lIHdlaWdodC48L3RleHQ+Cjwvc3ZnPgo=)

In code, that whole picture is one
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md):

``` r

cens <- list(sex    = as.data.frame(table(sex    = pop$sex)),
             region = as.data.frame(table(region = pop$region)))

spec <- weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
  step_pseudoweight(reference = sr, formula = ~ region + sex + age,
                    engine = "logit") |>
  step_model_calibration(
    x_formula = ~ sex + region,          # the KNOWN control totals: met exactly
    x_totals  = cens,
    models    = list(                    # one working model per study variable
      income   = y_model(income   ~ age + sex + region, engine = "glm"),
      employed = y_model(employed ~ age + sex + region, engine = "glm")),
    population = sr,
    crossfit   = 3)

fit <- prep(spec)
w   <- fit$final_weight
```

One column. Here is what it does to all four indicators, including the
two that were never modelled:

``` r

rbind(unweighted = pct(rep(1, nrow(vol))),
      uni_weight = pct(w))
#>            income employed poor retired
#> unweighted    2.3     -4.2 -7.5   -46.3
#> uni_weight    1.9      0.9 -4.8     3.9
```

The two indicators with a working model are corrected, and so is
`retired`, which has none: the pseudo-weight and the control totals
carry it. `poor` improves least, and that is the general pattern rather
than an accident of this draw. The cost of sharing one weight
concentrates on the rarest indicator, which is the one that most
deserves a weight of its own when the margin of error matters.

The exactness is not approximate.
[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
records every constraint and what the weights achieved:

``` r

head(fit$steps[[2]]$diagnostics, 7)
#>              constraint            type     target   achieved
#> (Intercept) (Intercept) X (consistency)     4495.0     4495.0
#> sexM               sexM X (consistency)     2184.0     2184.0
#> regionSouth regionSouth X (consistency)     1250.0     1250.0
#> regionEast   regionEast X (consistency)      927.0      927.0
#> regionWest   regionWest X (consistency)      748.0      748.0
#> income           income       y (model) 87647256.2 87647256.2
#> employed       employed       y (model)     1762.7     1762.7
```

## Where it stops working: the rank ceiling

Exact consistency is not free, and it does not degrade gracefully. It is
either met or lost, for every variable at once. The reason is a rank
condition.

Write `q` for the dimension of the span of the predictors the working
models use and `dim col(A)` for the number of known control totals. With
**linear working models fitted in sample**, every prediction lies inside
that one span, so the stacked system can only add

*K ≤ q − dim col(A)*

variables before it becomes rank deficient. Past that point the control
totals are not approximately met: they are missed.

![The rank ceiling and the two ways out of
it](data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPHN2ZyB3aWR0aD0iMTAwJSIgdmlld0JveD0iMCAwIDY4MCAyMzAiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwnSW50ZXInLFNlZ29lIFVJLFJvYm90byxzYW5zLXNlcmlmOyI+Cjx0aXRsZT5UaGUgcmFuayBjZWlsaW5nIGFuZCB0aGUgdHdvIHdheXMgb3V0IG9mIGl0PC90aXRsZT4KPGRlc2M+V2l0aCBsaW5lYXIgd29ya2luZyBtb2RlbHMgZXZlcnkgcHJlZGljdGlvbiBsaWVzIGluIHRoZSBzcGFuIG9mIHRoZSBtb2RlbCBibG9jaywgd2hpY2ggYWxyZWFkeSBjb250YWlucyB0aGUgY29udHJvbC10b3RhbCBibG9jaywgc28gb25seSBxIG1pbnVzIHRoZSBkaW1lbnNpb24gb2YgdGhlIGNvbnRyb2wtdG90YWwgYmxvY2sgZGlyZWN0aW9ucyBhcmUgbGVmdCBmb3Igc3R1ZHkgdmFyaWFibGVzLiBUd28gZXNjYXBlczogYSByaWNoZXIgcHJlZGljdG9yIGJhc2lzIGVubGFyZ2VzIHRoZSBzcGFuIGFuZCByYWlzZXMgdGhlIGNlaWxpbmcgYnkgb25lIHZhcmlhYmxlIGF0IGEgdGltZSwgd2hpbGUgYWRhcHRpdmUgbGVhcm5lcnMgYW5kIGNyb3NzLWZpdHRpbmcgcHJvZHVjZSBwcmVkaWN0aW9ucyBvdXRzaWRlIGFueSBzaW5nbGUgZml4ZWQgc3Bhbiwgc28gdGhlIGNlaWxpbmcgbm8gbG9uZ2VyIGFwcGxpZXMuPC9kZXNjPgo8cmVjdCB4PSIzMCIgeT0iMzQiIHdpZHRoPSIyNTAiIGhlaWdodD0iMTQwIiByeD0iMTAiIGZpbGw9IiNmNGYyZmIiIHN0cm9rZT0iIzUzNGFiNyIgc3Ryb2tlLXdpZHRoPSIxLjQiLz4KPHRleHQgeD0iMTU1IiB5PSI1NCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzNkMzU4MCI+c3BhbiBvZiB0aGUgbW9kZWwgYmxvY2ssIGRpbSBxPC90ZXh0Pgo8cmVjdCB4PSI2NiIgeT0iNjYiIHdpZHRoPSIxNzgiIGhlaWdodD0iNTIiIHJ4PSI4IiBmaWxsPSIjZmRmNmU4IiBzdHJva2U9IiNjOTkwMmEiIHN0cm9rZS13aWR0aD0iMS4zIi8+Cjx0ZXh0IHg9IjE1NSIgeT0iODgiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiM1YzQ0MTAiPmtub3duIGNvbnRyb2wgdG90YWxzPC90ZXh0Pgo8dGV4dCB4PSIxNTUiIHk9IjEwNiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzhhN2E1MCI+ZGltIGNvbChBKTwvdGV4dD4KPHRleHQgeD0iMTU1IiB5PSIxNDAiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiM0YTQ2NjAiPndoYXQgaXMgbGVmdCBmb3Igc3R1ZHkgdmFyaWFibGVzOjwvdGV4dD4KPHRleHQgeD0iMTU1IiB5PSIxNjAiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTMiIGZvbnQtd2VpZ2h0PSI2MDAiIGZpbGw9IiMzZDM1ODAiPnEgJiM4NzIyOyBkaW0gY29sKEEpPC90ZXh0PgoKPHRleHQgeD0iNDgwIiB5PSI0OCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZm9udC13ZWlnaHQ9IjYwMCIgZmlsbD0iIzNkMzU4MCI+dHdvIHdheXMgb3V0PC90ZXh0Pgo8cmVjdCB4PSIzMjAiIHk9IjYyIiB3aWR0aD0iMzIwIiBoZWlnaHQ9IjQ2IiByeD0iOCIgZmlsbD0iI2ZmZmZmZiIgc3Ryb2tlPSIjOWE5NmE4IiBzdHJva2Utd2lkdGg9IjEuMiIvPgo8dGV4dCB4PSIzMzYiIHk9IjgyIiBmb250LXNpemU9IjExLjUiIGZpbGw9IiMyMDI0MmUiPmEgcmljaGVyIHByZWRpY3RvciBiYXNpcyBlbmxhcmdlcyBxPC90ZXh0Pgo8dGV4dCB4PSIzMzYiIHk9Ijk5IiBmb250LXNpemU9IjExIiBmaWxsPSIjNmI2YTg2Ij50aGUgY2VpbGluZyBtb3ZlcyB1cCwgYW5kIGJpbmRzIGFnYWluIG9uZSB2YXJpYWJsZSBsYXRlcjwvdGV4dD4KPHJlY3QgeD0iMzIwIiB5PSIxMTgiIHdpZHRoPSIzMjAiIGhlaWdodD0iNTYiIHJ4PSI4IiBmaWxsPSIjZWFmNWYwIiBzdHJva2U9IiMxZDllNzUiIHN0cm9rZS13aWR0aD0iMS4zIi8+Cjx0ZXh0IHg9IjMzNiIgeT0iMTM4IiBmb250LXNpemU9IjExLjUiIGZpbGw9IiMxNTUwM2MiPmFkYXB0aXZlIGxlYXJuZXJzLCBvciBjcm9zcy1maXR0aW5nIGFueSBtb2RlbDwvdGV4dD4KPHRleHQgeD0iMzM2IiB5PSIxNTUiIGZvbnQtc2l6ZT0iMTEiIGZpbGw9IiMzZjdhNjQiPnByZWRpY3Rpb25zIHN0b3AgbHlpbmcgaW4gb25lIGZpeGVkIHNwYW4sPC90ZXh0Pgo8dGV4dCB4PSIzMzYiIHk9IjE3MCIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzNmN2E2NCI+c28gdGhlIGNlaWxpbmcgZG9lcyBub3QgYXBwbHkgYXQgYWxsPC90ZXh0Pgo8dGV4dCB4PSIzNDAiIHk9IjIwNiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZm9udC1zdHlsZT0iaXRhbGljIiBmaWxsPSIjOGE4NGE4Ij5GdWxsIHJhbmsgaXMgc3RpbGwgbm90IHRoZSBzYW1lIGFzIHdlbGwgY29uZGl0aW9uZWQuPC90ZXh0Pgo8L3N2Zz4K)

This is not a theoretical caution. It happens on these 1,000 volunteers:
the control totals here are `~ sex + region`, and the working models use
`~ age + sex + region`, so the span has 6 directions, the control totals
take 5, and the ceiling is **K = 1**. Watch the second variable break
it, and watch the two escapes:

``` r

mk <- function(ys, rhs = "~ age + sex + region")
  setNames(lapply(ys, function(v)
    y_model(as.formula(paste(v, rhs)), engine = "glm")), ys)

dev <- function(models, crossfit = NULL) {
  f <- prep(weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
    step_pseudoweight(reference = sr, formula = ~ region + sex + age) |>
    step_model_calibration(x_formula = ~ sex + region, x_totals = cens,
                           models = models, population = sr, crossfit = crossfit),
    warn = FALSE)
  d <- f$steps[[2]]$diagnostics
  max(abs(d$achieved - d$target) / abs(d$target))   # worst constraint, relative
}

signif(c(K1              = dev(mk("income")),
         K2              = dev(mk(c("income", "employed"))),
         K2_crossfit     = dev(mk(c("income", "employed")), crossfit = 3),
         K2_richer_basis = dev(mk(c("income", "employed"),
                                  "~ age + I(age^2) + sex * region"))), 2)
#>              K1              K2     K2_crossfit K2_richer_basis 
#>          0.0000          0.0011          0.0000          0.0000
```

Three of the four close to numerical zero, which is what exact means
here. `K2` does not close at all, and the size of what it leaves on the
table is not arbitrary: the model block is constrained to totals
*estimated* on the reference while the control-total block is
constrained to totals *known* from the census, and the two agree only up
to the reference’s sampling error. That is the shortfall you see.

Four numbers, and they fix the specification for production: **put the
known control totals in the exact-consistency block, give the working
models richer predictors, and cross-fit.** A working model that is
linear in exactly the consistency control totals adds no information and
breaks exactness.

## What sharing costs

Once the system is well conditioned, adding variables to it is cheap.
The price shows up in the dispersion of the weights, not in the control
totals:

``` r

ys <- c("income", "employed", "poor", "retired")
cost <- t(vapply(seq_along(ys), function(k) {
  f <- prep(weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
    step_pseudoweight(reference = sr, formula = ~ region + sex + age) |>
    step_model_calibration(x_formula = ~ sex + region, x_totals = cens,
                           models = mk(ys[seq_len(k)]), population = sr,
                           crossfit = 3), warn = FALSE)
  wk <- f$final_weight
  c(K = k, deff = design_effect(wk)$deff, max_min = max(wk) / min(wk[wk > 0]),
    negatives = sum(wk < 0))
}, numeric(4)))
round(cost, 2)
#>      K deff max_min negatives
#> [1,] 1 1.20    6.45         0
#> [2,] 2 1.26   11.02         0
#> [3,] 3 1.27   12.18         0
#> [4,] 4 1.47   26.71         0
```

Two failure modes end that, and they look nothing alike:

- **Collinearity.** Two learners fitted to strongly correlated outcomes
  give nearly parallel prediction columns. The achieved control totals
  start drifting from their targets and the package raises an
  ill-conditioning warning. Cross-fitting repairs this one.
- **Feasibility.** The control totals keep closing to numerical
  precision while units start receiving *negative* weights and the
  weight range grows by orders of magnitude. Nothing in the
  control-total diagnostics moves, and the design effect stops being
  readable as an effective sample size once negatives appear. Bounding
  the calibration repairs this one; cross-fitting does not.

So monitor the **negative count** and the **weight range** next to the
deviation from the control totals, and treat the first negative weight
as the stopping signal. Bounded calibration together with cross-fitting
is the production default.

## What the reference contributes

Now the arm we set up at the start. Same recipe, same draws, same point
weights; the only difference is whether the reference enters the
bootstrap with its replicates or with its design weights alone.

``` r

sr_fixed <- reference_sample(ref, weights = "d")          # no replicates
spec_fixed <- weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
  step_pseudoweight(reference = sr_fixed, formula = ~ region + sex + age) |>
  step_model_calibration(x_formula = ~ sex + region, x_totals = cens,
                         models = mk(c("income", "employed")),
                         population = sr_fixed, crossfit = 3)

b_full  <- bootstrap_weights(spec,       replicates = 20, seed = 2, progress = FALSE)
b_fixed <- bootstrap_weights(spec_fixed, replicates = 20, seed = 2, progress = FALSE)

c(reference_resampled = boot_mean(b_full,  "income")$se,
  reference_fixed     = boot_mean(b_fixed, "income")$se)
#> reference_resampled     reference_fixed 
#>            404.8120            321.6691
```

The point estimates are identical, because it is the same weight column.
Only the standard error moves, and it moves in one direction: holding
the reference fixed can only make the interval narrower, because a
source of variability has been dropped rather than estimated.

How much narrower depends on how much of the total uncertainty the
reference carries. On real household-survey structure with a reference
of 800 against 1,500 volunteers, the published study behind this
construction measures the estimated standard error divided by up to
**3.7**, taking a nominal 95% interval down to **42%** coverage.
Sampling error in an estimated target does not announce itself as an
unmet constraint, which is where an office would look for it.

[`bootstrap_weights()`](https://jpferreira33.github.io/weightflow/reference/bootstrap_weights.md)
now says so when the replicates are missing, and
[`jackknife_weights()`](https://jpferreira33.github.io/weightflow/reference/jackknife_weights.md)
says something stronger: a delete-one replicate has no reference
replicate to pair with, so it holds the reference fixed whatever you
pass. For this construction, use the bootstrap.

## Dissemination

The replicate weights are the deliverable, not just the point column.
For a non-probability source they are the only way a secondary user can
attach a standard error to an estimate the office never published.

``` r

out <- collect_replicate_weights(b_full, scramble = TRUE)
c(rows = nrow(out), columns = ncol(out))
#>    rows columns 
#>    1026      32
names(out)[1:4]
#> [1] "person_id"    "household_id" "psu"          "region"
```

`scramble = TRUE` permutes the replicate columns so the file cannot be
used to reconstruct the resampling pattern, which is a disclosure
channel in a clustered design.

## How large is this sample, really?

A big opt-in sample can carry a small *effective* one.
[`data_defect()`](https://jpferreira33.github.io/weightflow/reference/data_defect.md)
gives the Meng (2018) view: the error is governed by the correlation
between the outcome and participation, not by the raw count. That
correlation is not observable from the sample, so the answer is a range,
not a number.

``` r

data_defect(pw_only)
#> Data-defect diagnostics (non-probability sample)
#>   n = 1,026   N = 4,520   f = 0.2270
#>   strongest covariate-participation correlation: |r| = 0.226 (sexM)
#>   effective size by residual data-defect correlation (Meng 2018):
#>     |rho| = 0.001  ->  n_eff = 293,680  (*)
#>     |rho| = 0.005  ->  n_eff = 11,747  (*)
#>     |rho| = 0.010  ->  n_eff = 2,937  (*)
#>     |rho| = 0.050  ->  n_eff = 117
#>     |rho| = 0.100  ->  n_eff = 29
#>   (rho on the target variable is not observable; read as an ignorance range)
#>   (*) below |rho| = 0.0149 = 1/sqrt(N), the defect a simple random
#>       sample of this population shows by itself: those rows describe a
#>       sample more representative than a random one, so read them as a
#>       ceiling the formula allows and the design cannot reach.
```

## Hold something out, because the weights cannot see selection bias

Double robustness protects against a misspecified model **given**
ignorability, not against its failure. If participation depends on
something no model observes, every estimator here is biased, and the
weights will not tell you. Watch: participation now depends on income,
which appears in no model and in no control total.

``` r

set.seed(2)
z   <- as.numeric(scale(pop$income))                 # the driver nothing observes
t2  <- runif(N) < plogis(-1.6 + 0.8 * z)
v2  <- pop[t2, ]
r2  <- pop[sample(which(!t2), 800), c("region", "sex", "age")]; r2$d <- N / 800
sr2 <- reference_sample(r2, weights = "d")

f2 <- prep(weighting_spec(v2, base_weights = NULL, nonprob = TRUE) |>
  step_pseudoweight(reference = sr2, formula = ~ sex + age) |>
  step_model_calibration(x_formula = ~ sex,
                         x_totals = list(sex = as.data.frame(table(sex = pop$sex))),
                         models = list(income = y_model(income ~ sex + age)),
                         population = sr2, crossfit = 3), warn = FALSE)

w2 <- f2$final_weight; d2 <- f2$steps[[2]]$diagnostics
c(max_total_deviation = max(abs(d2$achieved - d2$target)),
  negative_weights    = sum(w2 < 0),
  design_effect       = round(design_effect(w2)$deff, 2))
#> max_total_deviation    negative_weights       design_effect 
#>                0.00                0.00                1.01
```

The control totals are met exactly, no unit gets a negative weight, and
the design effect is unremarkable. Nothing in that line is wrong and
nothing in it warns you, which is structural rather than a shortcoming
of these particular statistics: a diagnostic built from the weights and
the covariates behind them cannot detect a dependence on a variable
absent from both.

A quantity the adjustment was **never asked to reproduce** can. Here
`region` is in no model and in no control total, and its population
distribution is known:

``` r

round(100 * (as.numeric(tapply(w2, v2$region, sum)) /
             as.numeric(table(pop$region)) - 1), 1)
#> [1]  29.9  -9.0 -35.5  -3.8
```

Tens of per cent off, on a figure the weighted file should have
reproduced for free. Reserving one known population quantity as a
held-out benchmark is the cheapest protection available; the data-defect
range above is another. Holding a control total out in order to test
against it costs precision there, and the alternative is a weight whose
only evidence of validity is that it reproduces what it was told to
reproduce.

## The whole thing

``` r

sr   <- reference_sample(ref, weights = "d", replicates = rep_ref)
spec <- weighting_spec(volunteers, base_weights = NULL, nonprob = TRUE) |>
  step_pseudoweight(reference = sr, formula = ~ age + sex + region,
                    engine = "forest") |>
  step_model_calibration(
    x_formula = ~ age + sex, x_totals = census_totals,
    models = list(
      poverty  = y_model(poverty  ~ age + sex + region + size, engine = "forest"),
      employed = y_model(employed ~ age + sex + region + size, engine = "boost")),
    population = sr, crossfit = 3)

w    <- prep(spec)$final_weight
boot <- bootstrap_weights(spec, replicates = 200)
out  <- collect_replicate_weights(boot, scramble = TRUE)
```

Seven calls: one weight column, doubly robust, exact on the census
control totals, with replicate weights that propagate the participation
model, the K working models and the reference’s own sampling.

## In short

1.  Read the sum of the pseudo-weights against the estimated population,
    to three significant figures, **before** any calibration. It is the
    only point at which the construction is still visible.
2.  Put the known control totals in the consistency block; give the
    working models richer predictors and let the learner supply the
    non-linearity.
3.  Cross-fit whenever a model is an adaptive learner. It protects
    coverage and it raises the number of variables one weight can carry.
4.  Watch the negative count and the weight range, not only the
    deviation from the control totals. The first negative weight is the
    stopping signal.
5.  Treat the size of the reference as part of the specification, and
    pass its replicate weights, or state that you did not.
6.  Report the replication-bootstrap variance, never a fixed-total
    formula.
7.  Hold one known population quantity out of the adjustment and test
    against it. No diagnostic computed on the weights can do that job.
8.  Disseminate the replicate weights with the microdata.

## References

Elliott, M. R. and Valliant, R. (2017). Inference for non-probability
samples. *Statistical Science* 32(2), 249-264.

Ferreira, J. P. (2026). Two silent decisions in weighting an opt-in
sample against a probability reference sample. *Survey Practice*.
<doi:10.29115/SP-2026-0052>

Ferreira, J. P. (2026). One weight for many variables: why multipurpose
calibration of non-probability samples needs flexible working models,
and what sharing it costs. *Statistical Journal of the IAOS*, accepted.

Ferreira, J. P. (2026). weightflow: reproducible, recipe-aware survey
weighting for official statistics in R. *Statistical Journal of the
IAOS*, advance online. <doi:10.1177/18747455261484262>

Meng, X.-L. (2018). Statistical paradises and paradoxes in big data (I).
*Annals of Applied Statistics* 12(2), 685-726.

Wang, L., Valliant, R. and Li, Y. (2021). Adjusted logistic propensity
weighting methods for population inference using nonprobability
volunteer-based epidemiologic cohorts. *Statistics in Medicine* 40(24),
5237-5250.

Wu, C. and Sitter, R. R. (2001). A model-calibration approach to using
complete auxiliary information from survey data. *JASA* 96(453),
185-193.
