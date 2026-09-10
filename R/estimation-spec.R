# ---------------------------------------------------------------------------
# Estimation grammar (sibling of the weighting recipe). Runs over a SAVED coordinated
# object (weightflow_wave_boot / weightflow_wave_jack) and emits numbers, not weights.
#
# Why a separate grammar: survey/srvyr cannot express the overlap-covariance of a change
# (they would treat the waves as independent), nor gross flows. So the change/precision
# layer is our own. It follows the package's step_* philosophy but is a DIFFERENT, typed
# pipeline: weighting steps transform weights (w -> w'); estimation steps consume the
# coordinated replicates and produce estimates (they are sinks). Class weightflow_estimation
# so dispatch never collides with the weighting steps. It is a thin declarative front-end
# over the engine in variance-panel.R (change_estimate / panel_estimate / level_estimate);
# nothing is reimplemented. Heavy replicate build once (wave_bootstrap); cheap estimation
# many times (step_domain / step_estimate), like survey's design-once / svyby-many.
# ---------------------------------------------------------------------------

.as_estimation <- function(x) {
  if (inherits(x, "weightflow_estimation")) return(x)
  # A pipeline may also start from the SPEC of a single period, so that the same DSL
  # declares the estimands of a chained wave_step() run. The spec carries one wave's data,
  # which is all step_domain()/step_filter() need to validate against.
  if (inherits(x, "weighting_spec"))
    return(structure(list(wb = list(data = list(x$data)), spec = x,
                          domains = character(0), estimands = list(), filters = list()),
                     class = "weightflow_estimation"))
  if (inherits(x, c("weightflow_wave_boot", "weightflow_wave_jack")))
    return(structure(list(wb = x, domains = character(0), estimands = list(),
                          filters = list()),
                     class = "weightflow_estimation"))
  stop("An estimation pipeline starts from wave_bootstrap() or wave_jackknife().",
       call. = FALSE)
}

# Restrict a base statistic to the subpopulation defined by the stored filters, by MASKING
# (evaluating the estimand on the rows that pass, per wave) -- never by dropping rows, which
# would break the PSU-coordinated replicate alignment between waves. Filters stack (AND).
# The condition is evaluated against whatever wave's data is passed in, so a single wrapped
# function does the right thing inside change_estimate/level_estimate/panel_estimate.
.apply_filters <- function(base_fn, filters) {
  if (!length(filters)) return(base_fn)
  function(w, d) {
    keep <- rep(TRUE, nrow(d))
    for (f in filters) {
      v <- eval(f$expr, d, f$env)
      keep <- keep & !is.na(v) & as.logical(v)
    }
    if (!any(keep)) return(NA_real_)
    base_fn(w[keep], d[keep, , drop = FALSE])
  }
}

# translate the step_estimate() statistic DSL into a function(w, data). Recognised heads:
# mean(var), total(var), prop(cond), ratio(num, den), quantile(var, p); otherwise the
# expression must evaluate to a function(w, data).
.estimand_fn <- function(expr, env) {
  if (is.call(expr)) {
    head <- as.character(expr[[1]])
    args <- as.list(expr)[-1]
    # na.rm = TRUE: in survey outcomes a variable is often structurally missing
    # (e.g. `desocupado` is NA outside the labour force), so the estimand is over the
    # non-missing domain -- mean(desocupado) then is the unemployment rate among the LF.
    if (head == "mean" && length(args) == 1L) {
      v <- deparse(args[[1]]); return(function(w, d) stats::weighted.mean(d[[v]], w, na.rm = TRUE))
    }
    if (head == "total" && length(args) == 1L) {
      v <- deparse(args[[1]]); return(function(w, d) sum(w * d[[v]], na.rm = TRUE))
    }
    if (head == "prop" && length(args) == 1L) {
      cond <- args[[1]]
      return(function(w, d) stats::weighted.mean(as.numeric(eval(cond, d, env)), w, na.rm = TRUE))
    }
    if (head == "ratio" && length(args) == 2L) {
      n <- args[[1]]; dn <- args[[2]]
      return(function(w, d) sum(w * eval(n, d, env), na.rm = TRUE) /
                            sum(w * eval(dn, d, env), na.rm = TRUE))
    }
    if (head == "quantile" && length(args) == 2L) {
      v <- deparse(args[[1]]); p <- eval(args[[2]], env)
      return(function(w, d) .wf_wtd_quantile(d[[v]], w, p))
    }
  }
  f <- tryCatch(eval(expr, env), error = function(e) NULL)
  if (is.function(f)) return(f)
  stop("`statistic` must be one of mean(var), total(var), prop(cond), ratio(num, den), ",
       "quantile(var, p), or a function(w, data).", call. = FALSE)
}

