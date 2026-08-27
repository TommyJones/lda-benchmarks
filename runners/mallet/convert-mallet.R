#!/usr/bin/env Rscript
# Convert MALLET's text output into the phi.mtx / theta.mtx / fit.json contract.
#
# Two alignment jobs:
#   1. topic-word-weights are keyed by token string in MALLET's own vocabulary
#      order, so we reindex onto the corpus's canonical vocab by name. A term
#      MALLET never emitted stays at zero and is renormalized away.
#   2. doc-topics rows are keyed by the document name we wrote into mallet.txt,
#      so we reorder them back into corpus document order rather than trusting
#      MALLET to have preserved it.

suppressPackageStartupMessages({
  library(Matrix)
  library(jsonlite)
})

BENCH_ROOT <- Sys.getenv("LDA_BENCH_ROOT", unset = path.expand("~/lda-benchmarks"))
source(file.path(BENCH_ROOT, "R", "io.R"))

a <- commandArgs(trailingOnly = TRUE)
arg <- function(flag, as = identity) as(a[match(flag, a) + 1L])

corpus  <- arg("--corpus")
k       <- arg("--k", as.integer)
iters   <- arg("--iters", as.integer)
threads <- arg("--threads", as.integer)
seed    <- arg("--seed", as.integer)
out     <- arg("--out")
fit_sec <- arg("--fit-sec", as.numeric)

dtm <- read_dtm(corpus)
vocab <- colnames(dtm)
docids <- rownames(dtm)

# --- phi ----------------------------------------------------------------------
# topic-word-weights-file: "<topic>\t<token>\t<weight>", weights are
# count + beta, so normalizing the rows gives P(token | topic).
tw <- utils::read.delim(file.path(out, "topic-word-weights.txt"),
                        header = FALSE, quote = "", stringsAsFactors = FALSE,
                        col.names = c("topic", "token", "weight"))
col <- match(tw$token, vocab)
keep <- !is.na(col)
if (!all(keep)) {
  message("dropping ", sum(!keep), " MALLET tokens absent from canonical vocab")
}
phi <- matrix(0, nrow = k, ncol = length(vocab),
              dimnames = list(NULL, vocab))
phi[cbind(tw$topic[keep] + 1L, col[keep])] <- tw$weight[keep]
phi <- normalize_rows(phi)

# --- theta --------------------------------------------------------------------
# output-doc-topics (MALLET 2.0.8+): "<index>\t<name>\t<p_0>\t<p_1>..."
dt <- utils::read.delim(file.path(out, "doc-topics.txt"),
                        header = FALSE, quote = "", stringsAsFactors = FALSE,
                        comment.char = "#")
theta_raw <- as.matrix(dt[, 3:(2 + k), drop = FALSE])
rownames(theta_raw) <- as.character(dt[[2]])
stopifnot("MALLET doc-topics does not cover every document" =
            all(docids %in% rownames(theta_raw)))
theta <- normalize_rows(theta_raw[docids, , drop = FALSE])

mallet_version <- tryCatch(
  sub("^v", "", basename(Sys.getenv("MALLET_HOME"))), error = function(e) NA
)

write_fit(out, phi, theta, list(
  engine   = "mallet",
  language = "Java",
  corpus   = corpus,
  k        = k,
  iters    = iters,
  threads  = threads,
  seed     = seed,
  alpha    = 0.1,
  eta      = 0.05,
  fit_sec  = fit_sec,
  version  = "202108"
))
