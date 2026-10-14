# Rotating panels: net change, chaining and gross flows

A continuous household survey with a rotating design measures the same
units more than once. That is what makes the **change** between two
periods far more precise than the levels themselves, because the shared
sample cancels part of the sampling error, and it is also what makes the
change **harder** to estimate. The two samples are not independent, so
the variance of the change is not the sum of the two variances:

``` math
V\!\left(\hat\theta_t - \hat\theta_{t-1}\right) = V\!\left(\hat\theta_t\right) + V\!\left(\hat\theta_{t-1}\right) - 2\,\mathrm{Cov}\!\left(\hat\theta_t, \hat\theta_{t-1}\right)
```

and that covariance term is the whole problem. It is not a design
constant you can look up: it has to be *produced* by the way the
replicates are drawn.

This vignette covers the three things a rotating panel makes possible,
in the order an office needs them:

1.  the **net change** between two periods, with its honest variance;
2.  **chaining** period after period the way production actually runs,
    one month at a time, with only a small object traveling between
    runs;
3.  the **gross flows**, i.e. who moved between states, which need a
    longitudinal weight.

The package’s panel layer follows the methodology of Statistics Canada’s
Labour Force Survey (cat. 71-526-X, sec. 7.2.2) for the coordinated
replication, and ECLAC’s household-survey manual (chapters XVI and XVII)
for the longitudinal weight and the flows.

## The structure comes first

Before any weighting,
[`panel_design()`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)
reads the unit by wave crossing and describes what is actually there. It
computes nothing about weights.

``` r

pd <- panel_design(panel_ine, unit = c("household_id", "person_no"), wave = "wave",
                   rotation_group = "rotation_group", pattern = "6")
pd
#> <weightflow panel design>
#>   waves      : 3 (1, 2, 3)
#>   unit       : household_id + person_no
#>   rotation   : rotation_group  pattern: 6
#>   units      : 2783 (linked in >=2 waves: 2063, 74%)
#>   overlap (row wave retained in column wave):
#>   1    2    3   
#> 1 1.00 0.83 0.64
#> 2 0.83 1.00 0.81
#> 3 0.65 0.82 1.00
#>   Pr(panel selection), adjacent : 0.833, 0.833  (full combination: 0.667)
#>   overlap implied by pattern    : 0.83 0.67   (lag 1 2)
#>   pattern                       : 6 group(s) in sample, cycle 6, useful lags 1, 2, 3, 4, 5
```

Two things to read in that output.

The **overlap matrix** is observed, from the data. The **profile implied
by the pattern** is theoretical, derived from the rotation calendar. The
declared `pattern` is therefore *verification*, not configuration: when
the observed overlap falls below what the design implies, the linkage
key is suspect, and `PN-01` says so. Ordinary attrition pulls the
observed overlap down a little; a broken key pulls it down a lot.

The pattern is parsed into the whole profile, not just the adjacent lag,
because the informative lag is not always lag 1:

``` r

prof <- function(p) round(weightflow:::.wf_pattern_overlap(p)$profile[1:5], 3)
rbind(`6        (Canada LFS, ECH Uruguay)` = prof("6"),
      `4(0)1    (ECLAC ch. XVI example)`   = prof("4(0)1"),
      `2-(2)-2  (Chile ENE, Italy)`        = prof("2-(2)-2"),
      `4-8-4    (US CPS)`                  = prof("4-8-4"),
      `1(2)5    (PNAD Continua)`           = prof("1(2)5"))
#>                                        1     2    3     4     5
#> 6        (Canada LFS, ECH Uruguay) 0.833 0.667 0.50 0.333 0.167
#> 4(0)1    (ECLAC ch. XVI example)   0.750 0.500 0.25 0.000 0.000
#> 2-(2)-2  (Chile ENE, Italy)        0.500 0.000 0.25 0.500 0.250
#> 4-8-4    (US CPS)                  0.750 0.500 0.25 0.000 0.000
#> 1(2)5    (PNAD Continua)           0.000 0.000 0.80 0.000 0.000
```

Three readings that the full profile makes visible and a single number
would hide. Under `2-(2)-2` the lag 4 overlap equals the lag 1 overlap,
so a year on year change needs as much coordination as a quarter on
quarter one. Under `1(2)5` the adjacent overlap is **zero** and the
informative lag is 3, so a chain built around “the previous quarter” is
exactly backwards for the PNAD. And the cycle is not the number of
groups in sample: `2-(2)-2` has four groups in the field at any time but
a cycle six periods long.

The first two rows are the ones to read against each other:

