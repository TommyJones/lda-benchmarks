# LDA implementations in R and Python: a bake-off

Where does [tidylda](https://github.com/TommyJones/tidylda) sit in the wider topic-modeling
ecosystem? This repo measures ten LDA implementations across R, Python and Java on the same
corpora, with the same hyperparameters, scored by the same code.

This is blog-post rigor, not paper rigor: one machine, one run of each configuration (three
where the corpus is cheap enough), no statistical testing. It is meant to give an honest sense
of the landscape, not to establish a ranking that would survive peer review.

## What is compared

| Engine | Language | Family | Threads |
|---|---|---|---|
| tidylda | R | WarpLDA (Metropolis-Hastings) | `threads` |
| text2vec | R | WarpLDA | OpenMP |
| textmineR | R | collapsed Gibbs | `cpus` |
| topicmodels (Gibbs) | R | collapsed Gibbs | 1 |
| topicmodels (VEM) | R | variational EM | 1 |
| lda (Chang) | R | collapsed Gibbs | 1 |
| MALLET | Java | collapsed Gibbs | `--num-threads` |
| gensim | Python | online variational Bayes | `workers` |
| scikit-learn | Python | online variational Bayes | `n_jobs` |
| tomotopy | Python | collapsed Gibbs | `workers` |

The inclusion criterion is *popular and easy to use from R or Python*. Faster implementations
exist — the reference WarpLDA code beats everything here — but they are not something you can
`install.packages()` or `pip install` and call from a normal analysis, so they are out of scope.

`stm` is excluded: it is a different model, not an LDA implementation. Transfer learning, which
only tidylda offers, is also out of scope — this is about the common case.

Worth knowing before reading the results: **tidylda 0.1.0 is a WarpLDA sampler, not collapsed
Gibbs** (that changed after 0.0.7). Its closest algorithmic neighbor here is therefore text2vec,
not textmineR. As of this writing CRAN still carries tidylda 0.0.7, so the benchmark installs
0.1.0 from source and records the commit in `results/env/tidylda-provenance.txt`.

## How the comparison is kept fair

**One shared DTM.** Every engine fits the same `dgCMatrix` with the same vocabulary in the same
column order. Python and MALLET are handed that vocabulary index directly rather than tokenizing
for themselves.

**One scorer.** No engine reports its own numbers. Every run writes back `phi` (k × V) and
`theta` (D × k); `scripts/03-score.R` normalizes them, asserts they satisfy the contract, and
pushes all of them through the same two functions:

- **Probabilistic coherence** — `tidylda::calc_prob_coherence(beta, dtm, m = 5)`, averaged over topics.
- **R²** — `mvrsquared::calc_rsquared(y = dtm, yhat = list(x = rowSums(dtm) * theta, w = phi))`.

Both are in-sample, computed on the training DTM. That is how tidylda reports them natively.

**Identical hyperparameters, no tuning.** `alpha = 0.1` per topic, `eta`/`beta = 0.05`, and every
engine's hyperparameter optimizer explicitly disabled. Where a package has a different convention,
the runner converts: MALLET's `--alpha` is the sum over topics, so it gets `k * 0.1`.

**Quality against wall-clock time, not against iterations.** A Gibbs sweep and a variational pass
are different units of work, so "200 iterations each" would not be a fair comparison — it would
just be a comparison of two arbitrary numbers. Instead each engine is run at a ladder of
iteration counts and we plot what quality it reached against how long it took. The comparison is
which curve dominates.

**The iteration axis is not comparable across engines, and one case is worse than it looks.**
Beyond the Gibbs-vs-variational mismatch, `text2vec`'s `fit_transform(n_iter = N)` runs N
sampling passes with `update_topics = TRUE` and then, inside `transform_internal()`, a *second*
run of N passes with topics frozen to infer the document-topic matrix. At the same nominal
`n_iter` it therefore does roughly twice the passes of every other engine here. This does not
affect the quality-vs-time frontier, which plots measured time against measured quality and
never uses the iteration count as an axis — but it does mean no per-iteration claim should be
made from the raw `iters` column.

**One OS process per run**, launched under `/usr/bin/time -v`. That puts peak RSS on the same
footing across R, Python and the JVM, and stops runs from contaminating each other.

Two clocks are recorded. `fit_sec` is measured inside the runner and spans "here is the shared
DTM" through "training complete" — reshaping the matrix into whatever form the package demands is
included, because that is a real cost of using the package; extracting `phi`/`theta` afterwards
is excluded, because for some engines (gensim especially) that is an extra inference pass that
only our measurement protocol asks for. `wall_sec` is the whole process including interpreter
startup, which is why the report shows a baseline row per language.

## Corpora

| | docs | terms | tokens |
|---|---|---|---|
| `nih` (smoke test only) | 99 | 1,309 | 14,318 |
| `ap` (Associated Press, ships with topicmodels) | 2,242 | 9,172 | 424,341 |
| `20ng` (20 Newsgroups via sklearn) | 17,669 | 20,926 | 1,456,595 |

Both real corpora are pruned identically: terms in fewer than 5 documents or more than half of
them are dropped, then documents under 5 tokens, iterated to a fixed point.

## Reproducing

```bash
make setup     # GSL, R packages, Python venv, JDK + MALLET -- all into ~/opt, no root
make corpora
make smoke     # one cheap run per engine; do this first
make run       # the full grid, resumable
make score     # -> results/runs.csv
make report    # -> results/04-report.html
```

`scripts/98-verify.R` checks the apparatus itself: that our scoring reproduces tidylda's own
native R² and coherence exactly, and that tidylda really is invariant to `threads` as documented.
Both hold — which is what makes the thread sweep a pure wall-clock axis for tidylda, and the
contrast worth drawing against MALLET's and tomotopy's approximate parallel samplers, whose
quality the sweep reports alongside their speed.

## Caveats

- One machine (24 cores, 125 GB), one OS, one set of library versions. See `results/env/`.
- Metrics are in-sample. A held-out comparison would be a different, larger project.
- Coherence and R² measure different things and do not have to agree; both are reported.
- Peak RSS includes interpreter and JVM baseline. The report shows those baselines rather than
  silently subtracting them.
- `fit_sec` for MALLET is measured around the `train-topics` subprocess and so includes JVM
  startup; its corpus import step is excluded as corpus preparation.
