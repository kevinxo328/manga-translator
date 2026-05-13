---
license: apache-2.0
pipeline_tag: image-text-to-text
tags:
- PaddleOCR
- OCR
- manga
- mlx
- quantized
base_model: jzhang533/PaddleOCR-VL-For-Manga
language:
- ja
- multilingual
library_name: mlx
---

# PaddleOCR-VL-For-Manga (MLX 8-bit)

MLX-quantized version of [jzhang533/PaddleOCR-VL-For-Manga](https://huggingface.co/jzhang533/PaddleOCR-VL-For-Manga) for Apple Silicon. This model can be used standalone via `mlx_vlm`, or as the OCR engine in **[Manga Translator](https://github.com/kevinxo328/manga-translator)** — a native macOS app for reading and translating manga on-device.

## Changes from Base Model

The weights have been converted from BF16 to **8-bit affine quantization** (`group_size=64`) using [mlx-lm](https://github.com/ml-explore/mlx-examples). All other architecture files (tokenizer, processor, config) are unchanged from the original.

> **Note:** 4-bit quantization produces only newlines for this architecture and is unusable. 8-bit is the minimum viable quantization.

## Model Details

| Property | Value |
|---|---|
| Architecture | PaddleOCRVLForConditionalGeneration |
| Vision encoder | SiglipVisionModel |
| Language model hidden size | 1024 |
| Language model layers | 18 |
| Quantization | 8-bit affine, group_size=64 |
| Framework | [MLX](https://github.com/ml-explore/mlx) |
| Target hardware | Apple Silicon (M-series) |
| Model size | ~1.0 GB |

## Usage

This model is distributed as a zip archive (`model.zip`). Download and extract it, then load with `mlx_vlm`:

```python
from mlx_vlm import load, generate
from mlx_vlm.prompt_utils import apply_chat_template
from mlx_vlm.utils import load_config

model_path = "/path/to/extracted/model"
model, processor = load(model_path, trust_remote_code=True)
config = load_config(model_path, trust_remote_code=True)

prompt = apply_chat_template(processor, config, "OCR the text in this image.", num_images=1)
output = generate(model, processor, prompt, image="/path/to/manga_image.jpg")
print(output)
```

## Verification

Parity against the BF16 original was measured using Character Error Rate Delta (CER Delta) on manga crop samples:

- **Success threshold:** Average CER Delta ≤ 0.05
- **Metric:** BF16 output vs. 8-bit quantized output

## Manga Translator (macOS App)

This model powers the high-accuracy OCR feature in **[Manga Translator](https://github.com/kevinxo328/manga-translator)**, a native macOS app for reading and translating manga on Apple Silicon.

If you are looking for an easy way to use this model without writing code, check out the app.

## License

Apache 2.0 — same as the base model. See [LICENSE](https://www.apache.org/licenses/LICENSE-2.0).

## Citation

If you use this model, please cite the original:

```
@misc{PaddleOCR-VL-For-Manga,
  author = {jzhang533},
  title  = {PaddleOCR-VL-For-Manga},
  year   = {2024},
  url    = {https://huggingface.co/jzhang533/PaddleOCR-VL-For-Manga}
}
```
