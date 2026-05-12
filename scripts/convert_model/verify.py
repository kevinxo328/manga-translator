#!/usr/bin/env python3
"""Evaluate BF16 vs quantized PaddleOCR-VL consistency (parity).

Compares the output of the original BF16 model and the quantized MLX model
on image samples and reports the Character Error Rate (CER) delta.
"""

import argparse
import csv
import gc
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

import numpy as np

SCRIPT_DIR = Path(__file__).parent.resolve()
os.environ.setdefault("HF_HOME", str(SCRIPT_DIR / ".hf_cache"))

MODEL_ID = "jzhang533/PaddleOCR-VL-For-Manga"
DEFAULT_MAX_CER_DELTA = 0.05
DEFAULT_PROMPT = "Perform OCR on this manga image. Output only the text, no explanation."
DEFAULT_MAX_TOKENS = 1024
DEFAULT_DEBUG_VISION_LAYERS = (6, 18, 25, 27)
REPO_ROOT = SCRIPT_DIR.parent.parent
DETECTOR_CLI_BUILD_DIR = REPO_ROOT / ".xcodebuild-env" / "swift-build-cli"
DETECTOR_CLI_EXECUTABLE = DETECTOR_CLI_BUILD_DIR / "debug" / "DetectorExportCLI"
DETECTOR_MODEL_PATH = REPO_ROOT / "MangaTranslator" / "Resources" / "Models" / "comic-text-detector.onnx"
APP_CROP_PADDING_RATIO = 0.18
APP_MIN_HORIZONTAL_PADDING = 10.0
APP_MIN_VERTICAL_PADDING = 6.0
APP_ELONGATED_THRESHOLD = 1.6
APP_TALL_THRESHOLD = 0.7
APP_ELONGATED_HORIZONTAL_BOOST = 0.08
APP_TALL_VERTICAL_BOOST = 0.08


@dataclass(frozen=True)
class CropBox:
    x: float
    y: float
    width: float
    height: float


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
class LoadedDataset:
    mode: str
    samples: list[Sample]
    metadata: dict[str, Any] = field(default_factory=dict)


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
    original_text: str
    quantized_text: str
    cer_delta: float
    quantized_loop_detected: bool
    empty_output: bool
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class TensorSummary:
    dtype: str
    shape: list[int]
    mean: float
    std: float
    min: float
    max: float
    l2: float
    prefix: list[float]
    token_row_prefixes: list[list[float]]


@dataclass(frozen=True)
class TopToken:
    token_id: int
    logit: float


@dataclass(frozen=True)
class PrefillVisionLayerSubstepRecord:
    layer_index: int
    input_hidden_states: TensorSummary
    post_layer_norm1: TensorSummary
    pre_rotary_queries: TensorSummary
    pre_rotary_keys: TensorSummary
    post_rotary_queries: TensorSummary
    post_rotary_keys: TensorSummary
    values: TensorSummary
    attention_output: TensorSummary
    post_attention_residual: TensorSummary
    post_layer_norm2: TensorSummary
    fc1_output: TensorSummary
    gelu_output: TensorSummary
    mlp_output: TensorSummary
    output_hidden_states: TensorSummary


@dataclass(frozen=True)
class PrefillStageRecord:
    sample_id: str
    prepared_image_path: str
    source_image_path: str
    crop_box: list[float] | None
    crop_padding: float
    input_ids_count: int
    input_ids_prefix: list[int]
    target_width: int
    target_height: int
    generated_text: str
    generated_tokens: list[int]
    termination_token: int | None
    first_step_top_tokens: list[TopToken]
    pixel_values: TensorSummary
    vision_patch_embeddings: TensorSummary
    vision_position_embeddings: TensorSummary
    vision_input_embeddings: TensorSummary
    vision_first_layer_output: TensorSummary
    vision_layer_outputs: list[TensorSummary]
    vision_target_layer_substeps: list[PrefillVisionLayerSubstepRecord]
    encoded_vision_features: TensorSummary
    projected_image_features: TensorSummary
    merged_embeddings: TensorSummary
    first_step_logits: TensorSummary


