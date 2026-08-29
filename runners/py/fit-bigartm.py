#!/usr/bin/env python
"""BigARTM -- multi-threaded EM over a regularized topic model.

`artm.LDA` is BigARTM's convenience wrapper that configures the general ARTM
machinery as plain LDA: Dirichlet smoothing regularizers with tau = alpha on
theta and tau = beta on phi. The optimizer is offline EM, so it sits in the
variational family alongside gensim, scikit-learn and topicmodels-VEM, and it
takes the variational iteration ladder (collection passes, not Gibbs sweeps).

`num_document_passes` is left at BigARTM's default of 10. That is inner E-step
iterations per document per collection pass -- real work the Gibbs engines do
not do -- but it is the documented default and this benchmark compares engines
as they are normally used. The quality-vs-time frontier is the chart that makes
this comparable; the raw iteration count is not.

VOCABULARY ORDER IS NOT PRESERVED. BigARTM builds its own token ordering, so
`phi_`'s row index is a permutation of the vocabulary we handed it. Transposing
it naively would misalign every token and produce plausible-looking nonsense, so
phi is reindexed by token string onto the canonical order below.
"""
import os
import sys
import warnings

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import ALPHA, ETA, run_runner  # noqa: E402

warnings.filterwarnings("ignore")
import artm  # noqa: E402


def fit(dtm, vocab, k, iters, threads, seed, timer):
    # BigARTM's in-memory path takes a dense words-by-documents matrix, which
    # avoids writing its batch format to disk. Dense is affordable at these
    # corpus sizes and keeps the conversion honest -- no tokenization of ours.
    n_wd = np.asarray(dtm.T.todense(), dtype=np.float64)
    bv = artm.BatchVectorizer(
        data_format="bow_n_wd",
        n_wd=n_wd,
        vocabulary={i: w for i, w in enumerate(vocab)},
    )

    model = artm.LDA(
        num_topics=k,
        alpha=ALPHA,
        beta=ETA,
        seed=seed,
        num_processors=threads,
        cache_theta=True,
        dictionary=bv.dictionary,
    )
    model.fit_offline(batch_vectorizer=bv, num_collection_passes=iters)
    timer.stop()

    # phi_ is V x K with each topic summing to 1 down its column; its row index
    # is BigARTM's own token order, so reindex onto ours before transposing.
    phi_df = model.phi_.reindex(vocab)
    missing = int(phi_df.isna().any(axis=1).sum())
    if missing:
        # A canonical term BigARTM dropped stays at zero; run_runner renormalizes.
        print(f"  note: {missing} vocabulary terms absent from BigARTM's phi")
        phi_df = phi_df.fillna(0.0)
    phi = np.asarray(phi_df, dtype=np.float64).T

    # get_theta() is K x D with columns keyed by document id. Sort the columns
    # into corpus order rather than trusting the order they come back in.
    theta_df = model.get_theta()
    theta_df = theta_df.reindex(columns=sorted(theta_df.columns))
    theta = np.asarray(theta_df, dtype=np.float64).T

    return phi, theta


run_runner("bigartm", fit, lambda: artm.version())