# weighted quantile (Type-7-like, interpolated on the centred cumulative weight)
.wf_wtd_quantile <- function(x, w, p) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  x <- x[ok]; w <- w[ok]
  if (!length(x)) return(NA_real_)
  o <- order(x); x <- x[o]; w <- w[o]
  cw <- (cumsum(w) - 0.5 * w) / sum(w)
  stats::approx(cw, x, xout = p, rule = 2, ties = "ordered")$y
}

#' Declarative estimation over a coordinated panel object
#'
#' `step_domain()` and `step_estimate()` build an estimation pipeline (`weightflow_estimation`)
#' on top of a saved [wave_bootstrap()] / [wave_jackknife()] object, so that changes, levels
#' and linear contrasts -- with the honest overlap covariance -- can be requested declaratively
#' and disaggregated, the way the weighting recipe is built with `step_*`. It is a thin front
#' end over [change_estimate()], [panel_estimate()] and [level_estimate()]; the coordinated
#' replicates do the variance. Evaluate with [collect_estimates()] (printing does it too).
#'
#' @param x a `weightflow_wave_boot` / `weightflow_wave_jack`, or a `weightflow_estimation`
#'   to extend.
#' @param ... for `step_domain()`, one or more grouping columns (unquoted or as strings);
#'   they stack, so the disaggregation is their cross (e.g. region x sex).
#' @return a `weightflow_estimation`.
#' @seealso [collect_estimates()], [change_estimate()], [panel_estimate()], [level_estimate()]
#' @examples
#' t1 <- subset(panel_ine, ola == 1 & disp == "R")
#' t2 <- subset(panel_ine, ola == 2 & disp == "R")
#' wb <- wave_bootstrap(
#'   list(T1 = weighting_spec(t1, base_weights = w_base),
#'        T2 = weighting_spec(t2, base_weights = w_base)),
#'   replicates = 100, strata = "estrato", psu = "psu", seed = 1, progress = FALSE)
#'
#' # net change of the unemployment rate, by region
#' collect_estimates(wb |> step_domain(region) |>
#'   step_estimate(mean(desocupado), over = "change"))
#'
#' # subpopulation: same change among the working-age population (rows masked, not dropped)
#' collect_estimates(wb |> step_filter(edad >= 25 & edad <= 54) |>
#'   step_estimate(mean(desocupado), over = "change"))
#' @export
step_domain <- function(x, ...) {
  est <- .as_estimation(x)
  q <- as.list(substitute(list(...)))[-1]
  if (!length(q)) stop("step_domain() needs at least one grouping column.", call. = FALSE)
  cols <- vapply(q, function(e) if (is.symbol(e)) as.character(e)
                                else if (is.character(e)) e else deparse(e), character(1))
  # Require the domain column in EVERY wave (the intersection), not the union: a column
  # present in only some waves passes a union check but .domain_grid() then drops the waves
  # that lack it, silently returning NA for those cells. A domain must exist everywhere it is
  # estimated. (Also catches a mistyped column, which the national-total fallback would
  # otherwise hide.) (EST-03)
  common <- Reduce(intersect, lapply(est$wb$data, names))
  miss   <- setdiff(cols, common)
  if (length(miss))
    stop(sprintf("step_domain(): column(s) %s not present in EVERY wave's data (common: %s).",
                 paste(miss, collapse = ", "),
                 paste(utils::head(sort(common), 20L), collapse = ", ")), call. = FALSE)
  est$domains <- unique(c(est$domains, cols))
  est
}