def parse_crop_box_arg(raw_value: str) -> CropBox:
    """Parse a CLI crop argument in x,y,width,height form."""
    parts = [part.strip() for part in raw_value.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("crop must be formatted as x,y,width,height")

    try:
        x, y, width, height = (float(part) for part in parts)
    except ValueError as error:
        raise argparse.ArgumentTypeError("crop values must be numeric") from error

    if width <= 0 or height <= 0:
        raise argparse.ArgumentTypeError("crop width and height must be greater than zero")

    return CropBox(x=x, y=y, width=width, height=height)


def normalize_text(text: str) -> str:
    """Normalize punctuation and whitespace before comparison."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("…", "...").replace("……", "......").replace("！", "!").replace("？", "?")
    return "\n".join(line.rstrip() for line in text.splitlines()).strip()


def format_report_block(text: str) -> str:
    """Render model output as an indented multi-line block for terminal reports."""
    if not text:
        return textwrap.indent("[empty]", " " * 6)
    return textwrap.indent(text, " " * 6)


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
    x1 = max(0.0, min(box.x, float(image_width)))
    y1 = max(0.0, min(box.y, float(image_height)))
    x2 = max(x1, min(box.x + box.width, float(image_width)))
    y2 = max(y1, min(box.y + box.height, float(image_height)))
    return CropBox(x=x1, y=y1, width=max(0, x2 - x1), height=max(0, y2 - y1))


def expand_crop_box(box: CropBox, padding_ratio: float, image_width: int, image_height: int) -> CropBox:
    """Expand a crop box symmetrically by a ratio of its own width and height."""
    if padding_ratio <= 0:
        return clamp_crop_box(box, image_width, image_height)

    pad_x = box.width * padding_ratio
    pad_y = box.height * padding_ratio
    expanded = CropBox(
        x=box.x - pad_x,
        y=box.y - pad_y,
        width=box.width + pad_x * 2,
        height=box.height + pad_y * 2,
    )
    return integral_crop_box(clamp_crop_box(expanded, image_width, image_height), image_width, image_height)


def integral_crop_box(box: CropBox, image_width: int, image_height: int) -> CropBox:
    """Mirror CGRect.integral so PIL crops match Swift's pixel-aligned bounds."""
    clamped = clamp_crop_box(box, image_width, image_height)
    x1 = math.floor(clamped.x)
    y1 = math.floor(clamped.y)
    x2 = math.ceil(clamped.x + clamped.width)
    y2 = math.ceil(clamped.y + clamped.height)
    return clamp_crop_box(CropBox(x=x1, y=y1, width=x2 - x1, height=y2 - y1), image_width, image_height)


def expand_detector_crop_box(box: CropBox, image_width: int, image_height: int) -> CropBox:
    """Apply PaddleOCRVLRecognizer crop expansion semantics."""
    if box.width <= 0 or box.height <= 0:
        return integral_crop_box(box, image_width, image_height)

    aspect_ratio = box.width / box.height
    horizontal_padding = max(APP_MIN_HORIZONTAL_PADDING, box.width * APP_CROP_PADDING_RATIO)
    vertical_padding = max(APP_MIN_VERTICAL_PADDING, box.height * APP_CROP_PADDING_RATIO)

    if aspect_ratio >= APP_ELONGATED_THRESHOLD:
        horizontal_padding += box.width * APP_ELONGATED_HORIZONTAL_BOOST
    elif aspect_ratio <= APP_TALL_THRESHOLD:
        vertical_padding += box.height * APP_TALL_VERTICAL_BOOST

    expanded = CropBox(
        x=box.x - horizontal_padding,
        y=box.y - vertical_padding,
        width=box.width + horizontal_padding * 2,
        height=box.height + vertical_padding * 2,
    )
    return integral_crop_box(expanded, image_width, image_height)


def classify_record(
    sample: Sample,
    original_output: ModelOutput,
    quantized_output: ModelOutput,
    cer_delta: float,
) -> EvaluationRecord:
    """Build a structured evaluation record."""
    empty_output = not quantized_output.text.strip()
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
        original_text=original_output.text,
        quantized_text=quantized_output.text,
        cer_delta=cer_delta,
        quantized_loop_detected=quantized_output.loop_detected,
        empty_output=empty_output,
        metadata=sample.metadata,
    )


def summarize_records(records: list[EvaluationRecord], fail_threshold: float) -> dict[str, Any]:
    """Summarize evaluation metrics across all records."""
    cer_values = [record.cer_delta for record in records]
    return {
        "sample_count": len(records),
        "avg_cer": sum(cer_values) / len(cer_values) if cer_values else 0.0,
        "median_cer": percentile(cer_values, 0.5),
        "p90_cer": percentile(cer_values, 0.9),
        "max_cer": max(cer_values) if cer_values else 0.0,
        "fail_threshold": fail_threshold,
        "fail_count": sum(1 for record in records if record.cer_delta > fail_threshold),
        "empty_output_count": sum(1 for record in records if record.empty_output),
        "quantized_loop_count": sum(1 for record in records if record.quantized_loop_detected),
    }


def filter_samples_by_ids(dataset: LoadedDataset, sample_ids: list[str]) -> LoadedDataset:
    """Keep only the requested samples and fail if any requested IDs are missing."""
    if not sample_ids:
        return dataset

    requested = set(sample_ids)
    sample_map = {sample.sample_id: sample for sample in dataset.samples}
    missing = sorted(requested - set(sample_map.keys()))
    if missing:
        raise ValueError(f"missing requested sample ids: {', '.join(missing)}")

    filtered = [sample_map[sample_id] for sample_id in sample_ids]
    return LoadedDataset(mode=dataset.mode, samples=filtered, metadata=dataset.metadata)


