# ===========================================================================
# weightflow DEMO — new steps:
#   - bounded calibration (calfun = "logit" / bounds)
#   - step_assert        (quality checkpoint)
#   - step_trim_weights  (automatic, survey-style: floor 1, auto cap, strict)
#   - step_rescale       (normalize to n or to a total)
#
#   setwd("path/to/weightflow"); source("demo_new_steps.R")
# ===========================================================================

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

# --- Data: unequal design weights + differential nonresponse ----------------
# This creates weight spread, so bounds / trimming actually bite.
set.seed(13)
n      <- 1500
region <- sample(c("A", "B", "C"), n, replace = TRUE, prob = c(.5, .3, .2))
sex    <- sample(c("M", "F"), n, replace = TRUE)
pw     <- c(A = 10, B = 40, C = 120)[region] * runif(n, .8, 1.2)   # very unequal
income <- round(rlnorm(n, 9, .6))
p_resp <- c(A = .85, B = .70, C = .50)[region]                     # lower in C
responded <- rbinom(n, 1, p_resp)                                  # 0/1 dummy
dat <- data.frame(region, sex, pw, income, responded, stringsAsFactors = FALSE)

N <- sum(dat$pw)
# Stressed targets: push the income total +15% so the GREG g-weights spread out.
totals <- c("(Intercept)" = N,
            sexM          = round(N * 0.49),
            income        = round(1.15 * sum(dat$pw * dat$income)))

# Helper: range of the LAST step's per-unit factor (here, the calibration g)
g_range <- function(fitted) {
  wf  <- weight_factors(fitted)
  col <- utils::tail(grep("^factor_", names(wf), value = TRUE), 1)
  v   <- wf[[col]][is.finite(wf[[col]]) & wf[[col]] > 0]
  range(v)
}

# ===========================================================================
# 1. BOUNDED CALIBRATION: unbounded vs logit-bounded g-weights
# ===========================================================================
base_recipe <- weighting_spec(dat, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region")

# (a) Unbounded linear / GREG
f_unb <- prep(base_recipe |>
  step_calibrate(method = "linear", formula = ~ sex + income, totals = totals))

# (b) Logit-bounded: g forced into [0.7, 1.5]
f_bnd <- prep(base_recipe |>
  step_calibrate(method = "linear", formula = ~ sex + income, totals = totals,
                 calfun = "logit", bounds = c(0.7, 1.5)))

cat("\n=== 1. Bounded calibration ===\n")
cat(sprintf("Unbounded g range : [%.3f, %.3f]\n", g_range(f_unb)[1], g_range(f_unb)[2]))
cat(sprintf("Logit  g range    : [%.3f, %.3f]  (target bounds 0.70-1.50)\n",
            g_range(f_bnd)[1], g_range(f_bnd)[2]))
cat("Both still hit the totals (consistency); the bounded one avoids extreme g.\n")

# ===========================================================================
# 2. step_assert: quality checkpoint after calibration
# ===========================================================================
cat("\n=== 2. step_assert ===\n")

# (a) Warning mode: reports if a threshold is crossed but continues
f_chk <- prep(base_recipe |>
  step_calibrate(method = "linear", formula = ~ sex + income, totals = totals,
                 calfun = "logit", bounds = c(0.7, 1.5)) |>
  step_assert(max_deff = 2, max_weight_ratio = 6, min_n_eff = 700,
              on_fail = "warning"))
cat("Checkpoint diagnostics:\n")
print(f_chk$steps[[length(f_chk$steps)]]$diagnostics, row.names = FALSE)

# (b) Error mode: a deliberately tight threshold stops the cascade
res <- tryCatch(
  prep(base_recipe |>
    step_calibrate(method = "linear", formula = ~ sex + income, totals = totals) |>
    step_assert(max_deff = 1.05, on_fail = "error")),
  error = function(e) conditionMessage(e))
cat("Error-mode assert caught:", res, "\n")

# ===========================================================================
# 3. step_trim_weights: automatic, survey-style
# ===========================================================================
cat("\n=== 3. step_trim_weights (auto) ===\n")
f_trim <- prep(base_recipe |>
  step_trim_weights(lower = 1, upper = NULL, strict = TRUE))   # auto Tukey cap
wt0 <- collect_weights(prep(base_recipe))$.weight              # before trimming
wt1 <- collect_weights(f_trim)$.weight                         # after trimming
cat(sprintf("Before: min %.2f  max %.1f  sum %.0f\n", min(wt0), max(wt0), sum(wt0)))
cat(sprintf("After : min %.2f  max %.1f  sum %.0f\n", min(wt1), max(wt1), sum(wt1)))
print(f_trim$steps[[length(f_trim$steps)]]$diagnostics, row.names = FALSE)
cat("No weight below 1; the upper cap is set automatically (Q3 + 3*IQR);\n")
cat("the total is preserved by redistribution (strict = TRUE).\n")

# ===========================================================================
# 4. step_rescale: normalize the weights
# ===========================================================================
cat("\n=== 4. step_rescale ===\n")
f_n <- prep(base_recipe |> step_rescale(to = "n"))
f_t <- prep(base_recipe |> step_rescale(to = "total", total = 100000))
w_n <- collect_weights(f_n)$.weight
w_t <- collect_weights(f_t)$.weight
cat(sprintf("to = 'n'     : sum %.1f  (active units = %d, mean weight %.3f)\n",
            sum(w_n), length(w_n), mean(w_n)))
cat(sprintf("to = 'total' : sum %.1f  (target 100000)\n", sum(w_t)))
cat("Note: rescaling to n breaks the population totals on purpose -- use it only\n")
cat("when downstream software expects normalized weights.\n")

# ===========================================================================
# 5. Putting it together (sensible order) + diagnostics
# ===========================================================================
cat("\n=== 5. Full pipeline with the new steps ===\n")
full <- weighting_spec(dat, base_weights = pw) |>
  step_nonresponse(respondent = responded, method = "weighting_class", by = "region") |>
  step_calibrate(method = "linear", formula = ~ sex + income, totals = totals,
                 calfun = "logit", bounds = c(0.5, 2.5)) |>   # bounded -> no extremes
  step_assert(max_weight_ratio = 20, on_fail = "warning")     # guard, after calibrating
fitted <- prep(full)
summary(fitted)
plot(fitted)
