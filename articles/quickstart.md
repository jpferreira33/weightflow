# From raw sample to final weights

> **New here?** This is the 15-minute tour: what problem `weightflow`
> solves and the shortest recipe that produces analysis weights. For the
> statistical reasoning behind each adjustment, read [*Staged survey
> weighting: the adjustment
> logic*](https://jpferreira33.github.io/weightflow/articles/weightflow.md).

> **Development version.** The cascade shown here is on CRAN. Two
> conveniences used below are development-version only (GitHub): the
> tidy data-frame calibration totals (`count = "Freq"`) and the
> R-indicator line that
> [`summary()`](https://rdrr.io/r/base/summary.html) prints after a
> nonresponse step. Install with
> `remotes::install_github("jpferreira33/weightflow")`.

## The problem is not the weights

Every survey organization has weighting scripts. They grow over time,
absorb new adjustments, and eventually become difficult to understand,
maintain and reproduce. Two analysts can implement the *same* weighting
strategy in different ways, which turns audits, updates and
methodological reviews into archaeology.

The weights themselves are rarely the hard part. The hard part is that
the *strategy* (the sequence of methodological decisions that produced
the weights) is scattered across files, intermediate objects and the
memory of whoever ran them last. When the responsible methodologist
moves on, the knowledge often leaves with them.

A typical pipeline looks like this:

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwJSIgdmlld2JveD0iMCAwIDY4MCA0NzAiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwmIzM5O0ludGVyJiMzOTssU2Vnb2UgVUksUm9ib3RvLHNhbnMtc2VyaWY7Ij48dGl0bGU+CldlaWdodGluZyBzcHJlYWQgYWNyb3NzIHNjcmlwdHMgYW5kIGludGVybWVkaWF0ZSBmaWxlcwo8L3RpdGxlPgo8ZGVzYz5TYW1wbGluZyBmZWVkcyBzY3JpcHQxLlIsIHdoaWNoIHdyaXRlcyB3ZWlnaHRzMS5jc3YsIHJlYWQgYnkKc2NyaXB0Mi5SLCB3aGljaCB3cml0ZXMgd2VpZ2h0czIuY3N2LCByZWFkIGJ5IHNjcmlwdF9maW5hbF92Ny5SLCB3aGljaAp3cml0ZXMgZmluYWxfd2VpZ2h0c19ORVcuY3N2LiBUaGUgc3RlcHMgemlnemFnIGJldHdlZW4gY29kZSBmaWxlcyBhbmQKaW50ZXJtZWRpYXRlIENTVnMuPC9kZXNjPjxkZWZzPjxtYXJrZXIgaWQ9InFzcmVkIiB2aWV3Ym94PSIwIDAgMTAgMTAiIHJlZng9IjgiIHJlZnk9IjUiIG1hcmtlcndpZHRoPSI3IiBtYXJrZXJoZWlnaHQ9IjciIG9yaWVudD0iYXV0by1zdGFydC1yZXZlcnNlIj48cGF0aCBkPSJNMiAxTDggNUwyIDkiIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzlhOGY4ZiIgc3Ryb2tlLXdpZHRoPSIxLjciIC8+PC9tYXJrZXI+PC9kZWZzPjxsaW5lIHgxPSIzMjAiIHkxPSI2MiIgeDI9IjE4OCIgeTI9IjkwIiBzdHJva2U9IiM5YThmOGYiIHN0cm9rZS13aWR0aD0iMS41IiBtYXJrZXItZW5kPSJ1cmwoI3FzcmVkKSI+PC9saW5lPjxsaW5lIHgxPSIyNTUiIHkxPSIxMjAiIHgyPSI0MjMiIHkyPSIxNjgiIHN0cm9rZT0iIzlhOGY4ZiIgc3Ryb2tlLXdpZHRoPSIxLjUiIG1hcmtlci1lbmQ9InVybCgjcXNyZWQpIj48L2xpbmU+PGxpbmUgeDE9IjQyNSIgeTE9IjE4MiIgeDI9IjI1NyIgeTI9IjIyMCIgc3Ryb2tlPSIjOWE4ZjhmIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNxc3JlZCkiPjwvbGluZT48bGluZSB4MT0iMjU1IiB5MT0iMjM4IiB4Mj0iNDIzIiB5Mj0iMjg0IiBzdHJva2U9IiM5YThmOGYiIHN0cm9rZS13aWR0aD0iMS41IiBtYXJrZXItZW5kPSJ1cmwoI3FzcmVkKSI+PC9saW5lPjxsaW5lIHgxPSI0MjUiIHkxPSIyOTgiIHgyPSIyNjIiIHkyPSIzMzYiIHN0cm9rZT0iIzlhOGY4ZiIgc3Ryb2tlLXdpZHRoPSIxLjUiIG1hcmtlci1lbmQ9InVybCgjcXNyZWQpIj48L2xpbmU+PGxpbmUgeDE9IjI2NSIgeTE9IjM1NiIgeDI9IjQxMyIgeTI9IjM5MCIgc3Ryb2tlPSIjOWE4ZjhmIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNxc3JlZCkiPjwvbGluZT48cmVjdCB4PSIyOTAiIHk9IjI4IiB3aWR0aD0iMTAwIiBoZWlnaHQ9IjM0IiByeD0iMTciIGZpbGw9IiNlY2U5ZjYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjMiIC8+PHRleHQgeD0iMzQwIiB5PSI1MCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZmlsbD0iIzIwMjQyZSI+c2FtcGxpbmc8L3RleHQ+PHJlY3QgeD0iOTUiIHk9IjkwIiB3aWR0aD0iMTYwIiBoZWlnaHQ9IjQwIiByeD0iOCIgZmlsbD0iI2U4ZTdlZiIgc3Ryb2tlPSIjNmI2YTg2IiBzdHJva2Utd2lkdGg9IjEuMyIgLz48dGV4dCB4PSIxNzUiIHk9IjExNSIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IiYjMzk7SmV0QnJhaW5zIE1vbm8mIzM5Oyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjMzMzMjNmIj5zY3JpcHQxLlI8L3RleHQ+PHJlY3QgeD0iNDI1IiB5PSIxNTAiIHdpZHRoPSIxNjAiIGhlaWdodD0iNDAiIHJ4PSI4IiBmaWxsPSIjZjRlMmI4IiBzdHJva2U9IiNjOTkwMmEiIHN0cm9rZS13aWR0aD0iMS4zIiAvPjx0ZXh0IHg9IjUwNSIgeT0iMTc1IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmb250LWZhbWlseT0iJiMzOTtKZXRCcmFpbnMgTW9ubyYjMzk7LHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiM1YzQ0MTAiPndlaWdodHMxLmNzdjwvdGV4dD48cmVjdCB4PSI5NSIgeT0iMjA4IiB3aWR0aD0iMTYwIiBoZWlnaHQ9IjQwIiByeD0iOCIgZmlsbD0iI2U4ZTdlZiIgc3Ryb2tlPSIjNmI2YTg2IiBzdHJva2Utd2lkdGg9IjEuMyIgLz48dGV4dCB4PSIxNzUiIHk9IjIzMyIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IiYjMzk7SmV0QnJhaW5zIE1vbm8mIzM5Oyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjMzMzMjNmIj5zY3JpcHQyLlI8L3RleHQ+PHJlY3QgeD0iNDI1IiB5PSIyNjYiIHdpZHRoPSIxNjAiIGhlaWdodD0iNDAiIHJ4PSI4IiBmaWxsPSIjZjRlMmI4IiBzdHJva2U9IiNjOTkwMmEiIHN0cm9rZS13aWR0aD0iMS4zIiAvPjx0ZXh0IHg9IjUwNSIgeT0iMjkxIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmb250LWZhbWlseT0iJiMzOTtKZXRCcmFpbnMgTW9ubyYjMzk7LHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiM1YzQ0MTAiPndlaWdodHMyLmNzdjwvdGV4dD48cmVjdCB4PSI5MCIgeT0iMzI0IiB3aWR0aD0iMTc1IiBoZWlnaHQ9IjQwIiByeD0iOCIgZmlsbD0iI2U4ZTdlZiIgc3Ryb2tlPSIjNmI2YTg2IiBzdHJva2Utd2lkdGg9IjEuMyIgLz48dGV4dCB4PSIxNzciIHk9IjM0OSIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZm9udC1mYW1pbHk9IiYjMzk7SmV0QnJhaW5zIE1vbm8mIzM5Oyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjMzMzMjNmIj5zY3JpcHRfZmluYWxfdjcuUjwvdGV4dD48cmVjdCB4PSI0MTMiIHk9IjM4MiIgd2lkdGg9IjE5MCIgaGVpZ2h0PSI0MCIgcng9IjgiIGZpbGw9IiNmMmNmYzciIHN0cm9rZT0iI2MwNDkyZiIgc3Ryb2tlLXdpZHRoPSIxLjMiIC8+PHRleHQgeD0iNTA4IiB5PSI0MDciIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSImIzM5O0pldEJyYWlucyBNb25vJiMzOTssdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzdhMjYxOCI+ZmluYWxfd2VpZ2h0c19ORVcuY3N2PC90ZXh0Pjx0ZXh0IHg9IjM0MCIgeT0iNDUyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmb250LXN0eWxlPSJpdGFsaWMiIGZpbGw9IiM4YTdmN2YiPkxvZ2ljCnNjYXR0ZXJlZCBhY3Jvc3MgZmlsZXMgYW5kIHJ1biBvcmRlciwgbm90IGtlcHQgaW4gb25lIHBsYWNlLjwvdGV4dD48L3N2Zz4=)

Anyone who has worked in a statistical office recognizes this
immediately. Along the way you typically reach for many different
packages, spread the logic across several scripts, and generate hundreds
of lines of code. The methodology is real, but it is *implicit*: hidden
in file order, column names, intermediate files and undocumented tweaks.

## A map of what the steps are for

Before we look at any code, one picture. Weights exist because the
realized sample differs from the population we want to describe, in
specific, nameable ways. Each region below is corrected by a specific
step.

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwJSIgdmlld2JveD0iMCAwIDY4MCA1NjAiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwmIzM5O0ludGVyJiMzOTssU2Vnb2UgVUksUm9ib3RvLHNhbnMtc2VyaWY7Ij48dGl0bGU+CkZyb20gdGFyZ2V0IHBvcHVsYXRpb24gdG8gcmVzcG9uZGVudHMKPC90aXRsZT4KPGRlc2M+VHdvIG92ZXJsYXBwaW5nIGVsbGlwc2VzIHNob3cgdGhlIHRhcmdldCBwb3B1bGF0aW9uIGFuZCB0aGUKc2FtcGxpbmcgZnJhbWUsIHdpdGggdW5kZXJjb3ZlcmFnZSwgYW4gaW4tc2NvcGUgb3ZlcmxhcCwgYW5kCm91dC1vZi1zY29wZSB1bml0cy4gVGhlIGluLXNjb3BlIGFyZWEgaXMgc2FtcGxlZDsgdGhlIHNhbXBsZSBzcGxpdHMgaW50bwp1bmtub3duIGVsaWdpYmlsaXR5LCBpbmVsaWdpYmxlIGFuZCBlbGlnaWJsZSwgYW5kIGVsaWdpYmxlIHNwbGl0cyBpbnRvCm5vbnJlc3BvbmRlbnRzIGFuZCByZXNwb25kZW50cy4gQSBsZWdlbmQgbWFwcyBlYWNoIHJlZ2lvbiB0byBhCndlaWdodGZsb3cgc3RlcC48L2Rlc2M+PGRlZnM+PG1hcmtlciBpZD0icXNhcnJvdyIgdmlld2JveD0iMCAwIDEwIDEwIiByZWZ4PSI4IiByZWZ5PSI1IiBtYXJrZXJ3aWR0aD0iNyIgbWFya2VyaGVpZ2h0PSI3IiBvcmllbnQ9ImF1dG8tc3RhcnQtcmV2ZXJzZSI+PHBhdGggZD0iTTIgMUw4IDVMMiA5IiBmaWxsPSJub25lIiBzdHJva2U9IiM3YTdhODYiIHN0cm9rZS13aWR0aD0iMS42IiAvPjwvbWFya2VyPjwvZGVmcz48ZWxsaXBzZSBjeD0iMjU1IiBjeT0iMTEyIiByeD0iMTUyIiByeT0iNzIiIGZpbGw9IiM3YTZhZDAiIGZpbGwtb3BhY2l0eT0iMC4xNiIgc3Ryb2tlPSIjM2QzNTgwIiBzdHJva2Utd2lkdGg9IjEuNSI+PC9lbGxpcHNlPjxlbGxpcHNlIGN4PSI0MjUiIGN5PSIxMTIiIHJ4PSIxNTIiIHJ5PSI3MiIgZmlsbD0iIzhhOGY5YSIgZmlsbC1vcGFjaXR5PSIwLjE2IiBzdHJva2U9IiM1YjY0NzIiIHN0cm9rZS13aWR0aD0iMS41Ij48L2VsbGlwc2U+PHRleHQgeD0iMTgwIiB5PSI5MiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxNCIgZm9udC13ZWlnaHQ9IjYwMCIgZmlsbD0iIzIwMjQyZSI+VGFyZ2V0CnBvcHVsYXRpb248L3RleHQ+PHRleHQgeD0iNTAwIiB5PSI5MiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxNCIgZm9udC13ZWlnaHQ9IjYwMCIgZmlsbD0iIzIwMjQyZSI+RnJhbWU8L3RleHQ+PHRleHQgeD0iMTc4IiB5PSIxMjAiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiMzYTNmNGEiPlVuZGVyY292ZXJhZ2U8L3RleHQ+PHRleHQgeD0iMTc4IiB5PSIxMzYiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiMzYTNmNGEiPihtaXNzaW5nCmZyb20gZnJhbWUpPC90ZXh0Pjx0ZXh0IHg9IjM0MCIgeT0iMTE2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjE0IiBmaWxsPSIjMjAyNDJlIj5JbgpzY29wZTwvdGV4dD48dGV4dCB4PSI1MDAiIHk9IjEyMCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzNhM2Y0YSI+T3V0Cm9mIHNjb3BlPC90ZXh0Pjx0ZXh0IHg9IjUwMCIgeT0iMTM2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmaWxsPSIjM2EzZjRhIj4oaW5lbGlnaWJsZQpvbiBmcmFtZSk8L3RleHQ+PGxpbmUgeDE9IjM0MCIgeTE9IjE4NCIgeDI9IjM0MCIgeTI9IjIzMCIgc3Ryb2tlPSIjN2E3YTg2IiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNxc2Fycm93KSI+PC9saW5lPjx0ZXh0IHg9IjM1MCIgeT0iMjEyIiB0ZXh0LWFuY2hvcj0ic3RhcnQiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiMzYTNmNGEiPmRyYXcKc2FtcGxlIChkZXNpZ24gd2VpZ2h0IDEvz4ApPC90ZXh0PjxyZWN0IHg9IjU1IiB5PSIyMzIiIHdpZHRoPSI1NzAiIGhlaWdodD0iMTcwIiByeD0iMTAiIGZpbGw9IiNmNmY1ZmIiIHN0cm9rZT0iIzNkMzU4MCIgc3Ryb2tlLXdpZHRoPSIxLjQiIC8+PHRleHQgeD0iNzAiIHk9IjI1NiIgdGV4dC1hbmNob3I9InN0YXJ0IiBmb250LXNpemU9IjE0IiBmb250LXdlaWdodD0iNjAwIiBmaWxsPSIjMjAyNDJlIj5TYW1wbGUKKGtub3duIGluY2x1c2lvbiBwcm9iYWJpbGl0eSDPgCk8L3RleHQ+PHJlY3QgeD0iNzUiIHk9IjI4NCIgd2lkdGg9IjEzNSIgaGVpZ2h0PSI5OCIgcng9IjgiIGZpbGw9IiNmNGUyYjgiIHN0cm9rZT0iI2M5OTAyYSIgc3Ryb2tlLXdpZHRoPSIxLjMiIC8+PHRleHQgeD0iMTQyIiB5PSIzMjgiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTQiIGZpbGw9IiMyMDI0MmUiPlVua25vd248L3RleHQ+PHRleHQgeD0iMTQyIiB5PSIzNDYiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTQiIGZpbGw9IiMyMDI0MmUiPmVsaWdpYmlsaXR5PC90ZXh0PjxyZWN0IHg9IjIyNSIgeT0iMjg0IiB3aWR0aD0iMTIwIiBoZWlnaHQ9Ijk4IiByeD0iOCIgZmlsbD0iI2YyY2ZjNyIgc3Ryb2tlPSIjYzA0OTJmIiBzdHJva2Utd2lkdGg9IjEuMyIgLz48dGV4dCB4PSIyODUiIHk9IjMzOCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxNCIgZmlsbD0iIzIwMjQyZSI+SW5lbGlnaWJsZTwvdGV4dD48cmVjdCB4PSIzNjAiIHk9IjI3MCIgd2lkdGg9IjI1MiIgaGVpZ2h0PSIxMTUiIHJ4PSI4IiBmaWxsPSIjZTdlM2Y1IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS4zIiAvPjx0ZXh0IHg9IjM3NCIgeT0iMjg5IiB0ZXh0LWFuY2hvcj0ic3RhcnQiIGZvbnQtc2l6ZT0iMTQiIGZvbnQtd2VpZ2h0PSI2MDAiIGZpbGw9IiMyMDI0MmUiPkVsaWdpYmxlPC90ZXh0PjxyZWN0IHg9IjM3NCIgeT0iMzAwIiB3aWR0aD0iMTA4IiBoZWlnaHQ9IjcyIiByeD0iNyIgZmlsbD0iI2UzZTVlOSIgc3Ryb2tlPSIjOGE4ZjlhIiBzdHJva2Utd2lkdGg9IjEuMyIgLz48dGV4dCB4PSI0MjgiIHk9IjMzMiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZmlsbD0iIzIwMjQyZSI+Tm9uLTwvdGV4dD48dGV4dCB4PSI0MjgiIHk9IjM1MCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZmlsbD0iIzIwMjQyZSI+cmVzcG9uZGVudHM8L3RleHQ+PHJlY3QgeD0iNDk4IiB5PSIzMDAiIHdpZHRoPSIxMDAiIGhlaWdodD0iNzIiIHJ4PSI3IiBmaWxsPSIjY2RlYWRkIiBzdHJva2U9IiMxZDllNzUiIHN0cm9rZS13aWR0aD0iMS4zIiAvPjx0ZXh0IHg9IjU0OCIgeT0iMzQxIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmaWxsPSIjMjAyNDJlIj5SZXNwb25kZW50czwvdGV4dD48Y2lyY2xlIGN4PSI3NCIgY3k9IjQzMiIgcj0iNiIgZmlsbD0iI2M5OTAyYSI+PC9jaXJjbGU+PHRleHQgeD0iOTAiIHk9IjQzNiIgdGV4dC1hbmNob3I9InN0YXJ0IiBmb250LXNpemU9IjEyIiBmaWxsPSIjM2EzZjRhIj5Vbmtub3duCmVsaWdpYmlsaXR5IOKGkiBzdGVwX3Vua25vd25fZWxpZ2liaWxpdHkoKTogcmVkaXN0cmlidXRlIHRoZWlyCndlaWdodDwvdGV4dD48Y2lyY2xlIGN4PSI3NCIgY3k9IjQ1NiIgcj0iNiIgZmlsbD0iI2MwNDkyZiI+PC9jaXJjbGU+PHRleHQgeD0iOTAiIHk9IjQ2MCIgdGV4dC1hbmNob3I9InN0YXJ0IiBmb250LXNpemU9IjEyIiBmaWxsPSIjM2EzZjRhIj5JbmVsaWdpYmxlCuKGkiBzdGVwX2Ryb3BfaW5lbGlnaWJsZSgpOiByZW1vdmUgZnJvbSB0aGUgc2FtcGxlPC90ZXh0PjxjaXJjbGUgY3g9Ijc0IiBjeT0iNDgwIiByPSI2IiBmaWxsPSIjOGE4ZjlhIj48L2NpcmNsZT48dGV4dCB4PSI5MCIgeT0iNDg0IiB0ZXh0LWFuY2hvcj0ic3RhcnQiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiMzYTNmNGEiPk5vbnJlc3BvbmRlbnRzCuKGkiBzdGVwX25vbnJlc3BvbnNlKCk6IHJlc3BvbmRlbnRzIGFic29yYiB0aGVpciB3ZWlnaHQ8L3RleHQ+PGNpcmNsZSBjeD0iNzQiIGN5PSI1MDQiIHI9IjYiIGZpbGw9IiMxZDllNzUiPjwvY2lyY2xlPjx0ZXh0IHg9IjkwIiB5PSI1MDgiIHRleHQtYW5jaG9yPSJzdGFydCIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzNhM2Y0YSI+UmVzcG9uZGVudHMKY2FycnkgdGhlIGZpbmFsIGFuYWx5c2lzIHdlaWdodDwvdGV4dD48Y2lyY2xlIGN4PSI3NCIgY3k9IjUyOCIgcj0iNiIgZmlsbD0iIzdhNmFkMCI+PC9jaXJjbGU+PHRleHQgeD0iOTAiIHk9IjUzMiIgdGV4dC1hbmNob3I9InN0YXJ0IiBmb250LXNpemU9IjEyIiBmaWxsPSIjM2EzZjRhIj5Db3ZlcmFnZQomYW1wOyBrbm93biB0b3RhbHMg4oaSIHN0ZXBfY2FsaWJyYXRlKCk6IGFsaWduIHRvIHRoZSBwb3B1bGF0aW9uPC90ZXh0Pjwvc3ZnPg==)

