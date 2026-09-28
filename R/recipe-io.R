# Recipe serialization: write a weighting recipe (the METHOD, not the data) to a
# human-readable YAML file and read it back. The recipe becomes a versionable
# metadata artifact -- reviewable in a pull request, archived next to the report,
# referenceable from a metadata system -- and can be reconstructed into an
# executable weighting_spec when bound to fresh data.
#
# What is serialized: the base-weight column name, the non-probability flag, and
# each step's id, type and parameters. Formulas and captured column expressions are
# stored as text; a reference_sample() is stored as a DESCRIPTOR (its data is not
# metadata), so reconstructing a reference-bearing step needs the reference passed
# back in at read time.

# --- executable content: what a recipe is allowed to contain ---------------
# SECURITY (IO-03). A recipe stores captured conditions and formulas as TEXT, and
# prep() evaluates them with eval(expr, envir = data, enclos = baseenv()) -- where
# system(), unlink() and file.remove() are all in scope. So the `.wf: function`
# gate alone was never the whole door: a hand-edited `.wf: expr` or `.wf: formula`
# node executes on the first prep(), not at read time, which is exactly the shape
# of an attack on a file format meant to be exchanged between organizations and
# reviewed in a pull request.
#
# The gate is therefore a WHITELIST of calls, checked when allow_code = FALSE.
# It deliberately contains no higher-order function (no do.call/sapply/Reduce/...):
# those take a function as an ARGUMENT, so `sapply(1, system)` would pass a check
# that only inspects call heads. A call whose head is not a plain symbol -- an
# anonymous function, `x[[1]](...)`, `base::system(...)` -- is rejected outright.
.WF_SAFE_FNS <- c(
  "(", "{", "c", "[", "[[", "$", ":", "%in%", "%%", "%/%", "!", "&", "&&", "|", "||",
  "==", "!=", "<", ">", "<=", ">=", "+", "-", "*", "/", "^", "~", "I", "xor",
  "is.na", "is.finite", "is.null", "isTRUE", "isFALSE", "ifelse",
  "as.numeric", "as.integer", "as.character", "as.logical", "as.factor", "factor",
  "levels", "nlevels", "droplevels", "relevel", "interaction", "cut", "findInterval",
  "abs", "sqrt", "round", "floor", "ceiling", "trunc", "log", "log1p", "log2",
  "log10", "exp", "pmin", "pmax", "sign", "scale", "poly",
  "length", "rev", "sort", "seq_len", "seq_along", "rep", "unname",
  "nchar", "substr", "substring", "trimws", "tolower", "toupper", "paste", "paste0",
  "grepl", "sub", "gsub", "startsWith", "endsWith", "strsplit",
  "rowSums", "colSums", "rowMeans", "colMeans", "pmin.int", "pmax.int")

# Walk an expression and refuse anything the whitelist does not cover. `where`
# names the step, so the error says which line of the file to look at.
.wf_check_expr <- function(e, step_id, where = "expression") {
  if (is.call(e)) {
    f <- e[[1L]]
    bad <- !is.symbol(f) || !(as.character(f) %in% .WF_SAFE_FNS)
    if (bad)
      stop(sprintf(paste0(
        "Step '%s' stores the %s `%s`, which calls `%s`. Reading a recipe must not be able ",
        "to run arbitrary code, so only a fixed set of data-manipulation functions is ",
        "accepted. Inspect the file; if you trust it, re-read with ",
        "read_recipe(..., allow_code = TRUE)."),
        step_id, where, paste(deparse(e), collapse = " "),
        paste(deparse(f), collapse = "")), call. = FALSE)
    for (a in as.list(e)[-1L]) if (!identical(a, quote(expr = ))) .wf_check_expr(a, step_id, where)
  }
  invisible(TRUE)
}

