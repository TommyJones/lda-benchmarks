# Quality metrics, computed identically for every engine.
#
# The whole point of the phi/theta handoff is that no engine gets to score
# itself with its own conventions. tidylda, MALLET, gensim and the rest all get
# run through exactly these two functions on exactly the same DTM.
#
# Both metrics are in-sample -- computed on the training DTM -- which is how
# tidylda reports them natively. The README says so explicitly.

suppressPackageStartupMessages({
  library(Matrix)
})

#' Probabilistic coherence, averaged over topics.
#'
#' tidylda::calc_prob_coherence is exported, so we call the public function
#' rather than reimplementing it (it is the same routine textmineR uses).
score_coherence <- function(phi, dtm, m = 5) {
  coh <- tidylda::calc_prob_coherence(beta = phi, data = dtm, m = m)
  list(
    coherence_mean   = mean(coh, na.rm = TRUE),
    coherence_median = stats::median(coh, na.rm = TRUE),
    coherence_sd     = stats::sd(coh, na.rm = TRUE),
    coherence_by_topic = unname(coh)
  )
}

#' Goodness of fit R^2.
#'
#' tidylda's internal calc_lda_r2() is a thin wrapper over the public
#' mvrsquared::calc_rsquared, so we call mvrsquared directly and avoid depending
#' on a ::: internal. The document-length weighting of theta is what turns the
#' topic proportions back into expected token counts.
score_r2 <- function(phi, theta, dtm, threads = 1) {
  mvrsquared::calc_rsquared(
    y = dtm,
    yhat = list(x = rowSums(dtm) * theta, w = phi),
    return_ss_only = FALSE,
    threads = threads
  )
}

#' Validate the runner contract before scoring, so a misaligned runner fails
#' loudly here instead of silently producing a plausible-looking bad number.
check_fit <- function(phi, theta, dtm, tol = 1e-6) {
  vocab <- colnames(dtm)
  stopifnot(
    "phi must have one column per vocabulary term" =
      ncol(phi) == length(vocab),
    "theta must have one row per document" =
      nrow(theta) == nrow(dtm),
    "phi and theta must agree on the number of topics" =
      nrow(phi) == ncol(theta),
    "phi rows must sum to 1" =
      all(abs(rowSums(phi) - 1) < tol),
    "theta rows must sum to 1" =
      all(abs(rowSums(theta) - 1) < tol)
  )
  invisible(TRUE)
}

#' Score one fitted model. Returns a one-row-ish list, ready to be bound into
#' results/runs.csv.
score_fit <- function(phi, theta, dtm, m = 5, threads = 1) {
  phi <- normalize_rows(phi)
  theta <- normalize_rows(theta)
  colnames(phi) <- colnames(dtm)
  check_fit(phi, theta, dtm)

  coh <- score_coherence(phi, dtm, m = m)
  list(
    r2               = score_r2(phi, theta, dtm, threads = threads),
    coherence_mean   = coh$coherence_mean,
    coherence_median = coh$coherence_median,
    coherence_sd     = coh$coherence_sd
  )
}
