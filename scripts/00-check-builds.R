#!/usr/bin/env Rscript
# Fail loudly if any compiled engine was built without optimization.
#
# This exists because the first run of this benchmark measured an -O0 build of
# tidylda and reported it as 5x slower than it is. The cause: `~/tidylda/src/`
# held stale .o files from a devtools/pkgbuild debug build (which defaults to
# -O0), and `install.packages(<source dir>)` relinked them instead of
# recompiling. Nothing in the output looked wrong -- the numbers were simply
# from unoptimized code.
#
# GCC records the actual flags in DWARF as DW_AT_producer, and the LAST
# optimization flag on the line wins. So a producer reading "-O2 -O0" is an
# unoptimized binary wearing an -O2 costume. That string is the ground truth,
# not the Makevars and not what we think we passed.
#
# Run before any timing. `make run` depends on it.

pkgs <- c("tidylda", "text2vec", "textmineR", "topicmodels", "lda", "mvrsquared")

producer_opt <- function(so) {
  out <- suppressWarnings(system2("objdump", c("--dwarf=info", shQuote(so)),
                                  stdout = TRUE, stderr = FALSE))
  line <- grep("DW_AT_producer", out, value = TRUE)
  if (!length(line)) return(NA_character_)
  # Last -O flag wins, exactly as the compiler resolves it.
  flags <- regmatches(line[1], gregexpr("-O[0-9sgz]*", line[1]))[[1]]
  if (!length(flags)) return(NA_character_)
  flags[length(flags)]
}

bad <- character(0)
cat(sprintf("%-14s %-8s %s\n", "package", "opt", "shared object"))
for (p in pkgs) {
  so_dir <- system.file("libs", package = p)
  if (!nzchar(so_dir)) { cat(sprintf("%-14s %-8s (no compiled code)\n", p, "-")); next }
  sos <- list.files(so_dir, pattern = "\\.so$", full.names = TRUE)
  for (so in sos) {
    opt <- producer_opt(so)
    cat(sprintf("%-14s %-8s %s\n", p, ifelse(is.na(opt), "unknown", opt), basename(so)))
    if (!is.na(opt) && opt %in% c("-O0", "-Og")) bad <- c(bad, paste0(p, " (", opt, ")"))
  }
}

# Python and Java engines are prebuilt wheels and a released jar; they are not
# subject to this failure mode, so they are out of scope here.

if (length(bad)) {
  stop("\nUNOPTIMIZED BUILD DETECTED: ", paste(bad, collapse = ", "),
       "\nTimings from this build are not meaningful.",
       "\nFor a package installed from a source directory, delete src/*.o and",
       "\nsrc/*.so first -- R CMD INSTALL relinks stale objects rather than",
       "\nrecompiling them.\n")
}
cat("\nall compiled engines optimized\n")
