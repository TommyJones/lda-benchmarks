# Shared environment for every runner. Source this, don't execute it.
#
# The thread-limiting exports matter: BLAS/OpenMP libraries will happily grab
# every core, which would silently contaminate the single-threaded frontier runs
# and the thread-scaling sweep. Each runner sets these to its own --threads value
# before doing anything else.

LDA_BENCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LDA_BENCH_ROOT

export JAVA_HOME="$HOME/opt/jdk"
export MALLET_HOME="$HOME/opt/mallet"
export GSL_HOME="$HOME/opt/gsl"
export PATH="$JAVA_HOME/bin:$MALLET_HOME/bin:$GSL_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$GSL_HOME/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

export LDA_BENCH_PYTHON="$LDA_BENCH_ROOT/.venv/bin/python"

# Pin implicit parallelism to one core unless a runner overrides it.
lda_bench_set_threads() {
  local n="${1:-1}"
  export OMP_NUM_THREADS="$n"
  export OPENBLAS_NUM_THREADS="$n"
  export MKL_NUM_THREADS="$n"
  export NUMEXPR_NUM_THREADS="$n"
  export VECLIB_MAXIMUM_THREADS="$n"
  export RCPP_PARALLEL_NUM_THREADS="$n"
}
lda_bench_set_threads 1
