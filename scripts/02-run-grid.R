#!/usr/bin/env Rscript
# Execute the run grid.
#
# Every run is its own OS process, launched under /usr/bin/time -v. That gives
# peak RSS on one uniform footing across R, Python and the JVM, and keeps runs
# from contaminating each other's memory measurements. Runs are resumable: a run
# whose fit.json already exists is skipped, so the grid can be executed in
# chunks or restarted after an interruption.
#
# Usage:
#   Rscript scripts/02-run-grid.R                       # everything
#   Rscript scripts/02-run-grid.R --block frontier      # one block
#   Rscript scripts/02-run-grid.R --corpus ap --engine tidylda
#   Rscript scripts/02-run-grid.R --smoke               # nih, k=10, 20 iters
#   Rscript scripts/02-run-grid.R --calibrate           # one mid run per engine
#   Rscript scripts/02-run-grid.R --dry-run
#   Rscript scripts/02-run-grid.R --timeout 3600        # per-run cap, seconds

suppressPackageStartupMessages({
  library(jsonlite)
})

root <- Sys.getenv("LDA_BENCH_ROOT", unset = path.expand("~/lda-benchmarks"))
source(file.path(root, "R", "io.R"))
source(file.path(root, "R", "grid.R"))

a <- commandArgs(trailingOnly = TRUE)
opt <- function(flag, default = NULL) {
  i <- match(flag, a)
  if (is.na(i)) default else a[i + 1L]
}
has <- function(flag) flag %in% a

dry_run <- has("--dry-run")
smoke   <- has("--smoke")
calibrate <- has("--calibrate")

# A per-run wall-clock cap, so one pathological configuration cannot stall the
# whole grid. A run that hits it is recorded as timed out and skipped by the
# scorer rather than silently missing.
timeout_sec <- as.numeric(opt("--timeout", "5400"))

if (calibrate) {
  # One mid-ladder run per engine on AP at the headline k. Gives real per-engine
  # costs to size the rest of the grid against, for about ten runs.
  grid <- do.call(rbind, lapply(names(ENGINES), function(e) {
    data.frame(block = "calibrate", engine = e, corpus = "ap",
               k = DEFAULT_K, iters = engine_fixed_iters(e),
               threads = 1L, rep = 1L, stringsAsFactors = FALSE)
  }))
} else if (smoke) {
  # One cheap run per engine, end to end. Catches a broken runner before the
  # real grid spends hours on it.
  grid <- do.call(rbind, lapply(names(ENGINES), function(e) {
    data.frame(block = "smoke", engine = e, corpus = "nih", k = 10L,
               iters = if (engine_family(e) == "Variational") 5L else 20L,
               threads = 1L, rep = 1L, stringsAsFactors = FALSE)
  }))
} else {
  grid <- build_grid()
}

if (!is.null(opt("--block")))  grid <- grid[grid$block  == opt("--block"), ]
if (!is.null(opt("--corpus"))) grid <- grid[grid$corpus == opt("--corpus"), ]
if (!is.null(opt("--engine"))) grid <- grid[grid$engine == opt("--engine"), ]

# Cheapest first, so a broken configuration surfaces early rather than after the
# expensive runs have already been spent.
grid <- grid[order(grid$corpus != "nih", grid$corpus != "ap",
                   grid$k, grid$iters, grid$threads), ]

message(sprintf("grid: %d runs", nrow(grid)))
if (dry_run) {
  print(utils::head(grid, 50))
  quit(save = "no")
}

raw_dir <- file.path(root, "results", "raw")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)

