#!/usr/bin/env bash
# Build Vowpal Wabbit's CLI into ~/opt/vw, without root.
#
# VW is in this benchmark only through its command line. Its Python bindings
# cannot drive LDA at all -- Workspace.example(), learn() and predict() each
# raise "unsupported label parser used", because LDA has no label parser -- and
# the pip wheel ships no binary. So using VW's LDA from Python requires building
# it, which is itself worth knowing when judging what counts as "readily
# available off the shelf".
set -euo pipefail

OPT="$HOME/opt"
SRC="$OPT/src/vowpal_wabbit"
VERSION="9.11.2"

if [ -x "$OPT/vw/bin/vw" ]; then
  echo "vw already built: $("$OPT/vw/bin/vw" --version | head -1)"
  exit 0
fi

mkdir -p "$OPT/src" "$OPT/vw/bin"

if [ ! -d "$SRC" ]; then
  # --recursive: VW vendors fmt, spdlog, rapidjson and others as submodules.
  # The tags are bare version numbers, not v-prefixed.
  git clone -q --depth 1 --branch "$VERSION" --recursive \
    https://github.com/VowpalWabbit/vowpal_wabbit.git "$SRC"
fi

cd "$SRC"
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=OFF \
  -DVW_BUILD_VW_C_WRAPPER=OFF \
  -DUSE_LATEST_STD=On > /dev/null

# The CLI target is vw_cli_bin in 9.x (it was vw-bin in older releases).
cmake --build build --target vw_cli_bin -j "$(nproc)" > /dev/null

cp build/vowpalwabbit/cli/vw "$OPT/vw/bin/vw"
echo "vw: $("$OPT/vw/bin/vw" --version | head -1)"
echo "vw OK"
