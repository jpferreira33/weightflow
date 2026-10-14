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
margins, that serves every study variable at once – and the replicate
weights that let a user attach a standard error to it. It also shows
where the construction stops working, and how the package tells you.

## The two files

Nothing here is possible without a probability **reference**: a survey
that measures the same auxiliaries as the volunteers and carries real
design weights. The two files are complementary, and neither is
sufficient alone.

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwJSIgdmlld2JveD0iMCAwIDY4MCAzMjAiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwmIzM5O0ludGVyJiMzOTssU2Vnb2UgVUksUm9ib3RvLHNhbnMtc2VyaWY7Ij48dGl0bGU+ClRoZSB2b2x1bnRlZXIgZmlsZSBhbmQgdGhlIHByb2JhYmlsaXR5IHJlZmVyZW5jZQo8L3RpdGxlPgo8cD48ZGVzYz5UaGUgdm9sdW50ZWVyIGZpbGUgcmVjb3JkcyB0aGUgYXV4aWxpYXJpZXMgeCBhbmQgdGhlIHN0dWR5CnZhcmlhYmxlcyB5IGJ1dCBoYXMgbm8gd2VpZ2h0IGNvbHVtbi4gVGhlIHByb2JhYmlsaXR5IHJlZmVyZW5jZSByZWNvcmRzCnRoZSBzYW1lIGF1eGlsaWFyaWVzIHggYW5kIGNhcnJpZXMgZGVzaWduIHdlaWdodHMgZCwgYnV0IG5vdCB0aGUgc3R1ZHkKdmFyaWFibGVzLiBUaGUgY29uc3RydWN0aW9uIGZpbGxzIHRoZSBtaXNzaW5nIHdlaWdodCBjb2x1bW4gb24gdGhlCnZvbHVudGVlciBmaWxlIHdpdGggYSBzaW5nbGUgY29sdW1uIHVzZWQgZm9yIGV2ZXJ5IHN0dWR5CnZhcmlhYmxlLjwvZGVzYz48ZGVmcz48bWFya2VyIGlkPSJucDEiIHZpZXdib3g9IjAgMCAxMCAxMCIgcmVmeD0iOCIgcmVmeT0iNSIgbWFya2Vyd2lkdGg9IjciIG1hcmtlcmhlaWdodD0iNyIgb3JpZW50PSJhdXRvLXN0YXJ0LXJldmVyc2UiPjxwYXRoIGQ9Ik0yIDFMOCA1TDIgOSIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuOCIgLz48L21hcmtlcj48L2RlZnM+PC9wPgo8cD48dGV4dCB4PSIxNTAiIHk9IjI2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmb250LXdlaWdodD0iNjAwIiBmaWxsPSIjM2QzNTgwIj52b2x1bnRlZXIKZmlsZTwvdGV4dD48cmVjdCB4PSI0MCIgeT0iMzgiIHdpZHRoPSIyMjAiIGhlaWdodD0iMTA0IiByeD0iOCIgZmlsbD0iI2Y0ZjJmYiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuMyIgLz48cmVjdCB4PSI0MCIgeT0iMzgiIHdpZHRoPSIyMjAiIGhlaWdodD0iMjYiIHJ4PSI4IiBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS4zIiAvPjx0ZXh0IHg9Ijc2IiB5PSI1NiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZm9udC1mYW1pbHk9IiYjMzk7SmV0QnJhaW5zIE1vbm8mIzM5Oyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjM2QzNTgwIj54PC90ZXh0Pjx0ZXh0IHg9IjE1MCIgeT0iNTYiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSImIzM5O0pldEJyYWlucyBNb25vJiMzOTssdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzNkMzU4MCI+eTEK4oCmIHlLPC90ZXh0Pjx0ZXh0IHg9IjIyOCIgeT0iNTYiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSImIzM5O0pldEJyYWlucyBNb25vJiMzOTssdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzhhODRhOCI+dzwvdGV4dD48bGluZSB4MT0iMTEzIiB5MT0iMzgiIHgyPSIxMTMiIHkyPSIxNDIiIHN0cm9rZT0iI2M2YmVmNCIgc3Ryb2tlLXdpZHRoPSIxIj48L2xpbmU+PGxpbmUgeDE9IjE5NiIgeTE9IjM4IiB4Mj0iMTk2IiB5Mj0iMTQyIiBzdHJva2U9IiNjNmJlZjQiIHN0cm9rZS13aWR0aD0iMSI+PC9saW5lPjxyZWN0IHg9IjE5NiIgeT0iNjQiIHdpZHRoPSI2NCIgaGVpZ2h0PSI3OCIgZmlsbD0iI2ZkZjZlOCIgc3Ryb2tlPSIjYzk5MDJhIiBzdHJva2Utd2lkdGg9IjEuMyIgc3Ryb2tlLWRhc2hhcnJheT0iNCAzIiAvPjx0ZXh0IHg9IjIyOCIgeT0iMTA4IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjIyIiBmaWxsPSIjYzk5MDJhIj4/PC90ZXh0Pjx0ZXh0IHg9Ijc2IiB5PSI4NiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzZiNmE4NiI+YWdlCnNleDwvdGV4dD48dGV4dCB4PSI3NiIgeT0iMTA0IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjNmI2YTg2Ij5yZWdpb248L3RleHQ+PHRleHQgeD0iMTUwIiB5PSI4NiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzZiNmE4NiI+aW5jb21lPC90ZXh0Pjx0ZXh0IHg9IjE1MCIgeT0iMTA0IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjNmI2YTg2Ij5lbXBsb3llZDwvdGV4dD48dGV4dCB4PSIxNTAiIHk9IjEyMiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzZiNmE4NiI+4oCmPC90ZXh0PjwvcD4KPHA+PHRleHQgeD0iNTMwIiB5PSIyNiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZm9udC13ZWlnaHQ9IjYwMCIgZmlsbD0iIzNkMzU4MCI+cHJvYmFiaWxpdHkKcmVmZXJlbmNlPC90ZXh0PjxyZWN0IHg9IjQyMCIgeT0iMzgiIHdpZHRoPSIyMjAiIGhlaWdodD0iMTA0IiByeD0iOCIgZmlsbD0iI2Y0ZjJmYiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuMyIgLz48cmVjdCB4PSI0MjAiIHk9IjM4IiB3aWR0aD0iMjIwIiBoZWlnaHQ9IjI2IiByeD0iOCIgZmlsbD0iI2VjZTlmNiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuMyIgLz48dGV4dCB4PSI0NTYiIHk9IjU2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJiMzOTtKZXRCcmFpbnMgTW9ubyYjMzk7LHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiMzZDM1ODAiPng8L3RleHQ+PHRleHQgeD0iNTMwIiB5PSI1NiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZm9udC1mYW1pbHk9IiYjMzk7SmV0QnJhaW5zIE1vbm8mIzM5Oyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjOGE4NGE4Ij55MQrigKYgeUs8L3RleHQ+PHRleHQgeD0iNjA4IiB5PSI1NiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZm9udC1mYW1pbHk9IiYjMzk7SmV0QnJhaW5zIE1vbm8mIzM5Oyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjM2QzNTgwIj5kPC90ZXh0PjxsaW5lIHgxPSI0OTMiIHkxPSIzOCIgeDI9IjQ5MyIgeTI9IjE0MiIgc3Ryb2tlPSIjYzZiZWY0IiBzdHJva2Utd2lkdGg9IjEiPjwvbGluZT48bGluZSB4MT0iNTc2IiB5MT0iMzgiIHgyPSI1NzYiIHkyPSIxNDIiIHN0cm9rZT0iI2M2YmVmNCIgc3Ryb2tlLXdpZHRoPSIxIj48L2xpbmU+PHJlY3QgeD0iNDkzIiB5PSI2NCIgd2lkdGg9IjgzIiBoZWlnaHQ9Ijc4IiBmaWxsPSIjZjNmM2Y1IiBzdHJva2U9IiM5YTk2YTgiIHN0cm9rZS13aWR0aD0iMS4zIiBzdHJva2UtZGFzaGFycmF5PSI0IDMiIC8+PHRleHQgeD0iNTM0IiB5PSIxMDkiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTgiIGZpbGw9IiM5YTk2YTgiPuKAlDwvdGV4dD48dGV4dCB4PSI0NTYiIHk9Ijg2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjNmI2YTg2Ij5hZ2UKc2V4PC90ZXh0Pjx0ZXh0IHg9IjQ1NiIgeT0iMTA0IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjNmI2YTg2Ij5yZWdpb248L3RleHQ+PHRleHQgeD0iNjA4IiB5PSI4OSIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzZiNmE4NiI+a25vd24KYnk8L3RleHQ+PHRleHQgeD0iNjA4IiB5PSIxMDUiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTEiIGZpbGw9IiM2YjZhODYiPmRlc2lnbjwvdGV4dD48L3A+CjxsaW5lIHgxPSIxNTAiIHkxPSIxNTAiIHgyPSIzMDAiIHkyPSIxOTYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjUiIG1hcmtlci1lbmQ9InVybCgjbnAxKSI+PC9saW5lPjxsaW5lIHgxPSI1MzAiIHkxPSIxNTAiIHgyPSIzODAiIHkyPSIxOTYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjUiIG1hcmtlci1lbmQ9InVybCgjbnAxKSI+PC9saW5lPjxyZWN0IHg9IjIxNSIgeT0iMjA0IiB3aWR0aD0iMjUwIiBoZWlnaHQ9IjQ0IiByeD0iMTAiIGZpbGw9IiMzZDM1ODAiIC8+PHRleHQgeD0iMzQwIiB5PSIyMzEiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTQiIGZpbGw9IiNmZmZmZmYiPm9uZQp3ZWlnaHQgY29sdW1uPC90ZXh0Pjx0ZXh0IHg9IjM0MCIgeT0iMjcyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmaWxsPSIjNGE0NjYwIj5leGFjdApvbiB0aGUga25vd24gbWFyZ2lucywgZG91Ymx5IHJvYnVzdCw8L3RleHQ+PHRleHQgeD0iMzQwIiB5PSIyOTAiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiM0YTQ2NjAiPnVzZWQKZm9yIGV2ZXJ5IHN0dWR5IHZhcmlhYmxlPC90ZXh0Pjx0ZXh0IHg9IjM0MCIgeT0iMzEyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmb250LXN0eWxlPSJpdGFsaWMiIGZpbGw9IiM4YTg0YTgiPkEKZGFzaGVkIGNlbGwgaXMgbm90IG1lYXN1cmVkIG9uIHRoYXQgZmlsZS48L3RleHQ+PC9zdmc+)

