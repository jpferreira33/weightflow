# Unit tests for the internals of R/adjust-ml.R
# The learner helpers are tested directly (small hand-made frames) so the
# regression/classification split, the cross-fitting bookkeeping and the error
# branches are all reached without building a full spec. Optional-package
# branches are skipped when the package is absent.

set.seed(101)
n_ml  <- 60
ml_df <- data.frame(
  x      = stats::rnorm(n_ml),
  grp    = factor(rep(c("a", "b", "c"), length.out = n_ml))
)
ml_df$ycont  <- 2 + 3 * ml_df$x + stats::rnorm(n_ml)
ml_df$ybin   <- stats::rbinom(n_ml, 1, stats::plogis(0.6 * ml_df$x))
ml_df$ycount <- stats::rpois(n_ml, 3)
ml_w   <- rep(1, n_ml)
ml_new <- ml_df[1:10, ]

# ---------------------------------------------------------------------------
# .wf_threads()
# ---------------------------------------------------------------------------

test_that(".wf_threads defaults to 1 and honours the option", {
  old <- options(weightflow.num_threads = NULL)
  on.exit(options(old), add = TRUE)
  expect_identical(.wf_threads(), 1L)

  options(weightflow.num_threads = 4)
  expect_identical(.wf_threads(), 4L)

  options(weightflow.num_threads = 0)      # never below 1
  expect_identical(.wf_threads(), 1L)
})

# ---------------------------------------------------------------------------
# .crossfit_predict()
# ---------------------------------------------------------------------------

test_that(".crossfit_predict fills every unit from an out-of-sample model", {
  fp  <- function(train_idx, nd_idx) lapply(nd_idx, function(i) rep(7, length(i)))
  out <- .crossfit_predict(20, 4, seed = 1, fit_predict = fp)
  expect_length(out, 20L)
  expect_true(all(out == 7))
})

test_that(".crossfit_predict never trains on the unit it predicts", {
  overlap <- FALSE
  fp <- function(train_idx, nd_idx) {
    if (length(intersect(train_idx, nd_idx[[1]]))) overlap <<- TRUE
    lapply(nd_idx, function(i) rep(1, length(i)))
  }
  .crossfit_predict(20, 4, seed = 3, fit_predict = fp)
  expect_false(overlap)
})

test_that(".crossfit_predict keeps whole clusters inside the same fold", {
  cl    <- rep(1:6, each = 4)              # 6 clusters of 4 units
  folds <- integer(24)
  k     <- 0L
  fp <- function(train_idx, nd_idx) {
    k <<- k + 1L
    folds[nd_idx[[1]]] <<- k
    lapply(nd_idx, function(i) rep(0, length(i)))
  }
  .crossfit_predict(24, 3, cluster_id = cl, seed = 5, fit_predict = fp)
  expect_true(all(tapply(folds, cl, function(f) length(unique(f))) == 1L))
})

test_that(".crossfit_predict shrinks K when there are fewer clusters than folds", {
  cl <- rep(1:2, each = 3)                 # only 2 clusters, K = 5 requested
  nf <- 0L
  fp <- function(train_idx, nd_idx) {
    nf <<- nf + 1L
    lapply(nd_idx, function(i) rep(1, length(i)))
  }
  .crossfit_predict(6, 5, cluster_id = cl, seed = 2, fit_predict = fp)
  expect_equal(nf, 2L)
})

test_that(".crossfit_predict skips a fold that would leave no training rows", {
  called <- FALSE
  fp <- function(train_idx, nd_idx) {
    called <<- TRUE
    lapply(nd_idx, function(i) rep(1, length(i)))
  }
  out <- .crossfit_predict(5, 1, fit_predict = fp)   # K = 1 -> no training set
  expect_false(called)
  expect_true(all(out == 0))
})

test_that(".crossfit_predict is reproducible and restores the RNG state", {
  fp <- function(train_idx, nd_idx) lapply(nd_idx, function(i) rep(length(train_idx), length(i)))
  set.seed(99)
  before <- get(".Random.seed", envir = globalenv())
  a <- .crossfit_predict(20, 4, seed = 42, fit_predict = fp)
  expect_identical(get(".Random.seed", envir = globalenv()), before)
  b <- .crossfit_predict(20, 4, seed = 42, fit_predict = fp)
  expect_identical(a, b)
})

test_that(".crossfit_predict leaves no RNG state behind in a fresh session", {
  if (exists(".Random.seed", envir = globalenv(), inherits = FALSE))
    rm(".Random.seed", envir = globalenv())
  fp <- function(train_idx, nd_idx) lapply(nd_idx, function(i) rep(1, length(i)))
  .crossfit_predict(10, 2, seed = 7, fit_predict = fp)
  expect_false(exists(".Random.seed", envir = globalenv(), inherits = FALSE))
  set.seed(1)                                   # leave the session in a sane state
})

