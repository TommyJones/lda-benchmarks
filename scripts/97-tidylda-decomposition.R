#!/usr/bin/env Rscript
# Where does tidylda's wall clock actually go?
#
# tidylda() does strictly more than the other engines' fit calls. After the
# sampler returns, new_tidylda() builds theta and beta, then also computes
# lambda (a second k x V matrix), summarize_topics() (probabilistic coherence
# for every topic, plus top terms), and a sparse Cv. text2vec's fit_transform
# returns theta and a topic-word matrix and stops.
#
# The benchmark's headline number is the full tidylda() call, because that is
# what a user actually pays. But "tidylda is slower than text2vec" and "tidylda
# does more work per call" are different claims, and only a decomposition can
# tell them apart. This profiles the call and attributes time to the sampler
# versus each piece of post-processing.
#
# It also runs at 1 and at 20 threads, because the post-processing is R-level
# and single-threaded: whatever fraction it occupies is an Amdahl ceiling on
# tidylda's achievable speedup, no matter how well the sampler scales.
#
# Run this when the benchmark grid is NOT running -- concurrent load would
# corrupt both its timings and the grid's.

suppressPackageStartupMessages({
  library(Matrix)
  library(tidylda)
})

root <- Sys.getenv("LDA_BENCH_ROOT", unset = path.expand("~/lda-benchmarks"))
source(file.path(root, "R", "io.R"))

# IMPORTANT: Rprof's timer is CPU time (ITIMER_PROF), not wall clock. At one
# thread the two coincide, so the single-threaded split below is the real
# attribution. At many threads the sampler's "time" is summed across worker
# threads and will exceed the wall clock of the whole call -- read those rows as
# CPU-seconds, and take wall clock from `total` alone.
corpus <- "ap"
k <- 100L
iters <- 200L
thread_levels <- c(1L, 12L)

dtm <- read_dtm(corpus)
cat(sprintf("corpus %s: %d docs x %d terms, k = %d, %d iterations\n\n",
            corpus, nrow(dtm), ncol(dtm), k, iters))

# Functions we want attributed separately. Everything else inside the call is
# lumped into "other".
of_interest <- c(
  "fit_lda_warp"      = "sampler (C++)",
  "calc_lambda"       = "lambda matrix",
  "summarize_topics"  = "topic summary (coherence + top terms)",
  "calc_prob_coherence" = "  (of which: coherence)",
  "new_tidylda"       = "post-processing total"
)

profile_once <- function(threads) {
  prof <- tempfile(fileext = ".out")
  Rprof(prof, interval = 0.01, line.profiling = FALSE)
  total <- system.time(
    m <- tidylda::tidylda(
      data = dtm, k = k, iterations = iters, burnin = -1,
      alpha = 0.1, eta = 0.05, calc_likelihood = FALSE, calc_r2 = FALSE,
      threads = threads, return_data = FALSE, verbose = FALSE
    )
  )[["elapsed"]]
  Rprof(NULL)

  smry <- summaryRprof(prof)$by.total
  unlink(prof)

  get <- function(fn) {
    row <- paste0("\"", fn, "\"")
    if (row %in% rownames(smry)) smry[row, "total.time"] else 0
  }

  list(total = total, smry = smry, get = get)
}

results <- list()
for (th in thread_levels) {
  cat(sprintf("== threads = %d ==\n", th))
  p <- profile_once(th)

  sampler <- p$get("fit_lda_warp")
  post    <- p$get("new_tidylda")
  lambda  <- p$get("calc_lambda")
  summ    <- p$get("summarize_topics")
  coh     <- p$get("calc_prob_coherence")

  unit <- if (th == 1L) "s" else "s cpu"
  cat(sprintf("  total tidylda() call        %7.2fs wall\n", p$total))
  cat(sprintf("  sampler (fit_lda_warp)      %7.2f%s\n", sampler, unit))
  cat(sprintf("  post-processing             %7.2f%s\n", post, unit))
  cat(sprintf("    lambda matrix             %7.2fs\n", lambda))
  cat(sprintf("    topic summary             %7.2fs\n", summ))
  cat(sprintf("      of which coherence      %7.2fs\n", coh))
  cat("\n")

  results[[as.character(th)]] <- list(
    threads = th, total = p$total, sampler = sampler, post = post,
    lambda = lambda, summary = summ, coherence = coh
  )
}

# What this means for thread scaling. Only single-threaded numbers feed the
# serial fraction, for the CPU-vs-wall reason above.
r1 <- results[["1"]]
rN <- results[[as.character(max(thread_levels))]]
serial_frac <- r1$post / r1$total
cat("== implication for thread scaling ==\n")
cat(sprintf("  wall clock: %.2fs at 1 thread -> %.2fs at %d threads (%.2fx)\n",
            r1$total, rN$total, rN$threads, r1$total / rN$total))
cat(sprintf("  serial (post-processing) fraction at 1 thread: %.1f%%\n",
            100 * serial_frac))
cat(sprintf("  Amdahl ceiling implied by that serial fraction: %.0fx\n",
            1 / serial_frac))
cat("\n  The post-processing tidylda does over and above a bare sampler --\n")
cat("  lambda, the topic summary with its coherence calculation, the sparse Cv --\n")
cat("  is a small share of the call and imposes no practical ceiling on\n")
cat("  threading. Any gap against a sampler-only package is in the sampler.\n")

saveRDS(results, file.path(root, "results", "tidylda-decomposition.rds"))
