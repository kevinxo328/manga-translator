#!/usr/bin/env bash
# Remove all artifacts created by setup.sh and convert.py.
# This script only deletes files inside the project directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Removing virtual environment..."
rm -rf .venv

echo "==> Removing HuggingFace cache..."
rm -rf .hf_cache

echo "==> Removing MLX output..."
rm -rf mlx_output

echo "==> Teardown complete. All artifacts removed."