## A volunteer sample that is wrong in four different ways

We draw volunteers from the bundled `population` so that men and the
young over-participate, and we track four indicators of very different
character: a mean, a proportion, a **rare** proportion, and one that the
selection hits head on. None of them is used to decide who volunteers –
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

The unweighted file is not uniformly wrong – it is wrong by different
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
The margins close to numerical precision either way, no weight looks
odd, and the interval looks reasonable.

The sum of the pseudo-weights separates them, because each construction
leaves a different arithmetic trace:

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwJSIgdmlld2JveD0iMCAwIDY4MCAyMzIiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwmIzM5O0ludGVyJiMzOTssU2Vnb2UgVUksUm9ib3RvLHNhbnMtc2VyaWY7Ij48dGl0bGU+ClRocmVlIHdheXMgdG8gdHVybiBvbmUgZml0dGVkIHNjb3JlIGludG8gYSB3ZWlnaHQsIGFuZCB0aGUgdHJhY2UgZWFjaApsZWF2ZXMKPC90aXRsZT4KPHA+PGRlc2M+VGhlIGNvcnJlY3QgY29uc3RydWN0aW9uIHVzZXMgdGhlIG9kZHMgd2l0aCBhIGRlc2lnbi13ZWlnaHRlZApyZWZlcmVuY2UgYW5kIGl0cyBwc2V1ZG8td2VpZ2h0cyBzdW0gdG8gdGhlIGVzdGltYXRlZCBwb3B1bGF0aW9uIHNpemUuClVzaW5nIHRoZSBwbGFpbiBpbnZlcnNlIGFkZHMgb25lIHVuaXQgb2Ygd2VpZ2h0IHBlciB2b2x1bnRlZXIsIHNvIHRoZQpzdW0gb3ZlcnNob290cyBieSB0aGUgdm9sdW50ZWVyIHNoYXJlIG9mIHRoZSBwb3B1bGF0aW9uLiBFbnRlcmluZyB0aGUKcmVmZXJlbmNlIGF0IHdlaWdodCBvbmUgcmVzY2FsZXMgdGhlIHdlaWdodHMgYnkgdGhlIHJlZmVyZW5jZeKAmXMgb3duCnNhbXBsaW5nIGZyYWN0aW9uLCBzbyB0aGUgc3VtIGNvbGxhcHNlcyB0b3dhcmRzIHRoYXQgZnJhY3Rpb24uPC9kZXNjPjxyZWN0IHg9IjE2IiB5PSIyMiIgd2lkdGg9IjIwNiIgaGVpZ2h0PSIxNTAiIHJ4PSIxMCIgZmlsbD0iI2VhZjVmMCIgc3Ryb2tlPSIjMWQ5ZTc1IiBzdHJva2Utd2lkdGg9IjEuNSIgLz48dGV4dCB4PSIxMTkiIHk9IjQ0IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmb250LXdlaWdodD0iNjAwIiBmaWxsPSIjMTU1MDNjIj5DT1JSRUNUPC90ZXh0Pjx0ZXh0IHg9IjExOSIgeT0iNjYiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTMiIGZpbGw9IiMyMDI0MmUiPnRoZQpvZGRzPC90ZXh0Pjx0ZXh0IHg9IjExOSIgeT0iOTIiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTMiIGZvbnQtZmFtaWx5PSImIzM5O0pldEJyYWlucyBNb25vJiMzOTssdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzE1NTAzYyI+KDEKLSBwKSAvIHA8L3RleHQ+PHRleHQgeD0iMTE5IiB5PSIxMTMiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTEiIGZpbGw9IiMzZjdhNjQiPmRlc2lnbi13ZWlnaHRlZApyZWZlcmVuY2U8L3RleHQ+PHJlY3QgeD0iMzYiIHk9IjEyOCIgd2lkdGg9IjE2NiIgaGVpZ2h0PSIzMCIgcng9IjYiIGZpbGw9IiNmZmZmZmYiIHN0cm9rZT0iIzFkOWU3NSIgc3Ryb2tlLXdpZHRoPSIxLjIiIC8+PHRleHQgeD0iMTE5IiB5PSIxNDgiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSImIzM5O0pldEJyYWlucyBNb25vJiMzOTssdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzE1NTAzYyI+zqN3Ci8gTsyCID0gMTwvdGV4dD48L3A+CjxwPjxyZWN0IHg9IjIzNyIgeT0iMjIiIHdpZHRoPSIyMDYiIGhlaWdodD0iMTUwIiByeD0iMTAiIGZpbGw9IiNmZGY2ZTgiIHN0cm9rZT0iI2M5OTAyYSIgc3Ryb2tlLXdpZHRoPSIxLjUiIC8+PHRleHQgeD0iMzQwIiB5PSI0NCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZm9udC13ZWlnaHQ9IjYwMCIgZmlsbD0iIzhhNjQxNCI+UVVJRVQKRVJST1I8L3RleHQ+PHRleHQgeD0iMzQwIiB5PSI2NiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZmlsbD0iIzIwMjQyZSI+dGhlCnBsYWluIGludmVyc2U8L3RleHQ+PHRleHQgeD0iMzQwIiB5PSI5MiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IiYjMzk7SmV0QnJhaW5zIE1vbm8mIzM5Oyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjOGE2NDE0Ij4xCi8gcDwvdGV4dD48dGV4dCB4PSIzNDAiIHk9IjExMyIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzhhN2E1MCI+b25lCmV4dHJhIHVuaXQgb2Ygd2VpZ2h0IGVhY2g8L3RleHQ+PHJlY3QgeD0iMjU3IiB5PSIxMjgiIHdpZHRoPSIxNjYiIGhlaWdodD0iMzAiIHJ4PSI2IiBmaWxsPSIjZmZmZmZmIiBzdHJva2U9IiNjOTkwMmEiIHN0cm9rZS13aWR0aD0iMS4yIiAvPjx0ZXh0IHg9IjM0MCIgeT0iMTQ4IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJiMzOTtKZXRCcmFpbnMgTW9ubyYjMzk7LHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiM4YTY0MTQiPs6jdwovIE7MgiA9IDEgKyBu4bWlL048L3RleHQ+PC9wPgo8cD48cmVjdCB4PSI0NTgiIHk9IjIyIiB3aWR0aD0iMjA2IiBoZWlnaHQ9IjE1MCIgcng9IjEwIiBmaWxsPSIjZmJlY2ViIiBzdHJva2U9IiNjMDQ5MmYiIHN0cm9rZS13aWR0aD0iMS41IiAvPjx0ZXh0IHg9IjU2MSIgeT0iNDQiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTEiIGZvbnQtd2VpZ2h0PSI2MDAiIGZpbGw9IiM4YzJmMWMiPkxPVUQKRVJST1I8L3RleHQ+PHRleHQgeD0iNTYxIiB5PSI2NiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZmlsbD0iIzIwMjQyZSI+cmVmZXJlbmNlCmF0IHdlaWdodCBvbmU8L3RleHQ+PHRleHQgeD0iNTYxIiB5PSI5MiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IiYjMzk7SmV0QnJhaW5zIE1vbm8mIzM5Oyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjOGMyZjFjIj4oMQotIHApIC8gcDwvdGV4dD48dGV4dCB4PSI1NjEiIHk9IjExMyIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzlhNWE0OCI+c2NhbGVkCmJ5IHRoZSByZWZlcmVuY2XigJlzIG93biBmcmFjdGlvbjwvdGV4dD48cmVjdCB4PSI0NzgiIHk9IjEyOCIgd2lkdGg9IjE2NiIgaGVpZ2h0PSIzMCIgcng9IjYiIGZpbGw9IiNmZmZmZmYiIHN0cm9rZT0iI2MwNDkyZiIgc3Ryb2tlLXdpZHRoPSIxLjIiIC8+PHRleHQgeD0iNTYxIiB5PSIxNDgiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSImIzM5O0pldEJyYWlucyBNb25vJiMzOTssdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzhjMmYxYyI+zqN3Ci8gTsyCID0gbuG1oy9OPC90ZXh0PjwvcD4KPHRleHQgeD0iMzQwIiB5PSIxOTYiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiM0YTQ2NjAiPkVhY2gKdHJhY2UgaXMgYSBwcm9wZXJ0eSBvZiB0aGUgc3RhY2tpbmcsIG5vdCBhIHNpbXVsYXRpb24gcmVzdWx0LjwvdGV4dD48dGV4dCB4PSIzNDAiIHk9IjIxOCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZm9udC1zdHlsZT0iaXRhbGljIiBmaWxsPSIjOGE4NGE4Ij5BbmQKZWFjaCBpcyBnb25lIGFmdGVyIGEgY2FsaWJyYXRpb246IHRoZSBtYXJnaW4gYmxvY2sgaW1wb3NlcyB0aGUKcG9wdWxhdGlvbiB0b3RhbCB3aGljaGV2ZXIgY29uc3RydWN0aW9uIHByb2R1Y2VkIHRoZSB3ZWlnaHRzLjwvdGV4dD48L3N2Zz4=)

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
significant figures and before any calibration**: afterwards the margin
block imposes the population total and all three look identical.
weightflow builds the first construction, and the ratio is in the step’s
diagnostics.

