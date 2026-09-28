# Integration tests on the shipped panel datasets (panel_puro / panel_cl / panel_ine /
# panel_us). They exercise the whole panel pipeline on realistic data and check that
# panel_design measures each rotation system's overlap and raises the right alerts.
# Assertions are structural or magnitude-with-tolerance (never hardcoded point values).

expected_overlap <- c(panel_puro = 1.00, panel_cl = 0.50, panel_ine = 0.83, panel_us = 0.75)

test_that("every dataset has the documented structure and disposition codes", {
  for (nm in names(expected_overlap)) {
    df <- get(nm)
    expect_true(all(c("household_id", "person_id", "person_no", "stratum", "psu", "region",
                      "wave", "rotation_group", "pw", "disposition",
                      "employed", "unemployed", "income") %in% names(df)), info = nm)
    expect_true(all(df$disposition %in% c("R", "NR", "OS", "UNK")), info = nm)
    expect_gt(length(unique(df$wave)), 1L)                 # more than one wave
    # continuing persons: some id appears in >= 2 waves (the panel links)
    expect_gt(max(table(df$person_id)), 1L)
    # outcomes are observed only for respondents
    expect_true(all(is.na(df$unemployed[df$disposition != "R"])), info = nm)
  }
})

test_that("panel_design recovers each system's overlap and links the units", {
  for (nm in names(expected_overlap)) {
    pd <- panel_design(get(nm), unit = c("household_id", "person_no"), wave = "wave",
                       rotation_group = "rotation_group", cluster = "household_id")
    p  <- attr(pd, "wf_panel")
    expect_equal(unname(p$overlap[1, 2]), unname(expected_overlap[nm]), tolerance = 0.08,
                 info = nm)
    expect_gt(p$link_rate, 0.3)                            # units link across waves
    expect_false(any(grepl("PN-06", p$alerts)), info = nm) # good key -> no linkage alert
  }
})

test_that("the correct rotation pattern does not fire PN-01; a wrong one does", {
  # correct pattern (k s.t. (k-1)/k matches the system) -> group continuity matches -> quiet
  ok <- list(panel_cl = "2-2-2", panel_ine = "6", panel_us = "4-8-4")
  for (nm in names(ok)) {
    pd <- panel_design(get(nm), unit = c("household_id", "person_no"), wave = "wave",
                       rotation_group = "rotation_group", pattern = ok[[nm]])
    expect_false(any(grepl("PN-01", attr(pd, "wf_panel")$alerts)), info = nm)
  }
  # claim a 6-month pattern (implies 0.83) on Chile's 2-2-2 (~0.5) -> shortfall -> PN-01
  pd_bad <- panel_design(panel_cl, unit = c("household_id", "person_no"), wave = "wave",
                         rotation_group = "rotation_group", pattern = "6")
  expect_true(any(grepl("PN-01", attr(pd_bad, "wf_panel")$alerts)))
})

test_that("a broken linkage key raises PN-06", {
  broken <- panel_ine
  broken$household_id <- seq_len(nrow(broken))                # id unique per row -> nothing links
  pd <- panel_design(broken, unit = "household_id", wave = "wave")
  expect_true(any(grepl("PN-06", attr(pd, "wf_panel")$alerts)))
})

# ---- full estimation pipeline on real data, on every rotating system ----
resp_specs <- function(df, waves) {
  stats::setNames(lapply(waves, function(t) {
    weighting_spec(df[df$wave == t & df$disposition == "R", ], base_weights = pw)
  }), paste0("T", waves))
}

test_that("wave_bootstrap -> change of the unemployment rate runs on all systems", {
  skip_on_cran()
  for (nm in c("panel_cl", "panel_ine", "panel_us")) {
    df <- get(nm)
    wb <- wave_bootstrap(resp_specs(df, 1:2), replicates = 150,
                         strata = "stratum", psu = "psu", seed = 1, progress = FALSE)
    ch <- change_mean(wb, "unemployed")                   # na.rm -> unemployment rate
    expect_s3_class(ch, "weightflow_change")
    expect_true(is.finite(ch$estimate) && ch$se > 0, info = nm)
  }
})

test_that("estimation grammar agrees with the engine and disaggregates by region", {
  skip_on_cran()
  wb  <- wave_bootstrap(resp_specs(panel_ine, 1:2), replicates = 150,
                        strata = "stratum", psu = "psu", seed = 1, progress = FALSE)
  eng <- change_mean(wb, "unemployed")
  gr  <- collect_estimates(wb |> step_estimate(mean(unemployed), over = "change"))
  expect_equal(gr$table$estimate, eng$estimate)           # grammar == engine
  by  <- collect_estimates(wb |> step_domain(region) |>
                             step_estimate(mean(unemployed), over = "change"))
  expect_setequal(by$table$region, unique(panel_ine$region))
})

test_that("panel_mean / level_mean handle a structurally-NA outcome (na.rm)", {
  skip_on_cran()
  wb3 <- wave_bootstrap(resp_specs(panel_ine, 1:3), replicates = 100,
                        strata = "stratum", psu = "psu", seed = 1, progress = FALSE)
  pm <- panel_mean(wb3, "unemployed")                # unemployed is NA outside the labour force
  expect_true(is.finite(pm$estimate) && pm$se > 0)
  expect_true(is.finite(level_mean(wb3, "unemployed", wave = "T1")$estimate))
})

test_that("coordinated jackknife runs as the oracle on real data", {
  wj <- wave_jackknife(resp_specs(panel_ine, 1:2),
                       strata = "stratum", psu = "psu", progress = FALSE)
  ch <- change_mean(wj, "unemployed")
  expect_true(is.finite(ch$estimate))
  expect_true(ch$rho >= -1 && ch$rho <= 1)
})
