#!/usr/bin/env Rscript
# Install the R-side dependencies for the benchmark.
#
# tidylda 0.1.0 is on CRAN as of 2026-08-28, but the benchmark predates its
# acceptance and ran against a source build of the same version. We keep
# installing from the local tree, and record its git SHA in results/env/, so a
# re-run reproduces the exact binary that produced the published numbers rather
# than whatever CRAN carries later. Point this at CRAN instead if you want to
# benchmark the released build.

repos <- "https://cloud.r-project.org"

# topicmodels needs GSL headers; setup/install-gsl.sh puts them in ~/opt/gsl.
# It has no configure check -- src/ctm.c includes <gsl/gsl_rng.h> directly -- so
# the include path has to reach the compiler via a Makevars, not just PATH.
gsl_home <- path.expand("~/opt/gsl")
here <- dirname(sub("^--file=", "",
                    grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (dir.exists(gsl_home)) {
  Sys.setenv(PATH = paste(file.path(gsl_home, "bin"), Sys.getenv("PATH"), sep = ":"))
  Sys.setenv(R_MAKEVARS_USER = normalizePath(file.path(here, "Makevars")))
}

needed <- c(
  "topicmodels",  # VEM + Gibbs
  "lda",          # Chang's collapsed Gibbs
  "text2vec",     # WarpLDA
  "textmineR",    # collapsed Gibbs
  "mvrsquared",   # R^2, used by the scoring script
  "Matrix",
  "jsonlite",
  "ggplot2",
  "dplyr",
  "tidyr",
  "readr",
  "knitr",
  "rmarkdown"
)

missing <- setdiff(needed, rownames(installed.packages()))
if (length(missing)) {
  message("installing: ", paste(missing, collapse = ", "))
  install.packages(missing, repos = repos)
} else {
  message("all CRAN deps already present")
}

# --- tidylda from local source ------------------------------------------------
tidylda_src <- path.expand("~/tidylda")
if (!dir.exists(tidylda_src)) {
  stop("tidylda source not found at ", tidylda_src)
}
message("installing tidylda from source: ", tidylda_src)
install.packages(tidylda_src, repos = NULL, type = "source")

still_missing <- setdiff(c(needed, "tidylda"), rownames(installed.packages()))
if (length(still_missing)) {
  stop("failed to install: ", paste(still_missing, collapse = ", "))
}
message("R deps OK")