The distortion from stacking the reference at weight one disappears when
the reference is self-weighting, or when the calibration margins happen
to span its design strata – so the louder mistake is the one a later
step can absorb, and the quieter one is not.

Flexible learners are available for the participation model –
`engine = "tree"`, `"forest"`, `"boost"`, with `crossfit` – exactly as
for response propensities.

## Step two: one calibration that carries every variable

The pseudo-weight alone is consistent if the participation model is
right. A calibration is consistent if the working model for the outcome
is right. Doing both is doubly robust: correct if **either** holds.

The move that keeps it one column is to put all K study variables into
the *same* linear calibration system. Each gets its own working model –
its own predictors, its own learner – and the predictions enter as
columns of one stacked matrix alongside the known margins. One system,
one solution, one weight.

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwJSIgdmlld2JveD0iMCAwIDY4MCAzNTgiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwmIzM5O0ludGVyJiMzOTssU2Vnb2UgVUksUm9ib3RvLHNhbnMtc2VyaWY7Ij48dGl0bGU+ClRoZSBtdWx0aXB1cnBvc2UgZG91Ymx5IHJvYnVzdCB3ZWlnaHQgYXMgYSBzaW5nbGUgcmVjaXBlCjwvdGl0bGU+CjxwPjxkZXNjPlRoZSB2b2x1bnRlZXIgYW5kIHJlZmVyZW5jZSBmaWxlcyBmZWVkIGEgcGFydGljaXBhdGlvbiBtb2RlbAp0aGF0IHByb2R1Y2VzIHRoZSBwc2V1ZG8td2VpZ2h0LiBLIHdvcmtpbmcgbW9kZWxzLCBvbmUgcGVyIHN0dWR5CnZhcmlhYmxlLCBwcm9kdWNlIHByZWRpY3Rpb24gY29sdW1ucyB0aGF0IGFyZSBzdGFja2VkIHdpdGggdGhlIGtub3duCnBvcHVsYXRpb24gbWFyZ2lucyBpbnRvIG9uZSBsaW5lYXIgY2FsaWJyYXRpb24uIFRoZSBjYWxpYnJhdGlvbiByZXR1cm5zCmEgc2luZ2xlIHdlaWdodCBjb2x1bW4gdXNlZCBmb3IgZXZlcnkgaW5kaWNhdG9yLiBBIGJhbmQgdW5kZXJuZWF0aCBzaG93cwp0aGF0IHRoZSByZXBsaWNhdGlvbiBib290c3RyYXAgcmUtZXhlY3V0ZXMgZXZlcnkgc3RlcCBvbiBlYWNoIHJlcGxpY2F0ZSwKaW5jbHVkaW5nIHRoZSByZWZlcmVuY2UgcmVwbGljYXRlcy48L2Rlc2M+PGRlZnM+PG1hcmtlciBpZD0ibnAyIiB2aWV3Ym94PSIwIDAgMTAgMTAiIHJlZng9IjgiIHJlZnk9IjUiIG1hcmtlcndpZHRoPSI3IiBtYXJrZXJoZWlnaHQ9IjciIG9yaWVudD0iYXV0by1zdGFydC1yZXZlcnNlIj48cGF0aCBkPSJNMiAxTDggNUwyIDkiIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjgiIC8+PC9tYXJrZXI+PC9kZWZzPjwvcD4KPHA+PHJlY3QgeD0iMjQiIHk9IjQwIiB3aWR0aD0iMTIwIiBoZWlnaHQ9IjM0IiByeD0iOCIgZmlsbD0iI2VjZTlmNiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuMyIgLz48dGV4dCB4PSI4NCIgeT0iNjIiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiMyMDI0MmUiPnZvbHVudGVlcnM8L3RleHQ+PHJlY3QgeD0iMjQiIHk9Ijg2IiB3aWR0aD0iMTIwIiBoZWlnaHQ9IjM0IiByeD0iOCIgZmlsbD0iI2VjZTlmNiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuMyIgLz48dGV4dCB4PSI4NCIgeT0iMTA4IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmaWxsPSIjMjAyNDJlIj5yZWZlcmVuY2UKKyBkPC90ZXh0PjwvcD4KPHA+PGxpbmUgeDE9IjE0OCIgeTE9IjU3IiB4Mj0iMTk2IiB5Mj0iNzAiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjUiIG1hcmtlci1lbmQ9InVybCgjbnAyKSI+PC9saW5lPjxsaW5lIHgxPSIxNDgiIHkxPSIxMDMiIHgyPSIxOTYiIHkyPSI4OCIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNucDIpIj48L2xpbmU+PHJlY3QgeD0iMjAwIiB5PSI1NiIgd2lkdGg9IjE1MCIgaGVpZ2h0PSI0NCIgcng9IjgiIGZpbGw9IiNmNGYyZmIiIHN0cm9rZT0iIzUzNGFiNyIgc3Ryb2tlLXdpZHRoPSIxLjQiIC8+PHRleHQgeD0iMjc1IiB5PSI3NCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzIwMjQyZSI+cGFydGljaXBhdGlvbgptb2RlbDwvdGV4dD48dGV4dCB4PSIyNzUiIHk9IjkxIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmb250LWZhbWlseT0iJiMzOTtKZXRCcmFpbnMgTW9ubyYjMzk7LHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiM1MzRhYjciPigxCi0gcCkgLyBwPC90ZXh0PjwvcD4KPHA+PHJlY3QgeD0iMjAwIiB5PSIxMzIiIHdpZHRoPSIxNTAiIGhlaWdodD0iMjYiIHJ4PSI2IiBmaWxsPSIjZWFmNWYwIiBzdHJva2U9IiMxZDllNzUiIHN0cm9rZS13aWR0aD0iMS4yIiAvPjx0ZXh0IHg9IjI3NSIgeT0iMTUwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjMTU1MDNjIj55MQrihpIgbGVhcm5lciAxPC90ZXh0PjxyZWN0IHg9IjIwMCIgeT0iMTY0IiB3aWR0aD0iMTUwIiBoZWlnaHQ9IjI2IiByeD0iNiIgZmlsbD0iI2VhZjVmMCIgc3Ryb2tlPSIjMWQ5ZTc1IiBzdHJva2Utd2lkdGg9IjEuMiIgLz48dGV4dCB4PSIyNzUiIHk9IjE4MiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzE1NTAzYyI+eTIK4oaSIGxlYXJuZXIgMjwvdGV4dD48cmVjdCB4PSIyMDAiIHk9IjE5NiIgd2lkdGg9IjE1MCIgaGVpZ2h0PSIyNiIgcng9IjYiIGZpbGw9IiNlYWY1ZjAiIHN0cm9rZT0iIzFkOWU3NSIgc3Ryb2tlLXdpZHRoPSIxLjIiIC8+PHRleHQgeD0iMjc1IiB5PSIyMTQiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTEiIGZpbGw9IiMxNTUwM2MiPnlLCuKGkiBsZWFybmVyIEs8L3RleHQ+PHJlY3QgeD0iMjAwIiB5PSIyMzIiIHdpZHRoPSIxNTAiIGhlaWdodD0iMjYiIHJ4PSI2IiBmaWxsPSIjZmRmNmU4IiBzdHJva2U9IiNjOTkwMmEiIHN0cm9rZS13aWR0aD0iMS4yIiAvPjx0ZXh0IHg9IjI3NSIgeT0iMjUwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjExIiBmaWxsPSIjNWM0NDEwIj5rbm93bgptYXJnaW5zPC90ZXh0PjwvcD4KPHA+PGxpbmUgeDE9IjM1NCIgeTE9Ijc4IiB4Mj0iNDAyIiB5Mj0iMTQwIiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS41IiBtYXJrZXItZW5kPSJ1cmwoI25wMikiPjwvbGluZT48bGluZSB4MT0iMzU0IiB5MT0iMTQ1IiB4Mj0iNDAyIiB5Mj0iMTY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS41IiBtYXJrZXItZW5kPSJ1cmwoI25wMikiPjwvbGluZT48bGluZSB4MT0iMzU0IiB5MT0iMTc3IiB4Mj0iNDAyIiB5Mj0iMTgwIiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS41IiBtYXJrZXItZW5kPSJ1cmwoI25wMikiPjwvbGluZT48bGluZSB4MT0iMzU0IiB5MT0iMjA5IiB4Mj0iNDAyIiB5Mj0iMTk0IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS41IiBtYXJrZXItZW5kPSJ1cmwoI25wMikiPjwvbGluZT48bGluZSB4MT0iMzU0IiB5MT0iMjQ1IiB4Mj0iNDAyIiB5Mj0iMjA4IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS41IiBtYXJrZXItZW5kPSJ1cmwoI25wMikiPjwvbGluZT48L3A+CjxwPjxyZWN0IHg9IjQwNiIgeT0iMTQwIiB3aWR0aD0iMTM2IiBoZWlnaHQ9IjY4IiByeD0iOCIgZmlsbD0iI2Y0ZjJmYiIgc3Ryb2tlPSIjNTM0YWI3IiBzdHJva2Utd2lkdGg9IjEuNCIgLz48dGV4dCB4PSI0NzQiIHk9IjE2NiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzIwMjQyZSI+b25lCnN0YWNrZWQ8L3RleHQ+PHRleHQgeD0iNDc0IiB5PSIxODQiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiMyMDI0MmUiPmNhbGlicmF0aW9uPC90ZXh0Pjx0ZXh0IHg9IjQ3NCIgeT0iMjAwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEwIiBmaWxsPSIjNmI2YTg2Ij5zb2x2ZWQKb25jZTwvdGV4dD48L3A+CjxwPjxsaW5lIHgxPSI1NDYiIHkxPSIxNzQiIHgyPSI1ODYiIHkyPSIxNzQiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjUiIG1hcmtlci1lbmQ9InVybCgjbnAyKSI+PC9saW5lPjxyZWN0IHg9IjU5MCIgeT0iMTM0IiB3aWR0aD0iNjYiIGhlaWdodD0iODAiIHJ4PSI4IiBmaWxsPSIjM2QzNTgwIiAvPjx0ZXh0IHg9IjYyMyIgeT0iMTcwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmaWxsPSIjZmZmZmZmIj5vbmU8L3RleHQ+PHRleHQgeD0iNjIzIiB5PSIxODgiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTMiIGZpbGw9IiNmZmZmZmYiPndlaWdodDwvdGV4dD48L3A+CjxyZWN0IHg9IjI0IiB5PSIyNzgiIHdpZHRoPSI2MzIiIGhlaWdodD0iNTIiIHJ4PSI4IiBmaWxsPSIjZjdmNmZiIiBzdHJva2U9IiNiMGE2ZWUiIHN0cm9rZS13aWR0aD0iMS4yIiBzdHJva2UtZGFzaGFycmF5PSI1IDMiIC8+PHRleHQgeD0iMzQwIiB5PSIyOTkiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiM0YTQ2NjAiPnJlcGxpY2F0aW9uCmJvb3RzdHJhcDogcmUtZXhlY3V0ZXMgZXZlcnkgc3RlcCBhYm92ZSBvbiBlYWNoIHJlcGxpY2F0ZTwvdGV4dD48dGV4dCB4PSIzNDAiIHk9IjMxOCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzRhNDY2MCI+4oCUCnRoZSBwYXJ0aWNpcGF0aW9uIG1vZGVsLCB0aGUgSyB3b3JraW5nIG1vZGVscywgYW5kIHRoZSByZWZlcmVuY2U8L3RleHQ+PHRleHQgeD0iMzQwIiB5PSIzNDQiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTEiIGZvbnQtc3R5bGU9Iml0YWxpYyIgZmlsbD0iIzhhODRhOCI+RWFjaApzdHVkeSB2YXJpYWJsZSBrZWVwcyBpdHMgb3duIG1vZGVsOyB0aGUgZmlsZSBrZWVwcyBvbmUgd2VpZ2h0LjwvdGV4dD48L3N2Zz4=)

