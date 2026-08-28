#!/usr/bin/env python
"""tomotopy -- collapsed Gibbs in C++, multithreaded.

Like MALLET's parallel sampler, tomotopy's `workers > 1` partitions the sampling
work in a way that does not preserve the exact collapsed Gibbs chain. That is
the interesting thing to measure, not a reason to exclude it: the thread-scaling
runs report quality alongside speed so any degradation shows up.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import ALPHA, ETA, run_runner  # noqa: E402

import tomotopy as tp  # noqa: E402


def fit(dtm, vocab, k, iters, threads, seed, timer):
    model = tp.LDAModel(k=k, alpha=ALPHA, eta=ETA, seed=seed)

    # DISABLE HYPERPARAMETER OPTIMIZATION. tomotopy's `optim_interval` defaults
    # to 10, so out of the box it re-estimates alpha every 10 iterations and
    # drifts to an asymmetric prior (measured: 0.1 -> ~0.3-0.5 within 100
    # iterations). That is not a fair comparison in either direction -- it costs
    # time the other engines do not spend, and an optimized asymmetric alpha is
    # known to improve topic quality, so it flatters the fit as well. It is not
    # a constructor argument, only a settable attribute.
    model.optim_interval = 0

    # tomotopy takes token streams, so expand counts back into repeated tokens.
    # Its internal vocabulary is built in first-seen order, so we reindex phi
    # onto the canonical vocab afterwards rather than assuming they agree.
    dtm = dtm.tocsr()
    vocab_arr = np.asarray(vocab)
    for d in range(dtm.shape[0]):
        lo, hi = dtm.indptr[d], dtm.indptr[d + 1]
        toks = np.repeat(vocab_arr[dtm.indices[lo:hi]], dtm.data[lo:hi])
        model.add_doc(list(toks))

    model.train(iters, workers=threads)
    timer.stop()

    # Reindex tomotopy's vocabulary onto ours. Any canonical term tomotopy never
    # saw stays at zero; run_runner renormalizes.
    tp_vocab = list(model.used_vocabs)
    pos = {w: i for i, w in enumerate(vocab)}
    cols = np.array([pos[w] for w in tp_vocab])

    phi = np.zeros((k, len(vocab)))
    for t in range(k):
        phi[t, cols] = model.get_topic_word_dist(t)

    theta = np.vstack([doc.get_topic_dist() for doc in model.docs])
    return phi, theta


run_runner("tomotopy", fit, lambda: tp.__version__)
