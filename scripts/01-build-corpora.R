#!/usr/bin/env Rscript
# Build and export the shared corpora. Idempotent: skips a corpus whose
# dtm.rds already exists unless --force is passed.

suppressPackageStartupMessages({
  library(Matrix)
  library(jsonlite)
})

root <- Sys.getenv("LDA_BENCH_ROOT", unset = path.expand("~/lda-benchmarks"))
source(file.path(root, "R", "io.R"))
source(file.path(root, "R", "corpora.R"))

args <- commandArgs(trailingOnly = TRUE)
force <- "--force" %in% args
which_corpora <- setdiff(args, "--force")
if (!length(which_corpora)) which_corpora <- c("nih", "ap", "20ng")

builders <- list(
  nih   = build_nih,
  ap    = build_ap,
  `20ng` = function() build_20ng(file.path(root, "data", "20ng"))
)

for (corpus in which_corpora) {
  target <- file.path(root, "data", corpus, "dtm.rds")
  if (file.exists(target) && !force) {
    m <- jsonlite::fromJSON(file.path(root, "data", corpus, "manifest.json"))
    message(sprintf("%-5s cached: %d docs x %d terms, %d tokens",
                    corpus, m$n_docs, m$n_terms, m$n_tokens))
    next
  }
  message("building ", corpus, " ...")
  dtm <- builders[[corpus]]()
  m <- export_corpus(dtm, corpus, root = root)
  message(sprintf("%-5s built:  %d docs x %d terms, %d tokens (mean doc len %.1f)",
                  corpus, m$n_docs, m$n_terms, m$n_tokens, m$mean_doc_len))
}
