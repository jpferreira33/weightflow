test_that(".replication_card renders a jackknife design and flags lonely PSU", {
  fake <- structure(list(
    data = data.frame(region = c("N", "N", "S"), psu = c(1, 2, 3)),
    strata = "region", psu = "psu", R = 2L, method = "jackknife",
    lonely_psu = "collapse", cores = 1L, elapsed = 12.3),
    class = "weightflow_jack")
  h <- weightflow:::.replication_card(fake, "en")
  expect_match(h, "Replication-based variance estimation")
  expect_match(h, "JKn")           # strata present -> JKn
  expect_match(h, "12.3 s")        # run time
  expect_match(h, "single PSU")    # lonely-PSU attention note (S has 1 PSU)
})

test_that(".replication_card renders a bootstrap design with seed", {
  fake <- structure(list(
    data = data.frame(region = rep(c("N", "S"), each = 2), psu = 1:4),
    strata = "region", psu = "psu", R = 200L, method = "bootstrap",
    lonely_psu = "certainty", seed = 1, cores = 4L, elapsed = 95),
    class = "weightflow_boot")
  h <- weightflow:::.replication_card(fake, "es")
  expect_match(h, "Bootstrap")
  expect_match(h, "1.6 min")       # 95 s -> minutes
  expect_match(h, "Semilla")
})

test_that(".replication_card is empty for NULL / non-replicate input", {
  expect_identical(weightflow:::.replication_card(NULL, "en"), "")
  expect_identical(weightflow:::.replication_card(list(a = 1), "en"), "")
})