In code, that whole picture is one
[`step_model_calibration()`](https://jpferreira33.github.io/weightflow/reference/step_model_calibration.md):

``` r

cens <- list(sex    = as.data.frame(table(sex    = pop$sex)),
             region = as.data.frame(table(region = pop$region)))

spec <- weighting_spec(vol, base_weights = NULL, nonprob = TRUE) |>
  step_pseudoweight(reference = sr, formula = ~ region + sex + age,
                    engine = "logit") |>
  step_model_calibration(
    x_formula = ~ sex + region,          # the KNOWN margins: met exactly
    x_totals  = cens,
    models    = list(                    # one working model per study variable
      income   = y_model(income   ~ age + sex + region, engine = "glm"),
      employed = y_model(employed ~ age + sex + region, engine = "glm")),
    population = sr,
    crossfit   = 3)

fit <- prep(spec)
w   <- fit$final_weight
```

One column. Here is what it does to all four indicators – including the
two that were never modelled:

``` r

rbind(unweighted = pct(rep(1, nrow(vol))),
      uni_weight = pct(w))
#>            income employed poor retired
#> unweighted    2.3     -4.2 -7.5   -46.3
#> uni_weight    1.9      0.9 -4.8     3.9
```

The two indicators with a working model are corrected, and so is
`retired`, which has none: the pseudo-weight and the margins carry it.
`poor` improves least, and that is the general pattern rather than an
accident of this draw – the cost of sharing one weight concentrates on
the rarest indicator, which is the one that most deserves a weight of
its own when the margin of error matters.

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

Exact consistency is not free, and it does not degrade gracefully – it
is either met or lost, for every variable at once. The reason is a rank
condition.

Write `q` for the dimension of the span of the predictors the working
models use and `dim col(A)` for the number of known margins. With
**linear working models fitted in sample**, every prediction lies inside
that one span, so the stacked system can only add

*K ≤ q − dim col(A)*

variables before it becomes rank deficient. Past that point the margins
are not approximately met: they are missed.

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwJSIgdmlld2JveD0iMCAwIDY4MCAyMzAiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwmIzM5O0ludGVyJiMzOTssU2Vnb2UgVUksUm9ib3RvLHNhbnMtc2VyaWY7Ij48dGl0bGU+ClRoZSByYW5rIGNlaWxpbmcgYW5kIHRoZSB0d28gd2F5cyBvdXQgb2YgaXQKPC90aXRsZT4KPHA+PGRlc2M+V2l0aCBsaW5lYXIgd29ya2luZyBtb2RlbHMgZXZlcnkgcHJlZGljdGlvbiBsaWVzIGluIHRoZSBzcGFuIG9mCnRoZSBtb2RlbCBibG9jaywgd2hpY2ggYWxyZWFkeSBjb250YWlucyB0aGUgbWFyZ2luIGJsb2NrLCBzbyBvbmx5IHEKbWludXMgdGhlIGRpbWVuc2lvbiBvZiB0aGUgbWFyZ2luIGJsb2NrIGRpcmVjdGlvbnMgYXJlIGxlZnQgZm9yIHN0dWR5CnZhcmlhYmxlcy4gVHdvIGVzY2FwZXM6IGEgcmljaGVyIHByZWRpY3RvciBiYXNpcyBlbmxhcmdlcyB0aGUgc3BhbiBhbmQKcmFpc2VzIHRoZSBjZWlsaW5nIGJ5IG9uZSB2YXJpYWJsZSBhdCBhIHRpbWUsIHdoaWxlIGFkYXB0aXZlIGxlYXJuZXJzCmFuZCBjcm9zcy1maXR0aW5nIHByb2R1Y2UgcHJlZGljdGlvbnMgb3V0c2lkZSBhbnkgc2luZ2xlIGZpeGVkIHNwYW4sIHNvCnRoZSBjZWlsaW5nIG5vIGxvbmdlciBhcHBsaWVzLjwvZGVzYz48cmVjdCB4PSIzMCIgeT0iMzQiIHdpZHRoPSIyNTAiIGhlaWdodD0iMTQwIiByeD0iMTAiIGZpbGw9IiNmNGYyZmIiIHN0cm9rZT0iIzUzNGFiNyIgc3Ryb2tlLXdpZHRoPSIxLjQiIC8+PHRleHQgeD0iMTU1IiB5PSI1NCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzNkMzU4MCI+c3BhbgpvZiB0aGUgbW9kZWwgYmxvY2ssIGRpbSBxPC90ZXh0PjxyZWN0IHg9IjY2IiB5PSI2NiIgd2lkdGg9IjE3OCIgaGVpZ2h0PSI1MiIgcng9IjgiIGZpbGw9IiNmZGY2ZTgiIHN0cm9rZT0iI2M5OTAyYSIgc3Ryb2tlLXdpZHRoPSIxLjMiIC8+PHRleHQgeD0iMTU1IiB5PSI4OCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzVjNDQxMCI+a25vd24KbWFyZ2luczwvdGV4dD48dGV4dCB4PSIxNTUiIHk9IjEwNiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzhhN2E1MCI+ZGltCmNvbChBKTwvdGV4dD48dGV4dCB4PSIxNTUiIHk9IjE0MCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzRhNDY2MCI+d2hhdAppcyBsZWZ0IGZvciBzdHVkeSB2YXJpYWJsZXM6PC90ZXh0Pjx0ZXh0IHg9IjE1NSIgeT0iMTYwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmb250LXdlaWdodD0iNjAwIiBmaWxsPSIjM2QzNTgwIj5xCuKIkiBkaW0gY29sKEEpPC90ZXh0PjwvcD4KPHRleHQgeD0iNDgwIiB5PSI0OCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZm9udC13ZWlnaHQ9IjYwMCIgZmlsbD0iIzNkMzU4MCI+dHdvCndheXMgb3V0PC90ZXh0PjxyZWN0IHg9IjMyMCIgeT0iNjIiIHdpZHRoPSIzMjAiIGhlaWdodD0iNDYiIHJ4PSI4IiBmaWxsPSIjZmZmZmZmIiBzdHJva2U9IiM5YTk2YTgiIHN0cm9rZS13aWR0aD0iMS4yIiAvPjx0ZXh0IHg9IjMzNiIgeT0iODIiIGZvbnQtc2l6ZT0iMTEuNSIgZmlsbD0iIzIwMjQyZSI+YSByaWNoZXIgcHJlZGljdG9yCmJhc2lzIGVubGFyZ2VzIHE8L3RleHQ+PHRleHQgeD0iMzM2IiB5PSI5OSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzZiNmE4NiI+dGhlIGNlaWxpbmcgbW92ZXMgdXAsCmFuZCBiaW5kcyBhZ2FpbiBvbmUgdmFyaWFibGUgbGF0ZXI8L3RleHQ+PHJlY3QgeD0iMzIwIiB5PSIxMTgiIHdpZHRoPSIzMjAiIGhlaWdodD0iNTYiIHJ4PSI4IiBmaWxsPSIjZWFmNWYwIiBzdHJva2U9IiMxZDllNzUiIHN0cm9rZS13aWR0aD0iMS4zIiAvPjx0ZXh0IHg9IjMzNiIgeT0iMTM4IiBmb250LXNpemU9IjExLjUiIGZpbGw9IiMxNTUwM2MiPmFkYXB0aXZlIGxlYXJuZXJzLApvciBjcm9zcy1maXR0aW5nIGFueSBtb2RlbDwvdGV4dD48dGV4dCB4PSIzMzYiIHk9IjE1NSIgZm9udC1zaXplPSIxMSIgZmlsbD0iIzNmN2E2NCI+cHJlZGljdGlvbnMgc3RvcApseWluZyBpbiBvbmUgZml4ZWQgc3Bhbiw8L3RleHQ+PHRleHQgeD0iMzM2IiB5PSIxNzAiIGZvbnQtc2l6ZT0iMTEiIGZpbGw9IiMzZjdhNjQiPnNvIHRoZSBjZWlsaW5nIGRvZXMKbm90IGFwcGx5IGF0IGFsbDwvdGV4dD48dGV4dCB4PSIzNDAiIHk9IjIwNiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMSIgZm9udC1zdHlsZT0iaXRhbGljIiBmaWxsPSIjOGE4NGE4Ij5GdWxsCnJhbmsgaXMgc3RpbGwgbm90IHRoZSBzYW1lIGFzIHdlbGwgY29uZGl0aW9uZWQuPC90ZXh0Pjwvc3ZnPg==)