# ---------------------------------------------------------------------------
# .model_predict() -- glm engine
# ---------------------------------------------------------------------------

test_that(".model_predict fits a gaussian glm and predicts on several frames", {
  m <- list(formula = ycont ~ x, engine = "glm", family = "gaussian")
  p <- .model_predict(m, ml_df, ml_w, list(ml_new, ml_df[11:20, ]))
  expect_length(p, 2L)
  expect_length(p[[1]], 10L)
  expect_true(all(vapply(p, function(v) all(is.finite(v)), logical(1))))
})

test_that(".model_predict defaults to gaussian when no family is given", {
  m <- list(formula = ycont ~ x, engine = "glm")
  p <- .model_predict(m, ml_df, ml_w, list(ml_new))
  expect_true(all(is.finite(p[[1]])))
})

test_that(".model_predict fits binomial and poisson glms", {
  pb <- .model_predict(list(formula = ybin ~ x, engine = "glm", family = "binomial"),
                       ml_df, ml_w, list(ml_new))
  expect_true(all(pb[[1]] >= 0 & pb[[1]] <= 1))

  pp <- .model_predict(list(formula = ycount ~ x, engine = "glm", family = "poisson"),
                       ml_df, ml_w, list(ml_new))
  expect_true(all(pp[[1]] > 0))
})

test_that(".model_predict rejects an unknown family", {
  m <- list(formula = ycont ~ x, engine = "glm", family = "zzz")
  expect_error(.model_predict(m, ml_df, ml_w, list(ml_new)),
               "gaussian/binomial/poisson")
})

test_that(".model_predict rejects an unknown engine", {
  m <- list(formula = ycont ~ x, engine = "zzz")
  expect_error(.model_predict(m, ml_df, ml_w, list(ml_new)), "not recognized")
})

test_that(".model_predict points at the missing nonresponse step when y has NA", {
  bad <- ml_df; bad$ycont[3] <- NA
  m   <- list(formula = ycont ~ x, engine = "glm", family = "gaussian")
  expect_error(.model_predict(m, bad, ml_w, list(ml_new)), "missing values")
  expect_error(.model_predict(m, bad, ml_w, list(ml_new)), "nonresponse")
})

# ---------------------------------------------------------------------------
# .model_predict() -- optional learners
# ---------------------------------------------------------------------------

test_that(".model_predict runs the tree engine for regression and classification", {
  skip_if_not_installed("rpart")
  pr <- .model_predict(list(formula = ycont ~ x + grp, engine = "tree"),
                       ml_df, ml_w, list(ml_new))
  expect_true(all(is.finite(pr[[1]])))

  pc <- .model_predict(list(formula = ybin ~ x + grp, engine = "tree"),
                       ml_df, ml_w, list(ml_new))
  expect_true(all(pc[[1]] >= 0 & pc[[1]] <= 1))
})

test_that(".model_predict runs the forest engine for regression and classification", {
  skip_if_not_installed("ranger")
  pr <- .model_predict(list(formula = ycont ~ x + grp, engine = "forest"),
                       ml_df, ml_w, list(ml_new))
  expect_true(all(is.finite(pr[[1]])))

  pc <- .model_predict(list(formula = ybin ~ x + grp, engine = "forest",
                            family = "binomial"),
                       ml_df, ml_w, list(ml_new))
  expect_true(all(pc[[1]] >= 0 & pc[[1]] <= 1))
})

test_that(".model_predict runs the boosting engine for regression and classification", {
  skip_if_not_installed("xgboost")
  pr <- .model_predict(list(formula = ycont ~ x, engine = "boost"),
                       ml_df, ml_w, list(ml_new))
  expect_true(all(is.finite(pr[[1]])))

  pc <- .model_predict(list(formula = ybin ~ x, engine = "boost"),
                       ml_df, ml_w, list(ml_new))
  expect_true(all(pc[[1]] >= 0 & pc[[1]] <= 1))
})

test_that(".xgb_fit_predict aligns newdata columns missing from training", {
  skip_if_not_installed("xgboost")
  nd <- ml_df[ml_df$grp %in% c("a", "b"), ]
  nd$grp <- as.character(nd$grp)                # level "c" absent -> column added
  p  <- .xgb_fit_predict(ycont ~ x + grp, ml_df, ml_df$ycont, ml_w,
                         list(nd), classification = FALSE, nrounds = 20L)
  expect_length(p, 1L)
  expect_length(p[[1]], nrow(nd))
  expect_true(all(is.finite(p[[1]])))
})

test_that(".xgb_fit_predict returns probabilities for a classification objective", {
  skip_if_not_installed("xgboost")
  p <- .xgb_fit_predict(ybin ~ x, ml_df, ml_df$ybin, ml_w, list(ml_new),
                        classification = TRUE, nrounds = 20L)
  expect_true(all(p[[1]] >= 0 & p[[1]] <= 1))
})
