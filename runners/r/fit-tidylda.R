#!/usr/bin/env Rscript
# tidylda -- WarpLDA / Metropolis-Hastings, RcppThread parallel.
source(file.path(Sys.getenv("LDA_BENCH_ROOT", path.expand("~/lda-benchmarks")),
                 "runners", "r", "common.R"))
suppressPackageStartupMessages(library(tidylda))

fit <- function(dtm, k, iters, threads, seed, timer) {
  m <- tidylda::tidylda(
    data            = dtm,
    k               = k,
    iterations      = iters,
    burnin          = -1,      # no post-burnin averaging: report the raw sampler
    alpha           = ALPHA,
    eta             = ETA,
    calc_likelihood = FALSE,   # scored separately; keep the timed call to sampling
    calc_r2         = FALSE,
    threads         = threads,
    return_data     = FALSE,
    verbose         = FALSE
  )
  timer$stop()  # phi/theta come straight off the fitted object
  list(phi = m$beta, theta = m$theta,
       version = as.character(utils::packageVersion("tidylda")))
}

run_runner("tidylda")
