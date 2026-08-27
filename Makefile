# Reproduce the benchmark end to end:
#
#   make setup     one-time: GSL, R packages, Python venv, JDK + MALLET
#   make corpora   build and export the shared DTMs
#   make smoke     one cheap run per engine -- do this before `make run`
#   make run       the full grid (hours)
#   make score     compute R^2 and coherence -> results/runs.csv
#   make report    render the HTML writeup
#
# Everything is resumable: `make run` skips runs that already completed.

SHELL := /bin/bash
ROOT := $(shell pwd)
R := LDA_BENCH_ROOT=$(ROOT) Rscript

.PHONY: all setup corpora smoke run score report env clean-runs

all: corpora run score report

setup:
	bash setup/install-gsl.sh
	bash setup/install-java-mallet.sh
	bash setup/install-py-deps.sh
	$(R) setup/install-r-deps.R

corpora:
	source setup/env.sh && "$$LDA_BENCH_PYTHON" scripts/00-fetch-20ng.py
	$(R) scripts/01-build-corpora.R

smoke:
	$(R) scripts/02-run-grid.R --smoke

run:
	$(R) scripts/02-run-grid.R

score:
	$(R) scripts/03-score.R

report:
	$(R) -e 'rmarkdown::render("scripts/04-report.Rmd", output_dir = "results")'

env:
	$(R) scripts/99-record-env.R

clean-runs:
	rm -rf results/raw/*
