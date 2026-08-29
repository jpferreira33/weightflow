# response-propensity ML learners: threads, xgboost, cross-fitting, model prediction.

# xgboost works on numeric matrices, so the design matrix is built with
# model.matrix from the same formula, dropping the intercept column.
# Number of threads for the optional ML engines (ranger, xgboost). Defaults to
# 1 for reproducibility and to respect CRAN's check limits; users can raise it
# with options(weightflow.num_threads = n).
.wf_threads <- function() max(1L, as.integer(getOption("weightflow.num_threads", 1L)))

.xgb_fit_predict <- function(formula, train, y, w, newdatas, classification,
                             nrounds = 150L, max_depth = 4L, eta = 0.1) {
  if (!requireNamespace("xgboost", quietly = TRUE))
    stop("engine = 'boost' requires the 'xgboost' package (install.packages('xgboost')).")
  rhs <- stats::reformulate(attr(stats::terms(formula), "term.labels"))
  mm  <- function(df) {
    M <- stats::model.matrix(rhs, data = df)
    M[, colnames(M) != "(Intercept)", drop = FALSE]
  }
  Xtr <- mm(train)
  obj <- if (classification) "binary:logistic" else "reg:squarederror"
  dtr <- xgboost::xgb.DMatrix(data = Xtr, label = as.numeric(y), weight = w)
  fit <- xgboost::xgb.train(params = list(objective = obj, max_depth = max_depth,
                                          eta = eta, nthread = .wf_threads()),
                            data = dtr, nrounds = nrounds, verbose = 0)
  cols <- colnames(Xtr)
  lapply(newdatas, function(nd) {
    Mn <- mm(nd)
    miss <- setdiff(cols, colnames(Mn))           # align columns to training
    for (cc in miss) Mn <- cbind(Mn, stats::setNames(data.frame(0), cc))
    Mn <- as.matrix(Mn[, cols, drop = FALSE])
    as.numeric(stats::predict(fit, Mn))
  })
}

# Cross-fitting (K-fold out-of-sample prediction) to avoid overfitting when a
# flexible learner is used to estimate a propensity or an outcome model. For
# each fold k, the model is trained on the other K-1 folds and used to predict
# the held-out fold, so each unit's prediction comes from a model that did not
# see it. Folds are formed by cluster when `cluster_id` is given (so correlated
# units, e.g. a household, stay together and there is no information leakage).
# `fit_predict(train_idx, newdata_idx_list)` must fit on rows `train_idx` and
# return a list of prediction vectors, one per element of `newdata_idx_list`.
.crossfit_predict <- function(n, K, cluster_id = NULL, seed = NULL, fit_predict) {
  # Save & restore the caller's RNG state around the fold draw whether or not a
  # seed is given: with a seed the draw is reproducible, and either way the draw
  # does not advance (leak into) the caller's global random stream.
  if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
    old <- get(".Random.seed", envir = globalenv())
    on.exit(assign(".Random.seed", old, envir = globalenv()))
  } else {
    on.exit(rm(".Random.seed", envir = globalenv()))   # was unset (fresh session)
  }
  if (!is.null(seed)) set.seed(seed)
  if (is.null(cluster_id)) {
    fold <- sample(rep_len(seq_len(K), n))
  } else {                                   # assign whole clusters to folds
    uc       <- unique(cluster_id)
    cf       <- sample(rep_len(seq_len(K), length(uc)))
    names(cf) <- as.character(uc)
    fold     <- cf[as.character(cluster_id)]
  }
  K <- length(unique(fold))                  # may shrink if few clusters
  # #6: with a single (or single effective) fold, every unit is in the test set
  # and none in train; the loop would leave those predictions at 0, which become
  # 1e-6 propensities and weights x1e6. Fail loudly, and use NA (not 0) so any
  # unpredicted unit is caught rather than silently scored 0.
  if (K < 2L)
    stop(sprintf(paste0("Cross-fitting needs at least 2 folds, but only %d could be formed ",
                        "(too few %s to split). Use crossfit = NULL for in-sample fitting, ",
                        "fewer folds, or more %s."),
                 K, if (is.null(cluster_id)) "units" else "clusters",
                 if (is.null(cluster_id)) "units" else "clusters"), call. = FALSE)
  out <- rep(NA_real_, n)
  for (k in sort(unique(fold))) {
    test_idx  <- which(fold == k)
    train_idx <- which(fold != k)
    if (!length(train_idx)) next
    out[test_idx] <- fit_predict(train_idx, list(test_idx))[[1]]
  }
  if (anyNA(out))
    stop("Cross-fitting left some units without an out-of-fold prediction (a fold had no ",
         "training data). Reduce the number of folds or use crossfit = NULL.", call. = FALSE)
  out
}

