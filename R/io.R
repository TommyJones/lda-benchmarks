# Cross-language matrix interchange and small path helpers.
#
# Matrix Market is the interchange format: scipy.io.mmwrite on the Python side,
# Matrix::readMM here. No reticulate, no extra dependency on either side.

suppressPackageStartupMessages({
  library(Matrix)
})

bench_root <- function() {
  r <- Sys.getenv("LDA_BENCH_ROOT", unset = NA)
  if (!is.na(r) && nzchar(r)) return(r)
  path.expand("~/lda-benchmarks")
}

corpus_dir <- function(corpus) file.path(bench_root(), "data", corpus)

#' Read a corpus's canonical DTM (documents x terms, dgCMatrix with dimnames).
read_dtm <- function(corpus) {
  f <- file.path(corpus_dir(corpus), "dtm.rds")
  if (!file.exists(f)) {
    stop("corpus not built: ", corpus, " (missing ", f, ")\n",
         "run scripts/01-build-corpora.R first")
  }
  readRDS(f)
}

read_vocab <- function(corpus) {
  readLines(file.path(corpus_dir(corpus), "vocab.txt"))
}

#' Write a dense numeric matrix as Matrix Market. Python reads it with
#' scipy.io.mmread; we use it for phi/theta handoff in both directions.
write_matrix_mm <- function(x, path) {
  Matrix::writeMM(methods::as(Matrix::Matrix(as.matrix(x), sparse = TRUE), "dgCMatrix"), path)
  invisible(path)
}

read_matrix_mm <- function(path) {
  as.matrix(Matrix::readMM(path))
}

#' Row-normalize to a proper probability distribution, tolerating all-zero rows.
#'
#' Every engine hands back parameters in a slightly different state -- raw
#' counts (lda), unnormalized weights (MALLET), already-normalized (tidylda) --
#' so scoring normalizes everything before comparing. An all-zero row (a topic
#' no token was ever assigned to) becomes uniform rather than NaN.
normalize_rows <- function(x) {
  x <- as.matrix(x)
  s <- rowSums(x)
  bad <- !is.finite(s) | s <= 0
  if (any(bad)) {
    x[bad, ] <- 1 / ncol(x)
    s[bad] <- 1
  }
  x / s
}

#' Write the run's fitted parameters plus its timing record.
#'
#' Contract shared by every runner in runners/: phi is k x V with columns in the
#' corpus's canonical vocab order, theta is D x k with rows in corpus doc order.
write_fit <- function(out_dir, phi, theta, meta) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  write_matrix_mm(phi, file.path(out_dir, "phi.mtx"))
  write_matrix_mm(theta, file.path(out_dir, "theta.mtx"))
  # fit.json is written last: the driver treats its presence as "run complete"
  # so an interrupted grid resumes cleanly.
  writeLines(
    jsonlite::toJSON(meta, auto_unbox = TRUE, digits = 10, pretty = TRUE),
    file.path(out_dir, "fit.json")
  )
  invisible(out_dir)
}
