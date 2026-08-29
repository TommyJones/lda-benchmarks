#!/usr/bin/env python
"""lda (Jonathan Chang Python port) -- collapsed Gibbs in Cython, single threaded.

This is the Python/Cython implementation of the same sampler that the R `lda`
package provides in C. It is an instructive cross-language comparison: same
algorithm, same author lineage, different language binding.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import ALPHA, ETA, run_runner  # noqa: E402

import lda  # noqa: E402


def fit(dtm, vocab, k, iters, threads, seed, timer):
    # lda.fit wants a sparse matrix in scipy CSR format and integer dtype.
    dtm = dtm.tocsr()

    model = lda.LDA(
        n_topics=k,
        n_iter=iters,
        alpha=ALPHA,
        eta=ETA,
        random_state=seed,
    )
    model.fit(dtm)
    timer.stop()

    # lda.topic_word_ is k x V; lda.doc_topic_ is D x k.
    return model.topic_word_, model.doc_topic_


run_runner("pylda", fit, lambda: lda.__version__)
