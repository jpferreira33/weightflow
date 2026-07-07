# Release checklist — weightflow 0.2.0

Run these in order, right before submitting to CRAN. Everything below the
"Already handled" line is done and does NOT need to be redone.

## Steps at submission time

1. **Bump the version** in `DESCRIPTION`: `Version: 0.2.0`.
2. **NEWS**: rename the `## Development version` heading to `# weightflow 0.2.0`
   (and delete the "Install with remotes::install_github(...)" line at its end).
3. **Regenerate docs**: `devtools::document()`.
4. **Full local check** (must be 0 / 0 / 0):
   `devtools::check(env_vars = c("_R_CHECK_SYSTEM_CLOCK_" = "0"))`.
5. **Spelling & URLs**: `devtools::spell_check()`; `urlchecker::url_check()`.
6. **Multiplatform** (all green — with the version bumped, the previous
   "insufficient version" WARNING is gone):
   `devtools::check_win_devel()`, `check_win_release()`, `check_win_oldrelease()`;
   and trigger the R-hub workflow (Actions -> rhub.yaml -> Run workflow).
7. **Update `cran-comments.md`** with the environments you actually ran.
8. **Rebuild the pkgdown site** and deploy (`pkgdown::deploy_to_branch()` or let
   the CI workflow do it).
9. **Submit**: `devtools::submit_cran()`.
10. **After acceptance**: `git tag v0.2.0 && git push --tags`; bump to the next
    development version and start a new NEWS section.

## Already handled (do NOT redo)

- `\value{}` on every exported function/method; datasets and the package doc are
  correctly exempt. No `\dontrun{}` (only `\donttest{}` where genuinely needed).
- `Suggests` is complete (incl. `xgboost` for the new boost engine) and every
  suggested package is used conditionally.
- `.Rbuildignore` excludes `.github`, `docs`, `pkgdown`, `data-raw`, `paper`,
  `ech_data`, `vignettes/articles`, `cran-comments.md`, `RELEASE-CHECKLIST.md`.
- Snapshot, scale and spelling tests `skip_on_cran()`.
- Test suite: invariants, guardrails, snapshots, engines/cross-fitting, survey
  bridges; coverage ~85%. CI: R-CMD-check matrix, no-Suggests, coverage.
