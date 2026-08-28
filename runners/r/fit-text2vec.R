#!/usr/bin/env Rscript
# text2vec -- WarpLDA via RcppParallel. The closest algorithmic comparator to
# tidylda, which is why it is worth reading their two curves side by side.
source(file.path(Sys.getenv("LDA_BENCH_ROOT", path.expand("~/lda-benchmarks")),
                 "runners", "r", "common.R"))
suppressPackageStartupMessages(library(text2vec))

fit <- function(dtm, k, iters, threads, seed, timer) {
  # text2vec's WarpLDA is SINGLE THREADED. src/mcemlda/LDA.hpp has plain serial
  # loops in sample_by_doc/sample_by_word with no OpenMP pragmas anywhere, and
  # src/Makevars does not link OpenMP at all. The measured 1.00x across the
  # thread sweep is real. These options are set anyway so that if a future
  # version does parallelize, the runner caps it rather than silently using
  # every core.
  options(rsparse_omp_threads = threads, text2vec.mc.cores = threads)
  Sys.setenv(OMP_NUM_THREADS = threads)
  lda <- text2vec::LDA$new(
    n_topics         = k,
    doc_topic_prior  = ALPHA,
    topic_word_prior = ETA
  )
  theta <- lda$fit_transform(
    x                   = dtm,
    n_iter              = iters,
    # Defeat early stopping so a run does the iterations the ladder specifies.
    convergence_tol     = -1,
    n_check_convergence = iters,
    progressbar         = FALSE
  )
  timer$stop()  # fit_transform returns theta directly
  list(phi = lda$topic_word_distribution, theta = theta,
       version = as.character(utils::packageVersion("text2vec")))
}

run_runner("text2vec")