#' @rdname step_domain
#' @param condition for `step_filter()`, a logical expression (unquoted) that selects the
#'   subpopulation to estimate over -- e.g. `edad >= 25 & edad <= 54`. It is evaluated in
#'   each wave's data; rows are **masked** (not dropped), so the coordinated replicate
#'   structure and the overlap covariance are preserved. Multiple `step_filter()` calls
#'   stack (their conditions are ANDed).
#' @export
step_filter <- function(x, condition) {
  est <- .as_estimation(x)
  expr <- substitute(condition)
  if (missing(condition) || is.null(expr))
    stop("step_filter() needs a condition, e.g. step_filter(edad >= 25 & edad <= 54).",
         call. = FALSE)
  env <- parent.frame()
  # A bare name that is neither a column of any wave nor visible in the caller's scope is
  # almost surely a typo: fail now rather than as an opaque per-cell error at collect time.
  have <- unique(unlist(lapply(est$wb$data, names)))
  vars <- all.vars(expr)
  miss <- vars[!vars %in% have &
                 !vapply(vars, function(v) exists(v, envir = env), logical(1))]
  if (length(miss))
    stop(sprintf("step_filter(): name(s) %s not found in any wave's data or the calling scope.",
                 paste(miss, collapse = ", ")), call. = FALSE)
  est$filters <- c(est$filters, list(list(expr = expr, env = env)))
  est
}

#' @rdname step_domain
#' @param statistic the estimand, as a DSL call -- `mean(var)`, `total(var)`, `prop(cond)`,
#'   `ratio(num, den)`, `quantile(var, p)` -- or a `function(w, data)`.
#' @param over what to estimate: `"change"` (between two waves), `"level"` (one wave) or
#'   `"contrast"` (a linear combination, with `contrast=`). Default: `"change"` if the object
#'   has >= 2 waves, else `"level"`; `"contrast"` is implied when `contrast=` is given.
#' @param type for `over = "change"`, `"absolute"` (default) or `"relative"` (`theta2/theta1 - 1`).
#' @param waves optional wave label(s): one for `"level"`, two for `"change"`.
#' @param contrast numeric weights (one per wave) for `over = "contrast"`.
#' @param level confidence level.
#' @param label optional name for the estimand (defaults to the statistic's expression).
#' @export
step_estimate <- function(x, statistic, over = NULL, type = c("absolute", "relative"),
                          waves = NULL, contrast = NULL, level = 0.95, label = NULL) {
  est <- .as_estimation(x)
  st  <- substitute(statistic)
  fn  <- .estimand_fn(st, parent.frame())
  type <- match.arg(type)
  if (!is.null(over) && !over %in% c("change", "level", "contrast"))
    stop("`over` must be \"change\", \"level\" or \"contrast\".", call. = FALSE)
  est$estimands <- c(est$estimands, list(list(
    fn = fn, label = label %||% paste(deparse(st), collapse = ""),
    over = over, type = type, waves = waves, contrast = contrast, level = level)))
  est
}

#' @rdname step_domain
#' @param from,to for `step_transition()`, the from-/to-state columns.
#' @param format transition table format (`"row"`, `"col"`, `"joint"`, `"counts"`).
#' @export
step_transition <- function(x, from, to, format = c("row", "col", "joint", "counts")) {
  est <- .as_estimation(x)
  # Gross flows live on the LONGITUDINAL (wide) file with its ordinary bootstrap, not on the
  # two-wave coordinated object. Use the dedicated functions on that object instead.
  stop("Gross flows are computed on the longitudinal-weight bootstrap of the wide file, not on ",
       "the coordinated wave object. Build the longitudinal recipe, bootstrap_weights() it, and ",
       "call boot_transition(boot, from, to) (or transition_matrix() for the point estimate).",
       call. = FALSE)
}

# cross of the domain values that actually appear across the relevant waves
.domain_grid <- function(wb, doms, waves) {
  if (!length(doms)) return(NULL)
  parts <- lapply(waves, function(wv) {
    d <- wb$data[[wv]]
    if (!all(doms %in% names(d))) return(NULL)
    unique(d[doms])
  })
  grid <- unique(do.call(rbind, parts[!vapply(parts, is.null, logical(1))]))
  grid <- grid[stats::complete.cases(grid), , drop = FALSE]
  grid[do.call(order, as.list(grid)), , drop = FALSE]
}

# filter a base statistic to a domain cell (all domain columns equal the cell values)
.cell_fn <- function(base_fn, cols, vals) function(w, d) {
  keep <- rep(TRUE, nrow(d))
  for (k in seq_along(cols)) keep <- keep & !is.na(d[[cols[k]]]) & d[[cols[k]]] == vals[[k]]
  if (!any(keep)) return(NA_real_)
  base_fn(w[keep], d[keep, , drop = FALSE])
}

