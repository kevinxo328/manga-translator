#!/usr/bin/env python3
"""Download PaddleOCR-VL-For-Manga and convert to 8-bit MLX quantized format.

Uses mlx_vlm's native conversion pipeline to ensure compatibility with
mlx_vlm inference. 4-bit quantization produces only newlines for this model
architecture and is unusable; 8-bit is the minimum viable quantization.

Usage:
    source .venv/bin/activate
    python convert.py
"""

import hashlib
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
os.environ.setdefault("HF_HOME", str(SCRIPT_DIR / ".hf_cache"))

from mlx_vlm.convert import convert  # noqa: E402

MODEL_ID = "jzhang533/PaddleOCR-VL-For-Manga"
OUTPUT_DIR = SCRIPT_DIR / "mlx_output"
QUANTIZE_BITS = 8
GROUP_SIZE = 64


def sha256_directory(directory: Path) -> str:
    """Compute a SHA256 hash over all files in a directory (sorted by name)."""
    h = hashlib.sha256()
    for fpath in sorted(directory.rglob("*")):
        if fpath.is_file():
            h.update(fpath.read_bytes())
    return h.hexdigest()


def main() -> None:
    print(f"==> Converting {MODEL_ID}")
    print(f"    Output: {OUTPUT_DIR}")
    print(f"    Quantization: {QUANTIZE_BITS}-bit, group_size={GROUP_SIZE}")
    print(f"    HF_HOME: {os.environ['HF_HOME']}")

    convert(
        hf_path=MODEL_ID,
        mlx_path=str(OUTPUT_DIR),
        quantize=True,
        q_bits=QUANTIZE_BITS,
        q_group_size=GROUP_SIZE,
        trust_remote_code=True,
    )

    checksum = sha256_directory(OUTPUT_DIR)
    print(f"\n==> Conversion complete.")
    print(f"    Output directory: {OUTPUT_DIR}")
    print(f"    SHA256 (all files): {checksum}")

    checksum_file = OUTPUT_DIR / "SHA256SUMS"
    checksum_file.write_text(f"{checksum}  .\n")
    print(f"    Checksum written to: {checksum_file}")

    total_size = sum(f.stat().st_size for f in OUTPUT_DIR.rglob("*") if f.is_file())
    print(f"    Total size: {total_size / (1024 * 1024):.1f} MB")


if __name__ == "__main__":
    main()