This is not a theoretical caution – it happens on these 1,000
volunteers. The margins here are `~ sex + region`, and the working
models use `~ age + sex + region`: the span has 6 directions, the
margins take 5, so the ceiling is **K = 1**. Watch the second variable
break it, and watch the two escapes:

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

Three of the four close to numerical zero – that is what exact means
here. `K2` does not close at all, and the size of what it leaves on the
table is not arbitrary: the model block is constrained to totals
*estimated* on the reference while the margin block is constrained to
totals *known* from the census, and the two agree only up to the
reference’s sampling error. That is the shortfall you see.

Four numbers, and they fix the specification for production: **put the
known margins in the exact-consistency block, give the working models
richer predictors, and cross-fit.** A working model that is linear in
exactly the consistency margins adds no information and breaks
exactness.

## What sharing costs

Once the system is well conditioned, adding variables to it is cheap.
The price shows up in the dispersion of the weights, not in the margins:

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
  give nearly parallel prediction columns. The achieved margins start
  drifting from their targets and the package raises an ill-conditioning
  warning. Cross-fitting repairs this one.
- **Feasibility.** The margins keep closing to numerical precision while
  units start receiving *negative* weights and the weight range grows by
  orders of magnitude. Nothing in the margin diagnostics moves, and the
  design effect stops being readable as an effective sample size once
  negatives appear. Bounding the calibration repairs this one;
  cross-fitting does not.

