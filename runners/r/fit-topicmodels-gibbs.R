#!/usr/bin/env Rscript
# topicmodels, Gibbs -- the C implementation of Phan et al.'s GibbsLDA++.
# Single threaded by construction.
source(file.path(Sys.getenv("LDA_BENCH_ROOT", path.expand("~/lda-benchmarks")),
                 "runners", "r", "common.R"))
suppressPackageStartupMessages({
  library(topicmodels)
  library(slam)
})

fit <- function(dtm, k, iters, threads, seed, timer) {
  stm <- slam::as.simple_triplet_matrix(dtm)
  m <- topicmodels::LDA(
    stm, k = k, method = "Gibbs",
    control = list(
      alpha  = ALPHA,
      delta  = ETA,     # topicmodels calls the word prior delta
      iter   = iters,
      burnin = 0,       # burn-in is folded into the iteration ladder
      thin   = 1,
      best   = TRUE,
      seed   = seed,
      verbose = 0
    )
  )
  timer$stop()  # posterior() is extraction, not training
  post <- topicmodels::posterior(m)
  list(phi = post$terms, theta = post$topics,
       version = as.character(utils::packageVersion("topicmodels")))
}

run_runner("topicmodels-gibbs")
