#!/usr/bin/env bash
# Create an isolated venv for the Python contenders so we don't perturb the
# user's jupyter environment, and so the versions we report are the versions
# that actually ran.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$ROOT/.venv"

if [ ! -d "$VENV" ]; then
  python3 -m venv "$VENV"
fi

"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet \
  "numpy" \
  "scipy" \
  "scikit-learn" \
  "gensim" \
  "tomotopy"

"$VENV/bin/python" -c "
import gensim, sklearn, tomotopy, numpy, scipy
print('gensim', gensim.__version__)
print('sklearn', sklearn.__version__)
print('tomotopy', tomotopy.__version__)
print('numpy', numpy.__version__)
print('scipy', scipy.__version__)
"
echo "python deps OK"
