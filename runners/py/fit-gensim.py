#!/usr/bin/env python
"""gensim -- online variational Bayes (Hoffman et al.).

`iters` here is gensim `passes`, i.e. sweeps over the corpus, which is the
closest analogue to a Gibbs sweep. The per-document inner variational loop is
left at gensim's default.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import ALPHA, ETA, run_runner  # noqa: E402

import gensim  # noqa: E402
from gensim.matutils import Sparse2Corpus  # noqa: E402
from gensim.models import LdaModel, LdaMulticore  # noqa: E402


def fit(dtm, vocab, k, iters, threads, seed, timer):
    # Sparse2Corpus wants terms x documents.
    corpus = Sparse2Corpus(dtm.T, documents_columns=True)
    id2word = {i: w for i, w in enumerate(vocab)}

    common = dict(
        corpus=corpus,
        num_topics=k,
        id2word=id2word,
        passes=iters,
        alpha=np.full(k, ALPHA),
        eta=ETA,
        random_state=seed,
        eval_every=None,  # skip gensim's own perplexity logging
    )
    if threads > 1:
        model = LdaMulticore(workers=threads, **common)
    else:
        model = LdaModel(**common)
    timer.stop()

    # get_topics() is k x V indexed by id2word key, so it is already in the
    # corpus's canonical vocabulary order.
    phi = model.get_topics()

    # theta needs a separate inference pass, which is why it sits outside the
    # timed region.
    theta = np.zeros((dtm.shape[0], k))
    for i, bow in enumerate(corpus):
        for topic, p in model.get_document_topics(bow, minimum_probability=0.0):
            theta[i, topic] = p
    return phi, theta


run_runner("gensim", fit, lambda: gensim.__version__)