The frame and the population *overlap* rather than nest: some of the
target population is missing from the frame (undercoverage) and some
frame units are out of scope (overcoverage). From the sample downward it
is pure nesting (sample ⊃ eligible ⊃ respondents), and each split is a
step. The weights are not conjured; they are the consequence of this
sequence of decisions.

## The same strategy as one object

`weightflow` expresses the whole strategy as a single, explicit recipe.
Nothing is hidden in a script; nothing lives in an intermediate CSV.
Every methodological decision is a `step_*()` you can read top to
bottom:

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwJSIgdmlld2JveD0iMCAwIDY4MCA0NDgiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwmIzM5O0ludGVyJiMzOTssU2Vnb2UgVUksUm9ib3RvLHNhbnMtc2VyaWY7Ij48dGl0bGU+ClRoZSB3aG9sZSBzdHJhdGVneSBhcyBvbmUgcmVjaXBlIG9iamVjdAo8L3RpdGxlPgo8ZGVzYz5BIHNpbmdsZSBjb250YWluZXIgaG9sZHMgd2VpZ2h0aW5nX3NwZWMoKSBhbmQgYSBzdGFjayBvZiBzdGVwCmZ1bmN0aW9uczogdW5rbm93biBlbGlnaWJpbGl0eSwgZHJvcCBpbmVsaWdpYmxlLCBzZWxlY3Qgd2l0aGluLApub25yZXNwb25zZSwgY2FsaWJyYXRlIGFuZCB0cmltLiBBbiBhcnJvdyBsZWF2ZXMgdGhlIGNvbnRhaW5lciB0bwpwcmVwKCksIHdoaWNoIHByb2R1Y2VzIHRoZSBmaW5hbCB3ZWlnaHRzLjwvZGVzYz48ZGVmcz48bWFya2VyIGlkPSJxc3B1ciIgdmlld2JveD0iMCAwIDEwIDEwIiByZWZ4PSI4IiByZWZ5PSI1IiBtYXJrZXJ3aWR0aD0iNyIgbWFya2VyaGVpZ2h0PSI3IiBvcmllbnQ9ImF1dG8tc3RhcnQtcmV2ZXJzZSI+PHBhdGggZD0iTTIgMUw4IDVMMiA5IiBmaWxsPSJub25lIiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS43IiAvPjwvbWFya2VyPjwvZGVmcz48dGV4dCB4PSI2MCIgeT0iNDQiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtc3R5bGU9Iml0YWxpYyIgZmlsbD0iIzZhNmY3YSI+T25lCm9iamVjdDogdGhlIHdob2xlIHN0cmF0ZWd5LCBkZWZpbmVkIGxhemlseSwgcmVhZCB0b3AgdG8gYm90dG9tLjwvdGV4dD48cmVjdCB4PSI1NSIgeT0iNTUiIHdpZHRoPSI1NzAiIGhlaWdodD0iMzAwIiByeD0iMTIiIGZpbGw9IiNmNmY1ZmIiIHN0cm9rZT0iIzNkMzU4MCIgc3Ryb2tlLXdpZHRoPSIxLjYiIC8+PGxpbmUgeDE9IjcyIiB5MT0iOTgiIHgyPSI3MiIgeTI9IjMxOCIgc3Ryb2tlPSIjY2JiOGUwIiBzdHJva2Utd2lkdGg9IjEuNiI+PC9saW5lPjx0ZXh0IHg9Ijg0IiB5PSI5MCIgZm9udC1zaXplPSIxMyIgZm9udC13ZWlnaHQ9IjYwMCIgZm9udC1mYW1pbHk9IiYjMzk7SmV0QnJhaW5zIE1vbm8mIzM5Oyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjM2QzNTgwIj53ZWlnaHRpbmdfc3BlYyhkYXRhLApiYXNlX3dlaWdodHMpPC90ZXh0Pjx0ZXh0IHg9IjM3MiIgeT0iOTAiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSImIzM5O0pldEJyYWlucyBNb25vJiMzOTssdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzhhOGY5YSI+IwpkZXNpZ24gd2VpZ2h0cyAxL8+APC90ZXh0PjxyZWN0IHg9Ijg0IiB5PSIxMTAiIHdpZHRoPSIyMTIiIGhlaWdodD0iMjYiIHJ4PSIxMyIgZmlsbD0iI2VjZTlmNiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuMiIgLz48dGV4dCB4PSI5NSIgeT0iMTI4IiBmb250LXNpemU9IjEyLjUiIGZvbnQtZmFtaWx5PSImIzM5O0pldEJyYWlucyBNb25vJiMzOTssdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzNkMzU4MCI+c3RlcF91bmtub3duX2VsaWdpYmlsaXR5KCk8L3RleHQ+PHRleHQgeD0iMzcyIiB5PSIxMjgiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSImIzM5O0pldEJyYWlucyBNb25vJiMzOTssdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzhhOGY5YSI+IwpyZXNvbHZlIHVua25vd24gZWxpZ2liaWxpdHk8L3RleHQ+PHJlY3QgeD0iODQiIHk9IjE0OCIgd2lkdGg9IjE4MiIgaGVpZ2h0PSIyNiIgcng9IjEzIiBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS4yIiAvPjx0ZXh0IHg9Ijk1IiB5PSIxNjYiIGZvbnQtc2l6ZT0iMTIuNSIgZm9udC1mYW1pbHk9IiYjMzk7SmV0QnJhaW5zIE1vbm8mIzM5Oyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjM2QzNTgwIj5zdGVwX2Ryb3BfaW5lbGlnaWJsZSgpPC90ZXh0Pjx0ZXh0IHg9IjM3MiIgeT0iMTY2IiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJiMzOTtKZXRCcmFpbnMgTW9ubyYjMzk7LHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiM4YThmOWEiPiMKcmVtb3ZlIG91dC1vZi1zY29wZSB1bml0czwvdGV4dD48cmVjdCB4PSI4NCIgeT0iMTg2IiB3aWR0aD0iMTY4IiBoZWlnaHQ9IjI2IiByeD0iMTMiIGZpbGw9IiNlY2U5ZjYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjIiIC8+PHRleHQgeD0iOTUiIHk9IjIwNCIgZm9udC1zaXplPSIxMi41IiBmb250LWZhbWlseT0iJiMzOTtKZXRCcmFpbnMgTW9ubyYjMzk7LHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiMzZDM1ODAiPnN0ZXBfc2VsZWN0X3dpdGhpbigpPC90ZXh0Pjx0ZXh0IHg9IjM3MiIgeT0iMjA0IiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJiMzOTtKZXRCcmFpbnMgTW9ubyYjMzk7LHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiM4YThmOWEiPiMKd2l0aGluLWhvdXNlaG9sZCBzZWxlY3Rpb248L3RleHQ+PHJlY3QgeD0iODQiIHk9IjIyNCIgd2lkdGg9IjE1NiIgaGVpZ2h0PSIyNiIgcng9IjEzIiBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS4yIiAvPjx0ZXh0IHg9Ijk1IiB5PSIyNDIiIGZvbnQtc2l6ZT0iMTIuNSIgZm9udC1mYW1pbHk9IiYjMzk7SmV0QnJhaW5zIE1vbm8mIzM5Oyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjM2QzNTgwIj5zdGVwX25vbnJlc3BvbnNlKCk8L3RleHQ+PHRleHQgeD0iMzcyIiB5PSIyNDIiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSImIzM5O0pldEJyYWlucyBNb25vJiMzOTssdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzhhOGY5YSI+Iwpjb3JyZWN0IGZvciBub25yZXNwb25zZTwvdGV4dD48cmVjdCB4PSI4NCIgeT0iMjYyIiB3aWR0aD0iMTQwIiBoZWlnaHQ9IjI2IiByeD0iMTMiIGZpbGw9IiNlY2U5ZjYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjIiIC8+PHRleHQgeD0iOTUiIHk9IjI4MCIgZm9udC1zaXplPSIxMi41IiBmb250LWZhbWlseT0iJiMzOTtKZXRCcmFpbnMgTW9ubyYjMzk7LHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiMzZDM1ODAiPnN0ZXBfY2FsaWJyYXRlKCk8L3RleHQ+PHRleHQgeD0iMzcyIiB5PSIyODAiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSImIzM5O0pldEJyYWlucyBNb25vJiMzOTssdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzhhOGY5YSI+IwphbGlnbiB0byBwb3B1bGF0aW9uIHRvdGFsczwvdGV4dD48cmVjdCB4PSI4NCIgeT0iMzAwIiB3aWR0aD0iMTA0IiBoZWlnaHQ9IjI2IiByeD0iMTMiIGZpbGw9IiNlY2U5ZjYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjIiIC8+PHRleHQgeD0iOTUiIHk9IjMxOCIgZm9udC1zaXplPSIxMi41IiBmb250LWZhbWlseT0iJiMzOTtKZXRCcmFpbnMgTW9ubyYjMzk7LHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiMzZDM1ODAiPnN0ZXBfdHJpbSgpPC90ZXh0Pjx0ZXh0IHg9IjM3MiIgeT0iMzE4IiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJiMzOTtKZXRCcmFpbnMgTW9ubyYjMzk7LHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiM4YThmOWEiPiMKdGFtZSBleHRyZW1lIHdlaWdodHM8L3RleHQ+PGxpbmUgeDE9IjE1MCIgeTE9IjM1NSIgeDI9IjE1MCIgeTI9IjM4MiIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNxc3B1cikiPjwvbGluZT48cmVjdCB4PSIxMDMiIHk9IjM4MiIgd2lkdGg9Ijk1IiBoZWlnaHQ9IjMyIiByeD0iMTYiIGZpbGw9IiNlY2U5ZjYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjQiIC8+PHRleHQgeD0iMTUwIiB5PSI0MDMiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTMiIGZvbnQtZmFtaWx5PSImIzM5O0pldEJyYWlucyBNb25vJiMzOTssdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzNkMzU4MCI+cHJlcCgpPC90ZXh0PjxsaW5lIHgxPSIxOTgiIHkxPSIzOTgiIHgyPSIyNDMiIHkyPSIzOTgiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjUiIG1hcmtlci1lbmQ9InVybCgjcXNwdXIpIj48L2xpbmU+PHJlY3QgeD0iMjQ1IiB5PSIzODIiIHdpZHRoPSIxNzAiIGhlaWdodD0iMzIiIHJ4PSIxNiIgZmlsbD0iI2NkZWFkZCIgc3Ryb2tlPSIjMWQ5ZTc1IiBzdHJva2Utd2lkdGg9IjEuNCIgLz48dGV4dCB4PSIzMzAiIHk9IjQwMyIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZmlsbD0iIzE0NjAzZiI+ZmluYWwKd2VpZ2h0czwvdGV4dD48dGV4dCB4PSI0NDAiIHk9IjQwMyIgZm9udC1zaXplPSIxMiIgZm9udC1zdHlsZT0iaXRhbGljIiBmaWxsPSIjNmE2ZjdhIj5vbmUKb3V0cHV0IG9mIHRoZSBvYmplY3Q8L3RleHQ+PC9zdmc+)

