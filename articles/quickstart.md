# From raw sample to final weights

> **New here?** This is the 15-minute tour: what problem `weightflow`
> solves and the shortest recipe that produces analysis weights. For the
> statistical reasoning behind each adjustment, read [*Staged survey
> weighting: the adjustment
> logic*](https://jpferreira33.github.io/weightflow/articles/weightflow.md).

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

![Weighting spread across scripts and intermediate
files](data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPHN2ZyB3aWR0aD0iMTAwJSIgdmlld0JveD0iMCAwIDY4MCA0NzAiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwnSW50ZXInLFNlZ29lIFVJLFJvYm90byxzYW5zLXNlcmlmOyI+Cjx0aXRsZT5XZWlnaHRpbmcgc3ByZWFkIGFjcm9zcyBzY3JpcHRzIGFuZCBpbnRlcm1lZGlhdGUgZmlsZXM8L3RpdGxlPgo8ZGVzYz5TYW1wbGluZyBmZWVkcyBzY3JpcHQxLlIsIHdoaWNoIHdyaXRlcyB3ZWlnaHRzMS5jc3YsIHJlYWQgYnkgc2NyaXB0Mi5SLCB3aGljaCB3cml0ZXMgd2VpZ2h0czIuY3N2LCByZWFkIGJ5IHNjcmlwdF9maW5hbF92Ny5SLCB3aGljaCB3cml0ZXMgZmluYWxfd2VpZ2h0c19ORVcuY3N2LiBUaGUgc3RlcHMgemlnemFnIGJldHdlZW4gY29kZSBmaWxlcyBhbmQgaW50ZXJtZWRpYXRlIENTVnMuPC9kZXNjPgo8ZGVmcz48bWFya2VyIGlkPSJxc3JlZCIgdmlld0JveD0iMCAwIDEwIDEwIiByZWZYPSI4IiByZWZZPSI1IiBtYXJrZXJXaWR0aD0iNyIgbWFya2VySGVpZ2h0PSI3IiBvcmllbnQ9ImF1dG8tc3RhcnQtcmV2ZXJzZSI+PHBhdGggZD0iTTIgMUw4IDVMMiA5IiBmaWxsPSJub25lIiBzdHJva2U9IiM5YThmOGYiIHN0cm9rZS13aWR0aD0iMS43Ii8+PC9tYXJrZXI+PC9kZWZzPgo8bGluZSB4MT0iMzIwIiB5MT0iNjIiIHgyPSIxODgiIHkyPSI5MCIgc3Ryb2tlPSIjOWE4ZjhmIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNxc3JlZCkiLz4KPGxpbmUgeDE9IjI1NSIgeTE9IjEyMCIgeDI9IjQyMyIgeTI9IjE2OCIgc3Ryb2tlPSIjOWE4ZjhmIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNxc3JlZCkiLz4KPGxpbmUgeDE9IjQyNSIgeTE9IjE4MiIgeDI9IjI1NyIgeTI9IjIyMCIgc3Ryb2tlPSIjOWE4ZjhmIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNxc3JlZCkiLz4KPGxpbmUgeDE9IjI1NSIgeTE9IjIzOCIgeDI9IjQyMyIgeTI9IjI4NCIgc3Ryb2tlPSIjOWE4ZjhmIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNxc3JlZCkiLz4KPGxpbmUgeDE9IjQyNSIgeTE9IjI5OCIgeDI9IjI2MiIgeTI9IjMzNiIgc3Ryb2tlPSIjOWE4ZjhmIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNxc3JlZCkiLz4KPGxpbmUgeDE9IjI2NSIgeTE9IjM1NiIgeDI9IjQxMyIgeTI9IjM5MCIgc3Ryb2tlPSIjOWE4ZjhmIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNxc3JlZCkiLz4KPHJlY3QgeD0iMjkwIiB5PSIyOCIgd2lkdGg9IjEwMCIgaGVpZ2h0PSIzNCIgcng9IjE3IiBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS4zIi8+Cjx0ZXh0IHg9IjM0MCIgeT0iNTAiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTMiIGZpbGw9IiMyMDI0MmUiPnNhbXBsaW5nPC90ZXh0Pgo8cmVjdCB4PSI5NSIgeT0iOTAiIHdpZHRoPSIxNjAiIGhlaWdodD0iNDAiIHJ4PSI4IiBmaWxsPSIjZThlN2VmIiBzdHJva2U9IiM2YjZhODYiIHN0cm9rZS13aWR0aD0iMS4zIi8+Cjx0ZXh0IHg9IjE3NSIgeT0iMTE1IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjMzMzMjNmIj5zY3JpcHQxLlI8L3RleHQ+CjxyZWN0IHg9IjQyNSIgeT0iMTUwIiB3aWR0aD0iMTYwIiBoZWlnaHQ9IjQwIiByeD0iOCIgZmlsbD0iI2Y0ZTJiOCIgc3Ryb2tlPSIjYzk5MDJhIiBzdHJva2Utd2lkdGg9IjEuMyIvPgo8dGV4dCB4PSI1MDUiIHk9IjE3NSIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzVjNDQxMCI+d2VpZ2h0czEuY3N2PC90ZXh0Pgo8cmVjdCB4PSI5NSIgeT0iMjA4IiB3aWR0aD0iMTYwIiBoZWlnaHQ9IjQwIiByeD0iOCIgZmlsbD0iI2U4ZTdlZiIgc3Ryb2tlPSIjNmI2YTg2IiBzdHJva2Utd2lkdGg9IjEuMyIvPgo8dGV4dCB4PSIxNzUiIHk9IjIzMyIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzMzMzIzZiI+c2NyaXB0Mi5SPC90ZXh0Pgo8cmVjdCB4PSI0MjUiIHk9IjI2NiIgd2lkdGg9IjE2MCIgaGVpZ2h0PSI0MCIgcng9IjgiIGZpbGw9IiNmNGUyYjgiIHN0cm9rZT0iI2M5OTAyYSIgc3Ryb2tlLXdpZHRoPSIxLjMiLz4KPHRleHQgeD0iNTA1IiB5PSIyOTEiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTMiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiM1YzQ0MTAiPndlaWdodHMyLmNzdjwvdGV4dD4KPHJlY3QgeD0iOTAiIHk9IjMyNCIgd2lkdGg9IjE3NSIgaGVpZ2h0PSI0MCIgcng9IjgiIGZpbGw9IiNlOGU3ZWYiIHN0cm9rZT0iIzZiNmE4NiIgc3Ryb2tlLXdpZHRoPSIxLjMiLz4KPHRleHQgeD0iMTc3IiB5PSIzNDkiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiMzMzMyM2YiPnNjcmlwdF9maW5hbF92Ny5SPC90ZXh0Pgo8cmVjdCB4PSI0MTMiIHk9IjM4MiIgd2lkdGg9IjE5MCIgaGVpZ2h0PSI0MCIgcng9IjgiIGZpbGw9IiNmMmNmYzciIHN0cm9rZT0iI2MwNDkyZiIgc3Ryb2tlLXdpZHRoPSIxLjMiLz4KPHRleHQgeD0iNTA4IiB5PSI0MDciIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiM3YTI2MTgiPmZpbmFsX3dlaWdodHNfTkVXLmNzdjwvdGV4dD4KPHRleHQgeD0iMzQwIiB5PSI0NTIiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtc3R5bGU9Iml0YWxpYyIgZmlsbD0iIzhhN2Y3ZiI+TG9naWMgc2NhdHRlcmVkIGFjcm9zcyBmaWxlcyBhbmQgcnVuIG9yZGVyLCBub3Qga2VwdCBpbiBvbmUgcGxhY2UuPC90ZXh0Pgo8L3N2Zz4K)

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

![From target population to
respondents](data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPHN2ZyB3aWR0aD0iMTAwJSIgdmlld0JveD0iMCAwIDY4MCA1NjAiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwnSW50ZXInLFNlZ29lIFVJLFJvYm90byxzYW5zLXNlcmlmOyI+Cjx0aXRsZT5Gcm9tIHRhcmdldCBwb3B1bGF0aW9uIHRvIHJlc3BvbmRlbnRzPC90aXRsZT4KPGRlc2M+VHdvIG92ZXJsYXBwaW5nIGVsbGlwc2VzIHNob3cgdGhlIHRhcmdldCBwb3B1bGF0aW9uIGFuZCB0aGUgc2FtcGxpbmcgZnJhbWUsIHdpdGggdW5kZXJjb3ZlcmFnZSwgYW4gaW4tc2NvcGUgb3ZlcmxhcCwgYW5kIG91dC1vZi1zY29wZSB1bml0cy4gVGhlIGluLXNjb3BlIGFyZWEgaXMgc2FtcGxlZDsgdGhlIHNhbXBsZSBzcGxpdHMgaW50byB1bmtub3duIGVsaWdpYmlsaXR5LCBpbmVsaWdpYmxlIGFuZCBlbGlnaWJsZSwgYW5kIGVsaWdpYmxlIHNwbGl0cyBpbnRvIG5vbnJlc3BvbmRlbnRzIGFuZCByZXNwb25kZW50cy4gQSBsZWdlbmQgbWFwcyBlYWNoIHJlZ2lvbiB0byBhIHdlaWdodGZsb3cgc3RlcC48L2Rlc2M+CjxkZWZzPjxtYXJrZXIgaWQ9InFzYXJyb3ciIHZpZXdCb3g9IjAgMCAxMCAxMCIgcmVmWD0iOCIgcmVmWT0iNSIgbWFya2VyV2lkdGg9IjciIG1hcmtlckhlaWdodD0iNyIgb3JpZW50PSJhdXRvLXN0YXJ0LXJldmVyc2UiPjxwYXRoIGQ9Ik0yIDFMOCA1TDIgOSIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2E3YTg2IiBzdHJva2Utd2lkdGg9IjEuNiIvPjwvbWFya2VyPjwvZGVmcz4KPGVsbGlwc2UgY3g9IjI1NSIgY3k9IjExMiIgcng9IjE1MiIgcnk9IjcyIiBmaWxsPSIjN2E2YWQwIiBmaWxsLW9wYWNpdHk9IjAuMTYiIHN0cm9rZT0iIzNkMzU4MCIgc3Ryb2tlLXdpZHRoPSIxLjUiLz4KPGVsbGlwc2UgY3g9IjQyNSIgY3k9IjExMiIgcng9IjE1MiIgcnk9IjcyIiBmaWxsPSIjOGE4ZjlhIiBmaWxsLW9wYWNpdHk9IjAuMTYiIHN0cm9rZT0iIzViNjQ3MiIgc3Ryb2tlLXdpZHRoPSIxLjUiLz4KPHRleHQgeD0iMTgwIiB5PSI5MiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxNCIgZm9udC13ZWlnaHQ9IjYwMCIgZmlsbD0iIzIwMjQyZSI+VGFyZ2V0IHBvcHVsYXRpb248L3RleHQ+Cjx0ZXh0IHg9IjUwMCIgeT0iOTIiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTQiIGZvbnQtd2VpZ2h0PSI2MDAiIGZpbGw9IiMyMDI0MmUiPkZyYW1lPC90ZXh0Pgo8dGV4dCB4PSIxNzgiIHk9IjEyMCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzNhM2Y0YSI+VW5kZXJjb3ZlcmFnZTwvdGV4dD4KPHRleHQgeD0iMTc4IiB5PSIxMzYiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTIiIGZpbGw9IiMzYTNmNGEiPihtaXNzaW5nIGZyb20gZnJhbWUpPC90ZXh0Pgo8dGV4dCB4PSIzNDAiIHk9IjExNiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxNCIgZmlsbD0iIzIwMjQyZSI+SW4gc2NvcGU8L3RleHQ+Cjx0ZXh0IHg9IjUwMCIgeT0iMTIwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmaWxsPSIjM2EzZjRhIj5PdXQgb2Ygc2NvcGU8L3RleHQ+Cjx0ZXh0IHg9IjUwMCIgeT0iMTM2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEyIiBmaWxsPSIjM2EzZjRhIj4oaW5lbGlnaWJsZSBvbiBmcmFtZSk8L3RleHQ+CjxsaW5lIHgxPSIzNDAiIHkxPSIxODQiIHgyPSIzNDAiIHkyPSIyMzAiIHN0cm9rZT0iIzdhN2E4NiIgc3Ryb2tlLXdpZHRoPSIxLjUiIG1hcmtlci1lbmQ9InVybCgjcXNhcnJvdykiLz4KPHRleHQgeD0iMzUwIiB5PSIyMTIiIHRleHQtYW5jaG9yPSJzdGFydCIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzNhM2Y0YSI+ZHJhdyBzYW1wbGUgKGRlc2lnbiB3ZWlnaHQgMS8mIzk2MDspPC90ZXh0Pgo8cmVjdCB4PSI1NSIgeT0iMjMyIiB3aWR0aD0iNTcwIiBoZWlnaHQ9IjE3MCIgcng9IjEwIiBmaWxsPSIjZjZmNWZiIiBzdHJva2U9IiMzZDM1ODAiIHN0cm9rZS13aWR0aD0iMS40Ii8+Cjx0ZXh0IHg9IjcwIiB5PSIyNTYiIHRleHQtYW5jaG9yPSJzdGFydCIgZm9udC1zaXplPSIxNCIgZm9udC13ZWlnaHQ9IjYwMCIgZmlsbD0iIzIwMjQyZSI+U2FtcGxlIChrbm93biBpbmNsdXNpb24gcHJvYmFiaWxpdHkgJiM5NjA7KTwvdGV4dD4KPHJlY3QgeD0iNzUiIHk9IjI4NCIgd2lkdGg9IjEzNSIgaGVpZ2h0PSI5OCIgcng9IjgiIGZpbGw9IiNmNGUyYjgiIHN0cm9rZT0iI2M5OTAyYSIgc3Ryb2tlLXdpZHRoPSIxLjMiLz4KPHRleHQgeD0iMTQyIiB5PSIzMjgiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTQiIGZpbGw9IiMyMDI0MmUiPlVua25vd248L3RleHQ+Cjx0ZXh0IHg9IjE0MiIgeT0iMzQ2IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjE0IiBmaWxsPSIjMjAyNDJlIj5lbGlnaWJpbGl0eTwvdGV4dD4KPHJlY3QgeD0iMjI1IiB5PSIyODQiIHdpZHRoPSIxMjAiIGhlaWdodD0iOTgiIHJ4PSI4IiBmaWxsPSIjZjJjZmM3IiBzdHJva2U9IiNjMDQ5MmYiIHN0cm9rZS13aWR0aD0iMS4zIi8+Cjx0ZXh0IHg9IjI4NSIgeT0iMzM4IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjE0IiBmaWxsPSIjMjAyNDJlIj5JbmVsaWdpYmxlPC90ZXh0Pgo8cmVjdCB4PSIzNjAiIHk9IjI3MCIgd2lkdGg9IjI1MiIgaGVpZ2h0PSIxMTUiIHJ4PSI4IiBmaWxsPSIjZTdlM2Y1IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS4zIi8+Cjx0ZXh0IHg9IjM3NCIgeT0iMjg5IiB0ZXh0LWFuY2hvcj0ic3RhcnQiIGZvbnQtc2l6ZT0iMTQiIGZvbnQtd2VpZ2h0PSI2MDAiIGZpbGw9IiMyMDI0MmUiPkVsaWdpYmxlPC90ZXh0Pgo8cmVjdCB4PSIzNzQiIHk9IjMwMCIgd2lkdGg9IjEwOCIgaGVpZ2h0PSI3MiIgcng9IjciIGZpbGw9IiNlM2U1ZTkiIHN0cm9rZT0iIzhhOGY5YSIgc3Ryb2tlLXdpZHRoPSIxLjMiLz4KPHRleHQgeD0iNDI4IiB5PSIzMzIiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTMiIGZpbGw9IiMyMDI0MmUiPk5vbi08L3RleHQ+Cjx0ZXh0IHg9IjQyOCIgeT0iMzUwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmaWxsPSIjMjAyNDJlIj5yZXNwb25kZW50czwvdGV4dD4KPHJlY3QgeD0iNDk4IiB5PSIzMDAiIHdpZHRoPSIxMDAiIGhlaWdodD0iNzIiIHJ4PSI3IiBmaWxsPSIjY2RlYWRkIiBzdHJva2U9IiMxZDllNzUiIHN0cm9rZS13aWR0aD0iMS4zIi8+Cjx0ZXh0IHg9IjU0OCIgeT0iMzQxIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXNpemU9IjEzIiBmaWxsPSIjMjAyNDJlIj5SZXNwb25kZW50czwvdGV4dD4KPGNpcmNsZSBjeD0iNzQiIGN5PSI0MzIiIHI9IjYiIGZpbGw9IiNjOTkwMmEiLz4KPHRleHQgeD0iOTAiIHk9IjQzNiIgdGV4dC1hbmNob3I9InN0YXJ0IiBmb250LXNpemU9IjEyIiBmaWxsPSIjM2EzZjRhIj5Vbmtub3duIGVsaWdpYmlsaXR5ICYjODU5NDsgc3RlcF91bmtub3duX2VsaWdpYmlsaXR5KCk6IHJlZGlzdHJpYnV0ZSB0aGVpciB3ZWlnaHQ8L3RleHQ+CjxjaXJjbGUgY3g9Ijc0IiBjeT0iNDU2IiByPSI2IiBmaWxsPSIjYzA0OTJmIi8+Cjx0ZXh0IHg9IjkwIiB5PSI0NjAiIHRleHQtYW5jaG9yPSJzdGFydCIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzNhM2Y0YSI+SW5lbGlnaWJsZSAmIzg1OTQ7IHN0ZXBfZHJvcF9pbmVsaWdpYmxlKCk6IHJlbW92ZSBmcm9tIHRoZSBzYW1wbGU8L3RleHQ+CjxjaXJjbGUgY3g9Ijc0IiBjeT0iNDgwIiByPSI2IiBmaWxsPSIjOGE4ZjlhIi8+Cjx0ZXh0IHg9IjkwIiB5PSI0ODQiIHRleHQtYW5jaG9yPSJzdGFydCIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzNhM2Y0YSI+Tm9ucmVzcG9uZGVudHMgJiM4NTk0OyBzdGVwX25vbnJlc3BvbnNlKCk6IHJlc3BvbmRlbnRzIGFic29yYiB0aGVpciB3ZWlnaHQ8L3RleHQ+CjxjaXJjbGUgY3g9Ijc0IiBjeT0iNTA0IiByPSI2IiBmaWxsPSIjMWQ5ZTc1Ii8+Cjx0ZXh0IHg9IjkwIiB5PSI1MDgiIHRleHQtYW5jaG9yPSJzdGFydCIgZm9udC1zaXplPSIxMiIgZmlsbD0iIzNhM2Y0YSI+UmVzcG9uZGVudHMgY2FycnkgdGhlIGZpbmFsIGFuYWx5c2lzIHdlaWdodDwvdGV4dD4KPGNpcmNsZSBjeD0iNzQiIGN5PSI1MjgiIHI9IjYiIGZpbGw9IiM3YTZhZDAiLz4KPHRleHQgeD0iOTAiIHk9IjUzMiIgdGV4dC1hbmNob3I9InN0YXJ0IiBmb250LXNpemU9IjEyIiBmaWxsPSIjM2EzZjRhIj5Db3ZlcmFnZSAmYW1wOyBrbm93biB0b3RhbHMgJiM4NTk0OyBzdGVwX2NhbGlicmF0ZSgpOiBhbGlnbiB0byB0aGUgcG9wdWxhdGlvbjwvdGV4dD4KPC9zdmc+Cg==)

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

![The whole strategy as one recipe
object](data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPHN2ZyB3aWR0aD0iMTAwJSIgdmlld0JveD0iMCAwIDY4MCA0NDgiIHJvbGU9ImltZyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBzdHlsZT0iZm9udC1mYW1pbHk6LWFwcGxlLXN5c3RlbSwnSW50ZXInLFNlZ29lIFVJLFJvYm90byxzYW5zLXNlcmlmOyI+Cjx0aXRsZT5UaGUgd2hvbGUgc3RyYXRlZ3kgYXMgb25lIHJlY2lwZSBvYmplY3Q8L3RpdGxlPgo8ZGVzYz5BIHNpbmdsZSBjb250YWluZXIgaG9sZHMgd2VpZ2h0aW5nX3NwZWMoKSBhbmQgYSBzdGFjayBvZiBzdGVwIGZ1bmN0aW9uczogdW5rbm93biBlbGlnaWJpbGl0eSwgZHJvcCBpbmVsaWdpYmxlLCBzZWxlY3Qgd2l0aGluLCBub25yZXNwb25zZSwgY2FsaWJyYXRlIGFuZCB0cmltLiBBbiBhcnJvdyBsZWF2ZXMgdGhlIGNvbnRhaW5lciB0byBwcmVwKCksIHdoaWNoIHByb2R1Y2VzIHRoZSBmaW5hbCB3ZWlnaHRzLjwvZGVzYz4KPGRlZnM+PG1hcmtlciBpZD0icXNwdXIiIHZpZXdCb3g9IjAgMCAxMCAxMCIgcmVmWD0iOCIgcmVmWT0iNSIgbWFya2VyV2lkdGg9IjciIG1hcmtlckhlaWdodD0iNyIgb3JpZW50PSJhdXRvLXN0YXJ0LXJldmVyc2UiPjxwYXRoIGQ9Ik0yIDFMOCA1TDIgOSIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuNyIvPjwvbWFya2VyPjwvZGVmcz4KPHRleHQgeD0iNjAiIHk9IjQ0IiBmb250LXNpemU9IjEyIiBmb250LXN0eWxlPSJpdGFsaWMiIGZpbGw9IiM2YTZmN2EiPk9uZSBvYmplY3Q6IHRoZSB3aG9sZSBzdHJhdGVneSwgZGVmaW5lZCBsYXppbHksIHJlYWQgdG9wIHRvIGJvdHRvbS48L3RleHQ+CjxyZWN0IHg9IjU1IiB5PSI1NSIgd2lkdGg9IjU3MCIgaGVpZ2h0PSIzMDAiIHJ4PSIxMiIgZmlsbD0iI2Y2ZjVmYiIgc3Ryb2tlPSIjM2QzNTgwIiBzdHJva2Utd2lkdGg9IjEuNiIvPgo8bGluZSB4MT0iNzIiIHkxPSI5OCIgeDI9IjcyIiB5Mj0iMzE4IiBzdHJva2U9IiNjYmI4ZTAiIHN0cm9rZS13aWR0aD0iMS42Ii8+Cjx0ZXh0IHg9Ijg0IiB5PSI5MCIgZm9udC1zaXplPSIxMyIgZm9udC13ZWlnaHQ9IjYwMCIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzNkMzU4MCI+d2VpZ2h0aW5nX3NwZWMoZGF0YSwgYmFzZV93ZWlnaHRzKTwvdGV4dD4KPHRleHQgeD0iMzcyIiB5PSI5MCIgZm9udC1zaXplPSIxMiIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzhhOGY5YSI+IyBkZXNpZ24gd2VpZ2h0cyAxLyYjOTYwOzwvdGV4dD4KPHJlY3QgeD0iODQiIHk9IjExMCIgd2lkdGg9IjIxMiIgaGVpZ2h0PSIyNiIgcng9IjEzIiBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS4yIi8+Cjx0ZXh0IHg9Ijk1IiB5PSIxMjgiIGZvbnQtc2l6ZT0iMTIuNSIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzNkMzU4MCI+c3RlcF91bmtub3duX2VsaWdpYmlsaXR5KCk8L3RleHQ+Cjx0ZXh0IHg9IjM3MiIgeT0iMTI4IiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjOGE4ZjlhIj4jIHJlc29sdmUgdW5rbm93biBlbGlnaWJpbGl0eTwvdGV4dD4KPHJlY3QgeD0iODQiIHk9IjE0OCIgd2lkdGg9IjE4MiIgaGVpZ2h0PSIyNiIgcng9IjEzIiBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS4yIi8+Cjx0ZXh0IHg9Ijk1IiB5PSIxNjYiIGZvbnQtc2l6ZT0iMTIuNSIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzNkMzU4MCI+c3RlcF9kcm9wX2luZWxpZ2libGUoKTwvdGV4dD4KPHRleHQgeD0iMzcyIiB5PSIxNjYiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiM4YThmOWEiPiMgcmVtb3ZlIG91dC1vZi1zY29wZSB1bml0czwvdGV4dD4KPHJlY3QgeD0iODQiIHk9IjE4NiIgd2lkdGg9IjE2OCIgaGVpZ2h0PSIyNiIgcng9IjEzIiBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS4yIi8+Cjx0ZXh0IHg9Ijk1IiB5PSIyMDQiIGZvbnQtc2l6ZT0iMTIuNSIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzNkMzU4MCI+c3RlcF9zZWxlY3Rfd2l0aGluKCk8L3RleHQ+Cjx0ZXh0IHg9IjM3MiIgeT0iMjA0IiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjOGE4ZjlhIj4jIHdpdGhpbi1ob3VzZWhvbGQgc2VsZWN0aW9uPC90ZXh0Pgo8cmVjdCB4PSI4NCIgeT0iMjI0IiB3aWR0aD0iMTU2IiBoZWlnaHQ9IjI2IiByeD0iMTMiIGZpbGw9IiNlY2U5ZjYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjIiLz4KPHRleHQgeD0iOTUiIHk9IjI0MiIgZm9udC1zaXplPSIxMi41IiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjM2QzNTgwIj5zdGVwX25vbnJlc3BvbnNlKCk8L3RleHQ+Cjx0ZXh0IHg9IjM3MiIgeT0iMjQyIiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjOGE4ZjlhIj4jIGNvcnJlY3QgZm9yIG5vbnJlc3BvbnNlPC90ZXh0Pgo8cmVjdCB4PSI4NCIgeT0iMjYyIiB3aWR0aD0iMTQwIiBoZWlnaHQ9IjI2IiByeD0iMTMiIGZpbGw9IiNlY2U5ZjYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjIiLz4KPHRleHQgeD0iOTUiIHk9IjI4MCIgZm9udC1zaXplPSIxMi41IiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjM2QzNTgwIj5zdGVwX2NhbGlicmF0ZSgpPC90ZXh0Pgo8dGV4dCB4PSIzNzIiIHk9IjI4MCIgZm9udC1zaXplPSIxMiIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzhhOGY5YSI+IyBhbGlnbiB0byBwb3B1bGF0aW9uIHRvdGFsczwvdGV4dD4KPHJlY3QgeD0iODQiIHk9IjMwMCIgd2lkdGg9IjEwNCIgaGVpZ2h0PSIyNiIgcng9IjEzIiBmaWxsPSIjZWNlOWY2IiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS4yIi8+Cjx0ZXh0IHg9Ijk1IiB5PSIzMTgiIGZvbnQtc2l6ZT0iMTIuNSIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsdWktbW9ub3NwYWNlLG1vbm9zcGFjZSIgZmlsbD0iIzNkMzU4MCI+c3RlcF90cmltKCk8L3RleHQ+Cjx0ZXh0IHg9IjM3MiIgeT0iMzE4IiBmb250LXNpemU9IjEyIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJyx1aS1tb25vc3BhY2UsbW9ub3NwYWNlIiBmaWxsPSIjOGE4ZjlhIj4jIHRhbWUgZXh0cmVtZSB3ZWlnaHRzPC90ZXh0Pgo8bGluZSB4MT0iMTUwIiB5MT0iMzU1IiB4Mj0iMTUwIiB5Mj0iMzgyIiBzdHJva2U9IiM3YTZhZDAiIHN0cm9rZS13aWR0aD0iMS41IiBtYXJrZXItZW5kPSJ1cmwoI3FzcHVyKSIvPgo8cmVjdCB4PSIxMDMiIHk9IjM4MiIgd2lkdGg9Ijk1IiBoZWlnaHQ9IjMyIiByeD0iMTYiIGZpbGw9IiNlY2U5ZjYiIHN0cm9rZT0iIzdhNmFkMCIgc3Ryb2tlLXdpZHRoPSIxLjQiLz4KPHRleHQgeD0iMTUwIiB5PSI0MDMiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTMiIGZvbnQtZmFtaWx5PSInSmV0QnJhaW5zIE1vbm8nLHVpLW1vbm9zcGFjZSxtb25vc3BhY2UiIGZpbGw9IiMzZDM1ODAiPnByZXAoKTwvdGV4dD4KPGxpbmUgeDE9IjE5OCIgeTE9IjM5OCIgeDI9IjI0MyIgeTI9IjM5OCIgc3Ryb2tlPSIjN2E2YWQwIiBzdHJva2Utd2lkdGg9IjEuNSIgbWFya2VyLWVuZD0idXJsKCNxc3B1cikiLz4KPHJlY3QgeD0iMjQ1IiB5PSIzODIiIHdpZHRoPSIxNzAiIGhlaWdodD0iMzIiIHJ4PSIxNiIgZmlsbD0iI2NkZWFkZCIgc3Ryb2tlPSIjMWQ5ZTc1IiBzdHJva2Utd2lkdGg9IjEuNCIvPgo8dGV4dCB4PSIzMzAiIHk9IjQwMyIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1zaXplPSIxMyIgZmlsbD0iIzE0NjAzZiI+ZmluYWwgd2VpZ2h0czwvdGV4dD4KPHRleHQgeD0iNDQwIiB5PSI0MDMiIGZvbnQtc2l6ZT0iMTIiIGZvbnQtc3R5bGU9Iml0YWxpYyIgZmlsbD0iIzZhNmY3YSI+b25lIG91dHB1dCBvZiB0aGUgb2JqZWN0PC90ZXh0Pgo8L3N2Zz4K)

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
#>   1. unknown eligibility  [unknown_eligibility_1]
#>   2. nonresponse (weighting class)  [nonresponse_1]
#>   3. calibration (raking)  [calibrate_1]
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
#>  variable category target achieved prev_total    factor   n
#>    region    North   1570     1570  1487.5000 1.0554622  78
#>    region    South   1250     1250  1210.0000 1.0330579  72
#>    region     East    927      927   800.0000 1.1587500  52
#>    region     West    748      748   873.3333 0.8564885  68
#>       sex        F   2311     2311  2128.8015 1.0855873 130
#>       sex        M   2184     2184  2242.0318 0.9741164 140
#> (converged/iterated in 5 iterations)
#> Kish deff: 1.021 -> 1.045   |   n_eff: 265 -> 258
#> 
#> R-indicator (representativity of response): 0.895  (on region)
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
