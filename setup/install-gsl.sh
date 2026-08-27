#!/usr/bin/env bash
# Build GSL into ~/opt/gsl without root.
#
# topicmodels' src/ctm.c unconditionally includes <gsl/gsl_rng.h>, so the whole
# package fails to compile without GSL even though we only ever call LDA(). No
# passwordless sudo here, so we build it ourselves. topicmodels' configure finds
# it via gsl-config on PATH; we also bake an rpath so the resulting .so loads
# without LD_LIBRARY_PATH gymnastics in every runner.
set -euo pipefail

OPT="$HOME/opt"
PREFIX="$OPT/gsl"
GSL_VERSION="2.8"
SRC="$OPT/src"

if [ -x "$PREFIX/bin/gsl-config" ]; then
  echo "gsl already built: $("$PREFIX/bin/gsl-config" --version)"
  exit 0
fi

mkdir -p "$SRC"
cd "$SRC"

# ftp.gnu.org itself is unreachable from this host, so try mirrors in turn.
MIRRORS=(
  "https://mirrors.kernel.org/gnu/gsl/gsl-${GSL_VERSION}.tar.gz"
  "https://ftpmirror.gnu.org/gsl/gsl-${GSL_VERSION}.tar.gz"
  "https://ftp.gnu.org/gnu/gsl/gsl-${GSL_VERSION}.tar.gz"
)
if [ ! -s "gsl-${GSL_VERSION}.tar.gz" ]; then
  for url in "${MIRRORS[@]}"; do
    echo "downloading gsl ${GSL_VERSION} from ${url}..."
    if curl -fsSL --connect-timeout 20 "$url" -o "gsl-${GSL_VERSION}.tar.gz"; then
      break
    fi
    rm -f "gsl-${GSL_VERSION}.tar.gz"
  done
fi
if [ ! -s "gsl-${GSL_VERSION}.tar.gz" ]; then
  echo "could not download gsl from any mirror" >&2
  exit 1
fi

rm -rf "gsl-${GSL_VERSION}"
tar -xzf "gsl-${GSL_VERSION}.tar.gz"
cd "gsl-${GSL_VERSION}"

./configure --prefix="$PREFIX" --quiet
make -j"$(nproc)" -s
make install -s

echo "gsl: $("$PREFIX/bin/gsl-config" --version)"
echo "gsl OK"
