#!/usr/bin/env Rscript
# topicmodels, VEM -- Blei's original variational EM. Single threaded.
#
# "iterations" here means EM iterations, which are far more expensive than a
# Gibbs sweep. That mismatch is exactly why the headline chart is quality
# against wall-clock time rather than against iteration count.
source(file.path(Sys.getenv("LDA_BENCH_ROOT", path.expand("~/lda-benchmarks")),
                 "runners", "r", "common.R"))
suppressPackageStartupMessages({
  library(topicmodels)
  library(slam)
})

fit <- function(dtm, k, iters, threads, seed, timer) {
  stm <- slam::as.simple_triplet_matrix(dtm)
  m <- topicmodels::LDA(
    stm, k = k, method = "VEM",
    control = list(
      alpha          = ALPHA,
      estimate.alpha = FALSE,  # no hyperparameter optimization, as everywhere
      estimate.beta  = TRUE,
      seed           = seed,
      verbose        = 0,
      # tol = -1 defeats early stopping so the run actually executes the number
      # of EM iterations the ladder asked for.
      em  = list(iter.max = iters, tol = -1),
      var = list(iter.max = 20, tol = 1e-6)
    )
  )
  timer$stop()  # posterior() is extraction, not training
  post <- topicmodels::posterior(m)
  list(phi = post$terms, theta = post$topics,
       version = as.character(utils::packageVersion("topicmodels")))
}

run_runner("topicmodels-vem")
