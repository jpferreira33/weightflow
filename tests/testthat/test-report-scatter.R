test_that(".thin_scatter is deterministic and bounded by cap", {
  set.seed(1)
  n <- 20000L
  x <- rlnorm(n, 0, 0.5)
  y <- x * runif(n, 0.4, 2.2)
  i1 <- weightflow:::.thin_scatter(x, y, cap = 3000L)
  i2 <- weightflow:::.thin_scatter(x, y, cap = 3000L)
  expect_identical(i1, i2)            # reproducible
  expect_lte(length(i1), 3000L)       # respeta el cap
  expect_gt(length(i1), 2500L)        # usa casi todo el presupuesto
})

test_that(".thin_scatter keeps the extreme points on both tails", {
  set.seed(2)
  core <- rlnorm(20000, 0, 0.3)
  # inyecta extremos conocidos: pesos antes minimo y maximo, y maxima distancia a y=x
  x <- c(core, 1e-4, 40)
  y <- c(core * runif(20000, 0.9, 1.1), 1e-4, 90)
  i  <- weightflow:::.thin_scatter(x, y, cap = 3000L)
  expect_true(which.min(x) %in% i)   # peso-antes mas chico
  expect_true(which.max(x) %in% i)   # peso-antes mas grande
  expect_true(which.max(y) %in% i)   # peso-despues mas grande
  expect_true(which.max(abs(y - x)) %in% i)  # mayor cambio
})

test_that(".svg_scatter output is identical across runs (report reproducibility)", {
  set.seed(3)
  x <- rlnorm(20000, 0, 0.5); y <- x * runif(20000, 0.4, 2.2)
  expect_identical(weightflow:::.svg_scatter(x, y),
                   weightflow:::.svg_scatter(x, y))
})

test_that("small inputs are drawn in full", {
  x <- rlnorm(500, 0, 0.4); y <- x * runif(500, 0.5, 1.6)
  expect_identical(weightflow:::.thin_scatter(x, y), seq_along(x))
})
