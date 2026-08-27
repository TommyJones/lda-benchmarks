"""Shared scaffolding for the Python runners.

Mirrors runners/r/common.R: same CLI, same output contract. Each runner defines
fit(dtm, vocab, k, iters, threads, seed) -> (phi, theta) with phi's columns in
the corpus's canonical vocabulary order, and calls run_runner().
"""
import argparse
import json
import os
import time

import numpy as np
import scipy.io
import scipy.sparse

ROOT = os.environ.get(
    "LDA_BENCH_ROOT", os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)

# Held fixed across every engine in both languages.
ALPHA = 0.1
ETA = 0.05


def corpus_dir(corpus):
    return os.path.join(ROOT, "data", corpus)


def read_corpus(corpus):
    d = corpus_dir(corpus)
    dtm = scipy.io.mmread(os.path.join(d, "dtm.mtx"))
    dtm = scipy.sparse.csr_matrix(dtm, dtype=np.int32)
    with open(os.path.join(d, "vocab.txt")) as f:
        vocab = [line.rstrip("\n") for line in f]
    assert dtm.shape[1] == len(vocab), "vocab length disagrees with dtm"
    return dtm, vocab


def normalize_rows(x):
    """Row-normalize, mapping all-zero rows to uniform rather than NaN."""
    x = np.asarray(x, dtype=np.float64)
    s = x.sum(axis=1, keepdims=True)
    bad = ~np.isfinite(s) | (s <= 0)
    if bad.any():
        x = x.copy()
        x[bad.ravel(), :] = 1.0 / x.shape[1]
        s[bad] = 1.0
    return x / s


class Timer:
    """Marks the end of the timed region.

    The timed region runs from "here is the shared DTM" to "training is
    complete". Converting the DTM into whatever shape the package demands is
    inside it -- that is a real cost of using the package. Pulling phi and theta
    back out is outside it, because for some engines (gensim especially) that is
    an extra inference pass that only our measurement protocol asks for, and
    charging it to some engines and not others would be the unfair comparison.
    """

    def __init__(self):
        self.t0 = time.perf_counter()
        self.elapsed = None

    def stop(self):
        if self.elapsed is None:
            self.elapsed = time.perf_counter() - self.t0
        return self.elapsed


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--corpus", required=True)
    p.add_argument("--k", type=int, required=True)
    p.add_argument("--iters", type=int, required=True)
    p.add_argument("--threads", type=int, default=1)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--out", required=True)
    return p.parse_args()


def run_runner(engine, fit, version):
    args = parse_args()
    np.random.seed(args.seed)

    dtm, vocab = read_corpus(args.corpus)

    timer = Timer()
    phi, theta = fit(dtm, vocab, args.k, args.iters, args.threads, args.seed, timer)
    fit_sec = timer.stop()

    phi = normalize_rows(phi)
    theta = normalize_rows(theta)
    assert phi.shape == (args.k, len(vocab)), f"bad phi shape {phi.shape}"
    assert theta.shape == (dtm.shape[0], args.k), f"bad theta shape {theta.shape}"

    os.makedirs(args.out, exist_ok=True)
    scipy.io.mmwrite(os.path.join(args.out, "phi.mtx"), scipy.sparse.csr_matrix(phi))
    scipy.io.mmwrite(os.path.join(args.out, "theta.mtx"), scipy.sparse.csr_matrix(theta))

    meta = {
        "engine": engine,
        "language": "Python",
        "corpus": args.corpus,
        "k": args.k,
        "iters": args.iters,
        "threads": args.threads,
        "seed": args.seed,
        "alpha": ALPHA,
        "eta": ETA,
        "fit_sec": fit_sec,
        "version": version(),
    }
    # Written last: the driver treats fit.json as the "run complete" marker.
    with open(os.path.join(args.out, "fit.json"), "w") as f:
        json.dump(meta, f, indent=2)

    print(f"{engine} {args.corpus} k={args.k} iters={args.iters} "
          f"threads={args.threads} -> {fit_sec:.2f}s")
