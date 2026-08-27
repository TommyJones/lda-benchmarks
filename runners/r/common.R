# Shared scaffolding for the R runners.
#
# Every runner is a standalone script invoked in its own process:
#
#   Rscript runners/r/fit-tidylda.R --corpus ap --k 100 --iters 200 \
#           --threads 1 --seed 1 --out results/raw/<run-id>
#
# It must define fit(dtm, k, iters, threads, seed, timer) returning
# list(phi = <k x V>, theta = <D x k>) with phi's columns in the corpus's
# canonical vocabulary order, then call run_runner(). Nothing else.
#
# `timer` marks the end of the timed region: call timer$stop() as soon as
# training finishes. The timed region runs from "here is the shared DTM" to
# "training is complete". Reshaping the DTM into whatever form the package wants
# is inside it -- that is a real cost of using the package. Extracting phi and
# theta afterwards is outside it, because for some engines (gensim especially)
# that is an extra inference pass that only our measurement protocol asks for.

suppressPackageStartupMessages({
  library(Matrix)
  library(jsonlite)
})

BENCH_ROOT <- Sys.getenv("LDA_BENCH_ROOT", unset = path.expand("~/lda-benchmarks"))
source(file.path(BENCH_ROOT, "R", "io.R"))

# Hyperparameters held fixed across every engine. alpha is per-topic; eta is the
# per-term prior on topic-word distributions. No hyperparameter optimization
# anywhere -- each engine's optimizer is explicitly disabled in its runner.
ALPHA <- 0.1
ETA   <- 0.05

parse_args <- function() {
  a <- commandArgs(trailingOnly = TRUE)
  get <- function(flag, default = NULL, as = identity) {
    i <- match(flag, a)
    if (is.na(i)) {
      if (is.null(default)) stop("missing required argument: ", flag)
      return(default)
    }
    as(a[i + 1L])
  }
  list(
    corpus  = get("--corpus"),
    k       = get("--k", as = as.integer),
    iters   = get("--iters", as = as.integer),
    threads = get("--threads", 1L, as.integer),
    seed    = get("--seed", 1L, as.integer),
    out     = get("--out")
  )
}

#' Convert a dgCMatrix DTM to a list of documents, each a character vector of
#' tokens repeated by count. text2vec and a couple of others want token streams
#' rather than a matrix.
dtm_to_tokens <- function(dtm) {
  tdtm <- Matrix::t(dtm)
  vocab <- rownames(tdtm)
  p <- tdtm@p
  lapply(seq_len(ncol(tdtm)), function(d) {
    if (p[d + 1L] == p[d]) return(character(0))
    idx <- (p[d] + 1L):p[d + 1L]
    rep(vocab[tdtm@i[idx] + 1L], times = as.integer(tdtm@x[idx]))
  })
}

new_timer <- function() {
  e <- new.env(parent = emptyenv())
  e$t0 <- proc.time()[["elapsed"]]
  e$elapsed <- NA_real_
  e$stop <- function() {
    if (is.na(e$elapsed)) e$elapsed <- proc.time()[["elapsed"]] - e$t0
    e$elapsed
  }
  e
}

run_runner <- function(engine) {
  args <- parse_args()
  set.seed(args$seed)

  dtm <- read_dtm(args$corpus)

  timer <- new_timer()
  res <- fit(dtm, k = args$k, iters = args$iters,
             threads = args$threads, seed = args$seed, timer = timer)
  fit_sec <- timer$stop()

  phi <- as.matrix(res$phi)
  theta <- as.matrix(res$theta)
  stopifnot(ncol(phi) == ncol(dtm), nrow(theta) == nrow(dtm),
            nrow(phi) == ncol(theta))

  meta <- c(
    list(
      engine   = engine,
      language = "R",
      corpus   = args$corpus,
      k        = args$k,
      iters    = args$iters,
      threads  = args$threads,
      seed     = args$seed,
      alpha    = ALPHA,
      eta      = ETA,
      fit_sec  = fit_sec,
      version  = as.character(res$version %||% NA),
      r_version = paste(R.version$major, R.version$minor, sep = ".")
    ),
    res$extra
  )
  write_fit(args$out, phi, theta, meta)
  message(sprintf("%s %s k=%d iters=%d threads=%d -> %.2fs",
                  engine, args$corpus, args$k, args$iters, args$threads, fit_sec))
}

`%||%` <- function(x, y) if (is.null(x)) y else x
