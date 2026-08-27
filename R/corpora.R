# Build the shared corpora and export them in every format the runners need.
#
# One canonical DTM per corpus (dgCMatrix, documents x terms). Everything else --
# the Matrix Market file Python reads, the vocab index, the MALLET input -- is
# derived from it, so there is exactly one source of truth for what the models
# are fit on.

suppressPackageStartupMessages({
  library(Matrix)
})

#' Prune a DTM to a stable vocabulary and drop empty documents.
#'
#' Applied identically to every corpus so that differences between corpora are
#' about size, not about preprocessing. Iterated because dropping rare terms can
#' empty a document and dropping a document can make a term rare.
prune_dtm <- function(dtm, min_df = 5, max_df_prop = 0.5, min_doc_len = 5) {
  repeat {
    df <- Matrix::colSums(dtm > 0)
    keep_terms <- df >= min_df & df <= max_df_prop * nrow(dtm)
    if (!all(keep_terms)) dtm <- dtm[, keep_terms, drop = FALSE]

    len <- Matrix::rowSums(dtm)
    keep_docs <- len >= min_doc_len
    if (!all(keep_docs)) dtm <- dtm[keep_docs, , drop = FALSE]

    if (all(keep_terms) && all(keep_docs)) break
  }
  dtm
}

as_dgc <- function(x) {
  methods::as(methods::as(methods::as(x, "dMatrix"), "generalMatrix"), "CsparseMatrix")
}

# --- corpus constructors ------------------------------------------------------

build_ap <- function() {
  e <- new.env()
  utils::data("AssociatedPress", package = "topicmodels", envir = e)
  stm <- e$AssociatedPress
  dtm <- as_dgc(Matrix::sparseMatrix(
    i = stm$i, j = stm$j, x = as.numeric(stm$v),
    dims = c(stm$nrow, stm$ncol),
    dimnames = list(paste0("ap_", seq_len(stm$nrow)), stm$dimnames[[2]])
  ))
  prune_dtm(dtm)
}

build_20ng <- function(dir) {
  raw <- file.path(dir, "raw-dtm.mtx")
  if (!file.exists(raw)) {
    stop("run scripts/00-fetch-20ng.py first (missing ", raw, ")")
  }
  dtm <- as_dgc(Matrix::readMM(raw))
  dimnames(dtm) <- list(
    readLines(file.path(dir, "raw-docids.txt")),
    readLines(file.path(dir, "raw-vocab.txt"))
  )
  # Already pruned by CountVectorizer with the same thresholds; this is a no-op
  # in the normal case and a safety net if those settings ever drift.
  prune_dtm(dtm)
}

build_nih <- function() {
  # Smoke-test corpus: 100 documents that ship with tidylda. Fast enough to run
  # the entire pipeline across all ten engines in under a minute.
  e <- new.env()
  utils::data("nih_sample_dtm", package = "tidylda", envir = e)
  prune_dtm(as_dgc(e$nih_sample_dtm), min_df = 3, max_df_prop = 0.8, min_doc_len = 5)
}

# --- export -------------------------------------------------------------------

#' Write the MALLET input file.
#'
#' MALLET does its own tokenization, so to keep its vocabulary identical to
#' everyone else's we hand it documents that are already tokenized: each term
#' repeated by its count, space separated. Paired with --token-regex '\S+' and no
#' stoplist on the import side, MALLET's vocabulary is then exactly ours.
write_mallet_input <- function(dtm, path) {
  tdtm <- Matrix::t(dtm)  # column access per document
  vocab <- rownames(tdtm)
  docs <- rownames(dtm)
  con <- file(path, "w")
  on.exit(close(con))
  p <- tdtm@p
  for (d in seq_len(ncol(tdtm))) {
    idx <- (p[d] + 1L):p[d + 1L]
    if (p[d + 1L] > p[d]) {
      toks <- rep(vocab[tdtm@i[idx] + 1L], times = as.integer(tdtm@x[idx]))
    } else {
      toks <- character(0)
    }
    writeLines(paste(docs[d], "en", paste(toks, collapse = " "), sep = "\t"), con)
  }
  invisible(path)
}

#' Write every artifact the runners consume for one corpus.
export_corpus <- function(dtm, corpus, root = bench_root()) {
  dir <- file.path(root, "data", corpus)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)

  saveRDS(dtm, file.path(dir, "dtm.rds"))
  Matrix::writeMM(dtm, file.path(dir, "dtm.mtx"))
  writeLines(colnames(dtm), file.path(dir, "vocab.txt"))
  writeLines(rownames(dtm), file.path(dir, "docids.txt"))
  write_mallet_input(dtm, file.path(dir, "mallet.txt"))

  manifest <- list(
    corpus     = corpus,
    n_docs     = nrow(dtm),
    n_terms    = ncol(dtm),
    n_tokens   = sum(dtm),
    nnz        = length(dtm@x),
    mean_doc_len = mean(Matrix::rowSums(dtm)),
    built_at   = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
  writeLines(
    jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
    file.path(dir, "manifest.json")
  )
  manifest
}
