#!/usr/bin/env python
"""scikit-learn -- online variational Bayes.

`iters` is max_iter, i.e. passes over the corpus. Early stopping is defeated so
a run executes the number of passes the ladder asked for.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import ALPHA, ETA, run_runner  # noqa: E402

import sklearn  # noqa: E402
from sklearn.decomposition import LatentDirichletAllocation  # noqa: E402


def fit(dtm, vocab, k, iters, threads, seed, timer):
    model = LatentDirichletAllocation(
        n_components=k,
        doc_topic_prior=ALPHA,
        topic_word_prior=ETA,
        max_iter=iters,
        learning_method="batch",
        evaluate_every=-1,
        # perp_tol only applies when evaluate_every > 0; with batch learning and
        # evaluation off, max_iter is executed in full.
        n_jobs=threads,
        random_state=seed,
    )
    theta = model.fit_transform(dtm)
    timer.stop()

    # components_ is k x V unnormalized; common.run_runner normalizes.
    return model.components_, theta


run_runner("sklearn", fit, lambda: sklearn.__version__)
