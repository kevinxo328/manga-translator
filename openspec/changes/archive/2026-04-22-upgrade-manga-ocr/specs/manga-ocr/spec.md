## MODIFIED Requirements

### Requirement: Recognize Japanese text using manga-ocr
The system SHALL crop detected text regions from the original image, preprocess each crop (resize to manga-ocr input dimensions, normalize), and run the manga-ocr ONNX model (2025 fine-tuned version) to produce Japanese text strings. The system SHALL decode model output tokens using the manga-ocr tokenizer vocabulary. The 2025 model SHALL provide improved accuracy for modern manga fonts, SFX, and furigana compared to the legacy model.

#### Scenario: Vertical Japanese text in speech bubble
- **WHEN** a cropped text region containing vertical Japanese text is provided
- **THEN** the system returns the correctly recognized Japanese text string using the 2025 model weights

#### Scenario: Horizontal Japanese text
- **WHEN** a cropped text region containing horizontal Japanese text (e.g., title bar) is provided
- **THEN** the system returns the correctly recognized Japanese text string using the 2025 model weights

#### Scenario: SFX and artistic fonts
- **WHEN** a cropped text region containing artistic fonts or SFX (擬聲詞) is provided
- **THEN** the system returns a higher accuracy recognition result compared to the previous model version