# --- generic type-aware encoder / decoder ----------------------------------
.wf_encode <- function(x) {
  if (is.null(x)) return(NULL)
  if (inherits(x, "formula"))
    return(list(.wf = "formula", value = paste(deparse(x), collapse = " ")))
  if (is.symbol(x) || is.call(x))
    return(list(.wf = "expr", value = paste(deparse(x), collapse = " ")))
  if (inherits(x, "wf_reference_sample"))
    return(list(.wf = "reference_sample",
                n = length(attr(x, "wf_ref_weights")),
                vars = as.list(names(x)),
                has_replicates = !is.null(attr(x, "wf_ref_replicates"))))
  if (inherits(x, "wf_y_model"))
    return(list(.wf = "y_model",
                formula = paste(deparse(x$formula), collapse = " "),
                engine  = x$engine,
                family  = if (is.null(x$family)) NULL
                          else if (is.character(x$family)) x$family
                          else tryCatch(x$family$family, error = function(e) NULL)))
  if (is.function(x))
    return(list(.wf = "function", value = paste(deparse(x), collapse = "\n")))
  if (is.data.frame(x)) {
    # A small data frame is a control/totals TABLE (the target of the method, e.g.
    # a tidy poststratification total): that is metadata, so serialize it column by
    # column with types preserved. A large one is microdata (a population frame) and
    # must go through reference_sample() instead -- the threshold keeps a census out.
    if (nrow(x) > 10000L)
      stop(paste0("A step carries a data frame with ", format(nrow(x), big.mark = ","),
                  " rows, too large to be recipe metadata (it looks like microdata, not a ",
                  "control-totals table). Pass a population frame through reference_sample() ",
                  "instead."), call. = FALSE)
    return(list(.wf = "totals_table", nrow = nrow(x),
                columns = lapply(names(x), function(nm) {
                  col <- x[[nm]]
                  list(name = nm, class = class(col)[1],
                       ordered = is.ordered(col),
                       levels = if (is.factor(col)) as.list(levels(col)) else list(),
                       values = as.list(as.character(col)))
                })))
  }
  if (is.list(x))
    return(lapply(x, .wf_encode))
  # atomic: a bare scalar stays plain; a named or length>1 vector is tagged so its
  # names and mode survive the YAML round-trip (e.g. calibration margins/totals).
  if (is.atomic(x) && (length(x) != 1L || !is.null(names(x))))
    return(list(.wf = "vector", mode = typeof(x),
                names = if (is.null(names(x))) list() else as.list(names(x)),
                value = as.list(unname(x))))
  x
}

# Every formula a recipe carries goes through here, so the whitelist cannot be
# bypassed by adding a node type that builds one on its own (IO-03).
.wf_safe_formula <- function(txt, step_id, allow_code) {
  fo <- stats::as.formula(txt, env = baseenv())
  if (!isTRUE(allow_code)) .wf_check_expr(fo, step_id, "formula")
  fo
}

