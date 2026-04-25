#!/usr/bin/env python3
"""Compare BF16 original vs quantized model on test images.

Exits non-zero if average character error rate (CER) delta exceeds 5%.
Uses temperature=0 (greedy), n-gram loop deduplication, and Unicode
normalization (…↔..., ！↔!, ？↔?) before comparison.

Usage:
    source .venv/bin/activate
    python verify.py \
        --test-images /abs/path/to/test_images \
        --quantized-model /abs/path/to/mlx_output

Speed tip: --max-pixels 1411200 (half of default 2822400) gives ~3x speedup
with minimal quality loss on full manga pages.
"""

import argparse
import gc
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
os.environ.setdefault("HF_HOME", str(SCRIPT_DIR / ".hf_cache"))

import editdistance  # noqa: E402
import mlx.core as mx  # noqa: E402
from mlx_vlm import generate, load  # noqa: E402
from mlx_vlm.prompt_utils import apply_chat_template  # noqa: E402
from mlx_vlm.utils import load_config  # noqa: E402

MODEL_ID = "jzhang533/PaddleOCR-VL-For-Manga"
MAX_CER_DELTA = 0.05


def normalize_text(text: str) -> str:
    """Normalize Unicode punctuation variants before CER comparison."""
    return text.replace("…", "...").replace("……", "......").replace("！", "!").replace("？", "?")


def compute_cer(reference: str, hypothesis: str) -> float:
    """Compute character error rate between reference and hypothesis."""
    reference = normalize_text(reference)
    hypothesis = normalize_text(hypothesis)
    if len(reference) == 0:
        return 0.0 if len(hypothesis) == 0 else 1.0
    return editdistance.eval(reference, hypothesis) / len(reference)


def remove_ngram_loops(text: str, min_phrase_len: int = 8, max_gap: int = 100) -> str:
    """Remove repeated phrase loops from OCR output.

    Finds the longest phrase (>= min_phrase_len chars) that appears twice
    with a gap of at most max_gap chars between the end of the first
    occurrence and the start of the second, then truncates at the second
    occurrence. Short tokens like '!' and '...' are left untouched.
    """
    for phrase_len in range(len(text) // 2, min_phrase_len - 1, -1):
        for start in range(len(text) - phrase_len * 2 + 1):
            phrase = text[start : start + phrase_len]
            second = text.find(phrase, start + phrase_len)
            if second != -1:
                gap_len = second - (start + phrase_len)
                if gap_len <= max_gap:
                    return text[:second].rstrip()
    return text


def run_batch(model_path: str, images: list[Path], max_pixels: int) -> list[str]:
    """Load a model, run inference on all images, then unload."""
    model, processor = load(model_path, trust_remote_code=True)
    config = load_config(model_path, trust_remote_code=True)
    processor.image_processor.max_pixels = max_pixels
    raw_prompt = "OCR the text in this image."
    prompt = apply_chat_template(processor, config, raw_prompt, num_images=1)

    results = []
    for img_path in images:
        result = generate(
            model,
            processor,
            image=str(img_path),
            prompt=prompt,
            max_tokens=500,
            temperature=0,
            verbose=False,
        )
        results.append(remove_ngram_loops(result.text.strip()))

    # Unload model before loading the next one
    del model, processor
    gc.collect()
    mx.clear_cache()
    return results


def find_test_images(test_dir: Path) -> list[Path]:
    """Find image files in the test directory."""
    extensions = {".png", ".jpg", ".jpeg", ".webp"}
    images = []
    for f in sorted(test_dir.iterdir()):
        if f.suffix.lower() in extensions and f.is_file():
            images.append(f)
    return images


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify quantized model quality")
    parser.add_argument(
        "--test-images",
        type=lambda p: Path(p).resolve(),
        default=SCRIPT_DIR.parent.parent / "test_images",
        help="Absolute path to directory containing test images",
    )
    parser.add_argument(
        "--quantized-model",
        type=lambda p: Path(p).resolve(),
        default=SCRIPT_DIR / "mlx_output",
        help="Absolute path to quantized MLX model directory",
    )
    parser.add_argument(
        "--max-pixels",
        type=int,
        default=2822400,
        help="Max image pixels for vision encoder (default: 2822400). Use 1411200 for ~3x speedup.",
    )
    args = parser.parse_args()

    if not args.test_images.is_dir():
        print(f"Error: test images directory not found: {args.test_images}")
        sys.exit(1)

    if not args.quantized_model.is_dir():
        print(f"Error: quantized model directory not found: {args.quantized_model}")
        sys.exit(1)

    images = find_test_images(args.test_images)
    if not images:
        print(f"Error: no images found in {args.test_images}")
        sys.exit(1)

    print(f"==> Running original model: {MODEL_ID} (max_pixels={args.max_pixels})")
    orig_texts = run_batch(MODEL_ID, images, args.max_pixels)

    print(f"==> Running quantized model: {args.quantized_model} (max_pixels={args.max_pixels})")
    quant_texts = run_batch(str(args.quantized_model), images, args.max_pixels)

    cer_deltas = []
    print(f"\n==> Results ({len(images)} images):\n")

    for img_path, orig_text, quant_text in zip(images, orig_texts, quant_texts):
        cer_delta = compute_cer(orig_text, quant_text)
        status = "PASS" if cer_delta <= MAX_CER_DELTA else "FAIL"
        print(f"  [{status}] {img_path.name}")
        print(f"    Original:  {orig_text!r}")
        print(f"    Quantized: {quant_text!r}")
        print(f"    CER delta: {cer_delta:.4f}")
        print()
        cer_deltas.append(cer_delta)

    avg_cer_delta = sum(cer_deltas) / len(cer_deltas)
    max_cer_delta = max(cer_deltas)

    print(f"==> Summary:")
    print(f"    Average CER delta: {avg_cer_delta:.4f}")
    print(f"    Max CER delta:     {max_cer_delta:.4f}")
    print(f"    Threshold:         {MAX_CER_DELTA:.4f}")

    if avg_cer_delta > MAX_CER_DELTA:
        print(f"\n    FAILED: Average CER delta {avg_cer_delta:.4f} exceeds threshold {MAX_CER_DELTA}")
        sys.exit(1)
    else:
        print(f"\n    PASSED: Average CER delta within threshold")
        sys.exit(0)


if __name__ == "__main__":
    main()
