#!/usr/bin/env Rscript
# textmineR -- collapsed Gibbs, single threaded. tidylda's predecessor.
#
# FitLdaModel() in textmineR 3.0.6 has no threading argument at all: its formals
# are (dtm, k, iterations, burnin, alpha, beta, optimize_alpha, calc_likelihood,
# calc_coherence, calc_r2, ...). An earlier version of this runner passed
# `cpus = threads`, which `...` swallowed silently -- the measured 1.00x speedup
# across the thread sweep is textmineR genuinely not threading, not a mistake in
# how we called it. `threads` is accepted here and deliberately unused.
source(file.path(Sys.getenv("LDA_BENCH_ROOT", path.expand("~/lda-benchmarks")),
                 "runners", "r", "common.R"))
suppressPackageStartupMessages(library(textmineR))

fit <- function(dtm, k, iters, threads, seed, timer) {
  m <- textmineR::FitLdaModel(
    dtm             = dtm,
    k               = k,
    iterations      = iters,
    burnin          = -1,
    alpha           = ALPHA,
    beta            = ETA,
    optimize_alpha  = FALSE,
    calc_likelihood = FALSE,
    calc_coherence  = FALSE,
    calc_r2         = FALSE
  )
  timer$stop()
  list(phi = m$phi, theta = m$theta,
       version = as.character(utils::packageVersion("textmineR")))
}

run_runner("textmineR")
