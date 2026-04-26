# Model Conversion: PaddleOCR-VL-For-Manga

Convert `jzhang533/PaddleOCR-VL-For-Manga` to MLX quantized format for the
high-accuracy OCR feature on Apple Silicon, then benchmark BF16 vs quantized
behavior on page-level and crop-level datasets.

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

# Or convert a specific quantization variant
python convert.py --group-size 32 --output-dir ./mlx_output_g32

# 4. Verify page-level quality against BF16 original
python verify.py --test-images /abs/path/to/test_images

# 5. Verify crop-level parity with a manifest and export reports
python verify.py \
  --crop-manifest ./crop_manifest.example.json \
  --crop-padding 0.10 \
  --report-json ./reports/crop_g64.json \
  --report-csv ./reports/crop_g64.csv

# 6. Sweep quantization group sizes and crop padding
python sweep.py \
  --crop-manifest ./crop_manifest.example.json \
  --group-sizes 32,64,128 \
  --crop-paddings 0.0,0.05,0.10

# 7. Clean up when done
./teardown.sh
```

## Output

- `mlx_output/` — default 8-bit quantized model files (~1052 MB)
- `mlx_output/SHA256SUMS` — directory checksum for download verification
- `sweep_runs/` — optional conversion variants and `sweep_summary.json`
- `report.json` / `report.csv` — optional machine-readable evaluation reports

## Verification Modes

`verify.py` supports two dataset modes:

- `--test-images`: page-level sanity checks on full manga pages
- `--crop-manifest`: crop-level parity checks on detector-like text regions

Use `crop_manifest.example.json` as a template for local/private manifests. Keep
private benchmark manifests outside the repo.

Crop manifests use this schema:

```json
{
  "samples": [
    {
      "id": "001-bubble-1",
      "image": "../../test_images/001.jpg",
      "crop": [860, 180, 280, 210],
      "reference_text": "いいから\n早く来い",
      "metadata": {
        "page": "001"
      }
    }
  ]
}
```

`verify.py` always reports BF16 vs quantized CER delta and can additionally
report each model's CER to ground truth when `reference_text` is present.

## Metrics

The verification report includes:

- `avg_cer`
- `median_cer`
- `p90_cer`
- `max_cer`
- `fail_count`
- `catastrophic_count`
- `ordering_mismatch_count`
- `empty_output_count`
- `quantized_loop_count`

## Current Guidance

The current verification workflow has only been exercised on internal, non-public
sample sets. Those results are useful for engineering direction, but they are not
presented here as a public benchmark claim.

Current interpretation from internal phase0 experiments:

- Page-level sanity checks can materially overstate recognizer quantization drift
  because they include page assembly effects such as ordering changes, loops, and
  trailing-line truncation.
- Crop-level parity on detector-like text regions is the primary phase0 gate.
- `group_size=64` is the current default shipping candidate because it has stayed
  near BF16 behavior on internal crop-level checks without incurring the larger
  model size of `group_size=32`.
- Crop padding should be treated as an empirical tuning knob, not a fixed rule.
  It should be re-evaluated as the crop benchmark grows.

### Speed tip

```bash
# ~3x faster with minimal quality loss on full pages
python verify.py --max-pixels 1411200 --test-images /abs/path/to/test_images
```

Production inference on cropped manga text regions (~200×200 px) is estimated
at < 1 s per region.

## Tests

```bash
python -m unittest discover scripts/convert_model/tests
```

## Cleanup

`teardown.sh` removes `.venv/` and `.hf_cache/` inside this directory only.
No files outside the project directory are affected.
