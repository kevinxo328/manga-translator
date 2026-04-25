#!/usr/bin/env bash
# Set up a Python virtual environment for model conversion using uv.
# All HuggingFace downloads are stored locally in .hf_cache/ to avoid polluting
# the user's global cache.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Creating virtual environment with uv..."
uv venv .venv

echo "==> Installing dependencies..."
uv pip install -r requirements.txt

export HF_HOME="$SCRIPT_DIR/.hf_cache"
echo "==> HF_HOME set to $HF_HOME"

echo "==> Setup complete. Activate with: source .venv/bin/activate"
echo "    Remember to export HF_HOME=$SCRIPT_DIR/.hf_cache before running scripts."