#' Build the shell command for one run. Everything routes through setup/env.sh
#' so the thread caps on BLAS/OpenMP are applied identically in every language.
build_cmd <- function(row, out_dir) {
  spec <- ENGINES[[row$engine]]
  script <- file.path(root, spec$script)
  common_args <- sprintf(
    "--corpus %s --k %d --iters %d --threads %d --seed %d --out %s",
    row$corpus, row$k, row$iters, row$threads, row$rep, shQuote(out_dir)
  )
  inner <- switch(
    spec$kind,
    R      = sprintf("Rscript %s %s", shQuote(script), common_args),
    python = sprintf('"$LDA_BENCH_PYTHON" %s %s', shQuote(script), common_args),
    shell  = sprintf("bash %s %s", shQuote(script), common_args),
    stop("unknown runner kind: ", spec$kind)
  )
  sprintf(
    'source %s && lda_bench_set_threads %d && timeout --signal=KILL %d /usr/bin/time -v %s',
    shQuote(file.path(root, "setup", "env.sh")), row$threads, timeout_sec, inner
  )
}

#' Pull peak RSS and wall clock out of /usr/bin/time -v output.
parse_time_v <- function(lines) {
  # Split on the first ": " rather than the first ":" -- the label
  # "Elapsed (wall clock) time (h:mm:ss or m:ss)" contains colons of its own,
  # but none of them are followed by a space.
  grab <- function(pattern) {
    hit <- grep(pattern, lines, value = TRUE)
    if (!length(hit)) return(NA_character_)
    at <- regexpr(": ", hit[1], fixed = TRUE)
    if (at < 0) return(NA_character_)
    trimws(substring(hit[1], at + 2L))
  }
  rss <- suppressWarnings(as.numeric(grab("Maximum resident set size")))
  wall <- grab("Elapsed \\(wall clock\\) time")
  wall_sec <- NA_real_
  if (!is.na(wall)) {
    parts <- as.numeric(strsplit(wall, ":")[[1]])
    wall_sec <- switch(as.character(length(parts)),
                       "2" = parts[1] * 60 + parts[2],
                       "3" = parts[1] * 3600 + parts[2] * 60 + parts[3],
                       NA_real_)
  }
  list(max_rss_kb = rss, wall_sec = wall_sec)
}

failures <- list()
for (i in seq_len(nrow(grid))) {
  row <- grid[i, ]
  id <- run_id(row$engine, row$corpus, row$k, row$iters, row$threads, row$rep)
  out_dir <- file.path(raw_dir, id)

  if (file.exists(file.path(out_dir, "fit.json"))) {
    message(sprintf("[%d/%d] skip (done) %s", i, nrow(grid), id))
    next
  }
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  message(sprintf("[%d/%d] %s", i, nrow(grid), id))
  cmd <- build_cmd(row, out_dir)
  out <- suppressWarnings(
    system2("bash", c("-c", shQuote(cmd)), stdout = TRUE, stderr = TRUE)
  )
  status <- attr(out, "status")
  writeLines(out, file.path(out_dir, "run.log"))

  if (!is.null(status) && status != 0) {
    # 137 == SIGKILL, which here means `timeout` fired.
    why <- if (identical(as.integer(status), 137L))
      sprintf("TIMED OUT (>%.0fs)", timeout_sec) else paste("FAILED exit", status)
    message("  ", why, " -- see ", file.path(out_dir, "run.log"))
    writeLines(why, file.path(out_dir, "FAILED"))
    failures[[length(failures) + 1L]] <- cbind(row, exit = status, why = why)
    next
  }

  # Fold the process-level measurements into fit.json alongside the runner's own
  # in-process fit_sec.
  meta <- jsonlite::fromJSON(file.path(out_dir, "fit.json"))
  meta[names(parse_time_v(out))] <- parse_time_v(out)
  meta$block <- row$block
  meta$run_id <- id
  writeLines(jsonlite::toJSON(meta, auto_unbox = TRUE, digits = 10, pretty = TRUE),
             file.path(out_dir, "fit.json"))
}

if (length(failures)) {
  message("\n", length(failures), " run(s) failed:")
  print(do.call(rbind, failures))
} else {
  message("\nall runs completed")
}
