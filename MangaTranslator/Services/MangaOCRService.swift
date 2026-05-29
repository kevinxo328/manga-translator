import Foundation
import AppKit

actor MangaOCRService {
    private let detector: ComicTextDetecting
    var recognizer: (any OCRRecognizing)?

    init(detector: ComicTextDetecting = ComicTextDetectorService()) {
        self.detector = detector
    }

    func resetRecognizer() {
        recognizer?.unload()
        recognizer = nil
    }

    func setRecognizer(_ recognizer: (any OCRRecognizing)?) {
        self.recognizer = recognizer
    }

    static func makeRecognizer() throws -> any OCRRecognizing {
        let tokenizer = try MangaOCRTokenizer()
        return MangaOCRRecognizer(tokenizer: tokenizer)
    }

    func recognizeAndCluster(in image: NSImage) throws -> MangaOCRPageResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        return try recognizeAndCluster(in: cgImage)
    }

    // Recognises text for a single, caller-supplied region. Used by the Edit
    // Mode commit pipeline to re-OCR newly drawn or moved bubbles without
    // re-running detection over the whole page. Lazy-loads the default
    // recognizer if none is set — the caller is responsible for selecting a
    // PaddleOCR recognizer (via `setRecognizer`) when the device + download
    // state demands it.
    func recognizeRegion(in cgImage: CGImage, region: CGRect) throws -> String {
        if recognizer == nil {
            recognizer = try Self.makeRecognizer()
        }
        guard let recognizer else {
            throw MangaOCRError.inferenceError("failed to initialize recognizer")
        }
        let (text, _) = try recognizer.recognizeText(in: cgImage, region: region)
        return text
    }

    func recognizeAndCluster(in cgImage: CGImage) throws -> MangaOCRPageResult {
        if recognizer == nil {
            recognizer = try Self.makeRecognizer()
        }
        guard let recognizer else {
            throw MangaOCRError.inferenceError("failed to initialize recognizer")
        }

        DebugLogger.shared.log("Detecting text regions...", level: .info, category: .ocrManga)
        let detectorResult = try detector.detectTextRegions(in: cgImage)
        let regions = detectorResult.regions
        DebugLogger.shared.log("Found \(regions.count) text regions", level: .info, category: .ocrManga)

        if regions.isEmpty {
            return MangaOCRPageResult(bubbles: [], textPixelMask: nil, lowConfidenceDetectionCount: detectorResult.lowConfidenceRegionCount)
        }

        var bubbles = [BubbleCluster]()
        for (index, region) in regions.enumerated() {
            if region.boundingBox.width < 10 || region.boundingBox.height < 10 {
                continue
            }

            do {
                let (text, confidence) = try recognizer.recognizeText(in: cgImage, region: region.boundingBox)
                if text.isEmpty { continue }

                let isInverted: Bool
                if let mask = detectorResult.textPixelMask {
                    isInverted = classifyInverted(canvas: cgImage, seg: mask, region: region.boundingBox)
                } else {
                    isInverted = false
                }

                let observation = TextObservation(
                    boundingBox: region.boundingBox,
                    text: text,
                    confidence: confidence
                )

                let bubble = BubbleCluster(
                    boundingBox: region.boundingBox,
                    text: text,
                    observations: [observation],
                    index: index,
                    isInverted: isInverted
                )
                bubbles.append(bubble)
            } catch let error as PaddleOCRError {
                throw error
            } catch {
                DebugLogger.shared.log("OCR failed for region \(index): \(error.localizedDescription)", level: .warning, category: .ocrManga)
                continue
            }
        }

        DebugLogger.shared.log("Recognized \(bubbles.count) text bubbles", level: .info, category: .ocrManga)
        return MangaOCRPageResult(
            bubbles: bubbles,
            textPixelMask: detectorResult.textPixelMask,
            lowConfidenceDetectionCount: detectorResult.lowConfidenceRegionCount
        )
    }
}