# Returns E[y|x] (regression) or P(y = last level | x) (classification).
.model_predict <- function(m, train, w, newdatas) {
  f     <- m$formula
  yname <- as.character(f[[2]])
  yv    <- train[[yname]]
  if (anyNA(yv))
    stop(sprintf(paste0("Model-calibration outcome '%s' has missing values in the ",
      "training sample. This usually means a nonresponse step is missing before ",
      "step_model_calibration(): the outcome is only observed for respondents, so ",
      "adjust for nonresponse first so that nonrespondents are dropped."), yname),
      call. = FALSE)
  is_class <- isTRUE(m$family == "binomial") || is.factor(yv) || is.character(yv) ||
              (is.numeric(yv) && length(unique(yv[!is.na(yv)])) == 2L)
  train <- as.data.frame(train)
  train$.wts <- w                       # weights as a column -> avoids glm/rpart scoping
  if (any(train$.wts < 0, na.rm = TRUE))
    stop(sprintf(paste0("The model-based step received %d negative case weight(s), which ",
                        "the model engine ('%s') cannot fit (a bare glm() would only say ",
                        "\"negative weights not allowed\"). This usually means an earlier ",
                        "unbounded linear (GREG) calibration produced negative weights ",
                        "before this step. Add `bounds` to that calibration, or reorder the ",
                        "steps so the model runs on non-negative weights."),
                 sum(train$.wts < 0, na.rm = TRUE), m$engine), call. = FALSE)

  if (m$engine == "glm") {
    fam <- if (!is.null(m$family))
             switch(m$family, gaussian = stats::gaussian(),
                    binomial = stats::binomial(), poisson = stats::poisson(),
                    stop("`family` not recognized (use gaussian/binomial/poisson).") )
           else stats::gaussian()
    fit <- stats::glm(f, data = train, family = fam, weights = .wts)
    return(lapply(newdatas, function(nd)
      as.numeric(stats::predict(fit, newdata = nd, type = "response"))))
  }

  if (m$engine == "tree") {
    if (!requireNamespace("rpart", quietly = TRUE))
      stop("engine = 'tree' requires the 'rpart' package.")
    if (is_class) {
      train[[yname]] <- factor(train[[yname]]); lev <- levels(train[[yname]])
      fit <- rpart::rpart(f, data = train, method = "class", weights = .wts)
      return(lapply(newdatas, function(nd)
        as.numeric(stats::predict(fit, newdata = nd, type = "prob")[, lev[length(lev)]])))
    }
    fit <- rpart::rpart(f, data = train, method = "anova", weights = .wts)
    return(lapply(newdatas, function(nd) as.numeric(stats::predict(fit, newdata = nd))))
  }

  if (m$engine == "forest") {
    if (!requireNamespace("ranger", quietly = TRUE))
      stop("engine = 'forest' requires the 'ranger' package.")
    if (is_class) {
      train[[yname]] <- factor(train[[yname]]); lev <- levels(train[[yname]])
      fit <- ranger::ranger(f, data = train, probability = TRUE, case.weights = w,
                            num.threads = .wf_threads(), seed = 1L)
      return(lapply(newdatas, function(nd)
        as.numeric(stats::predict(fit, data = nd)$predictions[, lev[length(lev)]])))
    }
    fit <- ranger::ranger(f, data = train, case.weights = w,
                          num.threads = .wf_threads(), seed = 1L)
    return(lapply(newdatas, function(nd) as.numeric(stats::predict(fit, data = nd)$predictions)))
  }

  if (m$engine == "boost") {
    if (is_class) {
      ylev <- factor(train[[yname]])
      y01  <- as.integer(ylev) - 1L            # last level coded as 1
      return(.xgb_fit_predict(f, train, y01, w, newdatas, classification = TRUE))
    }
    return(.xgb_fit_predict(f, train, train[[yname]], w, newdatas, classification = FALSE))
  }
  stop(sprintf("engine '%s' not recognized.", m$engine))
}
