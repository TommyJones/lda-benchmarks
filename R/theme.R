# Shared plotting theme and palette.
#
# Color encodes *family* (WarpLDA / Gibbs / Variational), not engine. There are
# ten engines, which is more than any categorical palette can separate safely --
# the three-slot subset used here is the one that validates on all pairs, and
# family is the analytically meaningful grouping anyway. Engine identity comes
# from a direct label at the end of each curve plus the table view, so identity
# is never carried by color alone.

suppressPackageStartupMessages({
  library(ggplot2)
})

FAMILY_COLORS <- c(
  "WarpLDA"     = "#2a78d6",  # categorical slot 1
  "Gibbs"       = "#eb6834",  # slot 2
  "Variational" = "#1baf7a"   # slot 3
)

# Language, for the headline "what can each engine actually reach" chart. Three
# categories, which is the subset of the palette that validates on all pairs.
LANG_COLORS <- c(
  "R"      = "#2a78d6",
  "Python" = "#eb6834",
  "Java"   = "#1baf7a"
)

# Highlight-one-series encoding, for charts whose job is "tidylda versus the
# field". One accent against a recessive gray reads instantly and avoids
# spending eight hues on a comparison that only has two sides.
ACCENT <- "#2a78d6"
MUTED  <- "#b0aea6"

SURFACE      <- "#fcfcfb"
INK_PRIMARY  <- "#0b0b0b"
INK_SECOND   <- "#52514e"
INK_MUTED    <- "#8a8880"

theme_bench <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.background  = element_rect(fill = SURFACE, color = NA),
      panel.background = element_rect(fill = SURFACE, color = NA),
      plot.title       = element_text(color = INK_PRIMARY, face = "bold",
                                      size = base_size * 1.15),
      plot.subtitle    = element_text(color = INK_SECOND, size = base_size * 0.9),
      plot.caption     = element_text(color = INK_MUTED, size = base_size * 0.75,
                                      hjust = 0),
      axis.title       = element_text(color = INK_SECOND, size = base_size * 0.85),
      axis.text        = element_text(color = INK_SECOND, size = base_size * 0.8),
      strip.text       = element_text(color = INK_PRIMARY, face = "bold",
                                      size = base_size * 0.85),
      legend.title     = element_text(color = INK_SECOND, size = base_size * 0.8),
      legend.text      = element_text(color = INK_SECOND, size = base_size * 0.8),
      legend.position  = "top",
      # Recessive grid: present enough to read values off, never competing with
      # the data marks.
      panel.grid.major = element_line(color = "#e8e7e2", linewidth = 0.3),
      panel.grid.minor = element_blank()
    )
}