#' Evaluate an estimation pipeline
#'
#' Runs every estimand of a `weightflow_estimation` across the cross of its [step_domain()]
#' columns, using the coordinated replicates for the variance, and returns a tidy table.
#'
#' @param est a `weightflow_estimation` from [step_estimate()].
#' @return a `weightflow_estimation_result`: one row per (estimand x domain cell) with
#'   `estimate`, `se`, `ci_lower`, `ci_upper` and (for changes) `rho`. The object also
#'   carries a row-aligned `detail` frame (confidence level, effective replicates, the
#'   two wave levels behind a change and the overlap design effect) and the pipeline's
#'   `filters`, so [report_panel()] can document the estimates without re-running them.
#' @seealso [step_estimate()], [report_panel()]
#' @export
collect_estimates <- function(est) {
  if (!inherits(est, "weightflow_estimation"))
    stop("`est` must come from step_estimate() / step_domain().", call. = FALSE)
  if (!length(est$estimands)) stop("No estimands: add step_estimate(...).", call. = FALSE)
  wb <- est$wb; doms <- est$domains
  out <- list(); det <- list()
  fails <- character(0)                                # collect, don't swallow (audit C5)
  for (E in est$estimands) {
    over <- E$over %||% (if (!is.null(E$contrast)) "contrast"
                         else if (length(wb$waves) >= 2L) "change" else "level")
    wv <- if (!is.null(E$waves)) as.character(E$waves)
          else if (over == "level") wb$waves[1]
          else if (over == "contrast") wb$waves else wb$waves[1:2]
    # `.d` collects, per row, what the engine knows but the tidy table does not carry:
    # the confidence level actually used, how many replicates survived, the two wave
    # levels a change is built from, and the overlap design effect V / (V1 + V2). It is
    # kept ROW-ALIGNED and OUT of `table` on purpose -- the documented tidy shape (and
    # its print method) stays exactly as it was, and report_panel() gets the richer
    # numbers without paying for a second pass over the replicates.
    .d <- list()
    run <- function(fn) {
      r <- switch(over,
        level    = level_estimate(wb, fn, wave = wv, level = E$level),
        change   = change_estimate(wb, fn, waves = wv, level = E$level, type = E$type),
        contrast = panel_estimate(wb, fn, contrast = E$contrast, waves = wv, level = E$level))
      pt <- if (is.null(r$point)) c(NA_real_, NA_real_) else as.numeric(r$point)
      .d[[length(.d) + 1L]] <<- data.frame(
        level     = r$level %||% NA_real_,
        R         = if (is.null(r$R)) NA_integer_ else as.integer(r$R),
        wave_1    = if (length(pt) >= 1L) pt[1] else NA_real_,
        wave_2    = if (length(pt) >= 2L) pt[2] else NA_real_,
        deff      = r$deff_change %||% r$deff %||% NA_real_,
        se_indep  = if (is.null(r$Vind)) NA_real_ else sqrt(r$Vind),
        stringsAsFactors = FALSE)
      data.frame(estimate = r$estimate, se = r$se, ci_lower = r$ci_lower,
                 ci_upper = r$ci_upper, rho = if (is.null(r$rho)) NA_real_ else r$rho)
    }
    fn0 <- .apply_filters(E$fn, est$filters)     # mask to the subpopulation (audit: domain est.)
    grid <- .domain_grid(wb, doms, wv)
    if (is.null(grid)) {
      res <- tryCatch(run(fn0), error = function(e) {
        fails[[length(fails) + 1L]] <<- sprintf("'%s': %s", E$label, conditionMessage(e)); NULL
      })
      body <- if (is.null(res)) NULL else res
    } else {
      rows <- lapply(seq_len(nrow(grid)), function(i) {
        vals <- as.list(grid[i, , drop = FALSE])
        cell <- paste(sprintf("%s=%s", doms, vapply(vals, as.character, character(1))),
                      collapse = ", ")
        res  <- tryCatch(run(.cell_fn(fn0, doms, vals)), error = function(e) {
          fails[[length(fails) + 1L]] <<-
            sprintf("'%s' [%s]: %s", E$label, cell, conditionMessage(e)); NULL
        })
        if (is.null(res)) return(NULL)
        cbind(grid[i, , drop = FALSE], res, row.names = NULL)
      })
      body <- do.call(rbind, rows[!vapply(rows, is.null, logical(1))])
    }
    if (is.null(body)) next
    head <- data.frame(estimand = E$label, over = over,
                       type = if (over == "change") E$type else NA_character_,
                       stringsAsFactors = FALSE)
    out[[length(out) + 1L]] <- cbind(head[rep(1, nrow(body)), , drop = FALSE], body,
                                     row.names = NULL)
    # one detail row per successful run, in the same order as `body`
    dd <- if (length(.d)) do.call(rbind, .d) else NULL
    det[[length(det) + 1L]] <-
      if (!is.null(dd) && nrow(dd) == nrow(body)) dd else .na_detail(nrow(body))
  }
  if (length(fails)) {
    show <- utils::head(fails, 10L)
    warning(sprintf("collect_estimates(): %d estimate(s) failed and were dropped:\n  - %s%s",
                    length(fails), paste(show, collapse = "\n  - "),
                    if (length(fails) > length(show))
                      sprintf("\n  ... and %d more", length(fails) - length(show)) else ""),
            call. = FALSE)
  }
  if (!length(out))
    stop("collect_estimates(): every estimate failed; nothing to return. ",
         "See the warning above for the reasons.", call. = FALSE)
  tab <- do.call(rbind, out)
  structure(list(table = tab, domains = doms,
                 method = if (inherits(wb, "weightflow_wave_jack")) "jackknife" else "bootstrap",
                 waves = wb$waves,
                 detail = do.call(rbind, c(det, list(make.row.names = FALSE))),
                 # the subpopulation the estimates are over, as written by the user
                 filters = vapply(est$filters,
                                  function(f) paste(deparse(f$expr), collapse = " "),
                                  character(1)),
                 replicates = tryCatch(ncol(wb$reps[[1]]), error = function(e) NA_integer_)),
            class = "weightflow_estimation_result")
}

