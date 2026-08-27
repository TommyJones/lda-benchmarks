#!/usr/bin/env Rscript
# Record exactly what produced the numbers. Committed alongside results/runs.csv.

root <- Sys.getenv("LDA_BENCH_ROOT", unset = path.expand("~/lda-benchmarks"))
env_dir <- file.path(root, "results", "env")
dir.create(env_dir, recursive = TRUE, showWarnings = FALSE)

pkgs <- c("tidylda", "text2vec", "textmineR", "topicmodels", "lda",
          "mvrsquared", "Matrix")
for (p in pkgs) suppressPackageStartupMessages(library(p, character.only = TRUE))

capture <- function(file, expr) {
  writeLines(utils::capture.output(expr), file.path(env_dir, file))
}

capture("sessionInfo.txt", print(sessionInfo()))

# tidylda is installed from a local source tree rather than CRAN (CRAN still has
# 0.0.7, the old Gibbs sampler), so pin down exactly which commit that was.
tidylda_src <- path.expand("~/tidylda")
sha <- tryCatch(
  system2("git", c("-C", tidylda_src, "rev-parse", "HEAD"), stdout = TRUE),
  error = function(e) NA_character_
)
dirty <- tryCatch(
  length(system2("git", c("-C", tidylda_src, "status", "--porcelain"),
                 stdout = TRUE)) > 0,
  error = function(e) NA
)
writeLines(c(
  paste("tidylda version:", as.character(packageVersion("tidylda"))),
  paste("tidylda source:", tidylda_src),
  paste("tidylda git sha:", sha),
  paste("tidylda working tree dirty:", dirty)
), file.path(env_dir, "tidylda-provenance.txt"))

# Hardware and the rest of the toolchain.
sh <- function(cmd) tryCatch(system(cmd, intern = TRUE, ignore.stderr = TRUE),
                             error = function(e) character(0))
writeLines(c(
  paste("cores:", parallel::detectCores()),
  paste("R:", R.version.string),
  sh("free -h | head -2"),
  sh("lscpu | grep -E 'Model name|Socket|Thread|Core'"),
  sh("uname -a")
), file.path(env_dir, "hardware.txt"))

system(paste0(shQuote(file.path(root, ".venv/bin/pip")), " freeze > ",
              shQuote(file.path(env_dir, "pip-freeze.txt"))))
system(paste0("~/opt/jdk/bin/java -version 2> ",
              shQuote(file.path(env_dir, "java-version.txt"))))

message("wrote ", env_dir)
