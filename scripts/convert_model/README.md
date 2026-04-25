# Model Conversion: PaddleOCR-VL-For-Manga

Convert `jzhang533/PaddleOCR-VL-For-Manga` to 8-bit MLX quantized format for
the high-accuracy OCR feature on Apple Silicon.

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

# 4. Verify quality against BF16 original
python verify.py --test-images /abs/path/to/test_images

# 5. Clean up when done
./teardown.sh
```

## Output

- `mlx_output/` — 8-bit quantized model files (~1052 MB)
- `mlx_output/SHA256SUMS` — directory checksum for download verification

## Verification Results

Tested on 12 manga pages (full resolution, `temperature=0`, n-gram loop
deduplication, Unicode normalization):

| Result | Count |
|--------|-------|
| PASS (CER ≤ 5%) | 9 / 12 |
| Average CER delta | 8.25% |

Remaining failures are inherent 8-bit quantization limitations:
- `002.jpg` — quantized model hallucinates repeated dialogue (49.6%)
- `001.jpg` — reading order differs between BF16 and quantized (25.4%)
- `010.jpg` — quantized misses one trailing line (17.7%)

### Speed tip

```bash
# ~3x faster (5 s vs 15 s per image) with minimal quality loss on full pages
python verify.py --max-pixels 1411200 --test-images /abs/path/to/test_images
```

Production inference on cropped manga text regions (~200×200 px) is estimated
at < 1 s per region.

## Cleanup

`teardown.sh` removes `.venv/` and `.hf_cache/` inside this directory only.
No files outside the project directory are affected.
