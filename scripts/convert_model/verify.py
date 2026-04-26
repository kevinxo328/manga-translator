#!/usr/bin/env python3
"""Evaluate BF16 vs quantized PaddleOCR-VL on page-level or crop-level datasets.

The default mode compares full-page images under ``test_images/``. Crop mode reads
samples from a JSON manifest and measures recognizer drift on production-like text
regions. The script can optionally compare either model output against a provided
ground-truth string per crop.
"""

import argparse
import csv
import gc
import json
import math
import os
import sys
import tempfile
from collections import Counter
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).parent.resolve()
os.environ.setdefault("HF_HOME", str(SCRIPT_DIR / ".hf_cache"))

MODEL_ID = "jzhang533/PaddleOCR-VL-For-Manga"
DEFAULT_MAX_CER_DELTA = 0.05
DEFAULT_PROMPT = "OCR the text in this image."
DEFAULT_MAX_TOKENS = 500


@dataclass(frozen=True)
class CropBox:
    x: int
    y: int
    width: int
    height: int


@dataclass(frozen=True)
class Sample:
    sample_id: str
    image_path: Path
    mode: str
    crop_box: CropBox | None = None
    reference_text: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class PreparedSample:
    sample: Sample
    prepared_image_path: Path


@dataclass(frozen=True)
class ModelOutput:
    text: str
    raw_text: str
    loop_detected: bool


@dataclass(frozen=True)
class EvaluationRecord:
    sample_id: str
    mode: str
    image_path: str
    prepared_image_path: str
    crop_box: list[int] | None
    crop_padding: float
    reference_source: str
    original_text: str
    quantized_text: str
    cer_delta: float
    original_loop_detected: bool
    quantized_loop_detected: bool
    empty_output: bool
    ordering_mismatch: bool
    catastrophic: bool
    original_cer_to_gt: float | None = None
    quantized_cer_to_gt: float | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


