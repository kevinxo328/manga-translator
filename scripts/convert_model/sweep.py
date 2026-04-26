#!/usr/bin/env python3
"""Run conversion and verification sweeps for PaddleOCR-VL quantization experiments."""

import argparse
import json
import os
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
os.environ.setdefault("HF_HOME", str(SCRIPT_DIR / ".hf_cache"))

try:
    from .convert import MODEL_ID, run_conversion
    from .verify import (
        DEFAULT_MAX_CER_DELTA,
        DEFAULT_MAX_TOKENS,
        DEFAULT_PROMPT,
        evaluate_model_pair,
        load_crop_samples,
        load_page_samples,
    )
except ImportError:
    from convert import MODEL_ID, run_conversion
    from verify import (
        DEFAULT_MAX_CER_DELTA,
        DEFAULT_MAX_TOKENS,
        DEFAULT_PROMPT,
        evaluate_model_pair,
        load_crop_samples,
        load_page_samples,
    )


def parse_int_list(values: str) -> list[int]:
    return [int(value.strip()) for value in values.split(",") if value.strip()]


def parse_float_list(values: str) -> list[float]:
    return [float(value.strip()) for value in values.split(",") if value.strip()]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sweep PaddleOCR-VL quantization settings")
    dataset_group = parser.add_mutually_exclusive_group()
    dataset_group.add_argument(
        "--test-images",
        type=lambda p: Path(p).resolve(),
        default=SCRIPT_DIR.parent.parent / "test_images",
        help="Directory containing page-level test images",
    )
    dataset_group.add_argument(
        "--crop-manifest",
        type=lambda p: Path(p).resolve(),
        help="JSON manifest describing crop-level samples",
    )
    parser.add_argument(
        "--model-id",
        default=MODEL_ID,
        help="HuggingFace model ID to convert",
    )
    parser.add_argument(
        "--group-sizes",
        default="32,64,128",
        help="Comma-separated quantization group sizes",
    )
    parser.add_argument(
        "--crop-paddings",
        default="0.0",
        help="Comma-separated crop padding ratios",
    )
    parser.add_argument(
        "--output-root",
        type=lambda p: Path(p).resolve(),
        default=SCRIPT_DIR / "sweep_runs",
        help="Root directory for converted model variants and reports",
    )
    parser.add_argument(
        "--max-pixels",
        type=int,
        default=2822400,
        help="Max image pixels for inference",
    )
    parser.add_argument(
        "--prompt",
        action="append",
        dest="prompts",
        help="Prompt variant to test. Repeat to sweep multiple prompts.",
    )
    parser.add_argument(
        "--max-tokens",
        action="append",
        dest="max_tokens_values",
        type=int,
        help="Max token variant to test. Repeat to sweep multiple values.",
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.0,
        help="Sampling temperature for both models",
    )
    parser.add_argument(
        "--fail-threshold",
        type=float,
        default=DEFAULT_MAX_CER_DELTA,
        help="CER delta threshold used to mark a sample as failed",
    )
    parser.add_argument(
        "--skip-convert",
        action="store_true",
        help="Reuse existing converted outputs under --output-root",
    )
    parser.add_argument(
        "--q-bits",
        type=int,
        default=8,
        help="Quantization bit width (default: 8)",
    )
    return parser.parse_args()


def load_samples(args: argparse.Namespace):
    if args.crop_manifest is not None:
        return "crop", load_crop_samples(args.crop_manifest)
    return "page", load_page_samples(args.test_images)


def main() -> None:
    args = parse_args()
    group_sizes = parse_int_list(args.group_sizes)
    crop_paddings = parse_float_list(args.crop_paddings)
    prompts = args.prompts or [DEFAULT_PROMPT]
    max_tokens_values = args.max_tokens_values or [DEFAULT_MAX_TOKENS]

    dataset_mode, samples = load_samples(args)
    args.output_root.mkdir(parents=True, exist_ok=True)

    run_summaries = []
    for group_size in group_sizes:
        model_dir = args.output_root / f"q{args.q_bits}-g{group_size}"
        if not args.skip_convert:
            model_dir.mkdir(parents=True, exist_ok=True)
            run_conversion(
                model_id=args.model_id,
                output_dir=model_dir,
                quantize_bits=args.q_bits,
                group_size=group_size,
            )

        for crop_padding in crop_paddings:
            for prompt in prompts:
                for max_tokens in max_tokens_values:
                    records, summary = evaluate_model_pair(
                        samples=samples,
                        quantized_model_path=model_dir,
                        max_pixels=args.max_pixels,
                        prompt_text=prompt,
                        max_tokens=max_tokens,
                        temperature=args.temperature,
                        fail_threshold=args.fail_threshold,
                        crop_padding=crop_padding,
                    )
                    run_summaries.append(
                        {
                            "dataset_mode": dataset_mode,
                            "group_size": group_size,
                            "crop_padding": crop_padding,
                            "prompt": prompt,
                            "max_tokens": max_tokens,
                            "summary": summary,
                            "records": [record.sample_id for record in records],
                        }
                    )
                    print(
                        f"group_size={group_size} crop_padding={crop_padding:.2f} "
                        f"max_tokens={max_tokens} avg_cer={summary['avg_cer']:.4f} "
                        f"fails={summary['fail_count']} catastrophic={summary['catastrophic_count']}"
                    )

    summary_path = args.output_root / "sweep_summary.json"
    summary_path.write_text(json.dumps(run_summaries, ensure_ascii=False, indent=2))
    print(f"\n==> Sweep summary written to: {summary_path}")


if __name__ == "__main__":
    main()
