# panel_design() describes the rotation structure without touching weights;
# panel_merge() builds the wide longitudinal file. Deterministic small panels
# with a known overlap so the arithmetic can be asserted exactly.

make_long <- function() {
  # 3 waves, rotating: T1={1,2,3,4}, T2={2,3,4,5}, T3={3,4,5,6}
  # adjacent overlap = 3/4; units 2..5 linked, 1 and 6 appear once.
  rbind(
    data.frame(id = c(1, 2, 3, 4), mes = "T1", grp = c(1, 2, 3, 4)),
    data.frame(id = c(2, 3, 4, 5), mes = "T2", grp = c(2, 3, 4, 1)),
    data.frame(id = c(3, 4, 5, 6), mes = "T3", grp = c(3, 4, 1, 2)))
}

test_that("panel_design computes directional overlap and linkage", {
  pd <- panel_design(make_long(), unit = "id", wave = "mes",
                     rotation_group = "grp", pattern = "4(0)1")
  p <- attr(pd, "wf_panel")
  expect_s3_class(pd, "wf_panel_design")
  expect_identical(p$waves, c("T1", "T2", "T3"))
  # diagonal is 1; T1 retained in T2 is 3/4
  expect_equal(diag(p$overlap), c(T1 = 1, T2 = 1, T3 = 1))
  expect_equal(p$overlap["T1", "T2"], 0.75)
  expect_equal(p$overlap["T2", "T3"], 0.75)
  # 4 of 6 units appear in >= 2 waves
  expect_equal(p$n_units, 6L)
  expect_equal(p$n_linked, 4L)
  expect_equal(unname(p$n_per_wave), c(4L, 4L, 4L))
  # the data frame itself is unchanged in content
  expect_equal(nrow(pd), 12L)
})

test_that("PN-01 fires on a broken linkage key, not on ordinary attrition", {
  # broken key: almost nothing links (overlap ~0.2) vs pattern "6" (~0.83)
  broken <- rbind(data.frame(id = 1:5, mes = "T1"),
                  data.frame(id = 5:9, mes = "T2"))
  al <- attr(panel_design(broken, unit = "id", wave = "mes", pattern = "6"),
             "wf_panel")$alerts
  expect_true(any(grepl("PN-01", al)))
  # group continuity matching the pattern must NOT fire (0.75 == 4(0)1 nominal)
  ok <- attr(panel_design(make_long(), unit = "id", wave = "mes",
                          rotation_group = "grp", pattern = "4(0)1"), "wf_panel")$alerts
  expect_false(any(grepl("PN-01", ok)))
})

test_that("panel_design tolerates a coarser unit repeated within a wave", {
  # household tracked on person-level rows: ID repeats within a wave -> counted once
  d <- rbind(data.frame(ID = c(1, 1, 2), mes = "T1"),
             data.frame(ID = c(1, 2),    mes = "T2"))
  p <- attr(panel_design(d, unit = "ID", wave = "mes"), "wf_panel")
  expect_equal(p$n_units, 2L)               # households 1 and 2, not 3 rows
  expect_equal(p$overlap["T1", "T2"], 1)    # both persist
})

test_that("panel_design errors on fewer than 2 waves", {
  one <- data.frame(id = 1:3, mes = "T1", grp = 1:3)
  expect_error(panel_design(one, unit = "id", wave = "mes"), "at least 2 waves")
})

test_that("panel_design derives Pr(panel selection) from rotation groups", {
  pd <- panel_design(make_long(), unit = "id", wave = "mes", rotation_group = "grp")
  p <- attr(pd, "wf_panel")
  # groups present per wave = 4; groups common to an adjacent pair here = 3 -> 0.75
  expect_equal(p$pr_adjacent, c(0.75, 0.75))
})

test_that("panel_design accepts a composite unit key (household id + person line)", {
  # same household id reused across two persons; the person is ID + nper
  d <- rbind(
    data.frame(ID = c(10, 10, 11), nper = c(1, 2, 1), mes = "T1"),
    data.frame(ID = c(10, 11),     nper = c(1, 1),     mes = "T2"))   # person 10-2 drops out
  pd <- panel_design(d, unit = c("ID", "nper"), wave = "mes", cluster = "ID")
  p <- attr(pd, "wf_panel")
  expect_equal(p$n_units, 3L)                 # persons 10-1, 10-2, 11-1
  expect_equal(p$n_linked, 2L)                # 10-1 and 11-1 in both waves
  expect_equal(p$overlap["T1", "T2"], 2/3)    # 2 of 3 T1 persons retained
  # tracking the household instead links all of wave T1 into T2
  ph <- attr(panel_design(d, unit = "ID", wave = "mes"), "wf_panel")
  expect_equal(ph$n_units, 2L)                # households 10, 11
  expect_equal(ph$overlap["T1", "T2"], 1)     # both households persist
})

test_that("panel_merge builds the wide file with presence indicators", {
  t1 <- data.frame(id = c(1, 2, 3), edad = c(20, 30, 40), respondio = c(1, 1, 0))
  t2 <- data.frame(id = c(2, 3, 4), edad = c(31, 41, 25), respondio = c(1, 1, 1))
  wide <- panel_merge(list(T1 = t1, T2 = t2), by = "id",
                      responded = "respondio", require = "any")
  expect_equal(nrow(wide), 4L)                          # union of {1,2,3,4}
  expect_true(all(c("edad_T1", "edad_T2", ".wf_in_T1", ".wf_in_T2") %in% names(wide)))
  # unit 1 only in T1, unit 4 only in T2
  r1 <- wide[wide$id == 1, ]; r4 <- wide[wide$id == 4, ]
  expect_equal(r1$.wf_in_T1, 1L); expect_equal(r1$.wf_in_T2, 0L)
  expect_equal(r4$.wf_in_T1, 0L); expect_equal(r4$.wf_in_T2, 1L)
  # require = "all" keeps only the intersection {2,3}
  inter <- panel_merge(list(T1 = t1, T2 = t2), by = "id", require = "all")
  expect_equal(sort(inter$id), c(2, 3))
})

test_that("panel_merge joins on a composite key", {
  t1 <- data.frame(ID = c(1, 1, 2), nper = c(1, 2, 1), edad = c(40, 12, 33))
  t2 <- data.frame(ID = c(1, 2),    nper = c(1, 1),     edad = c(41, 34))
  wide <- panel_merge(list(T1 = t1, T2 = t2), by = c("ID", "nper"), require = "all")
  expect_equal(nrow(wide), 2L)                       # persons 1-1 and 2-1
  expect_true(all(c("ID", "nper", "edad_T1", "edad_T2") %in% names(wide)))
})
