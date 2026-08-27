#!/usr/bin/env Rscript
# textmineR -- collapsed Gibbs, RcppParallel. tidylda's predecessor.
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
    calc_r2         = FALSE,
    cpus            = threads
  )
  timer$stop()
  list(phi = m$phi, theta = m$theta,
       version = as.character(utils::packageVersion("textmineR")))
}

run_runner("textmineR")
