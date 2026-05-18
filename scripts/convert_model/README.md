# Model Conversion: PaddleOCR-VL-For-Manga

Convert `jzhang533/PaddleOCR-VL-For-Manga` to MLX quantized format for the
high-accuracy OCR feature on Apple Silicon, then verify consistency (parity)
between the BF16 original and the quantized 8-bit version.

> **Note:** 4-bit quantization produces only newlines for this model architecture
> and is unusable. 8-bit is the minimum viable quantization.

## Prerequisites

- macOS with Apple Silicon
- [uv](https://docs.astral.sh/uv/) installed
- ~12 GB free disk space (model download ~4 GB + quantized output ~1.1 GB)

## Usage

```bash
# 1. Set up environment
./setup.sh

# 2. Activate virtualenv
source .venv/bin/activate

# 3. Convert model (downloads from HuggingFace on first run)
python convert.py

# 4. Verify parity against BF16 original using example images
# Scans examples/ directory by default
python verify.py

# Verify a single image directly with an absolute path
python verify.py --image /abs/path/to/image.jpg

# Verify a single cropped region from one image
python verify.py --image /abs/path/to/image.jpg --crop 10,20,120,40

# Or verify a specific directory with detector-driven crops and a token limit
python verify.py --test-images ../../examples/book1 --max-tokens 100

# 5. Sweep quantization group sizes and export reports
python sweep.py --group-sizes 32,64,128 --report-json ./sweep_results.json

# 6. Upload to HuggingFace (set HF_TOKEN and HF_REPO_ID in .env first)
python upload.py                  # upload model zip + model card (default)
python upload.py --model-only     # upload model zip only
python upload.py --card-only      # upload MODEL_CARD.md only (no re-packing)
```

## Output

- `mlx_output/` — default 8-bit quantized model files (~1052 MB)
- `mlx_output/SHA256SUMS` — directory checksum for download verification
- `sweep_runs/` — optional conversion variants and `sweep_summary.json`

## Verification Strategy

The primary goal is **Parity**: ensuring the quantized model's output is
mathematically close to the original BF16 model. We measure this using
**Character Error Rate (CER) Delta**.

- **Default data**: `examples/` directory (full manga pages). The directory scan skips any subdirectory whose name starts with `.` or `_`.
- **`--image` data**: a single image file, optionally constrained with `--crop`.
- **`--test-images` data**: detector-driven region crops produced by the same
  `ComicTextDetectorService` used by the macOS app.
- **Primary metric**: CER Delta (BF16 vs. Quantized).
- **Success threshold**: Average CER Delta ≤ 0.05.

## Metrics

The verification report includes:

- `avg_cer`: Average CER Delta across all samples.
- `median_cer`: Median CER Delta.
- `p90_cer`: 90th percentile CER Delta.
- `fail_count`: Number of samples exceeding the CER Delta threshold.
- `quantized_loop_count`: Number of samples where the quantized model entered a loop.
- `empty_output_count`: Number of samples where the quantized model returned no text.

## Current Guidance

- **Single-image debugging is now first-class**: use `--image /abs/path/to/file`
  when you want a fast answer for one file without scanning a whole directory.
- **Optional crop for single-image mode**: `--crop x,y,width,height` runs OCR on
  one explicit region and avoids detector export entirely.
- **`--test-images` is crop-first**: page directories are converted into
  region-level OCR samples through the standalone Swift `DetectorExportCLI`.
  Full pages are not sent directly to OCR in this mode. The page scan also skips
  any subdirectory whose name starts with `.` or `_`.
- **Crop expansion parity**: detector crops are expanded with the same padding
  rules as `PaddleOCRVLRecognizer.expandedCropRegion()` in the app.
- **`--crop-manifest` remains supported**: curated crop datasets still use the
  explicit manifest coordinates plus the CLI `--crop-padding` setting.
- **Region-level reporting**: reports include per-region CER records, per-page
  summaries, and a `zero_region_pages` list when the detector finds nothing.
- **Detector JSON retention**: use `--keep-detector-json` to keep the temporary
  detector export, or `--detector-json-output <path>` to write it to a fixed
  location for debugging.
- **Group Size**: `group_size=64` is the default candidate as it balances
  model size and parity.

## Debug Recipes

```bash
# Fastest path: one image, no detector
python verify.py --image /abs/path/to/image.jpg

# One image, one explicit crop
python verify.py --image /abs/path/to/image.jpg --crop 10,20,120,40

# Directory mode with detector export preserved for later inspection
python verify.py \
  --test-images ../../examples/book1 \
  --detector-json-output ./detector.json \
  --report-json ./report.json

# Export quantized prefill-stage diagnostics for parity investigation
python verify.py \
  --image /abs/path/to/image.jpg \
  --crop 10,20,120,40 \
  --prefill-stage-report-json ./prefill.json
```

## Tests

```bash
python -m unittest discover scripts/convert_model/tests
xcodebuild test -project MangaTranslator.xcodeproj -scheme MangaTranslator -destination 'platform=macOS' -only-testing:MangaTranslatorTests/ComicTextDetectorExportTests
```

## Cleanup

`teardown.sh` removes `.venv/` and `.hf_cache/` inside this directory only.
No files outside the project directory are affected.