> **`weightflow` doesn’t just compute weights: it documents how they are
> constructed.**
>
> It does compute the weights, of course. But a weighting strategy is a
> sequence of methodological decisions, and `weightflow` turns those
> decisions into an explicit object that can be inspected, reproduced,
> modified and reused. The final weights are only *one* output of that
> object, and usually the least valuable one. The recipe is the
> institutional asset.

If you know the `recipes`/`tidymodels` world, the analogy is deliberate:
a recipe describes how a dish is produced, not the dish itself. A
`weightflow` recipe describes how the weights are produced, not the
weights themselves.

## The shortest real recipe

Enough theory. `weightflow` ships a small bundled example (a stratified
household sample, `sample_survey`, drawn from a known `population`), so
every line below actually runs.

``` r

str(sample_survey[, c("pw", "region", "sex", "unknown_elig", "responded")])
#> 'data.frame':    467 obs. of  5 variables:
#>  $ pw          : num  12.5 12.5 12.5 12.5 12.5 12.5 12.5 12.5 12.5 12.5 ...
#>  $ region      : Factor w/ 4 levels "North","South",..: 1 1 1 1 1 1 1 1 1 1 ...
#>  $ sex         : Factor w/ 2 levels "F","M": 1 1 2 2 2 2 1 1 1 1 ...
#>  $ unknown_elig: int  0 0 0 0 0 0 0 0 0 0 ...
#>  $ responded   : num  1 0 0 0 1 1 0 1 1 1 ...
```

