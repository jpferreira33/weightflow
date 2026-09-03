# Balanced integer rounding by the cube method (Deville & Tille 2004).
#
# Native implementation (no external sampling package). Rounds weights to a grid
# while keeping the calibrated totals -- not just the grand total -- as close as
# possible: each weight goes to its floor or its ceiling, and the choice of which
# ones go up is made by balanced sampling on the calibration variables, so the
# rounded weights reproduce every requested total up to the unavoidable
# integer-grid residual (at most one constraint's worth per balancing variable).
#
# Reference: CEPAL/ECLAC, "Metodologia ... encuestas de hogares", chapter 9,
# section F.2 (balanced rounding); Deville J-C, Tille Y (2004), "Efficient
# balanced sampling: the cube method", Biometrika 91(4):893-912. The fast flight
# phase follows Chauvet & Tille (2006) so the cost stays linear in the number of
# units (usable at census scale).

# Left null vector: u (length m) with t(B) %*% u = 0, for B an m x q matrix, m>q.
.wf_null_vec <- function(B) {
  sv  <- svd(B, nu = nrow(B), nv = 0)
  d   <- sv$d
  tol <- max(dim(B)) * .Machine$double.eps * (if (length(d)) d[1] else 1)
  r   <- sum(d > tol)
  if (r >= nrow(B)) return(NULL)          # full row rank: null space empty
  sv$u[, r + 1L]
}

# Fast flight phase: move the inclusion probabilities `pik` (the fractional parts)
# within a rolling window of q+1 units, along a direction that leaves
# sum_i pik_i * A_i unchanged, until each moved unit hits 0 or 1. Preserves the
# balancing totals exactly; leaves at most q units still fractional.
.wf_fast_flight <- function(pik, A, eps = 1e-9) {
  q    <- ncol(A); win <- q + 1L
  pool <- which(pik > eps & pik < 1 - eps)
  ptr  <- 0L
  refill <- function(cur) {
    while (ptr < length(pool) && length(cur) < win) {
      ptr <<- ptr + 1L; j <- pool[ptr]
      if (pik[j] > eps && pik[j] < 1 - eps) cur <- c(cur, j)
    }
    cur
  }
  cur <- refill(integer(0))
  repeat {
    cur <- cur[pik[cur] > eps & pik[cur] < 1 - eps]
    cur <- refill(cur)
    if (length(cur) < 2L) break
    u <- .wf_null_vec(A[cur, , drop = FALSE])
    if (is.null(u)) break
    p   <- pik[cur]
    l1  <- Inf; l2 <- Inf
    pos <- u >  eps; neg <- u < -eps
    if (any(pos)) { l1 <- min(l1, (1 - p[pos]) / u[pos]); l2 <- min(l2, p[pos] / u[pos]) }
    if (any(neg)) { l1 <- min(l1, -p[neg] / u[neg]);      l2 <- min(l2, (p[neg] - 1) / u[neg]) }
    if (!is.finite(l1) || !is.finite(l2) || (l1 + l2) <= 0) break
    pik[cur] <- pmin(pmax(
      if (stats::runif(1) < l2 / (l1 + l2)) p + l1 * u else p - l2 * u, 0), 1)
  }
  pik
}

# Landing phase by suppression of variables: for the units the flight phase left
# fractional (at most q), drop balancing constraints one at a time and keep
# flying; settle the last unit(s) by a Bernoulli draw. The residual imbalance is
# bounded by the number of dropped constraints.
.wf_landing <- function(pik, A, eps = 1e-9) {
  repeat {
    idx <- which(pik > eps & pik < 1 - eps)
    if (!length(idx)) break
    qp <- min(ncol(A), length(idx) - 1L)
    if (qp <= 0L) { pik[idx] <- as.numeric(stats::runif(length(idx)) < pik[idx]); break }
    before <- length(idx)
    pik    <- .wf_fast_flight(pik, A[, seq_len(qp), drop = FALSE], eps)
    idx2   <- which(pik > eps & pik < 1 - eps)
    if (length(idx2) >= before) { i <- idx2[1]; pik[i] <- as.numeric(stats::runif(1) < pik[i]) }
  }
  round(pik)
}

# Round `w` to `digits` decimals so that, on the rounding grid, the totals of the
# balancing variables `Z` (n x q, e.g. model.matrix(~ dam + estrato)) are
# preserved as closely as the integer grid allows. Every weight lands on its
# floor or its ceiling. Randomized (set a seed upstream for reproducibility).
.wf_balanced_round <- function(w, Z, digits = 0L) {
  f   <- 10^as.integer(digits)
  x   <- w * f
  fl  <- floor(x)
  pik <- x - fl                                   # fractional parts = inclusion probs
  Z   <- as.matrix(Z)
  storage.mode(Z) <- "double"
  pik <- .wf_fast_flight(pik, Z)
  S   <- .wf_landing(pik, Z)
  (fl + S) / f
}