def normalize_text(text: str) -> str:
    """Normalize punctuation and whitespace before comparison."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("…", "...").replace("……", "......").replace("！", "!").replace("？", "?")
    return "\n".join(line.rstrip() for line in text.splitlines()).strip()


def compute_cer(reference: str, hypothesis: str) -> float:
    """Compute character error rate between reference and hypothesis."""
    import editdistance

    reference = normalize_text(reference)
    hypothesis = normalize_text(hypothesis)
    if len(reference) == 0:
        return 0.0 if len(hypothesis) == 0 else 1.0
    return editdistance.eval(reference, hypothesis) / len(reference)


def remove_ngram_loops(text: str, min_phrase_len: int = 8, max_gap: int = 100) -> tuple[str, bool]:
    """Trim repeated long phrases and return the cleaned text plus a detection flag."""
    for phrase_len in range(len(text) // 2, min_phrase_len - 1, -1):
        for start in range(len(text) - phrase_len * 2 + 1):
            phrase = text[start : start + phrase_len]
            second = text.find(phrase, start + phrase_len)
            if second != -1:
                gap_len = second - (start + phrase_len)
                if gap_len <= max_gap:
                    return text[:second].rstrip(), True
    return text, False


def percentile(values: list[float], q: float) -> float:
    """Compute a simple inclusive percentile for a non-empty list of floats."""
    if not values:
        return 0.0
    if len(values) == 1:
        return values[0]
    ordered = sorted(values)
    position = q * (len(ordered) - 1)
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] + (ordered[upper] - ordered[lower]) * fraction


def clamp_crop_box(box: CropBox, image_width: int, image_height: int) -> CropBox:
    """Clamp a crop box to image bounds."""
    x1 = max(0, min(box.x, image_width))
    y1 = max(0, min(box.y, image_height))
    x2 = max(x1, min(box.x + box.width, image_width))
    y2 = max(y1, min(box.y + box.height, image_height))
    return CropBox(x=x1, y=y1, width=max(0, x2 - x1), height=max(0, y2 - y1))


def expand_crop_box(box: CropBox, padding_ratio: float, image_width: int, image_height: int) -> CropBox:
    """Expand a crop box symmetrically by a ratio of its own width and height."""
    if padding_ratio <= 0:
        return clamp_crop_box(box, image_width, image_height)

    pad_x = int(round(box.width * padding_ratio))
    pad_y = int(round(box.height * padding_ratio))
    expanded = CropBox(
        x=box.x - pad_x,
        y=box.y - pad_y,
        width=box.width + pad_x * 2,
        height=box.height + pad_y * 2,
    )
    return clamp_crop_box(expanded, image_width, image_height)


def detect_ordering_mismatch(reference: str, hypothesis: str) -> bool:
    """Heuristically detect line-order changes without penalizing identical content."""
    normalized_reference = normalize_text(reference)
    normalized_hypothesis = normalize_text(hypothesis)
    if not normalized_reference or not normalized_hypothesis:
        return False
    if normalized_reference == normalized_hypothesis:
        return False

    ref_lines = [line.strip() for line in normalized_reference.splitlines() if line.strip()]
    hyp_lines = [line.strip() for line in normalized_hypothesis.splitlines() if line.strip()]
    if len(ref_lines) < 2 or len(ref_lines) != len(hyp_lines):
        return False

    return Counter(ref_lines) == Counter(hyp_lines)


def classify_record(
    sample: Sample,
    original_output: ModelOutput,
    quantized_output: ModelOutput,
    cer_delta: float,
    fail_threshold: float,
    reference_source: str,
) -> EvaluationRecord:
    """Build a structured evaluation record with failure annotations."""
    ordering_mismatch = False
    if sample.mode == "page":
        ordering_mismatch = detect_ordering_mismatch(original_output.text, quantized_output.text)

    empty_output = not quantized_output.text.strip()
    catastrophic = (
        cer_delta >= max(fail_threshold * 4, 0.25)
        or empty_output
        or quantized_output.loop_detected
    )

    original_cer_to_gt = None
    quantized_cer_to_gt = None
    if sample.reference_text is not None:
        original_cer_to_gt = compute_cer(sample.reference_text, original_output.text)
        quantized_cer_to_gt = compute_cer(sample.reference_text, quantized_output.text)

    crop_box = None
    if sample.crop_box is not None:
        crop_box = [sample.crop_box.x, sample.crop_box.y, sample.crop_box.width, sample.crop_box.height]

    return EvaluationRecord(
        sample_id=sample.sample_id,
        mode=sample.mode,
        image_path=str(sample.image_path),
        prepared_image_path="",
        crop_box=crop_box,
        crop_padding=float(sample.metadata.get("crop_padding", 0.0)),
        reference_source=reference_source,
        original_text=original_output.text,
        quantized_text=quantized_output.text,
        cer_delta=cer_delta,
        original_loop_detected=original_output.loop_detected,
        quantized_loop_detected=quantized_output.loop_detected,
        empty_output=empty_output,
        ordering_mismatch=ordering_mismatch,
        catastrophic=catastrophic,
        original_cer_to_gt=original_cer_to_gt,
        quantized_cer_to_gt=quantized_cer_to_gt,
        metadata=sample.metadata,
    )


def summarize_records(records: list[EvaluationRecord], fail_threshold: float) -> dict[str, Any]:
    """Summarize evaluation metrics across all records."""
    cer_values = [record.cer_delta for record in records]
    summary = {
        "sample_count": len(records),
        "avg_cer": sum(cer_values) / len(cer_values) if cer_values else 0.0,
        "median_cer": percentile(cer_values, 0.5),
        "p90_cer": percentile(cer_values, 0.9),
        "max_cer": max(cer_values) if cer_values else 0.0,
        "fail_threshold": fail_threshold,
        "fail_count": sum(1 for record in records if record.cer_delta > fail_threshold),
        "catastrophic_count": sum(1 for record in records if record.catastrophic),
        "ordering_mismatch_count": sum(1 for record in records if record.ordering_mismatch),
        "empty_output_count": sum(1 for record in records if record.empty_output),
        "quantized_loop_count": sum(1 for record in records if record.quantized_loop_detected),
    }

    gt_records = [record for record in records if record.quantized_cer_to_gt is not None]
    if gt_records:
        summary["avg_quantized_cer_to_gt"] = sum(record.quantized_cer_to_gt for record in gt_records if record.quantized_cer_to_gt is not None) / len(gt_records)
        summary["avg_original_cer_to_gt"] = sum(record.original_cer_to_gt for record in gt_records if record.original_cer_to_gt is not None) / len(gt_records)

    return summary


def load_page_samples(test_dir: Path) -> list[Sample]:
    """Load full-page image samples from a directory."""
    extensions = {".png", ".jpg", ".jpeg", ".webp"}
    samples = []
    for image_path in sorted(test_dir.iterdir()):
        if image_path.is_file() and image_path.suffix.lower() in extensions:
            samples.append(Sample(sample_id=image_path.stem, image_path=image_path, mode="page"))
    return samples


def load_crop_samples(manifest_path: Path) -> list[Sample]:
    """Load crop samples from a JSON manifest."""
    payload = json.loads(manifest_path.read_text())
    raw_samples = payload.get("samples")
    if not isinstance(raw_samples, list):
        raise ValueError("crop manifest must contain a top-level 'samples' list")

    samples = []
    for index, raw_sample in enumerate(raw_samples):
        image_field = raw_sample.get("image")
        crop_field = raw_sample.get("crop")
        if not isinstance(image_field, str):
            raise ValueError(f"sample {index} missing string 'image'")
        if not isinstance(crop_field, list) or len(crop_field) != 4:
            raise ValueError(f"sample {index} missing four-element 'crop'")

        image_path = Path(image_field)
        if not image_path.is_absolute():
            image_path = (manifest_path.parent / image_path).resolve()

        sample_id = raw_sample.get("id") or f"{image_path.stem}-crop-{index + 1}"
        metadata = dict(raw_sample.get("metadata", {}))
        samples.append(
            Sample(
                sample_id=sample_id,
                image_path=image_path,
                mode="crop",
                crop_box=CropBox(
                    x=int(crop_field[0]),
                    y=int(crop_field[1]),
                    width=int(crop_field[2]),
                    height=int(crop_field[3]),
                ),
                reference_text=raw_sample.get("reference_text"),
                metadata=metadata,
            )
        )
    return samples


def prepare_samples(samples: list[Sample], crop_padding: float) -> list[PreparedSample]:
    """Prepare page images or cropped region images for inference."""
    if crop_padding < 0:
        raise ValueError("crop_padding must be non-negative")

    page_samples = [PreparedSample(sample=sample, prepared_image_path=sample.image_path) for sample in samples if sample.mode == "page"]
    crop_samples = [sample for sample in samples if sample.mode == "crop"]
    if not crop_samples:
        return page_samples

    from PIL import Image

    temp_dir = Path(tempfile.mkdtemp(prefix="paddleocr-vl-crops-"))
    prepared = list(page_samples)

    for sample in crop_samples:
        if sample.crop_box is None:
            raise ValueError(f"crop sample {sample.sample_id} is missing crop_box")
        with Image.open(sample.image_path) as image:
            width, height = image.size
            crop_box = expand_crop_box(sample.crop_box, crop_padding, width, height)
            if crop_box.width == 0 or crop_box.height == 0:
                raise ValueError(f"crop sample {sample.sample_id} produced an empty crop")

            cropped = image.crop((crop_box.x, crop_box.y, crop_box.x + crop_box.width, crop_box.y + crop_box.height))
            prepared_path = temp_dir / f"{sample.sample_id}{sample.image_path.suffix or '.png'}"
            cropped.save(prepared_path)

        updated_metadata = dict(sample.metadata)
        updated_metadata["crop_padding"] = crop_padding
        updated_sample = Sample(
            sample_id=sample.sample_id,
            image_path=sample.image_path,
            mode=sample.mode,
            crop_box=crop_box,
            reference_text=sample.reference_text,
            metadata=updated_metadata,
        )
        prepared.append(PreparedSample(sample=updated_sample, prepared_image_path=prepared_path))

    return prepared


def run_batch(
    model_path: str,
    images: list[Path],
    max_pixels: int,
    prompt_text: str,
    max_tokens: int,
    temperature: float,
) -> list[ModelOutput]:
    """Load a model, run inference on all images, then unload."""
    import mlx.core as mx
    from mlx_vlm import generate, load
    from mlx_vlm.prompt_utils import apply_chat_template
    from mlx_vlm.utils import load_config

    model, processor = load(model_path, trust_remote_code=True)
    config = load_config(model_path, trust_remote_code=True)
    processor.image_processor.max_pixels = max_pixels
    prompt = apply_chat_template(processor, config, prompt_text, num_images=1)

    results = []
    for img_path in images:
        result = generate(
            model,
            processor,
            image=str(img_path),
            prompt=prompt,
            max_tokens=max_tokens,
            temperature=temperature,
            verbose=False,
        )
        raw_text = result.text.strip()
        cleaned_text, loop_detected = remove_ngram_loops(raw_text)
        results.append(ModelOutput(text=cleaned_text, raw_text=raw_text, loop_detected=loop_detected))

    del model, processor
    gc.collect()
    mx.clear_cache()
    return results


def evaluate_model_pair(
    samples: list[Sample],
    quantized_model_path: Path,
    max_pixels: int,
    prompt_text: str,
    max_tokens: int,
    temperature: float,
    fail_threshold: float,
    crop_padding: float,
) -> tuple[list[EvaluationRecord], dict[str, Any]]:
    """Run BF16 and quantized inference and compute structured evaluation records."""
    prepared_samples = prepare_samples(samples, crop_padding)
    prepared_paths = [prepared.prepared_image_path for prepared in prepared_samples]
    original_outputs = run_batch(MODEL_ID, prepared_paths, max_pixels, prompt_text, max_tokens, temperature)
    quantized_outputs = run_batch(str(quantized_model_path), prepared_paths, max_pixels, prompt_text, max_tokens, temperature)

    records = []
    for prepared_sample, original_output, quantized_output in zip(prepared_samples, original_outputs, quantized_outputs):
        cer_delta = compute_cer(original_output.text, quantized_output.text)
        reference_source = "bf16"
        if prepared_sample.sample.reference_text is not None:
            reference_source = "bf16+ground_truth"
        record = classify_record(
            sample=prepared_sample.sample,
            original_output=original_output,
            quantized_output=quantized_output,
            cer_delta=cer_delta,
            fail_threshold=fail_threshold,
            reference_source=reference_source,
        )
        records.append(
            EvaluationRecord(
                **{
                    **asdict(record),
                    "prepared_image_path": str(prepared_sample.prepared_image_path),
                }
            )
        )

    summary = summarize_records(records, fail_threshold)
    return records, summary


def write_report_json(
    output_path: Path,
    dataset_mode: str,
    args: argparse.Namespace,
    records: list[EvaluationRecord],
    summary: dict[str, Any],
) -> None:
    """Write a machine-readable JSON report."""
    payload = {
        "config": {
            "dataset_mode": dataset_mode,
            "quantized_model": str(args.quantized_model),
            "max_pixels": args.max_pixels,
            "prompt": args.prompt,
            "max_tokens": args.max_tokens,
            "temperature": args.temperature,
            "crop_padding": args.crop_padding,
            "fail_threshold": args.fail_threshold,
        },
        "summary": summary,
        "records": [asdict(record) for record in records],
    }
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2))


def write_report_csv(output_path: Path, records: list[EvaluationRecord]) -> None:
    """Write a flat CSV report for spreadsheet analysis."""
    fieldnames = [
        "sample_id",
        "mode",
        "image_path",
        "prepared_image_path",
        "crop_box",
        "crop_padding",
        "reference_source",
        "cer_delta",
        "original_loop_detected",
        "quantized_loop_detected",
        "empty_output",
        "ordering_mismatch",
        "catastrophic",
        "original_cer_to_gt",
        "quantized_cer_to_gt",
    ]
    with output_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for record in records:
            row = {name: getattr(record, name) for name in fieldnames}
            row["crop_box"] = json.dumps(row["crop_box"]) if row["crop_box"] is not None else ""
            writer.writerow(row)


def print_human_report(records: list[EvaluationRecord], summary: dict[str, Any]) -> None:
    """Print a compact human-readable report."""
    print(f"==> Results ({len(records)} samples):\n")
    for record in records:
        status = "PASS" if record.cer_delta <= summary["fail_threshold"] else "FAIL"
        print(f"  [{status}] {record.sample_id} ({record.mode})")
        print(f"    Image:       {record.image_path}")
        if record.crop_box is not None:
            print(f"    Crop:        {record.crop_box} padding={record.crop_padding:.2f}")
        print(f"    Original:    {record.original_text!r}")
        print(f"    Quantized:   {record.quantized_text!r}")
        print(f"    CER delta:   {record.cer_delta:.4f}")
        flags = []
        if record.ordering_mismatch:
            flags.append("ordering-mismatch")
        if record.quantized_loop_detected:
            flags.append("quantized-loop")
        if record.empty_output:
            flags.append("empty-output")
        if record.catastrophic:
            flags.append("catastrophic")
        if flags:
            print(f"    Flags:       {', '.join(flags)}")
        if record.quantized_cer_to_gt is not None and record.original_cer_to_gt is not None:
            print(f"    GT CER:      orig={record.original_cer_to_gt:.4f} quant={record.quantized_cer_to_gt:.4f}")
        print()

    print("==> Summary:")
    print(f"    Average CER delta:     {summary['avg_cer']:.4f}")
    print(f"    Median CER delta:      {summary['median_cer']:.4f}")
    print(f"    P90 CER delta:         {summary['p90_cer']:.4f}")
    print(f"    Max CER delta:         {summary['max_cer']:.4f}")
    print(f"    Fail count:            {summary['fail_count']}")
    print(f"    Catastrophic count:    {summary['catastrophic_count']}")
    print(f"    Ordering mismatches:   {summary['ordering_mismatch_count']}")
    print(f"    Empty outputs:         {summary['empty_output_count']}")
    print(f"    Quantized loops:       {summary['quantized_loop_count']}")
    if "avg_quantized_cer_to_gt" in summary:
        print(f"    Avg quantized CER→GT:  {summary['avg_quantized_cer_to_gt']:.4f}")
        print(f"    Avg original CER→GT:   {summary['avg_original_cer_to_gt']:.4f}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify quantized PaddleOCR-VL quality")
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
        "--quantized-model",
        type=lambda p: Path(p).resolve(),
        default=SCRIPT_DIR / "mlx_output",
        help="Absolute path to quantized MLX model directory",
    )
    parser.add_argument(
        "--max-pixels",
        type=int,
        default=2822400,
        help="Max image pixels for the vision encoder",
    )
    parser.add_argument(
        "--prompt",
        default=DEFAULT_PROMPT,
        help="Prompt text used for both models",
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=DEFAULT_MAX_TOKENS,
        help="Max generated tokens per sample",
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.0,
        help="Sampling temperature for both models",
    )
    parser.add_argument(
        "--crop-padding",
        type=float,
        default=0.0,
        help="Extra padding ratio applied to crop samples",
    )
    parser.add_argument(
        "--fail-threshold",
        type=float,
        default=DEFAULT_MAX_CER_DELTA,
        help="CER delta threshold used to mark a sample as failed",
    )
    parser.add_argument(
        "--report-json",
        type=lambda p: Path(p).resolve(),
        help="Optional path for a JSON report",
    )
    parser.add_argument(
        "--report-csv",
        type=lambda p: Path(p).resolve(),
        help="Optional path for a CSV report",
    )
    return parser.parse_args()


def load_samples_from_args(args: argparse.Namespace) -> tuple[str, list[Sample]]:
    """Resolve dataset mode and load the corresponding samples."""
    if args.crop_manifest is not None:
        if not args.crop_manifest.is_file():
            raise FileNotFoundError(f"crop manifest not found: {args.crop_manifest}")
        return "crop", load_crop_samples(args.crop_manifest)

    if not args.test_images.is_dir():
        raise FileNotFoundError(f"test images directory not found: {args.test_images}")
    return "page", load_page_samples(args.test_images)


def main() -> None:
    args = parse_args()

    if not args.quantized_model.is_dir():
        print(f"Error: quantized model directory not found: {args.quantized_model}")
        sys.exit(1)

    try:
        dataset_mode, samples = load_samples_from_args(args)
    except (FileNotFoundError, ValueError) as error:
        print(f"Error: {error}")
        sys.exit(1)

    if not samples:
        print("Error: no samples found for verification")
        sys.exit(1)

    print(f"==> Dataset mode: {dataset_mode}")
    if dataset_mode == "crop":
        print(f"==> Crop padding: {args.crop_padding:.2f}")

    records, summary = evaluate_model_pair(
        samples=samples,
        quantized_model_path=args.quantized_model,
        max_pixels=args.max_pixels,
        prompt_text=args.prompt,
        max_tokens=args.max_tokens,
        temperature=args.temperature,
        fail_threshold=args.fail_threshold,
        crop_padding=args.crop_padding,
    )

    print_human_report(records, summary)

    if args.report_json is not None:
        write_report_json(args.report_json, dataset_mode, args, records, summary)
        print(f"\n==> JSON report written to: {args.report_json}")

    if args.report_csv is not None:
        write_report_csv(args.report_csv, records)
        print(f"==> CSV report written to: {args.report_csv}")

    if summary["fail_count"] > 0:
        print(f"\nFAILED: {summary['fail_count']} samples exceeded CER delta threshold {args.fail_threshold:.4f}")
        sys.exit(1)

    print("\nPASSED: All samples are within the CER delta threshold")
    sys.exit(0)


if __name__ == "__main__":
    main()
