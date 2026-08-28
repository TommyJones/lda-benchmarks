#!/usr/bin/env Rscript
# Render the README's figures to results/figures/*.png.
#
# The HTML report has to be downloaded or hosted to be read, which makes it
# useless as a landing page. These PNGs are committed so the README shows the
# results directly on GitHub. Same data, same theme as the report -- this script
# is not a second source of truth, it just re-renders the report's charts at a
# fixed size for embedding.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

root <- Sys.getenv("LDA_BENCH_ROOT", unset = path.expand("~/lda-benchmarks"))
source(file.path(root, "R", "grid.R"))
source(file.path(root, "R", "theme.R"))

fig_dir <- file.path(root, "results", "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

save_fig <- function(name, plot, height = 4.6, width = 10) {
  ggsave(file.path(fig_dir, name), plot, width = width, height = height,
         dpi = 110, bg = SURFACE)
  message("wrote ", name)
}

runs <- read.csv(file.path(root, "results", "runs.csv"), stringsAsFactors = FALSE)
runs <- runs[runs$corpus %in% c("ap", "20ng"), ]

fam <- vapply(names(ENGINES), function(e) ENGINES[[e]]$family, character(1))
runs$family <- factor(unname(fam[runs$engine]), levels = names(FAMILY_COLORS))
runs$corpus <- droplevels(factor(
  runs$corpus, levels = c("ap", "20ng"),
  labels = c("AP (2.2k docs)", "20 Newsgroups (17.7k docs)")
))
BIG <- levels(runs$corpus)[nlevels(runs$corpus)]

LANG <- c(tidylda = "R", text2vec = "R", textmineR = "R", `topicmodels-gibbs` = "R",
          `topicmodels-vem` = "R", lda = "R", mallet = "Java",
          gensim = "Python", sklearn = "Python", tomotopy = "Python")
fixed_it <- vapply(names(ENGINES), engine_fixed_iters, numeric(1))
par_eng <- names(ENGINES)[vapply(names(ENGINES),
                                 function(e) ENGINES[[e]]$parallel, logical(1))]

agg <- runs %>%
  group_by(block, engine, family, corpus, k, iters, threads) %>%
  summarise(fit_sec = median(fit_sec), max_rss_mb = median(max_rss_kb) / 1024,
            r2 = median(r2), coherence = median(coherence_mean), .groups = "drop")

# --- 1. best achievable time, by language --------------------------------------
best <- runs %>%
  filter(k == DEFAULT_K, iters == fixed_it[engine]) %>%
  group_by(engine, corpus, threads) %>%
  summarise(fit_sec = median(fit_sec), .groups = "drop") %>%
  group_by(engine, corpus) %>%
  slice_min(fit_sec, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  mutate(language = LANG[engine])

hl <- best %>% filter(corpus == BIG)
save_fig("fig-speed.png",
  ggplot(hl, aes(fit_sec, reorder(engine, -fit_sec), color = language)) +
    geom_segment(aes(x = min(fit_sec) * 0.75, xend = fit_sec,
                     yend = reorder(engine, -fit_sec)),
                 color = "#e0dfda", linewidth = 1.6, lineend = "round") +
    geom_point(size = 3.4) +
    geom_text(aes(label = ifelse(fit_sec >= 100, sprintf("%.0fs", fit_sec),
                                 sprintf("%.1fs", fit_sec))),
              hjust = -0.45, size = 3.2, color = INK_SECOND, show.legend = FALSE) +
    scale_x_log10(expand = expansion(mult = c(0.02, 0.16))) +
    scale_color_manual(values = LANG_COLORS, name = NULL) +
    labs(title = "Fastest time each implementation can reach",
         subtitle = paste0(BIG, ", k = 100, using as many cores as the package supports.\n",
                           "tidylda is the fastest of the R implementations; only a Python and a Java one are faster."),
         x = "Fit time, seconds (log scale)", y = NULL,
         caption = "Median of replicate runs. Gibbs/WarpLDA at 200 iterations, variational at 10 passes.") +
    theme_bench())

# --- 2. thread invariance ------------------------------------------------------
thr <- runs %>%
  filter(k == DEFAULT_K, iters == fixed_it[engine], engine %in% par_eng) %>%
  group_by(engine, corpus, threads) %>%
  summarise(coherence = median(coherence_mean), fit_sec = median(fit_sec),
            .groups = "drop") %>%
  mutate(is_tidylda = engine == "tidylda")

save_fig("fig-invariance.png",
  ggplot(thr, aes(threads, coherence, group = engine,
                  color = is_tidylda, linewidth = is_tidylda)) +
    geom_line() + geom_point(aes(size = is_tidylda)) +
    ggrepel::geom_text_repel(
      data = thr %>% group_by(engine, corpus) %>% slice_max(threads, n = 1) %>% ungroup(),
      aes(label = engine), size = 3, hjust = 0, direction = "y", nudge_x = 0.7,
      segment.color = INK_MUTED, segment.size = 0.25, min.segment.length = 0,
      show.legend = FALSE) +
    facet_wrap(~corpus) +
    scale_color_manual(values = c(`TRUE` = ACCENT, `FALSE` = MUTED), guide = "none") +
    scale_linewidth_manual(values = c(`TRUE` = 1.3, `FALSE` = 0.5), guide = "none") +
    scale_size_manual(values = c(`TRUE` = 2.4, `FALSE` = 1.4), guide = "none") +
    scale_x_continuous(breaks = THREAD_LEVELS, expand = expansion(mult = c(0.04, 0.22))) +
    labs(title = "Only tidylda gives the same answer regardless of core count",
         subtitle = "Mean topic coherence against threads. A flat line means the result reproduces across machines.",
         x = "Threads", y = "Mean probabilistic coherence",
         caption = "tidylda seeds every work item independently, so its output is bit-identical at any thread count.") +
    theme_bench())

# --- 3. quality vs time frontier ----------------------------------------------
d <- agg %>% filter(block == "frontier", threads == 1)
save_fig("fig-frontier.png", height = 5.8,
  ggplot(d, aes(fit_sec, coherence, color = family, group = engine)) +
    geom_line(linewidth = 0.7, alpha = 0.9) + geom_point(size = 2.2) +
    ggrepel::geom_text_repel(
      data = d %>% group_by(engine, corpus) %>% slice_max(fit_sec, n = 1) %>% ungroup(),
      aes(label = engine), size = 2.9, hjust = 0, direction = "y", nudge_x = 0.14,
      segment.color = INK_MUTED, segment.size = 0.25, min.segment.length = 0,
      box.padding = 0.32, max.overlaps = Inf, seed = 1, show.legend = FALSE) +
    scale_x_log10(expand = expansion(mult = c(0.04, 0.26)),
                  labels = function(x) format(x, big.mark = ",", scientific = FALSE,
                                              trim = TRUE, drop0trailing = TRUE)) +
    scale_color_manual(values = FAMILY_COLORS, name = NULL) +
    facet_wrap(~corpus, scales = "free") +
    labs(title = "Quality against wall-clock time",
         subtitle = "k = 100, single threaded. Each point is one setting on the engine's iteration ladder; up and to the left is better.",
         x = "Fit time, seconds (log scale)", y = "Mean probabilistic coherence",
         caption = "Comparing at equal iteration counts would be meaningless -- a Gibbs sweep and a variational pass are different units of work.") +
    theme_bench())

# --- 4. thread scaling ---------------------------------------------------------
sc <- thr %>%
  group_by(engine, corpus) %>%
  mutate(speedup = fit_sec[threads == 1] / fit_sec) %>%
  ungroup()

save_fig("fig-scaling.png",
  ggplot(sc, aes(threads, speedup, group = engine, color = is_tidylda,
                 linewidth = is_tidylda)) +
    geom_abline(slope = 1, intercept = 0, linetype = "22",
                color = INK_MUTED, linewidth = 0.4) +
    geom_line() + geom_point(aes(size = is_tidylda)) +
    ggrepel::geom_text_repel(
      data = sc %>% group_by(engine, corpus) %>% slice_max(threads, n = 1) %>% ungroup(),
      aes(label = engine), size = 3, hjust = 0, direction = "y", nudge_x = 0.7,
      segment.color = INK_MUTED, segment.size = 0.25, min.segment.length = 0,
      show.legend = FALSE) +
    facet_wrap(~corpus) +
    scale_color_manual(values = c(`TRUE` = ACCENT, `FALSE` = MUTED), guide = "none") +
    scale_linewidth_manual(values = c(`TRUE` = 1.3, `FALSE` = 0.5), guide = "none") +
    scale_size_manual(values = c(`TRUE` = 2.4, `FALSE` = 1.4), guide = "none") +
    scale_x_continuous(breaks = THREAD_LEVELS, expand = expansion(mult = c(0.04, 0.22))) +
    labs(title = "Speedup from additional cores",
         subtitle = "Relative to each engine's own single-threaded time. Dashed line is perfect linear scaling.",
         x = "Threads", y = "Speedup",
         caption = "Capped at 12 cores: the benchmark host is shared, and higher counts would have measured contention.") +
    theme_bench())

# --- 5. memory -----------------------------------------------------------------
mem <- agg %>%
  filter(block == "frontier", threads == 1, k == DEFAULT_K) %>%
  group_by(engine, family, corpus) %>%
  slice_max(iters, n = 1, with_ties = FALSE) %>% ungroup() %>%
  filter(corpus == BIG)

save_fig("fig-memory.png",
  ggplot(mem, aes(max_rss_mb, reorder(engine, max_rss_mb), fill = family)) +
    geom_col(width = 0.7) +
    geom_text(aes(label = sprintf("%.0f MB", max_rss_mb)), hjust = -0.15,
              size = 3.1, color = INK_SECOND) +
    scale_fill_manual(values = FAMILY_COLORS, name = NULL) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.18))) +
    labs(title = "Peak memory",
         subtitle = paste0(BIG, ", k = 100, longest iteration setting, single threaded."),
         x = "Peak resident set size (MB)", y = NULL,
         caption = "Whole-process peak RSS, so interpreter and JVM baselines are included rather than subtracted.") +
    theme_bench())

message("\nfigures written to ", fig_dir)
