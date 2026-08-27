# The experiment grid: which engines, at which settings, on which corpora.

# How each engine is invoked. `parallel` records whether the engine can use more
# than one core at all -- the thread-scaling sweep only covers those.
ENGINES <- list(
  tidylda           = list(kind = "R",      script = "runners/r/fit-tidylda.R",           family = "WarpLDA",   parallel = TRUE),
  text2vec          = list(kind = "R",      script = "runners/r/fit-text2vec.R",          family = "WarpLDA",   parallel = TRUE),
  textmineR         = list(kind = "R",      script = "runners/r/fit-textminer.R",         family = "Gibbs",     parallel = TRUE),
  `topicmodels-gibbs` = list(kind = "R",    script = "runners/r/fit-topicmodels-gibbs.R", family = "Gibbs",     parallel = FALSE),
  `topicmodels-vem` = list(kind = "R",      script = "runners/r/fit-topicmodels-vem.R",   family = "Variational", parallel = FALSE),
  lda               = list(kind = "R",      script = "runners/r/fit-lda.R",               family = "Gibbs",     parallel = FALSE),
  mallet            = list(kind = "shell",  script = "runners/mallet/fit-mallet.sh",      family = "Gibbs",     parallel = TRUE),
  gensim            = list(kind = "python", script = "runners/py/fit-gensim.py",          family = "Variational", parallel = TRUE),
  sklearn           = list(kind = "python", script = "runners/py/fit-sklearn.py",         family = "Variational", parallel = TRUE),
  tomotopy          = list(kind = "python", script = "runners/py/fit-tomotopy.py",        family = "Gibbs",     parallel = TRUE)
)

# Iteration ladders. A Gibbs/MH sweep and a variational pass are different units
# of work, which is the whole reason the headline chart plots quality against
# wall-clock time instead of against this number. The ladders are chosen so both
# families span a comparable range of *time*, not of iterations.
LADDER <- list(
  WarpLDA     = c(20, 50, 100, 200, 500),
  Gibbs       = c(20, 50, 100, 200, 500),
  Variational = c(1, 2, 5, 10, 25)
)

# A single mid-ladder setting, used where the experiment varies something other
# than iterations (thread scaling, the k sweep).
FIXED_ITERS <- list(WarpLDA = 200, Gibbs = 200, Variational = 10)

THREAD_LEVELS <- c(1, 2, 4, 8, 16, 20)  # capped at 20 of 24 cores
K_LEVELS <- c(25, 50, 100, 200)
DEFAULT_K <- 100

engine_family <- function(engine) ENGINES[[engine]]$family
engine_ladder <- function(engine) LADDER[[engine_family(engine)]]
engine_fixed_iters <- function(engine) FIXED_ITERS[[engine_family(engine)]]

run_id <- function(engine, corpus, k, iters, threads, rep) {
  sprintf("%s__%s__k%d__i%d__t%d__r%d", engine, corpus, k, iters, threads, rep)
}

#' Build the full experiment grid as a data frame of runs.
#'
#' Three blocks:
#'   frontier - the headline quality-vs-time curves, single threaded so the
#'              comparison is algorithmic rather than about who threads better
#'   threads  - scaling sweep at fixed iterations, parallel engines only
#'   k        - quality across topic counts, one rep, AP only
build_grid <- function(corpora = c("ap", "20ng"), reps = c(ap = 3, `20ng` = 1)) {
  rows <- list()

  add <- function(block, engine, corpus, k, iters, threads, n_reps) {
    for (rep in seq_len(n_reps)) {
      rows[[length(rows) + 1L]] <<- data.frame(
        block = block, engine = engine, corpus = corpus, k = k,
        iters = iters, threads = threads, rep = rep,
        stringsAsFactors = FALSE
      )
    }
  }

  for (corpus in corpora) {
    n_reps <- as.integer(reps[[corpus]])

    # frontier
    for (engine in names(ENGINES)) {
      for (iters in engine_ladder(engine)) {
        add("frontier", engine, corpus, DEFAULT_K, iters, 1L, n_reps)
      }
    }

    # thread scaling
    for (engine in names(ENGINES)) {
      if (!ENGINES[[engine]]$parallel) next
      for (th in THREAD_LEVELS) {
        if (th == 1L) next  # the threads=1 point is already in the frontier block
        add("threads", engine, corpus, DEFAULT_K,
            engine_fixed_iters(engine), th, n_reps)
      }
    }
  }

  # k sweep, AP only, one rep
  for (engine in names(ENGINES)) {
    for (k in K_LEVELS) {
      if (k == DEFAULT_K) next  # covered by the frontier block
      add("k", engine, "ap", k, engine_fixed_iters(engine), 1L, 1L)
    }
  }

  do.call(rbind, rows)
}
