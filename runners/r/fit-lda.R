#!/usr/bin/env Rscript
# Chang's `lda` -- collapsed Gibbs in C, single threaded.
#
# Two wrinkles this runner absorbs: its input is a list of 2-row integer
# matrices rather than a sparse matrix, and it returns raw assignment counts
# rather than distributions, so we add the priors back and normalize.
source(file.path(Sys.getenv("LDA_BENCH_ROOT", path.expand("~/lda-benchmarks")),
                 "runners", "r", "common.R"))
suppressPackageStartupMessages(library(lda))

#' dgCMatrix -> lda's documents format: one 2 x n_terms integer matrix per
#' document, row 1 = zero-based term index, row 2 = count. Term indices are
#' column positions in the shared DTM, so the vocabulary alignment is free.
as_lda_documents <- function(dtm) {
  tdtm <- Matrix::t(dtm)
  p <- tdtm@p
  lapply(seq_len(ncol(tdtm)), function(d) {
    if (p[d + 1L] == p[d]) {
      return(matrix(integer(0), nrow = 2L))
    }
    idx <- (p[d] + 1L):p[d + 1L]
    m <- rbind(as.integer(tdtm@i[idx]), as.integer(tdtm@x[idx]))
    storage.mode(m) <- "integer"
    m
  })
}

fit <- function(dtm, k, iters, threads, seed, timer) {
  docs <- as_lda_documents(dtm)
  f <- lda::lda.collapsed.gibbs.sampler(
    documents      = docs,
    K              = k,
    vocab          = colnames(dtm),
    num.iterations = iters,
    alpha          = ALPHA,
    eta            = ETA,
    compute.log.likelihood = FALSE
  )
  timer$stop()
  # $topics is k x V counts; $document_sums is k x D counts.
  list(
    phi     = normalize_rows(f$topics + ETA),
    theta   = normalize_rows(t(f$document_sums) + ALPHA),
    version = as.character(utils::packageVersion("lda"))
  )
}

run_runner("lda")
