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

# Or verify a specific directory with a token limit
python verify.py --test-images ../../examples/book1 --max-tokens 100

# 5. Sweep quantization group sizes and export reports
python sweep.py --group-sizes 32,64,128 --report-json ./sweep_results.json
```

## Output

- `mlx_output/` — default 8-bit quantized model files (~1052 MB)
- `mlx_output/SHA256SUMS` — directory checksum for download verification
- `sweep_runs/` — optional conversion variants and `sweep_summary.json`

## Verification Strategy

The primary goal is **Parity**: ensuring the quantized model's output is
mathematically close to the original BF16 model. We measure this using
**Character Error Rate (CER) Delta**.

- **Default data**: `examples/` directory (full manga pages).
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

- **Page-level vs Crop-level**: While `verify.py` scans full pages by default,
  production inference in the App happens on small text crops. Consistency on
  full pages is a conservative "stress test"—actual App performance on crops
  is expected to be higher.
- **Group Size**: `group_size=64` is the default candidate as it balances
  model size and parity.

## Tests

```bash
python -m unittest discover scripts/convert_model/tests
```

## Cleanup

`teardown.sh` removes `.venv/` and `.hf_cache/` inside this directory only.
No files outside the project directory are affected.