![Which earlier periods share sample with period
t](data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPHN2ZyB3aWR0aD0iMTAwJSIgdmlld0JveD0iMCAwIDk2MCAzNTYiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwnSW50ZXInLFNlZ29lIFVJLFJvYm90byxzYW5zLXNlcmlmOyI+Cjx0aXRsZT5XaGljaCBlYXJsaWVyIHBlcmlvZHMgc2hhcmUgc2FtcGxlIHdpdGggcGVyaW9kIHQ8L3RpdGxlPgo8ZGVzYz5VbmRlciBhIHNjaGVtZSBvZiBzaXggY29uc2VjdXRpdmUgcGVyaW9kcyB0aGUgY3VycmVudCBwZXJpb2Qgc2hhcmVzIHNhbXBsZSB3aXRoIHRoZSBmaXZlIHByZWNlZGluZyBvbmVzLCBzbyBmaXZlIGNhcnJpZXMgYXJlIHJldGFpbmVkLiBVbmRlciBhIHR3byBpbiwgdHdvIG91dCwgdHdvIGluIHNjaGVtZSBpdCBzaGFyZXMgc2FtcGxlIHdpdGggbGFncyBvbmUsIHRocmVlLCBmb3VyIGFuZCBmaXZlIGJ1dCBub3Qgd2l0aCBsYWcgdHdvLCBhbmQgdGhlIGxhZyBmb3VyIG92ZXJsYXAgaXMgYXMgbGFyZ2UgYXMgdGhlIGxhZyBvbmUgb3ZlcmxhcC48L2Rlc2M+CjxkZWZzPjxtYXJrZXIgaWQ9ImEzIiB2aWV3Qm94PSIwIDAgMTAgMTAiIHJlZlg9IjkiIHJlZlk9IjUiIG1hcmtlcldpZHRoPSI3IiBtYXJrZXJIZWlnaHQ9IjciIG9yaWVudD0iYXV0by1zdGFydC1yZXZlcnNlIj48cGF0aCBkPSJNMCwwIEwxMCw1IEwwLDEwIHoiIGZpbGw9IiM3YTZhZDAiLz48L21hcmtlcj48L2RlZnM+Cjx0ZXh0IGZpbGw9IiM4YTg0YTgiIGZvbnQtc2l6ZT0iMTAuNSIgbGV0dGVyLXNwYWNpbmc9IjEuMiIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iMjQiIHk9IjI0Ij5TQ0hFTUUgNiwgU0lYIENPTlNFQ1VUSVZFIChDQU5BREEgTEZTLCBFQ0ggVVJVR1VBWSk8L3RleHQ+CjxnPgo8cmVjdCBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS43NSIgeD0iMjQiIHk9IjQwIiB3aWR0aD0iMTE4IiBoZWlnaHQ9IjQ2IiByeD0iOCIvPgo8dGV4dCBmaWxsPSIjMjAyNDJlIiBmb250LXNpemU9IjEzIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiB4PSI4MyIgeT0iNjkiIHRleHQtYW5jaG9yPSJtaWRkbGUiPnQmIzg3MjI7NTwvdGV4dD4KPHJlY3QgZmlsbD0iI2VjZTlmNiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuNzUiIHg9IjE1OCIgeT0iNDAiIHdpZHRoPSIxMTgiIGhlaWdodD0iNDYiIHJ4PSI4Ii8+Cjx0ZXh0IGZpbGw9IiMyMDI0MmUiIGZvbnQtc2l6ZT0iMTMiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjIxNyIgeT0iNjkiIHRleHQtYW5jaG9yPSJtaWRkbGUiPnQmIzg3MjI7NDwvdGV4dD4KPHJlY3QgZmlsbD0iI2VjZTlmNiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuNzUiIHg9IjI5MiIgeT0iNDAiIHdpZHRoPSIxMTgiIGhlaWdodD0iNDYiIHJ4PSI4Ii8+Cjx0ZXh0IGZpbGw9IiMyMDI0MmUiIGZvbnQtc2l6ZT0iMTMiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjM1MSIgeT0iNjkiIHRleHQtYW5jaG9yPSJtaWRkbGUiPnQmIzg3MjI7MzwvdGV4dD4KPHJlY3QgZmlsbD0iI2VjZTlmNiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuNzUiIHg9IjQyNiIgeT0iNDAiIHdpZHRoPSIxMTgiIGhlaWdodD0iNDYiIHJ4PSI4Ii8+Cjx0ZXh0IGZpbGw9IiMyMDI0MmUiIGZvbnQtc2l6ZT0iMTMiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjQ4NSIgeT0iNjkiIHRleHQtYW5jaG9yPSJtaWRkbGUiPnQmIzg3MjI7MjwvdGV4dD4KPHJlY3QgZmlsbD0iI2VjZTlmNiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuNzUiIHg9IjU2MCIgeT0iNDAiIHdpZHRoPSIxMTgiIGhlaWdodD0iNDYiIHJ4PSI4Ii8+Cjx0ZXh0IGZpbGw9IiMyMDI0MmUiIGZvbnQtc2l6ZT0iMTMiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjYxOSIgeT0iNjkiIHRleHQtYW5jaG9yPSJtaWRkbGUiPnQmIzg3MjI7MTwvdGV4dD4KPHJlY3QgZmlsbD0iI2ZmZmZmZiIgc3Ryb2tlPSIjM2QzNTgwIiBzdHJva2Utd2lkdGg9IjIiIHg9IjY5NCIgeT0iNDAiIHdpZHRoPSIxMTgiIGhlaWdodD0iNDYiIHJ4PSI4Ii8+Cjx0ZXh0IGZpbGw9IiMyMDI0MmUiIGZvbnQtc2l6ZT0iMTMiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9Ijc1MyIgeT0iNjkiIHRleHQtYW5jaG9yPSJtaWRkbGUiPnQ8L3RleHQ+CjxwYXRoIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIyIiBmaWxsPSJub25lIiBkPSJNODMsODYgQzgzLDEyNCA3NTMsMTI0IDc1Myw5MiIgbWFya2VyLWVuZD0idXJsKCNhMykiLz4KPHBhdGggc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjIiIGZpbGw9Im5vbmUiIGQ9Ik0yMTcsODYgQzIxNywxMTYgNzUzLDExNiA3NTMsOTIiIG1hcmtlci1lbmQ9InVybCgjYTMpIi8+CjxwYXRoIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIyIiBmaWxsPSJub25lIiBkPSJNMzUxLDg2IEMzNTEsMTEwIDc1MywxMTAgNzUzLDkyIiBtYXJrZXItZW5kPSJ1cmwoI2EzKSIvPgo8cGF0aCBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMiIgZmlsbD0ibm9uZSIgZD0iTTQ4NSw4NiBDNDg1LDEwNiA3NTMsMTA2IDc1Myw5MiIgbWFya2VyLWVuZD0idXJsKCNhMykiLz4KPHBhdGggc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjIiIGZpbGw9Im5vbmUiIGQ9Ik02MTksODYgQzYxOSwxMDIgNzUzLDEwMiA3NTMsOTIiIG1hcmtlci1lbmQ9InVybCgjYTMpIi8+Cjx0ZXh0IGZpbGw9IiM0YTQ2NjAiIGZvbnQtc2l6ZT0iMTIiIHg9IjgzNiIgeT0iNjMiPjUgY2FycmllczwvdGV4dD4KPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iODM2IiB5PSI3OSI+b3ZlcmxhcCAwLjgzIGF0IGxhZyAxPC90ZXh0Pgo8L2c+CjxsaW5lIHN0cm9rZT0iI2Q5ZGNlNiIgc3Ryb2tlLXdpZHRoPSIxLjYiIGZpbGw9Im5vbmUiIHgxPSIyNCIgeTE9IjE2NCIgeDI9IjkzNiIgeTI9IjE2NCIvPgo8dGV4dCBmaWxsPSIjOGE4NGE4IiBmb250LXNpemU9IjEwLjUiIGxldHRlci1zcGFjaW5nPSIxLjIiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjI0IiB5PSIxOTgiPlNDSEVNRSAyLSgyKS0yLCBUV08gSU4sIFRXTyBPVVQsIFRXTyBJTiAoSVRBTFksIFBPTEFORCk8L3RleHQ+CjxnPgo8cmVjdCBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS43NSIgeD0iMjQiIHk9IjIxNCIgd2lkdGg9IjExOCIgaGVpZ2h0PSI0NiIgcng9IjgiLz4KPHRleHQgZmlsbD0iIzIwMjQyZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iODMiIHk9IjI0MyIgdGV4dC1hbmNob3I9Im1pZGRsZSI+dCYjODcyMjs1PC90ZXh0Pgo8cmVjdCBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS43NSIgeD0iMTU4IiB5PSIyMTQiIHdpZHRoPSIxMTgiIGhlaWdodD0iNDYiIHJ4PSI4Ii8+Cjx0ZXh0IGZpbGw9IiMyMDI0MmUiIGZvbnQtc2l6ZT0iMTMiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjIxNyIgeT0iMjQzIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIj50JiM4NzIyOzQ8L3RleHQ+CjxyZWN0IGZpbGw9IiNlY2U5ZjYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjc1IiB4PSIyOTIiIHk9IjIxNCIgd2lkdGg9IjExOCIgaGVpZ2h0PSI0NiIgcng9IjgiLz4KPHRleHQgZmlsbD0iIzIwMjQyZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iMzUxIiB5PSIyNDMiIHRleHQtYW5jaG9yPSJtaWRkbGUiPnQmIzg3MjI7MzwvdGV4dD4KPHJlY3QgZmlsbD0iI2YzZjNmNSIgc3Ryb2tlPSIjZDlkY2U2IiBzdHJva2Utd2lkdGg9IjEuNSIgeD0iNDI2IiB5PSIyMTQiIHdpZHRoPSIxMTgiIGhlaWdodD0iNDYiIHJ4PSI4Ii8+Cjx0ZXh0IGZpbGw9IiM0YTQ2NjAiIGZvbnQtc2l6ZT0iMTIiIHg9IjQ4NSIgeT0iMjM4IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIj50JiM4NzIyOzI8L3RleHQ+Cjx0ZXh0IGZpbGw9IiM0YTQ2NjAiIGZvbnQtc2l6ZT0iMTIiIHg9IjQ4NSIgeT0iMjU0IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIj5ubyBvdmVybGFwPC90ZXh0Pgo8cmVjdCBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS43NSIgeD0iNTYwIiB5PSIyMTQiIHdpZHRoPSIxMTgiIGhlaWdodD0iNDYiIHJ4PSI4Ii8+Cjx0ZXh0IGZpbGw9IiMyMDI0MmUiIGZvbnQtc2l6ZT0iMTMiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjYxOSIgeT0iMjQzIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIj50JiM4NzIyOzE8L3RleHQ+CjxyZWN0IGZpbGw9IiNmZmZmZmYiIHN0cm9rZT0iIzNkMzU4MCIgc3Ryb2tlLXdpZHRoPSIyIiB4PSI2OTQiIHk9IjIxNCIgd2lkdGg9IjExOCIgaGVpZ2h0PSI0NiIgcng9IjgiLz4KPHRleHQgZmlsbD0iIzIwMjQyZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iNzUzIiB5PSIyNDMiIHRleHQtYW5jaG9yPSJtaWRkbGUiPnQ8L3RleHQ+CjxwYXRoIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIyIiBmaWxsPSJub25lIiBkPSJNODMsMjYwIEM4MywyOTggNzUzLDI5OCA3NTMsMjY2IiBtYXJrZXItZW5kPSJ1cmwoI2EzKSIvPgo8cGF0aCBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMiIgZmlsbD0ibm9uZSIgZD0iTTIxNywyNjAgQzIxNywyOTAgNzUzLDI5MCA3NTMsMjY2IiBtYXJrZXItZW5kPSJ1cmwoI2EzKSIvPgo8cGF0aCBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMiIgZmlsbD0ibm9uZSIgZD0iTTM1MSwyNjAgQzM1MSwyODQgNzUzLDI4NCA3NTMsMjY2IiBtYXJrZXItZW5kPSJ1cmwoI2EzKSIvPgo8cGF0aCBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMiIgZmlsbD0ibm9uZSIgZD0iTTYxOSwyNjAgQzYxOSwyNzYgNzUzLDI3NiA3NTMsMjY2IiBtYXJrZXItZW5kPSJ1cmwoI2EzKSIvPgo8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSI4MzYiIHk9IjIzNyI+NCBjYXJyaWVzPC90ZXh0Pgo8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSI4MzYiIHk9IjI1MyI+bGFnIDQgYXMgYmlnIGFzIGxhZyAxPC90ZXh0Pgo8L2c+Cjx0ZXh0IGZpbGw9IiM0YTQ2NjAiIGZvbnQtc2l6ZT0iMTIiIHg9IjI0IiB5PSIzNDAiPlRoZSBvdmVybGFwIHByb2ZpbGUgZm9sbG93cyBmcm9tIHRoZSBzY2hlbWU6IDx0c3BhbiBmaWxsPSIjMjAyNDJlIiBmb250LXNpemU9IjEzIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIj5wYW5lbF9kZXNpZ24ocGF0dGVybiA9ICIyLSgyKS0yIik8L3RzcGFuPiBnaXZlcyBsYWdzIDEsIDMsIDQgYW5kIDUuPC90ZXh0PgoKPC9zdmc+Cg==)

Both notations are accepted and describe the same calendar: `"2-(2)-2"`
and `"2(2)2"` are the same design, as are the EU-LFS block notation and
ECLAC’s `n(m)k`.

The declared scheme is checked against the data in both directions.
**PN-01** fires when the observed overlap falls below what the scheme
implies, which points at a linkage key that is not stable between waves.
**PN-07** fires when two periods the scheme declares disjoint turn out
to share sample. Attrition can only remove overlap, never add it, so a
surplus means the declared scheme and the data disagree.

