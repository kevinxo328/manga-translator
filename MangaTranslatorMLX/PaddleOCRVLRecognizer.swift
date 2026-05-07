import Foundation
import CoreGraphics
import os

#if arch(arm64)
import MangaTranslatorMLX

extension Notification.Name {
    static let paddleOCRVLMemoryPressure = Notification.Name("MangaTranslatorPaddleOCRVLMemoryPressure")
}

// MARK: - PaddleOCRVLRecognizer

public final class PaddleOCRVLRecognizer: OCRRecognizing, @unchecked Sendable {
    private static let cropPaddingRatio: CGFloat = 0.18
    private static let minimumHorizontalPadding: CGFloat = 10
    private static let minimumVerticalPadding: CGFloat = 6
    private static let elongatedBubbleThreshold: CGFloat = 1.6
    private static let tallBubbleThreshold: CGFloat = 0.7
    private static let elongatedHorizontalBoostRatio: CGFloat = 0.08
    private static let tallVerticalBoostRatio: CGFloat = 0.08

    private var engine: (any PaddleOCRInferencing)?
    private let engineLock = NSLock()
    private let modelDirectory: URL
    private let engineFactory: (URL) throws -> any PaddleOCRInferencing
    private let logger = Logger(subsystem: "MangaTranslator", category: "PaddleOCRVL")
    private var memoryPressureObserver: NSObjectProtocol?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    convenience public init(modelDirectory: URL) {
        self.init(modelDirectory: modelDirectory) { dir in
            try DefaultPaddleOCREngine(modelDirectory: dir)
        }
    }

    init(modelDirectory: URL, engineFactory: @escaping (URL) throws -> any PaddleOCRInferencing) {
        self.modelDirectory = modelDirectory
        self.engineFactory = engineFactory
        setupMemoryPressureHandling()
    }

    deinit {
        memoryPressureSource?.cancel()
        if let observer = memoryPressureObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func unload() {
        engineLock.lock()
        defer { engineLock.unlock() }
        engine = nil
    }

    private func setupMemoryPressureHandling() {
        memoryPressureObserver = NotificationCenter.default.addObserver(
            forName: .paddleOCRVLMemoryPressure,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.unload()
            }
        }

        // Bridge real macOS memory pressure events to the notification
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            NotificationCenter.default.post(name: .paddleOCRVLMemoryPressure, object: nil)
        }
        source.resume()
        memoryPressureSource = source
    }

    // MARK: - OCRRecognizing

    public func recognizeText(in cgImage: CGImage, region: CGRect) throws -> (text: String, confidence: Float) {
        let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let expandedRegion = Self.expandedCropRegion(for: region, within: imageBounds)
        let clampedRegion = expandedRegion.intersection(imageBounds)

        guard clampedRegion.width > 0 && clampedRegion.height > 0 else {
            return ("", 0)
        }

        engineLock.lock()
        var currentEngine = engine
        if currentEngine == nil {
            guard let resolvedModelDirectory = ModelDownloadService.resolvedModelDirectory(in: modelDirectory) else {
                engineLock.unlock()
                throw PaddleOCRError.modelUnavailable
            }
            do {
                currentEngine = try engineFactory(resolvedModelDirectory)
                engine = currentEngine
            } catch {
                engineLock.unlock()
                throw PaddleOCRError.modelUnavailable
            }
        }
        engineLock.unlock()

        guard let activeEngine = currentEngine else {
            throw PaddleOCRError.modelUnavailable
        }

        guard let cropped = cgImage.cropping(to: clampedRegion) else {
            return ("", 0)
        }

        do {
            let (text, confidence) = try activeEngine.infer(image: cropped)
            return (cleanRecognizedText(text), confidence)
        } catch {
            throw Self.mapEngineError(error)
        }
    }

    private func cleanRecognizedText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "\u{FFFD}", with: "")

        // 1. Remove repeated punctuation loops (e.g. ".....", "!!!!")
        let punctuationPairs: [(String, String)] = [
            ("[\\.]{3,}", "."), ("[!]{3,}", "!"), ("[?]{3,}", "?"),
            ("[。]{3,}", "。"), ("[！]{3,}", "！"), ("[？]{3,}", "？"), ("[…]{2,}", "…")
        ]
        for (pattern, replacement) in punctuationPairs {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned, options: [],
                    range: NSRange(location: 0, length: cleaned.utf16.count),
                    withTemplate: replacement
                )
            }
        }

        // 2. Phrase loop cleanup: strip all trailing repetitions back to a single occurrence
        let words = cleaned.components(separatedBy: .whitespaces)
        if words.count >= 6 {
            for n in 2...4 {
                if words.count >= n * 3 {
                    let tail = Array(words.suffix(n))
                    let prev = Array(words.dropLast(n).suffix(n))
                    let prevPrev = Array(words.dropLast(n * 2).suffix(n))
                    if tail == prev && prev == prevPrev {
                        var cutAt = words.count
                        while cutAt >= n && Array(words[(cutAt - n)..<cutAt]) == tail {
                            cutAt -= n
                        }
                        cleaned = (Array(words[0..<cutAt]) + tail).joined(separator: " ")
                        return cleaned
                    }
                }
            }
        }

        return cleaned
    }

    private static func expandedCropRegion(for region: CGRect, within imageBounds: CGRect) -> CGRect {
        guard region.width > 0 && region.height > 0 else {
            return region.intersection(imageBounds)
        }

        let aspectRatio = region.width / region.height
        var horizontalPadding = max(minimumHorizontalPadding, region.width * cropPaddingRatio)
        var verticalPadding = max(minimumVerticalPadding, region.height * cropPaddingRatio)

        if aspectRatio >= elongatedBubbleThreshold {
            horizontalPadding += region.width * elongatedHorizontalBoostRatio
        } else if aspectRatio <= tallBubbleThreshold {
            verticalPadding += region.height * tallVerticalBoostRatio
        }

        let expanded = region.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        return expanded.intersection(imageBounds).integral
    }

    private static func mapEngineError(_ error: Error) -> PaddleOCRError {
        if let paddleError = error as? PaddleOCRError {
            return paddleError
        }
        if let engineError = error as? PaddleOCREngineError {
            switch engineError {
            case .modelUnavailable:
                return .modelUnavailable
            case .invalidInputImage:
                return .inferenceFailed("Invalid input image")
            case .runtimeFailure(let message):
                if isIncompatibleQuantizedWeights(message) {
                    return .verifyFailed
                }
                return .inferenceFailed(message)
            }
        }
        return .inferenceFailed(error.localizedDescription)
    }

    private static func isIncompatibleQuantizedWeights(_ message: String) -> Bool {
        message.contains("Unhandled keys")
            && message.contains("\"biases\"")
            && message.contains("\"scales\"")
    }
}
#endif
