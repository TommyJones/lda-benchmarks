#!/usr/bin/env python
"""Vowpal Wabbit -- online variational Bayes LDA, driven through the CLI.

VW's Python bindings cannot drive LDA: every path through Workspace.example(),
learn() and predict() raises "unsupported label parser used", because LDA has no
label parser. The pip wheel also ships no binary. So this runner shells out to a
`vw` built from source (setup/install-vw.sh), the same way the MALLET runner
does. That is worth recording as a usability fact about VW, not just an
implementation detail of this benchmark.

TWO THINGS MAKE THE VOCABULARY ALIGNMENT EXACT.

VW hashes feature names into 2^b slots, which would collide badly at our
vocabulary sizes (~835 expected collisions for V=20926 at b=18). But VW uses a
feature name that parses as an integer AS the index directly, without hashing.
So documents are emitted as `| <vocab_index>:<count> ...` and every term lands
on its own slot, provided 2^b > V -- checked below.

The weights VW reports are unnormalized (counts plus the prior, plus the random
initialization it gives unused slots), for both phi and theta. run_runner
normalizes both, so only the alignment has to be right here.
"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import ALPHA, ETA, run_runner  # noqa: E402

VW_BIN = os.path.expanduser("~/opt/vw/bin/vw")


def _vw_version():
    out = subprocess.run([VW_BIN, "--version"], capture_output=True, text=True)
    return out.stdout.strip().split()[0]


def fit(dtm, vocab, k, iters, threads, seed, timer):
    if not os.path.exists(VW_BIN):
        raise RuntimeError(f"vw binary not found at {VW_BIN}; run setup/install-vw.sh")

    V = len(vocab)
    bits = max(16, int(np.ceil(np.log2(V))) + 1)
    assert 2 ** bits > V, "bit precision too small: features would collide"

    work = tempfile.mkdtemp(prefix="vw-")
    data = os.path.join(work, "docs.vw")
    model = os.path.join(work, "model.vw")
    readable = os.path.join(work, "readable.txt")
    cache = os.path.join(work, "docs.cache")
    pred = os.path.join(work, "pred.txt")

    dtm = dtm.tocsr()
    D = dtm.shape[0]

    # Writing VW's text format is a real cost of using VW, so it is inside the
    # timed region -- same rule the other runners follow for reshaping input.
    with open(data, "w") as f:
        for d in range(D):
            lo, hi = dtm.indptr[d], dtm.indptr[d + 1]
            feats = " ".join(f"{i}:{c}" for i, c in
                             zip(dtm.indices[lo:hi], dtm.data[lo:hi]))
            f.write(f"| {feats}\n")

    # --minibatch/--power_t/--initial_t are the values in VW's own documented
    # LDA example, not tuning of ours. At VW's bare defaults (minibatch 1) the
    # online learning rate decays so fast that the model stops changing: 5 and
    # 25 passes gave indistinguishable output (mean theta entropy 2.359 vs
    # 2.361) even though the run took 3x longer. Measured both ways on AP at
    # k=100, 25 passes: bare defaults r2 0.0817 / coherence 0.0272, documented
    # settings r2 0.0625 / coherence 0.0550. We take the documented settings as
    # the more charitable configuration. Neither is close to the other engines,
    # so the conclusion does not rest on the choice.
    train = [
        VW_BIN, "--lda", str(k),
        "--lda_alpha", str(ALPHA),
        "--lda_rho", str(ETA),
        "--lda_D", str(D),
        "-b", str(bits),
        "--passes", str(iters),
        "--minibatch", "256", "--power_t", "0.5", "--initial_t", "1",
        "-k", "--cache_file", cache,
        "--random_seed", str(seed),
        "-d", data, "-f", model,
        "--readable_model", readable,
        "--quiet",
    ]
    r = subprocess.run(train, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"vw training failed:\n{r.stderr[-2000:]}")
    timer.stop()

    # --- phi: parse the readable model -----------------------------------------
    # Body lines are "<index> <w_1> ... <w_k>"; the header ends at "Checksum:".
    phi = np.zeros((k, V), dtype=np.float64)
    with open(readable) as f:
        body = False
        for line in f:
            if not body:
                if line.startswith("Checksum:"):
                    body = True
                continue
            parts = line.split()
            if len(parts) != k + 1:
                continue
            idx = int(parts[0])
            if idx < V:  # slots beyond the vocabulary are unused padding
                phi[:, idx] = np.asarray(parts[1:], dtype=np.float64)

    # --- theta: a scoring pass, outside the timed region ------------------------
    # This is an extra inference pass that only our measurement protocol asks
    # for, so it is excluded from the clock exactly as gensim's is.
    r = subprocess.run(
        [VW_BIN, "-i", model, "-t", "-d", data, "-p", pred, "--quiet"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        raise RuntimeError(f"vw prediction failed:\n{r.stderr[-2000:]}")

    theta = np.zeros((D, k), dtype=np.float64)
    with open(pred) as f:
        for i, line in enumerate(f):
            vals = line.split()
            if i < D and len(vals) == k:
                theta[i] = np.asarray(vals, dtype=np.float64)

    return phi, theta


run_runner("vowpalwabbit", fit, _vw_version)