So monitor the **negative count** and the **weight range** next to the
margin deviation, and treat the first negative weight as the stopping
signal. Bounded calibration together with cross-fitting is the
production default.

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

The point estimates are identical – it is the same weight column. Only
the standard error moves, and it moves in one direction: holding the
reference fixed can only make the interval narrower, because a source of
variability has been dropped rather than estimated.

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
something no model observes, every estimator here is biased – and the
weights will not tell you. Watch: participation now depends on income,
which appears in no model and no margin.

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
c(max_margin_deviation = max(abs(d2$achieved - d2$target)),
  negative_weights     = sum(w2 < 0),
  design_effect        = round(design_effect(w2)$deff, 2))
#> max_margin_deviation     negative_weights        design_effect 
#>                 0.00                 0.00                 1.01
```

The margins are met exactly, no unit gets a negative weight, and the
design effect is unremarkable. Nothing in that line is wrong and nothing
in it warns you, which is structural rather than a shortcoming of these
particular statistics: a diagnostic built from the weights and the
covariates behind them cannot detect a dependence on a variable absent
from both.

A quantity the adjustment was **never asked to reproduce** can. Here
`region` is in no model and no margin, and its population distribution
is known:

``` r

round(100 * (as.numeric(tapply(w2, v2$region, sum)) /
             as.numeric(table(pop$region)) - 1), 1)
#> [1]  29.9  -9.0 -35.5  -3.8
```

Tens of per cent off, on a figure the weighted file should have
reproduced for free. Reserving one known population quantity as a
held-out benchmark is the cheapest protection available; the data-defect
range above is another. Holding a margin out in order to test against it
costs precision there – and the alternative is a weight whose only
evidence of validity is that it reproduces what it was told to
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
margins, with replicate weights that propagate the participation model,
the K working models and the reference’s own sampling.

## In short

1.  Read the sum of the pseudo-weights against the estimated population,
    to three significant figures, **before** any calibration. It is the
    only point at which the construction is still visible.
2.  Put the known margins in the consistency block; give the working
    models richer predictors and let the learner supply the
    non-linearity.
3.  Cross-fit whenever a model is an adaptive learner. It protects
    coverage and it raises the number of variables one weight can carry.
4.  Watch the negative count and the weight range, not only the margin
    deviation. The first negative weight is the stopping signal.
5.  Treat the size of the reference as part of the specification, and
    pass its replicate weights – or state that you did not.
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
