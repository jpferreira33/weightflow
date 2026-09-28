# `by` in step_model_calibration() and step_pseudoweight(): the sample is
# partitioned and every domain is solved on its own units. For model calibration
# that means the working models are fitted within the domain AND the X totals hold
# within it; for pseudo-weighting, one participation model per domain.

mk_pop <- function(seed = 11, N = 9000) {
  set.seed(seed)
  dep <- sample(c("Montevideo", "Canelones", "Salto"), N, TRUE, c(.5, .3, .2))
  pop <- data.frame(dep = dep, x1 = stats::rnorm(N), x2 = stats::rnorm(N))
  b1  <- c(Montevideo = 3, Canelones = -1, Salto = 0.5)[dep]   # slope flips by domain
  pop$y <- 10 + b1 * pop$x1 + 0.4 * pop$x2 + stats::rnorm(N)
  pop
}
mk_smp <- function(pop, n = 1200) {
  s <- pop[sample(nrow(pop), n), ]
  s$w0 <- nrow(pop) / n
  s
}
one_model <- list(mu_y = y_model(y ~ x1 + x2, engine = "glm", family = "gaussian"))

test_that("step_model_calibration(by=) reproduces the X totals within each domain", {
  pop <- mk_pop(); smp <- mk_smp(pop)
  fit <- prep(weighting_spec(smp, base_weights = w0) |>
                step_model_calibration(population = pop, x_formula = ~ x1,
                                       models = one_model, by = "dep"), warn = FALSE)
  cw <- collect_weights(fit, drop_zero = FALSE)
  for (d in unique(pop$dep)) {
    i <- cw$dep == d; j <- pop$dep == d
    expect_equal(sum(cw$.weight[i]), sum(j), tolerance = 1e-8)
    expect_equal(sum(cw$.weight[i] * cw$x1[i]), sum(pop$x1[j]), tolerance = 1e-6)
  }
  dg <- fit$steps[[1]]$diagnostics
  expect_true("domain" %in% names(dg))
  expect_setequal(unique(dg$domain), unique(pop$dep))
  expect_match(attr(dg, "note"), "independently within 'dep'")
})

test_that("step_model_calibration(by=) fits each working model inside its own domain", {
  pop <- mk_pop(); smp <- mk_smp(pop)
  fit <- prep(weighting_spec(smp, base_weights = w0) |>
                step_model_calibration(population = pop, x_formula = ~ x1,
                                       models = one_model, by = "dep"), warn = FALSE)
  dg <- fit$steps[[1]]$diagnostics
  for (d in unique(pop$dep)) {
    s_d <- smp[smp$dep == d, ]; p_d <- pop[pop$dep == d, ]
    b_loc <- stats::coef(stats::lm(y ~ x1 + x2, data = s_d, weights = s_d$w0))
    b_nat <- stats::coef(stats::lm(y ~ x1 + x2, data = smp,  weights = smp$w0))
    got   <- dg$target[dg$domain == d & dg$constraint == "mu_y"]
    # the model target is built from the DOMAIN's fit, not the national one
    expect_equal(got, sum(cbind(1, p_d$x1, p_d$x2) %*% b_loc), tolerance = 1e-2)
    expect_false(isTRUE(all.equal(got, sum(cbind(1, p_d$x1, p_d$x2) %*% b_nat),
                                  tolerance = 1e-3)))
  }
})

test_that("without `by` the domain totals do NOT hold", {
  pop <- mk_pop(); smp <- mk_smp(pop)
  fit <- suppressWarnings(prep(weighting_spec(smp, base_weights = w0) |>
    step_model_calibration(population = pop, x_formula = ~ x1, models = one_model),
    warn = FALSE))
  cw  <- collect_weights(fit, drop_zero = FALSE)
  off <- vapply(unique(pop$dep), function(d)
    abs(sum(cw$.weight[cw$dep == d]) / sum(pop$dep == d) - 1), numeric(1))
  expect_true(any(off > 0.01))       # the national system leaves the domains adrift
})