.wf_decode <- function(x, references, step_id, allow_code = FALSE) {
  if (is.list(x) && !is.null(x$.wf)) {
    switch(x$.wf,
      formula = .wf_safe_formula(x$value, step_id, allow_code),
      expr    = { v <- str2lang(x$value)
                  if (!isTRUE(allow_code)) .wf_check_expr(v, step_id, "expression")
                  v },
      vector  = { v <- unlist(x$value, use.names = FALSE); storage.mode(v) <- x$mode
                  if (length(x$names)) names(v) <- unlist(x$names); v },
      totals_table = {
        cols <- lapply(x$columns, function(cd) {
          v <- as.character(unlist(cd$values, use.names = FALSE))
          switch(cd$class,
            ordered   = factor(v, levels = unlist(cd$levels), ordered = TRUE),
            factor    = factor(v, levels = unlist(cd$levels), ordered = isTRUE(cd$ordered)),
            numeric   = as.numeric(v),
            double    = as.numeric(v),
            integer   = as.integer(v),
            logical   = as.logical(v),
            Date      = as.Date(v),
            POSIXct   = as.POSIXct(v),
            v)
        })
        names(cols) <- vapply(x$columns, function(cd) cd$name, character(1))
        as.data.frame(cols, stringsAsFactors = FALSE)
      },
      y_model = {
        # SECURITY (IO-03): this branch used to build its formula WITHOUT the whitelist
        # the `formula` branch applies, so a y_model node was an open code-execution
        # path: the formula reaches step_model_calibration() untouched and runs inside
        # .model_predict() / model.matrix() on the first prep(). The NA guard does not
        # see it either -- all.vars() on `I(system("..."))` is character(0). Same check
        # as every other formula, and `engine`/`family` against closed catalogues, so a
        # hand-edited recipe cannot name an engine the constructor would have refused.
        eng <- x$engine %||% "glm"
        if (!is.character(eng) || length(eng) != 1L ||
            !eng %in% c("glm", "tree", "forest", "boost"))
          stop(sprintf(paste0("Step '%s' stores a y_model with engine '%s', which is not one ",
                              "of glm, tree, forest, boost."), step_id,
                       paste(utils::head(as.character(eng), 1L), collapse = "")), call. = FALSE)
        fam <- x$family
        if (!is.null(fam) && (!is.character(fam) || length(fam) != 1L ||
                              !fam %in% c("gaussian", "binomial", "poisson")))
          stop(sprintf(paste0("Step '%s' stores a y_model with family '%s', which is not one ",
                              "of gaussian, binomial, poisson."), step_id,
                       paste(utils::head(as.character(fam), 1L), collapse = "")), call. = FALSE)
        y_model(.wf_safe_formula(x$formula, step_id, allow_code), engine = eng, family = fam)
      },
      `function` = {
        # SECURITY: a `.wf: function` node carries arbitrary R source that would run
        # immediately here (eval at read time, before any prep()). A recipe is meant to
        # be exchanged between organizations, so evaluating it is a code-execution vector.
        # Refuse by default; only evaluate when the caller explicitly trusts the file.
        if (!isTRUE(allow_code))
          stop(sprintf(paste0("Step '%s' stores an R function as executable source. Reading it ",
                              "would run that code. If you trust this file, re-read with ",
                              "read_recipe(..., allow_code = TRUE); otherwise inspect the ",
                              "'value' under the function node first."), step_id),
               call. = FALSE)
        eval(str2lang(x$value), envir = baseenv())
      },
      previous_wave = stop(sprintf(paste0(
        "Step '%s' is a step_cre() whose `previous` is a fitted wave (its data, weights and ",
        "history), which the recipe does not store. A composite (CRE) recipe cannot be rebuilt ",
        "from YAML alone: build the previous wave in R and call step_cre(previous = <fit>) ",
        "directly."), step_id), call. = FALSE),
      microdata_frame = {
        pop <- if (is.list(references)) references[[step_id]] else NULL
        if (!is.data.frame(pop))
          stop(sprintf(paste0("Step '%s' uses a population frame of %s rows (%s), which the ",
                              "recipe stores as a descriptor only -- microdata is not metadata. ",
                              "Pass it back in: read_recipe(..., references = list(`%s` = <data ",
                              "frame>))."),
                       step_id, format(x$nrow %||% NA, big.mark = ","),
                       paste(unlist(x$vars), collapse = ", "), step_id), call. = FALSE)
        pop
      },
      reference_sample = {
        ref <- if (is.list(references)) references[[step_id]] else NULL
        if (!inherits(ref, "wf_reference_sample"))
          stop(sprintf(paste0("Step '%s' calibrates or pseudo-weights against a reference_sample(), ",
                              "whose data is not stored in the recipe. Pass it back in: ",
                              "read_recipe(..., references = list(`%s` = reference_sample(...)))."),
                       step_id, step_id), call. = FALSE)
        ref
      },
      stop(sprintf("Unknown encoded type '%s' in the recipe.", x$.wf), call. = FALSE))
  } else if (is.list(x)) {
    lapply(x, .wf_decode, references = references, step_id = step_id, allow_code = allow_code)
  } else x
}

