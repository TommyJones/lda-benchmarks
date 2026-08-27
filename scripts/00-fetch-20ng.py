#!/usr/bin/env python
"""Fetch and vectorize 20 Newsgroups once, in Python.

The corpus only exists behind sklearn's downloader, so Python builds it and
writes a Matrix Market DTM plus a vocabulary file. R reads those back as the
canonical corpus in 01-build-corpora.R. Doing it this way -- rather than
tokenizing separately in each language -- is what guarantees every engine sees
byte-identical input.
"""
import os
import sys

import numpy as np
import scipy.io
import scipy.sparse
from sklearn.datasets import fetch_20newsgroups
from sklearn.feature_extraction.text import CountVectorizer

ROOT = os.environ.get(
    "LDA_BENCH_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
OUT = os.path.join(ROOT, "data", "20ng")


def main():
    os.makedirs(OUT, exist_ok=True)
    target = os.path.join(OUT, "raw-dtm.mtx")
    if os.path.exists(target) and "--force" not in sys.argv:
        print("20ng already fetched; pass --force to rebuild")
        return

    print("fetching 20 newsgroups...")
    data = fetch_20newsgroups(
        subset="all",
        remove=("headers", "footers", "quotes"),
        shuffle=False,
    )

    # Deliberately plain preprocessing: lowercase alphabetic tokens of 3+ chars,
    # English stopwords out, terms in fewer than 5 documents or more than half of
    # them out. Nothing clever -- the benchmark is about samplers, not pipelines.
    vec = CountVectorizer(
        lowercase=True,
        token_pattern=r"(?u)\b[a-z][a-z][a-z]+\b",
        stop_words="english",
        min_df=5,
        max_df=0.5,
    )
    dtm = vec.fit_transform(data.data)
    vocab = vec.get_feature_names_out()

    # Drop documents that ended up empty; an all-zero row is undefined for
    # theta and several engines choke on it.
    keep = np.asarray(dtm.sum(axis=1)).ravel() > 0
    dtm = dtm[keep]

    dtm = scipy.sparse.csr_matrix(dtm, dtype=np.int32)
    print(f"20ng: {dtm.shape[0]} docs x {dtm.shape[1]} terms, "
          f"{dtm.nnz} nonzero, {int(dtm.sum())} tokens")

    scipy.io.mmwrite(os.path.join(OUT, "raw-dtm.mtx"), dtm, field="integer")
    with open(os.path.join(OUT, "raw-vocab.txt"), "w") as f:
        f.write("\n".join(vocab) + "\n")
    with open(os.path.join(OUT, "raw-docids.txt"), "w") as f:
        f.write("\n".join(f"doc_{i}" for i in np.flatnonzero(keep)) + "\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