## Net change between two periods

The coordinated bootstrap resamples **PSUs**, and a PSU present in both
waves is resampled the same way in both. That is what lets the overlap
show up as covariance.

``` r

w1 <- subset(panel_ine, wave == 1 & disposition == "R")
w2 <- subset(panel_ine, wave == 2 & disposition == "R")
rec <- function(d) weighting_spec(d, base_weights = pw) |>
  step_nonresponse(respondent = disposition == "R", by = "sex")

wb <- wave_bootstrap(list(T1 = rec(w1), T2 = rec(w2)), replicates = 60,
                     strata = "stratum", psu = "psu", seed = 1, progress = FALSE)
change_mean(wb, "unemployed")
#> <weightflow net change>
#>   T1 -> T2
#>   change     : -0.0149512   SE 0.0106493
#>   95% CI    : [-0.0358235, 0.00592097]
#>   V1 0.0001094 | V2 0.0001119 | Cov 5.395e-05 | rho 0.488   (levels)
#>   V = 0.0001134  vs  V1+V2 = 0.0002213  (deff_change 0.512: overlap saved 49%)
```

`rho` is the correlation the overlap induces, and `deff_change` is

``` math
\mathrm{deff}_\Delta = \frac{V\!\left(\hat\theta_t - \hat\theta_{t-1}\right)}{V\!\left(\hat\theta_t\right) + V\!\left(\hat\theta_{t-1}\right)}
```

the ratio between the variance reported here and what an office would
report if it treated the two periods as independent samples. A
`deff_change` near 0.5 means the overlap has paid for half the variance
of the change. Ignoring it does not give a conservative answer, it gives
a wrong one, in either direction depending on the sign of the
covariance.

## Chaining: how production actually runs

