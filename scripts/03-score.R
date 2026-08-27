#!/usr/bin/env Rscript
# Score every completed run and collapse results/raw/ into results/runs.csv.
#
# No engine scores itself. Every run's phi and theta are read back, normalized,
# checked against the runner contract, and pushed through the same two metric
# functions on the same DTM.
#
# Usage:
#   Rscript scripts/03-score.R            # score runs not yet scored
#   Rscript scripts/03-score.R --force    # rescore everything

suppressPackageStartupMessages({
  library(Matrix)
  library(jsonlite)
})

root <- Sys.getenv("LDA_BENCH_ROOT", unset = path.expand("~/lda-benchmarks"))
source(file.path(root, "R", "io.R"))
source(file.path(root, "R", "metrics.R"))

a <- commandArgs(trailingOnly = TRUE)
force <- "--force" %in% a
score_threads <- 8L  # metrics only; does not affect any timing we report

raw_dir <- file.path(root, "results", "raw")
run_dirs <- list.dirs(raw_dir, recursive = FALSE)

# Cache DTMs: scoring reloads the same handful of corpora hundreds of times.
dtm_cache <- new.env(parent = emptyenv())
get_dtm <- function(corpus) {
  if (is.null(dtm_cache[[corpus]])) dtm_cache[[corpus]] <- read_dtm(corpus)
  dtm_cache[[corpus]]
}

rows <- list()
for (d in run_dirs) {
  fit_json <- file.path(d, "fit.json")
  if (!file.exists(fit_json)) next
  meta <- jsonlite::fromJSON(fit_json)

  score_file <- file.path(d, "score.json")
  if (file.exists(score_file) && !force) {
    scores <- jsonlite::fromJSON(score_file)
  } else {
    dtm <- get_dtm(meta$corpus)
    phi <- read_matrix_mm(file.path(d, "phi.mtx"))
    theta <- read_matrix_mm(file.path(d, "theta.mtx"))

    scores <- tryCatch(
      score_fit(phi, theta, dtm, m = 5, threads = score_threads),
      error = function(e) {
        message("  scoring failed for ", basename(d), ": ", conditionMessage(e))
        list(r2 = NA_real_, coherence_mean = NA_real_,
             coherence_median = NA_real_, coherence_sd = NA_real_)
      }
    )
    writeLines(jsonlite::toJSON(scores, auto_unbox = TRUE, digits = 10),
               score_file)
    message(sprintf("scored %s: r2=%.4f coherence=%.4f",
                    basename(d), scores$r2, scores$coherence_mean))
  }

  rows[[length(rows) + 1L]] <- data.frame(
    run_id   = meta$run_id  %||% basename(d),
    block    = meta$block   %||% NA_character_,
    engine   = meta$engine,
    language = meta$language,
    corpus   = meta$corpus,
    k        = meta$k,
    iters    = meta$iters,
    threads  = meta$threads,
    rep      = meta$seed,
    fit_sec  = meta$fit_sec,
    wall_sec = meta$wall_sec %||% NA_real_,
    max_rss_kb = meta$max_rss_kb %||% NA_real_,
    r2       = scores$r2,
    coherence_mean   = scores$coherence_mean,
    coherence_median = scores$coherence_median,
    coherence_sd     = scores$coherence_sd,
    version  = meta$version %||% NA_character_,
    stringsAsFactors = FALSE
  )
}

if (!length(rows)) {
  stop("no completed runs found in ", raw_dir)
}

runs <- do.call(rbind, rows)
runs <- runs[order(runs$corpus, runs$engine, runs$k, runs$iters, runs$threads), ]
out <- file.path(root, "results", "runs.csv")
utils::write.csv(runs, out, row.names = FALSE)
message(sprintf("\nwrote %s (%d runs)", out, nrow(runs)))