# all-NA detail rows, so `detail` stays row-aligned with `table` even when an engine
# object did not carry the extra fields
.na_detail <- function(n) data.frame(
  level = rep(NA_real_, n), R = rep(NA_integer_, n), wave_1 = rep(NA_real_, n),
  wave_2 = rep(NA_real_, n), deff = rep(NA_real_, n), se_indep = rep(NA_real_, n))

#' @export
print.weightflow_estimation <- function(x, ...) {
  cat("<weightflow estimation pipeline>\n")
  cat(sprintf("  source     : %s (%d waves)\n",
              if (inherits(x$wb, "weightflow_wave_jack")) "coordinated jackknife" else
                "coordinated bootstrap", length(x$wb$waves)))
  cat(sprintf("  domains    : %s\n", if (length(x$domains)) paste(x$domains, collapse = " x ")
                                     else "(none)"))
  if (length(x$filters))
    cat(sprintf("  filter     : %s\n",
                paste(vapply(x$filters, function(f) paste(deparse(f$expr), collapse = ""),
                             character(1)), collapse = " & ")))
  cat(sprintf("  estimands  : %d\n", length(x$estimands)))
  # List the estimands declaratively; do NOT run collect_estimates() here (audit C10):
  # printing must be cheap and side-effect-free -- a full coordinated estimation can take
  # seconds to minutes. Show what will be computed and how to trigger it.
  for (E in x$estimands) {
    over <- E$over %||% (if (!is.null(E$contrast)) "contrast"
                         else if (length(x$wb$waves) >= 2L) "change" else "level")
    cat(sprintf("    - %s  (over = %s%s)\n", E$label, over,
                if (over == "change") sprintf(", type = %s", E$type) else ""))
  }
  if (length(x$estimands))
    cat("  -> collect_estimates() to evaluate\n")
  invisible(x)
}

#' @export
print.weightflow_estimation_result <- function(x, ...) {
  cat(sprintf("<weightflow estimates [%s]  %s>\n", x$method,
              paste(x$waves, collapse = ", ")))
  tab <- x$table
  num <- vapply(tab, is.numeric, logical(1))
  tab[num] <- lapply(tab[num], function(c) signif(c, 4))
  print(tab, row.names = FALSE)
  invisible(x)
}