A minimal but complete cascade: start from the design weights, resolve
unknown eligibility, correct for nonresponse, and calibrate to the
population totals of `region` and `sex`. We pass those totals in the
**tidy** form: a small data frame per margin with the categories and a
counts column. [`table()`](https://rdrr.io/r/base/table.html) already
produces exactly that shape (its counts column is named `Freq`):

``` r

m_region <- as.data.frame(table(region = population$region))
m_sex    <- as.data.frame(table(sex    = population$sex))
m_region
#>   region Freq
#> 1  North 1570
#> 2  South 1250
#> 3   East  927
#> 4   West  748
```

``` r

fit <- weighting_spec(sample_survey, base_weights = pw) |>
  step_unknown_eligibility(unknown = unknown_elig, by = "region") |>
  step_nonresponse(respondent = responded, method = "weighting_class",
                   by = "region") |>
  step_calibrate(method = "raking",
                 totals = list(m_region, m_sex), count = "Freq") |>
  prep()
```

[`prep()`](https://jpferreira33.github.io/weightflow/reference/prep.md)
is where the recipe is actually estimated. Everything before it only
*records* the strategy.
[`collect_weights()`](https://jpferreira33.github.io/weightflow/reference/collect_weights.md)
returns the data with the final weight attached as `.weight`:

``` r

w <- collect_weights(fit)
summary(w$.weight)
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>   10.69   12.85   18.07   16.65   19.35   20.94
```

## The object is the documentation

Because the strategy is an object, it explains itself.
[`summary()`](https://rdrr.io/r/base/summary.html) walks the cascade
step by step, reporting how many units each stage touched, how weights
changed, and diagnostics such as the design effect:

``` r

summary(fit)
#> 
#> == Weighting specification (weightflow) ==
#> Data    : 467 cases
#> Base wts: pw
#> Steps   :
#>   1. unknown eligibility
#>   2. nonresponse (weighting class)
#>   3. calibration (raking)
#> Status  : estimated (prep)
#> 
#> Stage summary:
#>                             stage n_active sum_wts cv_wts deff_kish n_eff
#>                              base      467    4371  0.236     1.056   442
#>  stage_1_step_unknown_eligibility      449    4371  0.250     1.063   423
#>          stage_2_step_nonresponse      270    4371  0.144     1.021   265
#>            stage_3_step_calibrate      270    4495  0.211     1.045   258
#> 
#> deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
#> n_eff = n_active / deff_kish. Both worsen with each adjustment and
#> improve with trimming.
#> 
#> --- Step 1: unknown eligibility ---
#>   cell  level n_known n_unknown   factor
#>   East person      96         0 1.000000
#>  North person     113         6 1.053097
#>  South person     113         8 1.070796
#>   West person     127         4 1.031496
#> Kish deff: 1.056 -> 1.063   |   n_eff: 442 -> 423
#> 
#> --- Step 2: nonresponse (weighting class) ---
#>   cell n_respondents n_nonresponse   factor
#>   East            52            44 1.846154
#>  North            78            35 1.448718
#>  South            72            41 1.569444
#>   West            68            59 1.867647
#> Kish deff: 1.063 -> 1.021   |   n_eff: 423 -> 265
#> 
#> --- Step 3: calibration (raking) ---
#>  variable category target achieved
#>    region     East    927      927
#>    region    North   1570     1570
#>    region    South   1250     1250
#>    region     West    748      748
#>       sex        F   2311     2311
#>       sex        M   2184     2184
#> (converged/iterated in 5 iterations)
#> Kish deff: 1.021 -> 1.045   |   n_eff: 265 -> 258
#> 
#> R-indicator (representativity of response): 0.869  (on region)
```

That printout *is* the methodological record. You did not write a
separate memo describing what the scripts did; the recipe and its
summary are the memo. Re-running it next year, or handing it to a
colleague, reproduces the exact same weights and the exact same
explanation.

## Where to go next

You now have runnable weights and a mental map. To go deeper:

- [*Staged survey weighting: the adjustment
  logic*](https://jpferreira33.github.io/weightflow/articles/weightflow.md)
  covers the statistical reasoning behind each stage and why order
  matters.
- [*Preparing the
  sample*](https://jpferreira33.github.io/weightflow/articles/preparing-the-sample.md)
  covers eligibility, rosters and within-household selection in detail.
- [*Nonresponse: weighting classes and
  propensities*](https://jpferreira33.github.io/weightflow/articles/nonresponse-propensities.md)
  and
  [*Calibration*](https://jpferreira33.github.io/weightflow/articles/calibration.md)
  cover the two workhorse adjustments.
- [*Variance
  estimation*](https://jpferreira33.github.io/weightflow/articles/variance-estimation.md)
  covers the bootstrap and jackknife that re-apply the whole recipe, so
  uncertainty from nonresponse and calibration reaches your standard
  errors.