def summarize_tensor(values: Any, prefix_count: int = 16) -> TensorSummary:
    """Create a compact numeric summary for tensor parity diagnostics."""
    if type(values).__module__.startswith("mlx"):
        import mlx.core as mx

        flat = values.astype(mx.float32).reshape(-1)
        if flat.size == 0:
            return TensorSummary(
                dtype=str(values.dtype),
                shape=list(values.shape),
                mean=0.0,
                std=0.0,
                min=0.0,
                max=0.0,
                l2=0.0,
                prefix=[],
                token_row_prefixes=[],
            )

        mean = flat.mean()
        std = flat.std()
        min_value = flat.min()
        max_value = flat.max()
        l2 = mx.sqrt(mx.sum(flat * flat))
        prefix = flat[:prefix_count]
        token_row_prefixes: list[list[float]] = []
        if values.ndim in (2, 3):
            row_count = int(values.shape[-2])
            row_width = int(values.shape[-1])
            row_view = values.astype(mx.float32).reshape(-1, row_width)
            sample_indices = sorted({0, max(0, row_count // 2), max(0, row_count - 1)})
            sampled_rows = row_view[sample_indices, :prefix_count]
            mx.eval(sampled_rows)
            token_row_prefixes = [
                [float(item) for item in row]
                for row in sampled_rows.tolist()
            ]
        mx.eval(mean, std, min_value, max_value, l2, prefix)
        return TensorSummary(
            dtype=str(values.dtype),
            shape=list(values.shape),
            mean=float(mean.item()),
            std=float(std.item()),
            min=float(min_value.item()),
            max=float(max_value.item()),
            l2=float(l2.item()),
            prefix=[float(item) for item in prefix.tolist()],
            token_row_prefixes=token_row_prefixes,
        )

    array = np.asarray(values, dtype=np.float32)
    flat = array.reshape(-1)
    if flat.size == 0:
        return TensorSummary(
            dtype=str(array.dtype),
            shape=list(array.shape),
            mean=0.0,
            std=0.0,
            min=0.0,
            max=0.0,
            l2=0.0,
            prefix=[],
            token_row_prefixes=[],
        )

    token_row_prefixes: list[list[float]] = []
    if array.ndim in (2, 3):
        sample_indices = sorted({0, max(0, array.shape[-2] // 2), max(0, array.shape[-2] - 1)})
        token_row_prefixes = [
            row[:prefix_count].astype(np.float32).tolist()
            for row in array.reshape(-1, array.shape[-1])[sample_indices]
        ]

    return TensorSummary(
        dtype=str(array.dtype),
        shape=list(array.shape),
        mean=float(array.mean()),
        std=float(array.std()),
        min=float(array.min()),
        max=float(array.max()),
        l2=float(np.linalg.norm(flat)),
        prefix=flat[:prefix_count].astype(np.float32).tolist(),
        token_row_prefixes=token_row_prefixes,
    )


def list_page_images(test_dir: Path) -> list[Path]:
    """List page images from a directory recursively."""
    extensions = {".png", ".jpg", ".jpeg", ".webp"}
    image_paths = []
    for image_path in sorted(test_dir.rglob("*")):
        if image_path.is_file() and image_path.suffix.lower() in extensions:
            image_paths.append(image_path.resolve())
    return image_paths


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


def run_detector_export_cli(page_images: list[Path], output_path: Path) -> None:
    """Build and run the standalone Swift detector export CLI to emit detector JSON."""
    if shutil.which("swift") is None:
        raise RuntimeError("swift is required for --test-images detector export")
    if not DETECTOR_MODEL_PATH.is_file():
        raise RuntimeError(f"detector model not found: {DETECTOR_MODEL_PATH}")

    request_dir = Path(tempfile.mkdtemp(prefix="paddleocr-detector-request-"))
    request_file_path = request_dir / "detector-export-request.json"
    request_file_path.write_text(json.dumps({"imagePaths": [str(path) for path in page_images]}))

    onnxruntime_path = REPO_ROOT / ".xcodebuild-env" / "SourcePackages" / "artifacts" / "onnxruntime-swift-package-manager" / "onnxruntime" / "onnxruntime.xcframework"
    if not onnxruntime_path.exists():
        print("==> Resolving Swift dependencies (onnxruntime missing)...")
        resolve_command = [
            "xcodebuild",
            "-resolvePackageDependencies",
            "-project",
            str(REPO_ROOT / "MangaTranslator.xcodeproj"),
            "-clonedSourcePackagesDirPath",
            str(REPO_ROOT / ".xcodebuild-env" / "SourcePackages"),
        ]
        resolve_result = subprocess.run(
            resolve_command,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        if resolve_result.returncode != 0:
            output = "\n".join(part for part in [resolve_result.stdout.strip(), resolve_result.stderr.strip()] if part).strip()
            raise RuntimeError(f"Failed to resolve SPM dependencies:\n{output}")

    build_command = [
        "swift",
        "build",
        "--product",
        "DetectorExportCLI",
        "--scratch-path",
        str(DETECTOR_CLI_BUILD_DIR),
    ]
    build_env = os.environ.copy()
    build_env.update(
        {
            "HOME": str(REPO_ROOT / ".xcodebuild-env" / "home"),
            "XDG_CACHE_HOME": str(REPO_ROOT / ".xcodebuild-env" / "xdg-cache"),
            "CLANG_MODULE_CACHE_PATH": str(REPO_ROOT / ".xcodebuild-env" / "clang-module-cache"),
            "SWIFTPM_MODULECACHE_OVERRIDE": str(REPO_ROOT / ".xcodebuild-env" / "swiftpm-module-cache"),
        }
    )

    build_result = subprocess.run(
        build_command,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
        env=build_env,
    )
    if build_result.returncode != 0:
        output = "\n".join(part for part in [build_result.stdout.strip(), build_result.stderr.strip()] if part).strip()
        raise RuntimeError(f"detector export CLI build failed:\n{output}")
    if not DETECTOR_CLI_EXECUTABLE.is_file():
        raise RuntimeError(f"detector export executable not found: {DETECTOR_CLI_EXECUTABLE}")

    run_command = [
        str(DETECTOR_CLI_EXECUTABLE),
        "--model-path",
        str(DETECTOR_MODEL_PATH),
        "--image-list-json",
        str(request_file_path),
        "--output",
        str(output_path),
    ]
    run_result = subprocess.run(
        run_command,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    request_file_path.unlink(missing_ok=True)
    request_dir.rmdir()
    if run_result.returncode != 0:
        output = "\n".join(part for part in [run_result.stdout.strip(), run_result.stderr.strip()] if part).strip()
        raise RuntimeError(f"detector export command failed:\n{output}")
    if not output_path.is_file():
        raise RuntimeError(f"detector export command did not create JSON: {output_path}")


def load_detector_samples(detector_json_path: Path, test_dir: Path) -> LoadedDataset:
    """Parse detector-export JSON into crop samples plus page metadata."""
    payload = json.loads(detector_json_path.read_text())
    if payload.get("schemaVersion") != 1:
        raise ValueError("detector export must use schemaVersion 1")

    raw_pages = payload.get("pages")
    if not isinstance(raw_pages, list):
        raise ValueError("detector export must contain a top-level 'pages' list")

    samples: list[Sample] = []
    page_summaries: list[dict[str, Any]] = []
    zero_region_pages: list[str] = []

    for page_index, raw_page in enumerate(raw_pages):
        image_field = raw_page.get("imagePath")
        regions_field = raw_page.get("regions")
        if not isinstance(image_field, str):
            raise ValueError(f"detector page {page_index} missing string 'imagePath'")
        if not isinstance(regions_field, list):
            raise ValueError(f"detector page {page_index} missing list 'regions'")

        image_path = Path(image_field).resolve()
        try:
            rel_path = image_path.relative_to(test_dir.resolve())
            page_id = str(rel_path.with_suffix(""))
        except ValueError:
            page_id = image_path.stem

        page_summary = {
            "page_id": page_id,
            "image_path": str(image_path),
            "region_count": len(regions_field),
        }
        page_summaries.append(page_summary)
        if not regions_field:
            zero_region_pages.append(page_id)

        for region_index, raw_region in enumerate(regions_field):
            samples.append(
                Sample(
                    sample_id=f"{page_id}#region-{region_index + 1:03d}",
                    image_path=image_path,
                    mode="detector_crop",
                    crop_box=CropBox(
                        x=float(raw_region["x"]),
                        y=float(raw_region["y"]),
                        width=float(raw_region["width"]),
                        height=float(raw_region["height"]),
                    ),
                    metadata={
                        "page_id": page_id,
                        "region_index": region_index,
                        "detector_confidence": float(raw_region["confidence"]),
                        "detector_class_index": int(raw_region["classIndex"]),
                    },
                )
            )

    return LoadedDataset(
        mode="detector",
        samples=samples,
        metadata={
            "page_count": len(page_summaries),
            "page_summaries": page_summaries,
            "zero_region_pages": zero_region_pages,
            "detector_json_path": str(detector_json_path),
        },
    )


def load_test_image_samples(
    test_dir: Path,
    keep_detector_json: bool = False,
    detector_json_output: Path | None = None,
) -> LoadedDataset:
    """Run detector export for page images and convert the JSON into region samples."""
    page_images = list_page_images(test_dir)
    if not page_images:
        return LoadedDataset(mode="detector", samples=[], metadata={"page_count": 0, "page_summaries": [], "zero_region_pages": []})

    if detector_json_output is None:
        temp_dir = Path(tempfile.mkdtemp(prefix="paddleocr-detector-export-"))
        detector_json_path = temp_dir / "detector-export.json"
        should_cleanup = not keep_detector_json
    else:
        detector_json_path = detector_json_output.resolve()
        detector_json_path.parent.mkdir(parents=True, exist_ok=True)
        should_cleanup = False

    run_detector_export_cli(page_images, detector_json_path)
    dataset = load_detector_samples(detector_json_path, test_dir)

    if should_cleanup:
        detector_json_path.unlink(missing_ok=True)
        detector_json_path.parent.rmdir()
    else:
        dataset.metadata["detector_json_path"] = str(detector_json_path)

    return dataset


def load_single_image_sample(image_path: Path, crop_box: CropBox | None) -> LoadedDataset:
    """Load a single image sample, optionally constrained to a crop box."""
    resolved_image_path = image_path.resolve()
    if not resolved_image_path.is_file():
        raise FileNotFoundError(f"image not found: {resolved_image_path}")

    from PIL import Image

    with Image.open(resolved_image_path) as image:
        width, height = image.size

    effective_crop_box = crop_box or CropBox(x=0.0, y=0.0, width=float(width), height=float(height))
    effective_crop_box = clamp_crop_box(effective_crop_box, width, height)
    if effective_crop_box.width <= 0 or effective_crop_box.height <= 0:
        raise ValueError(f"crop produced an empty region for image: {resolved_image_path}")

    page_id = resolved_image_path.stem
    sample = Sample(
        sample_id=page_id,
        image_path=resolved_image_path,
        mode="single_image_crop" if crop_box is not None else "single_image",
        crop_box=effective_crop_box,
        metadata={"page_id": page_id},
    )
    return LoadedDataset(
        mode="single_image",
        samples=[sample],
        metadata={
            "page_count": 1,
            "page_summaries": [
                {
                    "page_id": page_id,
                    "image_path": str(resolved_image_path),
                    "region_count": 1,
                }
            ],
            "zero_region_pages": [],
        },
    )


def prepare_samples(samples: list[Sample], crop_padding: float) -> list[PreparedSample]:
    """Prepare page images or cropped region images for inference."""
    if crop_padding < 0:
        raise ValueError("crop_padding must be non-negative")

    from PIL import Image

    temp_dir = Path(tempfile.mkdtemp(prefix="paddleocr-vl-crops-"))
    prepared = []

    for sample in samples:
        if sample.crop_box is None:
            raise ValueError(f"crop sample {sample.sample_id} is missing crop_box")
        with Image.open(sample.image_path) as image:
            width, height = image.size
            if sample.mode == "detector_crop":
                crop_box = expand_detector_crop_box(sample.crop_box, width, height)
            else:
                crop_box = expand_crop_box(sample.crop_box, crop_padding, width, height)
            if crop_box.width == 0 or crop_box.height == 0:
                raise ValueError(f"crop sample {sample.sample_id} produced an empty crop")

            cropped = image.crop(
                (
                    int(crop_box.x),
                    int(crop_box.y),
                    int(crop_box.x + crop_box.width),
                    int(crop_box.y + crop_box.height),
                )
            )
            prepared_path = temp_dir / f"{sample.sample_id.replace('/', '_')}{sample.image_path.suffix or '.png'}"
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


def summarize_prefill_stages(
    model_path: Path,
    prepared_samples: list[PreparedSample],
    max_pixels: int,
    prompt_text: str,
    max_tokens: int,
    temperature: float,
) -> list[PrefillStageRecord]:
    """Export quantized-model prefill summaries for direct parity comparison."""
    import mlx.core as mx
    from mlx_vlm import load
    from mlx_vlm.generate import generate_step
    from mlx_vlm.models.paddleocr_vl.vision import apply_rotary_pos_emb_vision
    from mlx_vlm.prompt_utils import apply_chat_template
    from mlx_vlm.utils import load_config
    from PIL import Image

    model, processor = load(str(model_path), trust_remote_code=True)
    config = load_config(str(model_path), trust_remote_code=True)
    processor.image_processor.max_pixels = max_pixels
    prompt = apply_chat_template(processor, config, prompt_text, num_images=1)
    tokenizer = processor.tokenizer if hasattr(processor, "tokenizer") else processor
    tokenizer.stopping_criteria.reset(model.config.eos_token_id)
    debug_layer_indices = set(DEFAULT_DEBUG_VISION_LAYERS)

    records: list[PrefillStageRecord] = []
    for prepared_sample in prepared_samples:
        with Image.open(prepared_sample.prepared_image_path) as image:
            inputs = processor(images=image.convert("RGB"), text=prompt, return_tensors="np")

        input_ids = mx.array(inputs["input_ids"])
        pixel_values = mx.array(inputs["pixel_values"])
        attention_mask = mx.array(inputs["attention_mask"]).astype(mx.int32)
        image_grid_thw = mx.array(inputs["image_grid_thw"])

        vision_embeddings = model.visual.embeddings(pixel_values, image_grid_thw)
        patch_embeddings = model.visual.embeddings.patch_embedding(
            pixel_values.reshape(-1, pixel_values.shape[2], pixel_values.shape[3], pixel_values.shape[4]).transpose(0, 2, 3, 1)
        ).astype(model.visual.embeddings.patch_embedding.weight.dtype)
        patch_embeddings = patch_embeddings.transpose(0, 3, 1, 2).flatten(-2).squeeze(-1)
        patch_embeddings = patch_embeddings.reshape(-1, patch_embeddings.shape[-1])
        position_embeddings = vision_embeddings - patch_embeddings
        rotary_pos_emb = model.visual.rot_pos_emb(image_grid_thw)
        cu_seqlens = []
        for index in range(image_grid_thw.shape[0]):
            seq_len = image_grid_thw[index, 1] * image_grid_thw[index, 2]
            cu_seqlens.append(mx.repeat(seq_len, image_grid_thw[index, 0]))
        cu_seqlens = mx.concatenate(cu_seqlens)
        cu_seqlens = mx.cumsum(cu_seqlens.astype(mx.int32), axis=0)
        cu_seqlens = mx.pad(cu_seqlens, (1, 0), mode="constant", constant_values=0)

        encoded_vision_features = vision_embeddings
        first_layer_output = None
        layer_outputs: list[TensorSummary] = []
        layer_substeps: list[PrefillVisionLayerSubstepRecord] = []
        for layer_index, layer in enumerate(model.visual.layers):
            layer_number = layer_index + 1
            input_hidden_states = encoded_vision_features
            post_layer_norm1 = layer.layer_norm1(input_hidden_states)
            qkv = layer.self_attn.qkv(post_layer_norm1).reshape(
                post_layer_norm1.shape[0], 3, layer.self_attn.num_heads, -1
            ).transpose(1, 0, 2, 3)
            pre_rotary_queries, pre_rotary_keys, values = mx.split(qkv, 3)
            post_rotary_queries = apply_rotary_pos_emb_vision(
                mx.expand_dims(pre_rotary_queries, 0), rotary_pos_emb
            )[0]
            post_rotary_keys = apply_rotary_pos_emb_vision(
                mx.expand_dims(pre_rotary_keys, 0), rotary_pos_emb
            )[0]
            q = post_rotary_queries.transpose(0, 2, 1, 3)
            k = post_rotary_keys.transpose(0, 2, 1, 3)
            v = values.transpose(0, 2, 1, 3)
            vision_attention_mask = mx.ones(
                (1, post_layer_norm1.shape[0], post_layer_norm1.shape[0]),
                dtype=post_layer_norm1.dtype,
            )
            for i in range(1, len(cu_seqlens)):
                start = int(cu_seqlens[i - 1])
                end = int(cu_seqlens[i])
                vision_attention_mask[start:end, start:end] = 0
            attention_output = mx.fast.scaled_dot_product_attention(
                q, k, v, scale=layer.self_attn.scale, mask=vision_attention_mask
            ).transpose(0, 2, 1, 3).reshape(post_layer_norm1.shape[0], -1)
            attention_output = layer.self_attn.out_proj(attention_output)
            post_attention_residual = input_hidden_states + attention_output
            post_layer_norm2 = layer.layer_norm2(post_attention_residual)
            fc1_output = layer.mlp.fc1(post_layer_norm2)
            gelu_output = layer.mlp.activation_fn(fc1_output)
            mlp_output = layer.mlp.fc2(gelu_output)
            encoded_vision_features = post_attention_residual + mlp_output
            if layer_index == 0:
                first_layer_output = encoded_vision_features
            layer_outputs.append(summarize_tensor(encoded_vision_features))
            if layer_number in debug_layer_indices:
                layer_substeps.append(
                    PrefillVisionLayerSubstepRecord(
                        layer_index=layer_number,
                        input_hidden_states=summarize_tensor(input_hidden_states),
                        post_layer_norm1=summarize_tensor(post_layer_norm1),
                        pre_rotary_queries=summarize_tensor(pre_rotary_queries),
                        pre_rotary_keys=summarize_tensor(pre_rotary_keys),
                        post_rotary_queries=summarize_tensor(post_rotary_queries),
                        post_rotary_keys=summarize_tensor(post_rotary_keys),
                        values=summarize_tensor(values),
                        attention_output=summarize_tensor(attention_output),
                        post_attention_residual=summarize_tensor(post_attention_residual),
                        post_layer_norm2=summarize_tensor(post_layer_norm2),
                        fc1_output=summarize_tensor(fc1_output),
                        gelu_output=summarize_tensor(gelu_output),
                        mlp_output=summarize_tensor(mlp_output),
                        output_hidden_states=summarize_tensor(encoded_vision_features),
                    )
                )
        encoded_vision_features = model.visual.post_layernorm(encoded_vision_features)
        projected_image_features = model.visual.projector(encoded_vision_features, image_grid_thw)

        text_embeddings = model.language_model.model.embed_tokens(input_ids)
        merged_embeddings = model.merge_input_ids_with_image_features(
            model.config.image_token_id,
            projected_image_features,
            text_embeddings,
            input_ids,
        )
        position_ids, _ = model.language_model.get_rope_index(
            input_ids,
            image_grid_thw,
            None,
            attention_mask,
        )
        first_step_logits = model.language_model(
            input_ids,
            inputs_embeds=merged_embeddings,
            mask=attention_mask,
            pixel_values=pixel_values,
            image_grid_thw=image_grid_thw,
            position_ids=position_ids,
        ).logits[:, -1, :]

        top_indices = mx.argpartition(first_step_logits[0], kth=-5)[-5:]
        top_pairs = sorted(
            [
                TopToken(token_id=int(token_id), logit=float(first_step_logits[0][token_id].item()))
                for token_id in top_indices.tolist()
            ],
            key=lambda token: token.logit,
            reverse=True,
        )

        generated_tokens: list[int] = []
        termination_token: int | None = None
        generator = generate_step(
            input_ids,
            model,
            pixel_values,
            attention_mask,
            image_grid_thw=image_grid_thw,
            max_tokens=max_tokens,
            temperature=temperature,
        )
        for token, _ in generator:
            generated_tokens.append(int(token))
            if tokenizer.stopping_criteria(token):
                termination_token = int(token)
                break

        generated_text = processor.decode(generated_tokens, skip_special_tokens=False).strip()

        target_height = int(image_grid_thw[0, 1].item()) * processor.image_processor.patch_size
        target_width = int(image_grid_thw[0, 2].item()) * processor.image_processor.patch_size

        mx.eval(
            pixel_values,
            encoded_vision_features,
            projected_image_features,
            merged_embeddings,
            first_step_logits,
        )

        crop_box = None
        if prepared_sample.sample.crop_box is not None:
            crop_box = [
                prepared_sample.sample.crop_box.x,
                prepared_sample.sample.crop_box.y,
                prepared_sample.sample.crop_box.width,
                prepared_sample.sample.crop_box.height,
            ]

        records.append(
            PrefillStageRecord(
                sample_id=prepared_sample.sample.sample_id,
                prepared_image_path=str(prepared_sample.prepared_image_path),
                source_image_path=str(prepared_sample.sample.image_path),
                crop_box=crop_box,
                crop_padding=float(prepared_sample.sample.metadata.get("crop_padding", 0.0)),
                input_ids_count=int(input_ids.shape[1]),
                input_ids_prefix=[int(token) for token in input_ids[0, :16].tolist()],
                target_width=target_width,
                target_height=target_height,
                generated_text=generated_text,
                generated_tokens=generated_tokens,
                termination_token=termination_token,
                first_step_top_tokens=top_pairs,
                pixel_values=summarize_tensor(pixel_values),
                vision_patch_embeddings=summarize_tensor(patch_embeddings),
                vision_position_embeddings=summarize_tensor(position_embeddings),
                vision_input_embeddings=summarize_tensor(vision_embeddings),
                vision_first_layer_output=summarize_tensor(first_layer_output),
                vision_layer_outputs=layer_outputs,
                vision_target_layer_substeps=layer_substeps,
                encoded_vision_features=summarize_tensor(encoded_vision_features),
                projected_image_features=summarize_tensor(projected_image_features),
                merged_embeddings=summarize_tensor(merged_embeddings),
                first_step_logits=summarize_tensor(first_step_logits),
            )
        )

    del model, processor
    gc.collect()
    mx.clear_cache()
    return records


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
        record = classify_record(
            sample=prepared_sample.sample,
            original_output=original_output,
            quantized_output=quantized_output,
            cer_delta=cer_delta,
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
    dataset_metadata: dict[str, Any],
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
        "dataset": dataset_metadata,
        "summary": summary,
        "records": [asdict(record) for record in records],
        "page_summaries": summarize_pages(records, dataset_metadata),
    }
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2))


def write_prefill_stage_report_json(
    output_path: Path,
    args: argparse.Namespace,
    dataset_metadata: dict[str, Any],
    records: list[PrefillStageRecord],
) -> None:
    """Write prefill-stage diagnostics in a Swift-aligned JSON structure."""
    payload = {
        "config": {
            "dataset_mode": "prefill_stage_diagnostics",
            "quantized_model": str(args.quantized_model),
            "max_pixels": args.max_pixels,
            "prompt": args.prompt,
            "max_tokens": args.max_tokens,
            "temperature": args.temperature,
            "crop_padding": args.crop_padding,
            "sample_ids": args.sample_id,
        },
        "dataset": dataset_metadata,
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
        "cer_delta",
        "quantized_loop_detected",
        "empty_output",
    ]
    with output_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for record in records:
            row = {name: getattr(record, name) for name in fieldnames}
            row["crop_box"] = json.dumps(row["crop_box"]) if row["crop_box"] is not None else ""
            writer.writerow(row)


def summarize_pages(records: list[EvaluationRecord], dataset_metadata: dict[str, Any]) -> list[dict[str, Any]]:
    """Summarize region-level results back into per-page aggregates."""
    page_map = {
        page["page_id"]: {
            **page,
            "fail_count": 0,
            "max_cer": 0.0,
            "empty_output_count": 0,
        }
        for page in dataset_metadata.get("page_summaries", [])
    }

    for record in records:
        page_id = record.metadata.get("page_id")
        if page_id is None:
            continue
        page_entry = page_map.setdefault(
            page_id,
            {
                "page_id": page_id,
                "image_path": record.image_path,
                "region_count": 0,
                "fail_count": 0,
                "max_cer": 0.0,
                "empty_output_count": 0,
            },
        )
        page_entry["region_count"] += 1
        page_entry["fail_count"] += int(record.cer_delta > 0)
        page_entry["max_cer"] = max(page_entry["max_cer"], record.cer_delta)
        page_entry["empty_output_count"] += int(record.empty_output)

    return list(page_map.values())


def print_human_report(records: list[EvaluationRecord], summary: dict[str, Any], dataset_metadata: dict[str, Any]) -> None:
    """Print a compact human-readable report."""
    print(f"==> Parity Results ({len(records)} samples):\n")
    for record in records:
        status = "PASS" if record.cer_delta <= summary["fail_threshold"] else "FAIL"
        print(f"  [{status}] {record.sample_id} ({record.mode})")
        print(f"    Image:       {record.image_path}")
        print("    Original:")
        print(format_report_block(record.original_text))
        print("    Quantized:")
        print(format_report_block(record.quantized_text))
        print(f"    CER delta:   {record.cer_delta:.4f}")
        flags = []
        if record.quantized_loop_detected:
            flags.append("quantized-loop")
        if record.empty_output:
            flags.append("empty-output")
        if flags:
            print(f"    Flags:       {', '.join(flags)}")
        print()

    page_summaries = summarize_pages(records, dataset_metadata)
    if page_summaries:
        print("==> Page Summary:")
        for page in page_summaries:
            print(
                f"    {page['page_id']}: regions={page['region_count']} "
                f"fails={page['fail_count']} max_cer={page['max_cer']:.4f} "
                f"empty_outputs={page['empty_output_count']}"
            )
        print(f"    Zero-region pages:      {len(dataset_metadata.get('zero_region_pages', []))}")

    print("==> Summary:")
    print(f"    Average CER delta:     {summary['avg_cer']:.4f}")
    print(f"    Median CER delta:      {summary['median_cer']:.4f}")
    print(f"    P90 CER delta:         {summary['p90_cer']:.4f}")
    print(f"    Max CER delta:         {summary['max_cer']:.4f}")
    print(f"    Fail count:            {summary['fail_count']}")
    print(f"    Empty outputs:         {summary['empty_output_count']}")
    print(f"    Quantized loops:       {summary['quantized_loop_count']}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify quantized PaddleOCR-VL quality")
    dataset_group = parser.add_mutually_exclusive_group()
    dataset_group.add_argument(
        "--image",
        type=lambda p: Path(p).expanduser().resolve(),
        help="Single image file to verify directly. Supports absolute paths.",
    )
    dataset_group.add_argument(
        "--test-images",
        type=lambda p: Path(p).resolve(),
        default=SCRIPT_DIR.parent.parent / "examples",
        help="Directory containing test images (default: examples/)",
    )
    dataset_group.add_argument(
        "--crop-manifest",
        type=lambda p: Path(p).resolve(),
        help="JSON manifest describing crop-level samples",
    )
    parser.add_argument(
        "--crop",
        type=parse_crop_box_arg,
        help="Optional crop for --image in x,y,width,height form",
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
        help="Extra padding ratio applied to --crop-manifest samples",
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
    parser.add_argument(
        "--prefill-stage-report-json",
        type=lambda p: Path(p).resolve(),
        help="Optional path for a quantized-model prefill-stage JSON report",
    )
    parser.add_argument(
        "--sample-id",
        action="append",
        default=[],
        help="Optional sample ID filter. Repeat to keep multiple samples.",
    )
    parser.add_argument(
        "--keep-detector-json",
        action="store_true",
        help="Keep the generated detector JSON when using --test-images",
    )
    parser.add_argument(
        "--detector-json-output",
        type=lambda p: Path(p).resolve(),
        help="Optional output path for detector JSON generated by --test-images",
    )
    return parser.parse_args()


def load_samples_from_args(args: argparse.Namespace) -> LoadedDataset:
    """Resolve dataset mode and load the corresponding samples."""
    if args.image is not None:
        return load_single_image_sample(args.image, crop_box=args.crop)

    if args.crop_manifest is not None:
        if not args.crop_manifest.is_file():
            raise FileNotFoundError(f"crop manifest not found: {args.crop_manifest}")
        samples = load_crop_samples(args.crop_manifest)
        page_ids = sorted({sample.image_path.stem for sample in samples})
        return LoadedDataset(
            mode="crop_manifest",
            samples=samples,
            metadata={
                "page_count": len(page_ids),
                "page_summaries": [{"page_id": page_id, "image_path": "", "region_count": 0} for page_id in page_ids],
                "zero_region_pages": [],
            },
        )

    if not args.test_images.is_dir():
        raise FileNotFoundError(f"test images directory not found: {args.test_images}")
    return load_test_image_samples(
        args.test_images,
        keep_detector_json=args.keep_detector_json,
        detector_json_output=args.detector_json_output,
    )


def main() -> None:
    args = parse_args()

    if not args.quantized_model.is_dir():
        print(f"Error: quantized model directory not found: {args.quantized_model}")
        sys.exit(1)

    try:
        dataset = load_samples_from_args(args)
    except (FileNotFoundError, ValueError) as error:
        print(f"Error: {error}")
        sys.exit(1)
    except RuntimeError as error:
        print(f"Error: {error}")
        sys.exit(1)

    try:
        dataset = filter_samples_by_ids(dataset, args.sample_id)
    except ValueError as error:
        print(f"Error: {error}")
        sys.exit(1)

    if not dataset.samples:
        print("Error: no samples found for verification")
        sys.exit(1)

    print(f"==> Dataset mode: {dataset.mode}")
    test_data = args.image if args.image is not None else (args.test_images if args.crop_manifest is None else args.crop_manifest)
    print(f"==> Test data: {test_data}")
    if args.image is None and args.crop_manifest is None:
        print(f"==> Detector pages: {dataset.metadata.get('page_count', 0)}")
        print(f"==> Zero-region pages: {len(dataset.metadata.get('zero_region_pages', []))}")
        if args.keep_detector_json or args.detector_json_output is not None:
            print(f"==> Detector JSON: {dataset.metadata.get('detector_json_path')}")

    records, summary = evaluate_model_pair(
        samples=dataset.samples,
        quantized_model_path=args.quantized_model,
        max_pixels=args.max_pixels,
        prompt_text=args.prompt,
        max_tokens=args.max_tokens,
        temperature=args.temperature,
        fail_threshold=args.fail_threshold,
        crop_padding=args.crop_padding,
    )

    print_human_report(records, summary, dataset.metadata)

    if args.report_json is not None:
        write_report_json(args.report_json, dataset.mode, args, records, summary, dataset.metadata)
        print(f"\n==> JSON report written to: {args.report_json}")

    if args.report_csv is not None:
        write_report_csv(args.report_csv, records)
        print(f"==> CSV report written to: {args.report_csv}")

    if args.prefill_stage_report_json is not None:
        prepared_samples = prepare_samples(dataset.samples, args.crop_padding)
        prefill_records = summarize_prefill_stages(
            model_path=args.quantized_model,
            prepared_samples=prepared_samples,
            max_pixels=args.max_pixels,
            prompt_text=args.prompt,
            max_tokens=args.max_tokens,
            temperature=args.temperature,
        )
        write_prefill_stage_report_json(
            args.prefill_stage_report_json,
            args,
            dataset.metadata,
            prefill_records,
        )
        print(f"==> Prefill-stage JSON report written to: {args.prefill_stage_report_json}")

    if summary["fail_count"] > 0:
        print(f"\nFAILED: {summary['fail_count']} samples exceeded CER delta threshold {args.fail_threshold:.4f}")
        sys.exit(1)

    print("\nPASSED: All samples are within the CER delta threshold")
    sys.exit(0)


if __name__ == "__main__":
    main()