#' Write a weighting recipe to a YAML file
#'
#' Serializes the recipe (the weighting *method*, not the data) to a human-readable
#' YAML file: the base-weight column, the non-probability flag, and every step's id,
#' type and parameters. The file is a versionable metadata artifact you can review
#' in a pull request, archive next to the quality report, or reference from a
#' metadata system. Read it back with [read_recipe()].
#'
#' Formulas and captured column expressions are stored as text. A `reference_sample()`
#' is stored as a descriptor only (its microdata is not metadata), so a step that
#' calibrates or pseudo-weights against a reference must be given that reference
#' again when the recipe is reconstructed. Small control-totals tables (for example
#' a tidy poststratification total) are serialized in full; a data frame larger than
#' 10,000 rows is treated as microdata and rejected (route it through
#' `reference_sample()`).
#'
#' A recipe is portable only if its captured expressions reference columns of the
#' data (for example `respondent = responded`). An expression that referenced
#' objects from your R session (say `respondent = id %in% ids_resp`) is stored as
#' text but cannot be reconstructed elsewhere, and will error at `prep()`.
#'
#' @param object a `weighting_spec` (or a prepped one; only the recipe is written,
#'   never the weights or the data).
#' @param file path to the `.yml`/`.yaml` file to write.
#' @param timestamp whether to record the write time (UTC) in the file. Default
#'   `TRUE`; set `FALSE` for byte-identical output across writes of the same recipe
#'   (cleaner version-control diffs).
#' @return the `file` path, invisibly.
#' @seealso [read_recipe()]
#' @examples
#' spec <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
#'   step_calibrate(method = "raking", margins = list(region = c(table(population$region))))
#' f <- tempfile(fileext = ".yml")
#' write_recipe(spec, f)
#' @export
#' @family recipe serialization
write_recipe <- function(object, file, timestamp = TRUE) {
  if (!requireNamespace("yaml", quietly = TRUE))
    stop("write_recipe() needs the 'yaml' package. Run install.packages('yaml').", call. = FALSE)
  if (!inherits(object, c("weighting_spec", "prepped_weighting_spec")))
    stop("`object` must be a weighting_spec (the recipe, optionally prepped).", call. = FALSE)
  bw <- object$base_weights
  bw_out <- if (isTRUE(object$nonprob) && grepl("^\\.wf_base1", bw)) NULL else bw
  steps <- lapply(object$steps, function(s) {
    fields <- s[setdiff(names(s), c("env", "diagnostics", "alerts", "id"))]
    # step_cre() holds the entire PREPPED previous wave (data + weights + history) in
    # `previous`. That is a fitted object, not recipe metadata: serializing it would dump
    # the previous wave's microdata into the YAML (a data leak) or abort on a realistic wave.
    # Replace it with a marker; the previous wave is re-supplied on read, like a reference. (IO-02)
    if (inherits(s, "step_cre") && !is.null(fields$previous))
      fields$previous <- list(.wf = "previous_wave")
    # Same class of leak, second door (IO-04). `population =` of step_calibrate() /
    # step_model_calibration() is a POPULATION FRAME -- the documented way to pass
    # one -- and the generic encoder serialized it value by value: the shipped
    # `population` came out as a 625 KB recipe carrying person_id and every income.
    # A file advertised as "the method, not the data" must not be a disclosure
    # vector, so store a descriptor and ask for the frame back at read time, exactly
    # as reference_sample() already does. (A reference_sample is already a
    # descriptor, so it is left alone.)
    if (is.data.frame(fields$population))
      fields$population <- list(.wf = "microdata_frame", nrow = nrow(fields$population),
                                vars = as.list(names(fields$population)))
    list(id = s$id %||% NA_character_, type = class(s)[1],
         classes = as.list(class(s)),
         params = .wf_encode(fields))
  })
  doc <- list(weightflow_recipe = list(
    version      = as.character(utils::packageVersion("weightflow")),
    created      = if (isTRUE(timestamp))
                     format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC") else NULL,
    base_weights = bw_out,
    nonprob      = isTRUE(object$nonprob),
    steps        = steps))
  writeLines(yaml::as.yaml(doc, precision = 15), con = file)
  invisible(file)
}

