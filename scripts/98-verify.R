#!/usr/bin/env Rscript
# Checks that the measurement apparatus itself is sound. Run once after setup;
# it is fast (AP, small k) and it is what stands behind the claims in the README.
#
#   1. Our scoring reproduces tidylda's own native coherence and R^2 numbers.
#      If it does not, the phi/theta handoff is lying somewhere.
#   2. tidylda really is invariant to `threads`, as documented. That is what
#      makes the thread sweep a pure wall-clock axis for tidylda -- and it is
#      the contrast with MALLET's and tomotopy's approximate parallel samplers.

suppressPackageStartupMessages({
  library(Matrix)
  library(tidylda)
})

root <- Sys.getenv("LDA_BENCH_ROOT", unset = path.expand("~/lda-benchmarks"))
source(file.path(root, "R", "io.R"))
source(file.path(root, "R", "metrics.R"))

dtm <- read_dtm("ap")
k <- 20L
iters <- 100L

cat("== 1. scoring agrees with tidylda's native metrics ==\n")
m <- tidylda::tidylda(data = dtm, k = k, iterations = iters, burnin = -1,
                      alpha = 0.1, eta = 0.05, calc_likelihood = FALSE,
                      calc_r2 = TRUE, threads = 1, verbose = FALSE)

ours <- score_fit(m$beta, m$theta, dtm, m = 5, threads = 4)
native_coh <- mean(m$summary$coherence, na.rm = TRUE)

cat(sprintf("  R^2       native %.6f | ours %.6f | diff %.2e\n",
            m$r2, ours$r2, abs(m$r2 - ours$r2)))
cat(sprintf("  coherence native %.6f | ours %.6f | diff %.2e\n",
            native_coh, ours$coherence_mean, abs(native_coh - ours$coherence_mean)))
stopifnot(abs(m$r2 - ours$r2) < 1e-8,
          abs(native_coh - ours$coherence_mean) < 1e-8)
cat("  OK\n\n")

cat("== 2. tidylda is invariant to thread count ==\n")
fit_at <- function(threads) {
  set.seed(42)
  tidylda::tidylda(data = dtm, k = k, iterations = iters, burnin = -1,
                   alpha = 0.1, eta = 0.05, calc_likelihood = FALSE,
                   calc_r2 = FALSE, threads = threads, verbose = FALSE)
}
a <- fit_at(1L)
b <- fit_at(20L)
d_beta  <- max(abs(a$beta - b$beta))
d_theta <- max(abs(a$theta - b$theta))
cat(sprintf("  max |beta_1 - beta_20|   = %.3e\n", d_beta))
cat(sprintf("  max |theta_1 - theta_20| = %.3e\n", d_theta))
if (d_beta == 0 && d_theta == 0) {
  cat("  OK -- bit-identical\n")
} else {
  cat("  NOTE: not bit-identical; the thread sweep must report quality as well\n",
      "  as speed for tidylda too. Recorded rather than asserted.\n")
}
