#!/usr/bin/env python3
"""Download PaddleOCR-VL-For-Manga and convert to MLX quantized format.

Uses mlx_vlm's native conversion pipeline to ensure compatibility with
mlx_vlm inference. 4-bit quantization produces only newlines for this model
architecture and is unusable; 8-bit is the minimum viable quantization.

Usage:
    source .venv/bin/activate
    python convert.py
"""

import argparse
import hashlib
import os
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
os.environ.setdefault("HF_HOME", str(SCRIPT_DIR / ".hf_cache"))

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


def run_conversion(model_id: str, output_dir: Path, quantize_bits: int, group_size: int) -> str:
    """Run MLX conversion and return the output directory checksum."""
    from mlx_vlm.convert import convert

    print(f"==> Converting {model_id}")
    print(f"    Output: {output_dir}")
    print(f"    Quantization: {quantize_bits}-bit, group_size={group_size}")
    print(f"    HF_HOME: {os.environ['HF_HOME']}")

    convert(
        hf_path=model_id,
        mlx_path=str(output_dir),
        quantize=True,
        q_bits=quantize_bits,
        q_group_size=group_size,
        trust_remote_code=True,
    )

    checksum = sha256_directory(output_dir)
    print(f"\n==> Conversion complete.")
    print(f"    Output directory: {output_dir}")
    print(f"    SHA256 (all files): {checksum}")

    checksum_file = output_dir / "SHA256SUMS"
    checksum_file.write_text(f"{checksum}  .\n")
    print(f"    Checksum written to: {checksum_file}")

    total_size = sum(f.stat().st_size for f in output_dir.rglob("*") if f.is_file())
    print(f"    Total size: {total_size / (1024 * 1024):.1f} MB")
    return checksum


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert PaddleOCR-VL-For-Manga to MLX format")
    parser.add_argument(
        "--model-id",
        default=MODEL_ID,
        help="HuggingFace model ID to convert",
    )
    parser.add_argument(
        "--output-dir",
        type=lambda p: Path(p).resolve(),
        default=OUTPUT_DIR,
        help="Output directory for the converted MLX model",
    )
    parser.add_argument(
        "--q-bits",
        type=int,
        default=QUANTIZE_BITS,
        help="Quantization bit width (default: 8)",
    )
    parser.add_argument(
        "--group-size",
        type=int,
        default=GROUP_SIZE,
        help="Quantization group size (default: 64)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    run_conversion(
        model_id=args.model_id,
        output_dir=args.output_dir,
        quantize_bits=args.q_bits,
        group_size=args.group_size,
    )


if __name__ == "__main__":
    main()