#' Read a weighting recipe from a YAML file
#'
#' Reads a recipe written by [write_recipe()]. With `data = NULL` (the default) it
#' returns an inspectable recipe manifest (for review or archival); pass `data` to
#' reconstruct an executable `weighting_spec` bound to that data, ready for [prep()].
#'
#' A reconstructed recipe is validated only when you call [prep()]: a hand-edited
#' recipe with an out-of-range or mistyped value surfaces its error there, not at
#' `read_recipe()` time. And because reading a recipe evaluates the stored
#' expressions, only read recipes you trust, as you would `source()` an R script.
#'
#' @param file path to the recipe `.yml`/`.yaml` file.
#' @param data optional data frame. When supplied, the recipe is rebuilt into a
#'   `weighting_spec` on this data. The columns the steps reference (weights,
#'   auxiliaries, disposition flags) must exist in `data`.
#' @param references optional named list, named by the id of the step that needs
#'   each object, restoring what the recipe stores only as a descriptor because it is
#'   microdata rather than metadata: a `reference_sample()` for a step that calibrates
#'   or pseudo-weights against a reference, and the `population` data frame of
#'   [step_calibrate()] / [step_model_calibration()].
#' @param allow_code single logical, the gate on **every** executable thing a recipe
#'   file can carry: the conditions and formulas it stores as text, and a step that
#'   stores an R function as source. With `FALSE` (the default) a stored expression is
#'   accepted only if every call in it is on a fixed whitelist of data-manipulation
#'   functions (comparisons, arithmetic, `is.na()`, `factor()`, `cut()`, string and
#'   `apply`-free helpers), and a function node is refused outright. That matters
#'   because a recipe is meant to be exchanged between organizations: an expression
#'   like `{ system("...") ; responded }` runs at the first [prep()], not at read
#'   time. Set `TRUE` only for a file you trust, exactly as you would `source()` it.
#' @return With `data = NULL`, a `weightflow_recipe` manifest (a list with a print
#'   method). With `data`, a `weighting_spec`.
#' @seealso [write_recipe()]
#' @examples
#' spec <- weighting_spec(sample_survey, base_weights = pw) |>
#'   step_nonresponse(respondent = responded, method = "weighting_class", by = "region")
#' f <- tempfile(fileext = ".yml"); write_recipe(spec, f)
#' read_recipe(f)                       # inspect the manifest
#' spec2 <- read_recipe(f, data = sample_survey)   # rebuild an executable recipe
#' @export
#' @family recipe serialization
read_recipe <- function(file, data = NULL, references = NULL, allow_code = FALSE) {
  if (!requireNamespace("yaml", quietly = TRUE))
    stop("read_recipe() needs the 'yaml' package. Run install.packages('yaml').", call. = FALSE)
  doc <- yaml::read_yaml(file)$weightflow_recipe
  if (is.null(doc) || is.null(doc$steps))
    stop("`file` is not a weightflow recipe (no `weightflow_recipe` block).", call. = FALSE)
  manifest <- structure(list(
    version = doc$version, created = doc$created,
    base_weights = doc$base_weights, nonprob = isTRUE(doc$nonprob),
    steps = doc$steps), class = "weightflow_recipe")
  if (is.null(data)) return(manifest)

  # Reconstruct an executable spec. Build the base spec directly (the constructor
  # captures base_weights by NSE, which a stored name cannot drive), then rebuild
  # each step object from its decoded parameters and append it.
  if (!is.data.frame(data)) stop("`data` must be a data frame.", call. = FALSE)
  bw <- manifest$base_weights
  if (is.null(bw)) {
    if (!manifest$nonprob)
      stop("The recipe has no base weights but is not a non-probability recipe.", call. = FALSE)
    bw <- ".wf_base1"; while (bw %in% names(data)) bw <- paste0(bw, "_")
    data[[bw]] <- 1
  } else if (!bw %in% names(data)) {
    stop(sprintf("Base-weight column '%s' is not in `data`.", bw), call. = FALSE)
  }
  spec <- structure(list(data = data, base_weights = bw, steps = list(),
                         nonprob = isTRUE(manifest$nonprob)),
                    class = "weighting_spec")
  for (st in doc$steps) {
    params <- .wf_decode(st$params, references, st$id, allow_code = allow_code)
    if (!is.list(params)) params <- list()
    params$env <- baseenv()
    # The step's FULL class vector, not just class()[1] (IO-05). Three steps carry an
    # intermediate class that does the work: step_attrition is dispatched as
    # step_nonresponse, and step_longitudinal / step_cross_sectional are read as
    # step_scope. Dropping it made a round-tripped step_attrition() recipe die in
    # prep() with "no applicable method for 'apply_step'", and silently turned a
    # longitudinal recipe into a cross-sectional one -- same weights, guard rails off.
    # `type` is still written, so a recipe from an older version still reads.
    cls <- if (!is.null(st$classes)) unlist(st$classes) else c(st$type, "weighting_step")
    if (!"weighting_step" %in% cls) cls <- c(cls, "weighting_step")
    class(params) <- cls
    spec <- .add_step(spec, params, id = if (is.na(st$id)) NULL else st$id)
  }
  spec
}

#' @export
print.weightflow_recipe <- function(x, ...) {
  cat(sprintf("weightflow recipe (written by version %s, %s)\n",
              x$version %||% "?", x$created %||% "?"))
  cat(sprintf("  base weights: %s%s\n",
              if (is.null(x$base_weights)) "none (non-probability sample)" else x$base_weights,
              if (isTRUE(x$nonprob)) "   [non-probability]" else ""))
  cat(sprintf("  %d step(s):\n", length(x$steps)))
  for (st in x$steps)
    cat(sprintf("    - %-14s %s\n", sub("^step_", "", st$type), st$id))
  cat("  Pass `data =` to read_recipe() to rebuild an executable recipe.\n")
  invisible(x)
}