[`wave_bootstrap()`](https://jpferreira33.github.io/weightflow/reference/wave_bootstrap.md)
wants every wave at once. An office does not have them: it publishes
month `t` weeks after month `t-1`, and the twelfth month of the year
cannot wait for the first eleven to be reprocessed.
[`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
runs **one period at a time**, and hands the next period a small object,
the *carry*, that is all it needs.

![The cycle of one
period](data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPHN2ZyB3aWR0aD0iMTAwJSIgdmlld0JveD0iMCAwIDk2MCA0NTIiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwnSW50ZXInLFNlZ29lIFVJLFJvYm90byxzYW5zLXNlcmlmOyI+Cjx0aXRsZT5UaGUgY3ljbGUgb2Ygb25lIHBlcmlvZDwvdGl0bGU+CjxkZXNjPlRoZSBwZXJpb2QgbWljcm9kYXRhIGFuZCBpdHMgcmVjaXBlLCB0b2dldGhlciB3aXRoIHRoZSBjYXJyaWVzIHJldGFpbmVkIGZyb20gZWFybGllciBwZXJpb2RzIHRoYXQgc2hhcmUgc2FtcGxlIHdpdGggaXQsIGdvIGludG8gd2F2ZV9zdGVwLCB3aGljaCByZXR1cm5zIHRoZSBjcm9zcy1zZWN0aW9uYWwgd2VpZ2h0cywgdGhlIGxldmVsIHdpdGggaXRzIHN0YW5kYXJkIGVycm9yLCB0aGUgbmV0IGNoYW5nZSB3aXRoIGl0cyBzdGFuZGFyZCBlcnJvciwgYW5kIGEgbmV3IGNhcnJ5LiBUaGUgY2FycnkgaXMgc2F2ZWQgYW5kIHRoZSBuZXh0IHBlcmlvZCB0YWtlcyBpdCBhcyBhbiBpbnB1dC48L2Rlc2M+CjxkZWZzPjxtYXJrZXIgaWQ9ImExIiB2aWV3Qm94PSIwIDAgMTAgMTAiIHJlZlg9IjkiIHJlZlk9IjUiIG1hcmtlcldpZHRoPSI3IiBtYXJrZXJIZWlnaHQ9IjciIG9yaWVudD0iYXV0by1zdGFydC1yZXZlcnNlIj48cGF0aCBkPSJNMCwwIEwxMCw1IEwwLDEwIHoiIGZpbGw9IiM0YTQ2NjAiLz48L21hcmtlcj48bWFya2VyIGlkPSJhMiIgdmlld0JveD0iMCAwIDEwIDEwIiByZWZYPSI5IiByZWZZPSI1IiBtYXJrZXJXaWR0aD0iNyIgbWFya2VySGVpZ2h0PSI3IiBvcmllbnQ9ImF1dG8tc3RhcnQtcmV2ZXJzZSI+PHBhdGggZD0iTTAsMCBMMTAsNSBMMCwxMCB6IiBmaWxsPSIjN2E2YWQwIi8+PC9tYXJrZXI+PC9kZWZzPgoKICAgICAgPHRleHQgZmlsbD0iIzhhODRhOCIgZm9udC1zaXplPSIxMC41IiBsZXR0ZXItc3BhY2luZz0iMS4yIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiB4PSIyNCIgeT0iMjYiPklOUFVUUzwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzhhODRhOCIgZm9udC1zaXplPSIxMC41IiBsZXR0ZXItc3BhY2luZz0iMS4yIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiB4PSIzNjgiIHk9IjI2Ij5USEUgU1RFUDwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzhhODRhOCIgZm9udC1zaXplPSIxMC41IiBsZXR0ZXItc3BhY2luZz0iMS4yIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiB4PSI2NjAiIHk9IjI2Ij5PVVRQVVRTPC90ZXh0PgoKICAgICAgPHJlY3QgZmlsbD0iI2ZmZmZmZiIgc3Ryb2tlPSIjZDlkY2U2IiBzdHJva2Utd2lkdGg9IjEuNSIgeD0iMjQiIHk9IjQyIiB3aWR0aD0iMjMyIiBoZWlnaHQ9IjgyIiByeD0iMTAiLz4KICAgICAgPHRleHQgZmlsbD0iIzIwMjQyZSIgZm9udC1zaXplPSIxNC41IiBmb250LXdlaWdodD0iNjAwIiB4PSI0MiIgeT0iNzAiPlBlcmlvZCB0IG1pY3JvZGF0YTwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iNDIiIHk9IjkyIj5wbHVzIHRoZSB3ZWlnaHRpbmcgcmVjaXBlPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjMjAyNDJlIiBmb250LXNpemU9IjEzIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiB4PSI0MiIgeT0iMTEyIj53ZWlnaHRpbmdfc3BlYyguLi4pPC90ZXh0PgoKICAgICAgPHJlY3QgZmlsbD0iI2VjZTlmNiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuNzUiIHg9IjI0IiB5PSIxNTIiIHdpZHRoPSIyMzIiIGhlaWdodD0iMTA0IiByeD0iMTAiLz4KICAgICAgPHRleHQgZmlsbD0iIzIwMjQyZSIgZm9udC1zaXplPSIxNC41IiBmb250LXdlaWdodD0iNjAwIiB4PSI0MiIgeT0iMTgwIj5DYXJyaWVzIHJldGFpbmVkPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSI0MiIgeT0iMjAyIj5vbmUgcGVyIGxhZyB3aXRoIGEgcG9zaXRpdmU8L3RleHQ+CiAgICAgIDx0ZXh0IGZpbGw9IiM0YTQ2NjAiIGZvbnQtc2l6ZT0iMTIiIHg9IjQyIiB5PSIyMjAiPnNhbXBsZSBvdmVybGFwPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNTM0YWI3IiBmb250LXNpemU9IjEyLjUiIGZvbnQtd2VpZ2h0PSI1MDAiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjQyIiB5PSIyNDIiPjIwMjYtMDEucmRzICYjMTgzOyAyMDI2LTAzLnJkczwvdGV4dD4KCiAgICAgIDxsaW5lIHN0cm9rZT0iIzRhNDY2MCIgc3Ryb2tlLXdpZHRoPSIxLjYiIGZpbGw9Im5vbmUiIHgxPSIyNTYiIHkxPSI4MyIgeDI9IjM1NiIgeTI9IjEyOCIgbWFya2VyLWVuZD0idXJsKCNhMSkiLz4KICAgICAgPGxpbmUgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjIiIGZpbGw9Im5vbmUiIHgxPSIyNTYiIHkxPSIyMDQiIHgyPSIzNTYiIHkyPSIxNzYiIG1hcmtlci1lbmQ9InVybCgjYTIpIi8+CiAgICAgIDx0ZXh0IGZpbGw9IiM0YTQ2NjAiIGZvbnQtc2l6ZT0iMTIiIHg9IjI3MiIgeT0iNzgiPnNwZWM8L3RleHQ+CiAgICAgIDx0ZXh0IGZpbGw9IiM1MzRhYjciIGZvbnQtc2l6ZT0iMTIuNSIgZm9udC13ZWlnaHQ9IjUwMCIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iMjYyIiB5PSIyMjIiPnByZXZpb3VzID0gbGlzdCguLi4pPC90ZXh0PgoKICAgICAgPHJlY3QgZmlsbD0iI2ZmZmZmZiIgc3Ryb2tlPSIjM2QzNTgwIiBzdHJva2Utd2lkdGg9IjIiIHg9IjM2MCIgeT0iMTE4IiB3aWR0aD0iMjEyIiBoZWlnaHQ9Ijk2IiByeD0iMTEiLz4KICAgICAgPHRleHQgZmlsbD0iIzIwMjQyZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iNDY2IiB5PSIxNTgiIHRleHQtYW5jaG9yPSJtaWRkbGUiPndhdmVfc3RlcCgpPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSI0NjYiIHk9IjE4MiIgdGV4dC1hbmNob3I9Im1pZGRsZSI+cmUtcnVucyB0aGUgd2hvbGUgcmVjaXBlPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSI0NjYiIHk9IjIwMCIgdGV4dC1hbmNob3I9Im1pZGRsZSI+b24gZXZlcnkgcmVwbGljYXRlPC90ZXh0PgoKICAgICAgPGxpbmUgc3Ryb2tlPSIjNGE0NjYwIiBzdHJva2Utd2lkdGg9IjEuNiIgZmlsbD0ibm9uZSIgeDE9IjU3MiIgeTE9IjE1MCIgeDI9IjY1NiIgeTI9Ijc2IiAgbWFya2VyLWVuZD0idXJsKCNhMSkiLz4KICAgICAgPGxpbmUgc3Ryb2tlPSIjNGE0NjYwIiBzdHJva2Utd2lkdGg9IjEuNiIgZmlsbD0ibm9uZSIgeDE9IjU3MiIgeTE9IjE2MCIgeDI9IjY1NiIgeTI9IjE0NiIgbWFya2VyLWVuZD0idXJsKCNhMSkiLz4KICAgICAgPGxpbmUgc3Ryb2tlPSIjNGE0NjYwIiBzdHJva2Utd2lkdGg9IjEuNiIgZmlsbD0ibm9uZSIgeDE9IjU3MiIgeTE9IjE3NiIgeDI9IjY1NiIgeTI9IjIxNiIgbWFya2VyLWVuZD0idXJsKCNhMSkiLz4KICAgICAgPGxpbmUgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjIiIGZpbGw9Im5vbmUiIHgxPSI1NzIiIHkxPSIxOTIiIHgyPSI2NTYiIHkyPSIyOTIiIG1hcmtlci1lbmQ9InVybCgjYTIpIi8+CgogICAgICA8cmVjdCBmaWxsPSIjZmZmZmZmIiBzdHJva2U9IiNkOWRjZTYiIHN0cm9rZS13aWR0aD0iMS41IiB4PSI2NjAiIHk9IjQyIiB3aWR0aD0iMjc2IiBoZWlnaHQ9IjYyIiByeD0iMTAiLz4KICAgICAgPHRleHQgZmlsbD0iIzIwMjQyZSIgZm9udC1zaXplPSIxNC41IiBmb250LXdlaWdodD0iNjAwIiB4PSI2NzgiIHk9IjY4Ij5Dcm9zcy1zZWN0aW9uYWwgd2VpZ2h0czwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzIwMjQyZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iNjc4IiB5PSI5MCI+JHdlaWdodHM8L3RleHQ+CgogICAgICA8cmVjdCBmaWxsPSIjZmZmZmZmIiBzdHJva2U9IiNkOWRjZTYiIHN0cm9rZS13aWR0aD0iMS41IiB4PSI2NjAiIHk9IjExNiIgd2lkdGg9IjI3NiIgaGVpZ2h0PSI2MiIgcng9IjEwIi8+CiAgICAgIDx0ZXh0IGZpbGw9IiMyMDI0MmUiIGZvbnQtc2l6ZT0iMTQuNSIgZm9udC13ZWlnaHQ9IjYwMCIgeD0iNjc4IiB5PSIxNDIiPkxldmVsIGFuZCBpdHMgc3RhbmRhcmQgZXJyb3I8L3RleHQ+CiAgICAgIDx0ZXh0IGZpbGw9IiMyMDI0MmUiIGZvbnQtc2l6ZT0iMTMiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjY3OCIgeT0iMTY0Ij4kbGV2ZWw8L3RleHQ+CgogICAgICA8cmVjdCBmaWxsPSIjZmZmZmZmIiBzdHJva2U9IiNkOWRjZTYiIHN0cm9rZS13aWR0aD0iMS41IiB4PSI2NjAiIHk9IjE5MCIgd2lkdGg9IjI3NiIgaGVpZ2h0PSI2MiIgcng9IjEwIi8+CiAgICAgIDx0ZXh0IGZpbGw9IiMyMDI0MmUiIGZvbnQtc2l6ZT0iMTQuNSIgZm9udC13ZWlnaHQ9IjYwMCIgeD0iNjc4IiB5PSIyMTYiPk5ldCBjaGFuZ2UgYW5kIGl0cyBTRTwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzIwMjQyZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iNjc4IiB5PSIyMzgiPiRjaGFuZ2U8L3RleHQ+CgogICAgICA8cmVjdCBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS43NSIgeD0iNjYwIiB5PSIyNjQiIHdpZHRoPSIyNzYiIGhlaWdodD0iNzAiIHJ4PSIxMCIvPgogICAgICA8dGV4dCBmaWxsPSIjMjAyNDJlIiBmb250LXNpemU9IjE0LjUiIGZvbnQtd2VpZ2h0PSI2MDAiIHg9IjY3OCIgeT0iMjkwIj5DYXJyeSBmb3IgcGVyaW9kIHQ8L3RleHQ+CiAgICAgIDx0ZXh0IGZpbGw9IiM1MzRhYjciIGZvbnQtc2l6ZT0iMTIuNSIgZm9udC13ZWlnaHQ9IjUwMCIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iNjc4IiB5PSIzMTIiPndhdmVfY2Fycnkob3V0KTwvdGV4dD4KCiAgICAgIDxwYXRoIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIyIiBmaWxsPSJub25lIiBkPSJNNzk4LDMzNCBMNzk4LDM5OCBMMTQwLDM5OCBMMTQwLDI2MCIgbWFya2VyLWVuZD0idXJsKCNhMikiLz4KICAgICAgPHRleHQgZmlsbD0iIzUzNGFiNyIgZm9udC1zaXplPSIxMi41IiBmb250LXdlaWdodD0iNTAwIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiB4PSI0NzAiIHk9IjM5MCIgdGV4dC1hbmNob3I9Im1pZGRsZSI+c2F2ZVJEUygpLCBhbmQgdGhlIG5leHQgcGVyaW9kIHRha2VzIGl0IGFzIGFuIGlucHV0PC90ZXh0PgoKICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iMjQiIHk9IjQzMiI+VGhlIHdlaWdodCB0aGUgb2ZmaWNlIHB1Ymxpc2hlcyBpcyA8dHNwYW4gZmlsbD0iIzIwMjQyZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSI+JHdlaWdodHM8L3RzcGFuPiwgaWRlbnRpY2FsIHRvIDx0c3BhbiBmaWxsPSIjMjAyNDJlIiBmb250LXNpemU9IjEzIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIj5wcmVwKHNwZWMpJGZpbmFsX3dlaWdodDwvdHNwYW4+LjwvdGV4dD4KCjwvc3ZnPgo=)

Here is a three period chain, run the way production runs it: each
period separately, writing its carry to disk, with nothing else
surviving between runs.

### The estimands are declared, not programmed

What to estimate, over which domains and on which subuniverse is
declared with the same DSL as the rest of the package, and the plan is
handed to
[`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
whole:

``` r

dk   <- subset(panel_ine, wave == 1 & disposition == "R")
plan <- rec(dk) |>
  step_domain(sex) |>                                   # domains of study
  step_estimate(mean(unemployed), label = "unemp")      # the estimand

plan
#> <weightflow estimation pipeline>
#>   source     : coordinated bootstrap (0 waves)
#>   domains    : sex
#>   estimands  : 1
#>     - unemp  (over = level)
#>   -> collect_estimates() to evaluate
```

[`step_filter()`](https://jpferreira33.github.io/weightflow/reference/step_domain.md)
would add a subuniverse (working age population, the employed,
households with a female head). It masks rows rather than deleting them,
so the coordinated replicate structure stays intact.

This matters here more than it does in a single period. The carry stores
the `R` replicate values of every estimand **under its label**, and the
next period matches them by name. An estimand added halfway through the
chain does not exist in the earlier carry, so there are no replicate
pairs to estimate a covariance from.
[`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
says so rather than reporting a change as if the two periods were
independent:

``` r

d1 <- subset(panel_ine, wave == 1 & disposition == "R")
d2 <- subset(panel_ine, wave == 2 & disposition == "R")
one <- function(d) rec(d) |> step_estimate(mean(unemployed), label = "unemp")
two <- function(d) one(d) |> step_estimate(mean(age), label = "mean_age")   # declared late

s1 <- wave_step(rec(d1), estimands = one(d1), replicates = 20, strata = "stratum",
                psu = "psu", period = "t1", seed = 1, progress = FALSE)
s2 <- try(wave_step(rec(d2), previous = wave_carry(s1), estimands = two(d2),
                    replicates = 20, strata = "stratum", psu = "psu",
                    period = "t2", seed = 2, progress = FALSE), silent = TRUE)
#> Warning: carry 't1' has no replicate values for 1 estimand(s) (mean_age), so no
#> change is reported for them. Declare the same `estimands`/`by` in every period
#> of the chain, or re-run that period.
```

### The chain

``` r

store <- file.path(tempdir(), "carry"); dir.create(store, showWarnings = FALSE)
month <- c("2026-01", "2026-02", "2026-03")

for (k in 1:3) {
  dk   <- subset(panel_ine, wave == k & disposition == "R")
  plan <- rec(dk) |> step_domain(sex) |> step_estimate(mean(unemployed), label = "unemp")
  prev <- lapply(rev(list.files(store, full.names = TRUE)), readRDS)   # what is on disk
  out  <- wave_step(rec(dk), previous = if (length(prev)) prev else NULL,
                    estimands = plan, replicates = 60, strata = "stratum", psu = "psu",
                    period = month[k], seed = k, progress = FALSE)
  saveRDS(wave_carry(out), file.path(store, paste0(month[k], ".rds")))
}

list.files(store)
#> [1] "2026-01.rds" "2026-02.rds" "2026-03.rds"
```

One declared estimand and one domain give three series, the total and
the two levels of `sex`, and the third period reports a change against
**each** earlier period it shares sample with, not only the adjacent
one:

``` r

out$change[, c("estimand", "from", "to", "estimate", "se", "rho", "deff_change")]
#>      estimand    from      to     estimate         se       rho deff_change
#> 1       unemp 2026-02 2026-03  0.015956715 0.01222748 0.5294995   0.4718879
#> 2 unemp|sex=F 2026-02 2026-03  0.027289650 0.01806427 0.5582719   0.4454167
#> 3 unemp|sex=M 2026-02 2026-03  0.005787666 0.01745125 0.5464332   0.4620931
#> 4       unemp 2026-01 2026-03  0.001005467 0.01294508 0.4808183   0.5198849
#> 5 unemp|sex=F 2026-01 2026-03 -0.001630680 0.02179629 0.4318623   0.5682533
#> 6 unemp|sex=M 2026-01 2026-03  0.006013244 0.01525588 0.5522920   0.4482943
```

Three properties worth stating plainly.

**The cross-sectional weights are untouched.** Coordination adds the
change and the carry; it never moves the point estimate the office
publishes.

``` r

all.equal(out$weights, prep(rec(subset(panel_ine, wave == 3 & disposition == "R")))$final_weight)
#> [1] TRUE
```

**`previous` is a list, not a file.** Which earlier periods share sample
with this one is decided by the rotation calendar, as the figure above
shows. Each PSU inherits its multiplicity from the most recent carry
that contains it, so gaps and returning cohorts resolve themselves.

**The coordination is exact when the stratum keeps its size.**
Coordination transfers the PSU *multiplicities*, and when `n_h` is
unchanged the transfer is a permutation, case (ii) of the LFS
methodology, so no replicate needs adjusting:

``` r

out$strata
#>   stratum n_psu inherited fresh case coordinated
#> 1       1    10        10     0    i           1
#> 2       2    10        10     0    i           1
#> 3       3    10        10     0    i           1
#> 4       4    10        10     0    i           1
#> 5       5    10        10     0    i           1
#> 6       6    10        10     0    i           1
```

`case` is the coordination case per stratum and `coordinated` is the
share of replicates that closed without adjustment. That column is the
quality indicator that decides whether a figure is publishable, and the
four cases are set out in
[`vignette("coordinated-replication")`](https://jpferreira33.github.io/weightflow/articles/coordinated-replication.md).

## What has to be saved

This is the question an office asks first, because it decides the
production architecture. The answer is: one object per period, and it is
small.

![What the carry holds, thin and
fat](data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPHN2ZyB3aWR0aD0iMTAwJSIgdmlld0JveD0iMCAwIDk2MCAzNDAiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwnSW50ZXInLFNlZ29lIFVJLFJvYm90byxzYW5zLXNlcmlmOyI+Cjx0aXRsZT5XaGF0IHRoZSB0aGluIGNhcnJ5IGFuZCB0aGUgZmF0IGNhcnJ5IGhvbGQ8L3RpdGxlPgo8ZGVzYz5UaGUgdGhpbiBjYXJyeSBob2xkcyB0aGUgUFNVIG11bHRpcGxpY2l0aWVzLCB0aGUgc3RyYXR1bSBvZiBlYWNoIFBTVSwgdGhlIG51bWJlciBvZiBQU1VzIHBlciBzdHJhdHVtLCB0aGUgcmVwbGljYXRlIHZhbHVlcyBhbmQgdGhlIHBvaW50IGVzdGltYXRlIG9mIGV2ZXJ5IGVzdGltYW5kLCBhbmQgYSBmaW5nZXJwcmludCBvZiB0aGUgcGVyaW9kIGRhdGEuIEl0IHdlaWdocyBmb3VyIGtpbG9ieXRlcyBhbmQgaG9sZHMgbm8gcGVyc29uIGxldmVsIGRhdGEuIFRoZSBmYXQgY2FycnksIHJlcXVpcmVkIGJ5IGEgY29tcG9zaXRlIHJlY2lwZSwgYWRkcyB0aGUgcmVwbGljYXRlIHdlaWdodCBtYXRyaXgsIHRoZSBwZXJpb2QgbWljcm9kYXRhIGFuZCB0aGUgcG9pbnQgd2VpZ2h0cywgYW5kIHdlaWdocyBhYm91dCBvbmUgaHVuZHJlZCBhbmQgc2l4dHkga2lsb2J5dGVzLjwvZGVzYz4KPGRlZnM+PC9kZWZzPgoKICAgICAgPHRleHQgZmlsbD0iIzhhODRhOCIgZm9udC1zaXplPSIxMC41IiBsZXR0ZXItc3BhY2luZz0iMS4yIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiB4PSIyNCIgeT0iMjQiPlRISU4gQ0FSUlksIE5PIENPTVBPU0lURSBTVEVQPC90ZXh0PgogICAgICA8cmVjdCBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS43NSIgeD0iMjQiIHk9IjQwIiB3aWR0aD0iNDMwIiBoZWlnaHQ9IjI1MiIgcng9IjEyIi8+CiAgICAgIDx0ZXh0IGZpbGw9IiM1MzRhYjciIGZvbnQtc2l6ZT0iMTIuNSIgZm9udC13ZWlnaHQ9IjUwMCIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iNDQiIHk9IjY4Ij4kbXVsdDwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iMTUwIiB5PSI2OCI+UFNVICYjMjE1OyBSIGludGVnZXJzPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSIxNTAiIHk9Ijg2Ij50aGUgbXVsdGlwbGljaXRpZXMgdGhhdCBjb29yZGluYXRlIHRoZSBuZXh0IHBlcmlvZDwvdGV4dD4KICAgICAgPGxpbmUgc3Ryb2tlPSIjZDlkY2U2IiBzdHJva2Utd2lkdGg9IjEuNiIgZmlsbD0ibm9uZSIgeDE9IjQ0IiB5MT0iMTAyIiB4Mj0iNDM0IiB5Mj0iMTAyIi8+CiAgICAgIDx0ZXh0IGZpbGw9IiM1MzRhYjciIGZvbnQtc2l6ZT0iMTIuNSIgZm9udC13ZWlnaHQ9IjUwMCIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iNDQiIHk9IjEyNiI+JHBzdV9zdHJhdHVtPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSIxNTAiIHk9IjEyNiI+dGhlIHN0cmF0dW0gZWFjaCBQU1UgYmVsb25ncyB0bzwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzUzNGFiNyIgZm9udC1zaXplPSIxMi41IiBmb250LXdlaWdodD0iNTAwIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiB4PSI0NCIgeT0iMTQ4Ij4kbmg8L3RleHQ+CiAgICAgIDx0ZXh0IGZpbGw9IiM0YTQ2NjAiIGZvbnQtc2l6ZT0iMTIiIHg9IjE1MCIgeT0iMTQ4Ij5udW1iZXIgb2YgUFNVcyBwZXIgc3RyYXR1bTwvdGV4dD4KICAgICAgPGxpbmUgc3Ryb2tlPSIjZDlkY2U2IiBzdHJva2Utd2lkdGg9IjEuNiIgZmlsbD0ibm9uZSIgeDE9IjQ0IiB5MT0iMTY0IiB4Mj0iNDM0IiB5Mj0iMTY0Ii8+CiAgICAgIDx0ZXh0IGZpbGw9IiM1MzRhYjciIGZvbnQtc2l6ZT0iMTIuNSIgZm9udC13ZWlnaHQ9IjUwMCIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iNDQiIHk9IjE4OCI+JHRoZXRhPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSIxNTAiIHk9IjE4OCI+dGhlIFIgcmVwbGljYXRlIHZhbHVlcyBvZiBldmVyeSBlc3RpbWFuZDwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iMTUwIiB5PSIyMDYiPnRoaXMgaXMgd2hlcmUgdGhlIGNvdmFyaWFuY2UgYmV0d2VlbiBwZXJpb2RzIGNvbWVzIGZyb208L3RleHQ+CiAgICAgIDx0ZXh0IGZpbGw9IiM1MzRhYjciIGZvbnQtc2l6ZT0iMTIuNSIgZm9udC13ZWlnaHQ9IjUwMCIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iNDQiIHk9IjIyOCI+JHBvaW50PC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSIxNTAiIHk9IjIyOCI+dGhlIHBvaW50IGVzdGltYXRlIG9mIGV2ZXJ5IGVzdGltYW5kPC90ZXh0PgogICAgICA8bGluZSBzdHJva2U9IiNkOWRjZTYiIHN0cm9rZS13aWR0aD0iMS42IiBmaWxsPSJub25lIiB4MT0iNDQiIHkxPSIyNDQiIHgyPSI0MzQiIHkyPSIyNDQiLz4KICAgICAgPHRleHQgZmlsbD0iIzUzNGFiNyIgZm9udC1zaXplPSIxMi41IiBmb250LXdlaWdodD0iNTAwIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiB4PSI0NCIgeT0iMjY4Ij4kZGF0YV9mcDwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iMTUwIiB5PSIyNjgiPmEgZmluZ2VycHJpbnQgb2YgdGhlIG1pY3JvZGF0YSwgdG8gaWRlbnRpZnkgdGhlIHBlcmlvZDwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iMjQiIHk9IjMxNiI+NCBLQi4gTm8gcGVyc29uLWxldmVsIGRhdGEuPC90ZXh0PgoKICAgICAgPHRleHQgZmlsbD0iIzhhODRhOCIgZm9udC1zaXplPSIxMC41IiBsZXR0ZXItc3BhY2luZz0iMS4yIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiB4PSI1MDYiIHk9IjI0Ij5GQVQgQ0FSUlksIFdJVEggc3RlcF9jcmUoKTwvdGV4dD4KICAgICAgPHJlY3QgZmlsbD0iI2ZkZjZlOCIgc3Ryb2tlPSIjYzk5MDJhIiBzdHJva2Utd2lkdGg9IjEuNzUiIHg9IjUwNiIgeT0iNDAiIHdpZHRoPSI0MzAiIGhlaWdodD0iMjUyIiByeD0iMTIiLz4KICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iNTI2IiB5PSI2OCI+ZXZlcnl0aGluZyBpbiB0aGUgdGhpbiBjYXJyeSwgYW5kPC90ZXh0PgogICAgICA8bGluZSBzdHJva2U9IiNkOWRjZTYiIHN0cm9rZS13aWR0aD0iMS42IiBmaWxsPSJub25lIiB4MT0iNTI2IiB5MT0iODQiIHgyPSI5MTYiIHkyPSI4NCIvPgogICAgICA8dGV4dCBmaWxsPSIjOGE2NDE0IiBmb250LXNpemU9IjEyLjUiIGZvbnQtd2VpZ2h0PSI1MDAiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjUyNiIgeT0iMTEyIj4kcmVwczwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iNjMyIiB5PSIxMTIiPnVuaXRzICYjMjE1OyBSPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSI2MzIiIHk9IjEzMCI+dGhlIHJlcGxpY2F0ZSB3ZWlnaHRzIG9mIHRoZSBwZXJpb2Q7PC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSI2MzIiIHk9IjE0OCI+dGhpcyBpcyB3aGF0IHJlYnVpbGRzIFpoYXQgcmVwbGljYXRlIGJ5IHJlcGxpY2F0ZTwvdGV4dD4KICAgICAgPGxpbmUgc3Ryb2tlPSIjZDlkY2U2IiBzdHJva2Utd2lkdGg9IjEuNiIgZmlsbD0ibm9uZSIgeDE9IjUyNiIgeTE9IjE2NCIgeDI9IjkxNiIgeTI9IjE2NCIvPgogICAgICA8dGV4dCBmaWxsPSIjOGE2NDE0IiBmb250LXNpemU9IjEyLjUiIGZvbnQtd2VpZ2h0PSI1MDAiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjUyNiIgeT0iMTg4Ij4kZGF0YTwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iNjMyIiB5PSIxODgiPnRoZSBwZXJpb2QgbWljcm9kYXRhLCBuZWVkZWQgdG8gYnVpbGQ8L3RleHQ+CiAgICAgIDx0ZXh0IGZpbGw9IiM0YTQ2NjAiIGZvbnQtc2l6ZT0iMTIiIHg9IjYzMiIgeT0iMjA2Ij50aGUgY29tcG9zaXRlIFogYmxvY2tzPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjOGE2NDE0IiBmb250LXNpemU9IjEyLjUiIGZvbnQtd2VpZ2h0PSI1MDAiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjUyNiIgeT0iMjI4Ij4kd2VpZ2h0czwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iNjMyIiB5PSIyMjgiPnRoZSBwb2ludCB3ZWlnaHRzIG9mIHRoZSBwZXJpb2Q8L3RleHQ+CiAgICAgIDxsaW5lIHN0cm9rZT0iI2Q5ZGNlNiIgc3Ryb2tlLXdpZHRoPSIxLjYiIGZpbGw9Im5vbmUiIHgxPSI1MjYiIHkxPSIyNDQiIHgyPSI5MTYiIHkyPSIyNDQiLz4KICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iNTI2IiB5PSIyNjgiPml0IGlzIHBpY2tlZCBhdXRvbWF0aWNhbGx5OiBjYXJyeSA9ICJhdXRvIiBkZXRlY3RzIGl0PC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSI1MDYiIHk9IjMxNiI+MTYwIEtCLiBJdCBob2xkcyBtaWNyb2RhdGE6IHRyZWF0IGl0IGFzIHN1Y2guPC90ZXh0PgoKPC9zdmc+Cg==)

``` r

cy <- readRDS(file.path(store, "2026-03.rds"))
names(cy)[!vapply(cy, is.null, logical(1))]
#> [1] "period"      "seq"         "mult"        "nh"          "psu_stratum"
#> [6] "theta"       "point"       "data_fp"     "meta"

c(carry_KB  = round(file.size(file.path(store, "2026-03.rds")) / 1024, 1),
  period_rows = nrow(subset(panel_ine, wave == 3 & disposition == "R")))
#>    carry_KB period_rows 
#>         5.1      1718.0
```

Four kilobytes against a period file of some seventeen hundred rows, and
no person level data in it at all: `$data`, `$reps` and `$weights` are
`NULL` in a thin carry. It is a sufficient statistic for the
coordination, not a copy of the survey. That matters for more than disk:
a carry can be moved between systems and kept for years without carrying
a disclosure problem with it.

A recipe ending in
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
is the exception. Its control totals are **estimated with the previous
wave**, so replicate `b` of period `t` has to rebuild them from
replicate `b` of period `t-1`, which means the previous period’s
replicate weights have to travel too. `carry = "auto"` detects it, and
the object grows accordingly:

``` r

thin <- wave_step(rec(w1), estimands = one(w1), replicates = 60, strata = "stratum",
                  psu = "psu", period = "t1", seed = 1, progress = FALSE)
fat  <- wave_step(rec(w1), estimands = one(w1), replicates = 60, strata = "stratum",
                  psu = "psu", period = "t1", seed = 1, carry = "fat", progress = FALSE)

f <- function(x) { p <- tempfile(); saveRDS(wave_carry(x), p); round(file.size(p) / 1024, 1) }
c(thin_KB = f(thin), fat_KB = f(fat))
#> thin_KB  fat_KB 
#>     4.0   160.7
```

Forty times larger, and it holds the microdata. Keep it under the same
rules as the microdata itself.

## Combinations over the chain

[`wave_step()`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
reports pairwise changes. A rolling quarter is not pairwise, and
[`wave_contrast()`](https://jpferreira33.github.io/weightflow/reference/wave_contrast.md)
estimates any linear combination straight from the saved carries,
without the waves being in memory:

``` r

tr <- lapply(file.path(store, paste0(month, ".rds")), readRDS)

wave_contrast(tr, "unemp")[, c("estimand", "estimate", "se", "lo", "hi")]
#>   estimand estimate         se       lo       hi
#> 1    unemp 0.275714 0.01057827 0.254981 0.296447
wave_contrast(tr, "unemp", contrast = c(-1, 0, 1))[, c("estimand", "estimate", "se")]
#>   estimand    estimate         se
#> 1    unemp 0.001005467 0.01294508
```

That second line is the change from January to March, computed from
three files on disk, and it is the same number the chain already
reported in `$change`. It works because each carry stores the `R`
replicate values of every declared estimand, and those replicates are
**paired across periods**: the coordination transferred the
multiplicities. Stacking them into an `R` by `W` matrix recovers the
whole covariance matrix, and any contrast follows from it as
`V(a'theta) = a' Sigma a`:

``` r

S <- vapply(tr, function(p) p$theta[["unemp"]], numeric(60))
colnames(S) <- month
signif(stats::cov(S), 3)
#>          2026-01  2026-02  2026-03
#> 2026-01 1.55e-04 1.09e-04 7.81e-05
#> 2026-02 1.09e-04 1.49e-04 8.43e-05
#> 2026-03 7.81e-05 8.43e-05 1.72e-04
```

The covariances fall off with the lag, as the overlap profile says they
should.

### The composite estimator

When the recipe ends in
[`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md),
the calibration of period $`t`$ targets two blocks at once: the known
demographic totals $`\mathbf{X}`$, and composite totals
$`\widehat{\mathbf{Z}}`$**estimated with the previous wave**. Treating
the second block as if it were known makes the variance
anticonservative, which is why the fat carry exists. `$n_cre_injected`
and `$n_cre_skipped` audit that the injection happened, and a recipe
that points at a period missing from the chain is refused rather than
quietly given the wrong one.

The estimator, its two imputations for the birth rotation group and the
tuning constant $`\alpha`$ are in
[`vignette("composite-estimation")`](https://jpferreira33.github.io/weightflow/articles/composite-estimation.md).

## Gross flows: who moved

A net change is a difference of aggregates. It cannot distinguish an
immobile population from one where equal numbers enter and leave
employment. For that you need the **longitudinal** file and a
longitudinal weight. It is a second branch off the same microdata and
the same cross-sectional recipe, and it does not take part in the chain:
it produces no carry and consumes none.

![The two branches: how much changed, and who
moved](data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPHN2ZyB3aWR0aD0iMTAwJSIgdmlld0JveD0iMCAwIDk2MCAzOTYiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwnSW50ZXInLFNlZ29lIFVJLFJvYm90byxzYW5zLXNlcmlmOyI+Cjx0aXRsZT5UaGUgdHdvIGJyYW5jaGVzOiBob3cgbXVjaCBjaGFuZ2VkLCBhbmQgd2hvIG1vdmVkPC90aXRsZT4KPGRlc2M+VGhlIGNyb3NzLXNlY3Rpb25hbCBicmFuY2ggd2VpZ2h0cyBlYWNoIHdhdmUgc2VwYXJhdGVseSBhbmQgdGhlIGNvb3JkaW5hdGVkIGJvb3RzdHJhcCByZXR1cm5zIHRoZSBuZXQgY2hhbmdlIHdpdGggaXRzIHN0YW5kYXJkIGVycm9yLiBUaGUgbG9uZ2l0dWRpbmFsIGJyYW5jaCBsaW5rcyB0aGUgc2FtZSB1bml0cyBpbnRvIGEgd2lkZSBmaWxlLCBhZGp1c3RzIGZvciBhdHRyaXRpb24gYW5kIHJldHVybnMgdGhlIGdyb3NzIGZsb3cgbWF0cml4LCB3aXRoIGEgYm9vdHN0cmFwIHN0YW5kYXJkIGVycm9yIHBlciBjZWxsLjwvZGVzYz4KPGRlZnM+PG1hcmtlciBpZD0iYTYiIHZpZXdCb3g9IjAgMCAxMCAxMCIgcmVmWD0iOSIgcmVmWT0iNSIgbWFya2VyV2lkdGg9IjciIG1hcmtlckhlaWdodD0iNyIgb3JpZW50PSJhdXRvLXN0YXJ0LXJldmVyc2UiPjxwYXRoIGQ9Ik0wLDAgTDEwLDUgTDAsMTAgeiIgZmlsbD0iIzFkOWU3NSIvPjwvbWFya2VyPjxtYXJrZXIgaWQ9ImE3IiB2aWV3Qm94PSIwIDAgMTAgMTAiIHJlZlg9IjkiIHJlZlk9IjUiIG1hcmtlcldpZHRoPSI3IiBtYXJrZXJIZWlnaHQ9IjciIG9yaWVudD0iYXV0by1zdGFydC1yZXZlcnNlIj48cGF0aCBkPSJNMCwwIEwxMCw1IEwwLDEwIHoiIGZpbGw9IiM0YTQ2NjAiLz48L21hcmtlcj48L2RlZnM+CgogICAgICA8cmVjdCBmaWxsPSIjZmZmZmZmIiBzdHJva2U9IiNkOWRjZTYiIHN0cm9rZS13aWR0aD0iMS41IiB4PSIyNCIgeT0iNDYiIHdpZHRoPSIxOTYiIGhlaWdodD0iNjYiIHJ4PSIxMCIvPgogICAgICA8dGV4dCBmaWxsPSIjMjAyNDJlIiBmb250LXNpemU9IjE0LjUiIGZvbnQtd2VpZ2h0PSI2MDAiIHg9IjQyIiB5PSI3MiI+V2F2ZSB0PC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSI0MiIgeT0iOTQiPmNyb3NzLXNlY3Rpb25hbCByZWNpcGUsIHByZXAoKTwvdGV4dD4KCiAgICAgIDxyZWN0IGZpbGw9IiNmZmZmZmYiIHN0cm9rZT0iI2Q5ZGNlNiIgc3Ryb2tlLXdpZHRoPSIxLjUiIHg9IjI0IiB5PSIxNDYiIHdpZHRoPSIxOTYiIGhlaWdodD0iNjYiIHJ4PSIxMCIvPgogICAgICA8dGV4dCBmaWxsPSIjMjAyNDJlIiBmb250LXNpemU9IjE0LjUiIGZvbnQtd2VpZ2h0PSI2MDAiIHg9IjQyIiB5PSIxNzIiPldhdmUgdCsxPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSI0MiIgeT0iMTk0Ij5jcm9zcy1zZWN0aW9uYWwgcmVjaXBlLCBwcmVwKCk8L3RleHQ+CgogICAgICA8dGV4dCBmaWxsPSIjOGE4NGE4IiBmb250LXNpemU9IjEwLjUiIGxldHRlci1zcGFjaW5nPSIxLjIiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjI3MCIgeT0iMzQiPkNST1NTLVNFQ1RJT05BTCBCUkFOQ0g6IEhPVyBNVUNIIENIQU5HRUQ8L3RleHQ+CiAgICAgIDxsaW5lIHN0cm9rZT0iIzRhNDY2MCIgc3Ryb2tlLXdpZHRoPSIxLjYiIGZpbGw9Im5vbmUiIHgxPSIyMjAiIHkxPSI3OSIgeDI9IjMwNCIgeTI9IjEwMCIgbWFya2VyLWVuZD0idXJsKCNhNykiLz4KICAgICAgPGxpbmUgc3Ryb2tlPSIjNGE0NjYwIiBzdHJva2Utd2lkdGg9IjEuNiIgZmlsbD0ibm9uZSIgeDE9IjIyMCIgeTE9IjE3OSIgeDI9IjMwNCIgeTI9IjEzMCIgbWFya2VyLWVuZD0idXJsKCNhNykiLz4KICAgICAgPHJlY3QgZmlsbD0iI2ZmZmZmZiIgc3Ryb2tlPSIjM2QzNTgwIiBzdHJva2Utd2lkdGg9IjIiIHg9IjMwOCIgeT0iNzYiIHdpZHRoPSIxOTAiIGhlaWdodD0iNzYiIHJ4PSIxMSIvPgogICAgICA8dGV4dCBmaWxsPSIjMjAyNDJlIiBmb250LXNpemU9IjEzIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiB4PSI0MDMiIHk9IjEwNiIgdGV4dC1hbmNob3I9Im1pZGRsZSI+d2F2ZV9zdGVwKCk8L3RleHQ+CiAgICAgIDx0ZXh0IGZpbGw9IiM0YTQ2NjAiIGZvbnQtc2l6ZT0iMTIiIHg9IjQwMyIgeT0iMTMwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIj5jb29yZGluYXRlZCBib290c3RyYXA8L3RleHQ+CiAgICAgIDxsaW5lIHN0cm9rZT0iIzRhNDY2MCIgc3Ryb2tlLXdpZHRoPSIxLjYiIGZpbGw9Im5vbmUiIHgxPSI0OTgiIHkxPSIxMTQiIHgyPSI1OTYiIHkyPSIxMTQiIG1hcmtlci1lbmQ9InVybCgjYTcpIi8+CiAgICAgIDxyZWN0IGZpbGw9IiNmZmZmZmYiIHN0cm9rZT0iI2Q5ZGNlNiIgc3Ryb2tlLXdpZHRoPSIxLjUiIHg9IjYwMCIgeT0iODIiIHdpZHRoPSIzMzYiIGhlaWdodD0iNjYiIHJ4PSIxMCIvPgogICAgICA8dGV4dCBmaWxsPSIjMjAyNDJlIiBmb250LXNpemU9IjE0LjUiIGZvbnQtd2VpZ2h0PSI2MDAiIHg9IjYxOCIgeT0iMTA4Ij5OZXQgY2hhbmdlIHdpdGggaXRzIFNFPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSI2MTgiIHk9IjEzMCI+ViA9IFYxICsgVjIgLSAyIGNvdiwgb25lIG51bWJlciBwZXIgZXN0aW1hbmQ8L3RleHQ+CgogICAgICA8bGluZSBzdHJva2U9IiNkOWRjZTYiIHN0cm9rZS13aWR0aD0iMS42IiBmaWxsPSJub25lIiB4MT0iMjQiIHkxPSIyMzgiIHgyPSI5MzYiIHkyPSIyMzgiLz4KCiAgICAgIDx0ZXh0IGZpbGw9IiM4YTg0YTgiIGZvbnQtc2l6ZT0iMTAuNSIgbGV0dGVyLXNwYWNpbmc9IjEuMiIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgeD0iMjcwIiB5PSIyNTAiPkxPTkdJVFVESU5BTCBCUkFOQ0g6IFdITyBNT1ZFRDwvdGV4dD4KICAgICAgPHBhdGggc3Ryb2tlPSIjMWQ5ZTc1IiBzdHJva2Utd2lkdGg9IjIiIGZpbGw9Im5vbmUiIGQ9Ik0xMjIsMjEyIEwxMjIsMjkwIEwzMDQsMjkwIiBtYXJrZXItZW5kPSJ1cmwoI2E2KSIvPgogICAgICA8dGV4dCBmaWxsPSIjMTU1MDNjIiBmb250LXNpemU9IjEyLjUiIGZvbnQtd2VpZ2h0PSI1MDAiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIHg9IjEzMiIgeT0iMjU4Ij5wYW5lbF9tZXJnZSgpPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSIxMzIiIHk9IjI3NiI+bGlua3Mgb24gdGhlIHVuaXQga2V5PC90ZXh0PgoKICAgICAgPHJlY3QgZmlsbD0iI2VhZjVmMCIgc3Ryb2tlPSIjMWQ5ZTc1IiBzdHJva2Utd2lkdGg9IjEuNzUiIHg9IjMwOCIgeT0iMjU2IiB3aWR0aD0iMTkwIiBoZWlnaHQ9IjkwIiByeD0iMTEiLz4KICAgICAgPHRleHQgZmlsbD0iIzIwMjQyZSIgZm9udC1zaXplPSIxNC41IiBmb250LXdlaWdodD0iNjAwIiB4PSI0MDMiIHk9IjI4MiIgdGV4dC1hbmNob3I9Im1pZGRsZSI+V2lkZSBmaWxlPC90ZXh0PgogICAgICA8dGV4dCBmaWxsPSIjNGE0NjYwIiBmb250LXNpemU9IjEyIiB4PSI0MDMiIHk9IjMwNCIgdGV4dC1hbmNob3I9Im1pZGRsZSI+b25lIHJvdyBwZXIgdW5pdDwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzE1NTAzYyIgZm9udC1zaXplPSIxMi41IiBmb250LXdlaWdodD0iNTAwIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiB4PSI0MDMiIHk9IjMyNiIgdGV4dC1hbmNob3I9Im1pZGRsZSI+c3RlcF9hdHRyaXRpb24oKTwvdGV4dD4KCiAgICAgIDxsaW5lIHN0cm9rZT0iIzFkOWU3NSIgc3Ryb2tlLXdpZHRoPSIyIiBmaWxsPSJub25lIiB4MT0iNDk4IiB5MT0iMzAwIiB4Mj0iNTk2IiB5Mj0iMzAwIiBtYXJrZXItZW5kPSJ1cmwoI2E2KSIvPgogICAgICA8cmVjdCBmaWxsPSIjZWFmNWYwIiBzdHJva2U9IiMxZDllNzUiIHN0cm9rZS13aWR0aD0iMS43NSIgeD0iNjAwIiB5PSIyNTYiIHdpZHRoPSIzMzYiIGhlaWdodD0iOTAiIHJ4PSIxMCIvPgogICAgICA8dGV4dCBmaWxsPSIjMjAyNDJlIiBmb250LXNpemU9IjE0LjUiIGZvbnQtd2VpZ2h0PSI2MDAiIHg9IjYxOCIgeT0iMjgyIj5Hcm9zcyBmbG93IG1hdHJpeDwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iNjE4IiB5PSIzMDQiPlAoc3RhdGUgYXQgdCsxIHwgc3RhdGUgYXQgdCksIGNvdW50cywgbmV0IGZsb3dzLDwvdGV4dD4KICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iNjE4IiB5PSIzMjIiPnN0YXllcnMgYW5kIG1vdmVycywgZWFjaCB3aXRoIGEgYm9vdHN0cmFwIFNFPC90ZXh0PgoKICAgICAgPHRleHQgZmlsbD0iIzRhNDY2MCIgZm9udC1zaXplPSIxMiIgeD0iMjQiIHk9IjM4MCI+Qm90aCBicmFuY2hlcyBzdGFydCBmcm9tIHRoZSBzYW1lIG1pY3JvZGF0YSBhbmQgdGhlIHNhbWUgY3Jvc3Mtc2VjdGlvbmFsIHJlY2lwZS48L3RleHQ+Cgo8L3N2Zz4K)

``` r

wide <- panel_merge(list(T1 = subset(panel_ine, wave == 1),
                         T2 = subset(panel_ine, wave == 2)),
                    by = c("household_id", "person_no"), require = "all")

lw <- weighting_spec(wide, base_weights = pw_T1) |>
  step_drop_ineligible(disposition_T2 == "OS", reason = "left the target population") |>
  step_attrition(respondent = disposition_T2 == "R", method = "propensity",
                 formula = ~ age_T1 + sex_T1) |>
  prep()

transition_matrix(lw, from = "lf_status_T1", to = "lf_status_T2", format = "row")
#> Warning: The flow table covers 96.2% of the weight: 3.8% with a missing state.
#> Those units are not in any cell, so the conditional and joint formats
#> renormalize over the rest. In a panel that share is usually the attrition --
#> decide it explicitly (an 'out of scope' state, or step_drop_ineligible()).
#> <weightflow transition: lf_status_T1 -> lf_status_T2  [row]>
#>        to
#> from       emp inact  unemp
#>   emp   0.9547     0 0.0453
#>   inact 0.0000     1 0.0000
#>   unemp 0.1120     0 0.8880
```

[`boot_transition()`](https://jpferreira33.github.io/weightflow/reference/boot_transition.md)
adds a standard error per cell, and
[`boot_flows()`](https://jpferreira33.github.io/weightflow/reference/boot_flows.md)
gives the same information as population totals plus the net flows
`i->j` minus `j->i` and the margins, i.e. how many started in each
state, ended in each, stayed, and moved.

A caveat about the illustration, not the method: the four shipped panel
datasets are synthetic, and in all of them **inactivity is an absorbing
state**, so nobody enters or leaves it. The matrix above therefore shows
movement only between employment and unemployment, and the `inact` row
and column are degenerate. The mechanics are the point here; on real
microdata the transitions in and out of inactivity are usually the
interesting ones.

Note the order of the two steps, which is not cosmetic. **Leaving the
target population is not nonresponse.** Someone who died or emigrated is
removed from the universe with
[`step_drop_ineligible()`](https://jpferreira33.github.io/weightflow/reference/step_drop_ineligible.md),
and their weight is not redistributed to anyone. Someone who is still in
the universe but did not answer is attrition, and their weight *is*
redistributed, among the units that remain. Collapsing the two inflates
the population.

Three further conventions govern a longitudinal weight: who belongs to
the longitudinal population, which period’s totals to calibrate to, and
why cross-sectional estimates from a longitudinal file are reference
only. They are decisions the analyst makes and the package cannot check,
and they are set out in
[`vignette("panel-longitudinal")`](https://jpferreira33.github.io/weightflow/articles/panel-longitudinal.md)
and in
[`?step_cross_sectional`](https://jpferreira33.github.io/weightflow/reference/step_cross_sectional.md).

## Where to look next

This vignette is the entry point; three companions go deeper into the
pieces it uses.

- [`vignette("coordinated-replication")`](https://jpferreira33.github.io/weightflow/articles/coordinated-replication.md)
  for what actually travels between waves, the four coordination cases,
  and how to read the `$strata` diagnostic that decides whether a change
  is publishable.
- [`vignette("composite-estimation")`](https://jpferreira33.github.io/weightflow/articles/composite-estimation.md)
  for
  [`step_cre()`](https://jpferreira33.github.io/weightflow/reference/step_cre.md)
  in full: what the composite estimator buys, and why its control totals
  make its variance a special case.
- [`vignette("panel-longitudinal")`](https://jpferreira33.github.io/weightflow/articles/panel-longitudinal.md)
  for the **pure** panel: attrition over many waves, the longitudinal
  weight, and gross flows.

For the reference pages:
[`?wave_step`](https://jpferreira33.github.io/weightflow/reference/wave_step.md)
and
[`?wave_carry`](https://jpferreira33.github.io/weightflow/reference/wave_carry.md)
for the chaining engine,
[`?wave_contrast`](https://jpferreira33.github.io/weightflow/reference/wave_contrast.md)
for combinations over a chain,
[`?panel_design`](https://jpferreira33.github.io/weightflow/reference/panel_design.md)
for the structure layer,
[`?transition_matrix`](https://jpferreira33.github.io/weightflow/reference/transition_matrix.md)
for the flows, and
[`?report_panel`](https://jpferreira33.github.io/weightflow/reference/report_panel.md)
for a quality report of a panel run.
[`vignette("variance-estimation")`](https://jpferreira33.github.io/weightflow/articles/variance-estimation.md)
covers the single-period bootstrap this one builds on, and
[`vignette("validation")`](https://jpferreira33.github.io/weightflow/articles/validation.md)
checks the change variance against an analytic estimator from a
different family.
