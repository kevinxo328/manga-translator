## Context

`MangaTranslator` currently utilizes a `manga-ocr` recognition engine based on ONNX Runtime. The existing weight files have limited capability in handling complex artistic fonts and background noise prevalent in modern manga. The community has released models fine-tuned with 2024-2025 data, which we plan to integrate.

## Goals / Non-Goals

**Goals:**
- Upgrade `manga-ocr` weights to the 2025 version.
- Update the corresponding tokenizer vocabulary (`vocab.txt`).
- Maintain the existing ONNX Runtime inference architecture for a seamless upgrade.

**Non-Goals:**
- No CoreML conversion or hardware acceleration optimization in this phase (Mid-term goal).
- No changes to the text detection model (`comic-text-detector.onnx`).
- No modification to the core inference logic in Swift.

## Decisions

### Decision 1: Adopt `l0wgear/manga-ocr-2025-onnx`
**Rationale**: This model has been community-converted to ONNX, and its directory structure (separated Encoder/Decoder) is fully compatible with the current loading logic in `MangaOCRRecognizer.swift`.

### Decision 2: Synchronize `vocab.txt` Update
**Rationale**: The fine-tuned model may use different token indices or include new characters. The vocabulary file must be perfectly aligned with the model weights to avoid decoding errors or gibberish.

## Risks / Trade-offs

- **[Risk] Increased Model Size** → **[Mitigation]** The new ONNX model size is similar to the legacy version (~140MB), resulting in no significant impact on the App Bundle size.
- **[Risk] Vocabulary Incompatibility** → **[Mitigation]** Update expected outputs in test cases and execute unit tests immediately after replacement.
