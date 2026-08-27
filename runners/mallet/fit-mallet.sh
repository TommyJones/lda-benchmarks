#!/usr/bin/env bash
# MALLET -- collapsed Gibbs on the JVM, with the multithreaded sampler that
# relaxes the exact-chain guarantee when --num-threads > 1.
#
# Driven through the CLI rather than the R `mallet` package: that avoids rJava
# and `R CMD javareconf` (which want write access we do not have here), and it
# fits the one-process-per-run measurement design.
#
# Vocabulary alignment: data/<corpus>/mallet.txt holds documents already
# tokenized to our shared vocabulary, one token per term occurrence. With
# --token-regex '\S+' and no stoplist, MALLET's vocabulary is exactly ours.
# It can still drop a term, so the R-side conversion reindexes by token string.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/setup/env.sh"

CORPUS=""; K=""; ITERS=""; THREADS=1; SEED=1; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --corpus)  CORPUS="$2"; shift 2 ;;
    --k)       K="$2"; shift 2 ;;
    --iters)   ITERS="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --seed)    SEED="$2"; shift 2 ;;
    --out)     OUT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

DATA="$LDA_BENCH_ROOT/data/$CORPUS"
mkdir -p "$OUT"

# MALLET's --alpha is the sum over topics, not the per-topic value, so scale to
# match the alpha=0.1 per topic every other engine uses.
ALPHA_SUM=$(awk -v k="$K" 'BEGIN { printf "%.6f", k * 0.1 }')
BETA=0.05

# Give the JVM enough heap that GC thrash is not what we are measuring.
export MALLET_MEMORY="${MALLET_MEMORY:-8g}"

# --- import (not timed: this is corpus preparation, done once per corpus) -----
SEQ="$DATA/mallet-${CORPUS}.sequence"
if [ ! -f "$SEQ" ]; then
  mallet import-file \
    --input "$DATA/mallet.txt" \
    --output "$SEQ" \
    --keep-sequence \
    --token-regex '\S+' \
    --line-regex '^([^\t]*)\t([^\t]*)\t(.*)$' > /dev/null
fi

# --- train --------------------------------------------------------------------
START=$(date +%s.%N)
mallet train-topics \
  --input "$SEQ" \
  --num-topics "$K" \
  --num-iterations "$ITERS" \
  --num-threads "$THREADS" \
  --random-seed "$SEED" \
  --alpha "$ALPHA_SUM" \
  --beta "$BETA" \
  --optimize-interval 0 \
  --optimize-burn-in 0 \
  --show-topics-interval 0 \
  --topic-word-weights-file "$OUT/topic-word-weights.txt" \
  --output-doc-topics "$OUT/doc-topics.txt" \
  > "$OUT/mallet.log" 2>&1
END=$(date +%s.%N)

FIT_SEC=$(awk -v a="$START" -v b="$END" 'BEGIN { printf "%.4f", b - a }')

# Convert MALLET's text output into the phi.mtx / theta.mtx / fit.json contract.
Rscript "$LDA_BENCH_ROOT/runners/mallet/convert-mallet.R" \
  --corpus "$CORPUS" --k "$K" --iters "$ITERS" --threads "$THREADS" \
  --seed "$SEED" --out "$OUT" --fit-sec "$FIT_SEC"

echo "mallet $CORPUS k=$K iters=$ITERS threads=$THREADS -> ${FIT_SEC}s"