test_that("step_model_calibration(by=) validates the domain, the frame and the sizes", {
  pop <- mk_pop(); smp <- mk_smp(pop)
  mc <- function(...) prep(weighting_spec(smp, base_weights = w0) |>
                             step_model_calibration(population = pop, x_formula = ~ x1,
                                                    models = one_model, ...), warn = FALSE)
  expect_error(mc(by = "nope"), "not found in the data")
  p2 <- pop; p2$dep <- NULL
  expect_error(prep(weighting_spec(smp, base_weights = w0) |>
                      step_model_calibration(population = p2, x_formula = ~ x1,
                                             models = one_model, by = "dep"), warn = FALSE),
               "not found in `population`")
  # a national named vector under `by` would be applied to every domain
  expect_error(mc(by = "dep", x_totals = c("(Intercept)" = 9000, x1 = 0)),
               "counted once per domain")
  # a domain too small to carry its own system is named, with the arithmetic
  s3 <- smp; s3$dep[s3$dep == "Salto"][-(1:2)] <- "Canelones"
  expect_error(prep(weighting_spec(s3, base_weights = w0) |>
                      step_model_calibration(population = pop, x_formula = ~ x1,
                                             models = one_model, by = "dep",
                                             crossfit = 3), warn = FALSE),
               "Salto \\(n = 2\\)")
  # an NA domain has no partition to belong to
  s4 <- smp; s4$dep[1:3] <- NA
  expect_error(prep(weighting_spec(s4, base_weights = w0) |>
                      step_model_calibration(population = pop, x_formula = ~ x1,
                                             models = one_model, by = "dep"), warn = FALSE),
               "missing values")
})

test_that("step_pseudoweight(by=) fits one participation model per domain", {
  set.seed(5); N <- 20000
  dep <- sample(c("Montevideo", "Canelones", "Salto"), N, TRUE, c(.5, .3, .2))
  U <- data.frame(dep = dep, edad = stats::rnorm(N), educ = stats::rnorm(N))
  b <- c(Montevideo = 1.2, Canelones = -1.2, Salto = 0.2)[dep]   # sign flips by domain
  p <- 1 / (1 + exp(-(-1 + b * U$edad + 0.3 * U$educ)))
  vol <- U[stats::runif(N) < p, ]
  ref <- U[sample(N, 3000), ]; ref$w <- N / 3000
  rs  <- reference_sample(ref, weights = "w")

  psw <- function(by) {
    f <- prep(weighting_spec(vol, nonprob = TRUE) |>
                step_pseudoweight(reference = rs, formula = ~ edad + educ, by = by),
              warn = FALSE)
    collect_weights(f, drop_zero = FALSE)
  }
  gap <- function(cw) max(vapply(unique(U$dep), function(d)
    abs(sum(cw$.weight[cw$dep == d] * cw$edad[cw$dep == d]) - sum(U$edad[U$dep == d])),
    numeric(1)))
  # a single national model cannot hold a slope that flips sign across domains
  expect_lt(gap(psw("dep")), gap(psw(NULL)))

  f <- prep(weighting_spec(vol, nonprob = TRUE) |>
              step_pseudoweight(reference = rs, formula = ~ edad + educ, by = "dep"),
            warn = FALSE)
  dg <- f$steps[[1]]$diagnostics
  expect_true("domain" %in% names(dg))
  expect_setequal(unique(dg$domain), unique(U$dep))
  expect_match(attr(dg, "note"), "one participation model per domain")
})

test_that("step_pseudoweight(by=) validates the domain and the per-side sizes", {
  set.seed(6); N <- 6000
  U <- data.frame(dep = sample(c("A", "B"), N, TRUE), x = stats::rnorm(N))
  vol <- U[stats::runif(N) < 0.3, ]
  ref <- U[sample(N, 900), ]; ref$w <- N / 900
  rs  <- reference_sample(ref, weights = "w")
  sp  <- function(d, r) prep(weighting_spec(d, nonprob = TRUE) |>
                               step_pseudoweight(reference = r, formula = ~ x, by = "dep"),
                             warn = FALSE)
  expect_error(prep(weighting_spec(vol, nonprob = TRUE) |>
                      step_pseudoweight(reference = rs, formula = ~ x, by = "nope"),
                    warn = FALSE), "not found in the non-probability sample")
  r2 <- ref; r2$dep <- NULL
  expect_error(sp(vol, reference_sample(r2, weights = "w")), "not found in the `reference`")
  # a domain in the sample with no reference unit has nothing to compare against
  v3 <- vol; v3$dep[1:5] <- "C"
  expect_error(sp(v3, rs), "absent from the")
})
