import XCTest
@testable import MangaTranslator
import AppKit
import Foundation

#if arch(arm64)
@testable import MangaTranslatorMLX

@MainActor
final class PaddleOCRProductionParityDiagnosticTests: XCTestCase {
    private let parityDetectorJSONPath = URL(fileURLWithPath: "/private/tmp/paddle-detector-examples.json")
    private let parityVerifyJSONPath = URL(fileURLWithPath: "/private/tmp/paddle-verify-examples.json")

    private struct DetectorRegionSample {
        let sampleID: String
        let imagePath: String
        let region: CGRect
    }

    func testExportProductionPathOutputsForVerifyParity() throws {
        executionTimeAllowance = 20 * 60

        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping")
            return
        }

        let detectorData = try Data(contentsOf: parityDetectorJSONPath)
        guard let payload = try JSONSerialization.jsonObject(with: detectorData) as? [String: Any],
              let pages = payload["pages"] as? [[String: Any]] else {
            XCTFail("Could not parse detector export JSON at \(parityDetectorJSONPath.path)")
            return
        }

        let recognizer = PaddleOCRVLRecognizer(modelDirectory: resolvedDir)
        var records: [[String: Any]] = []

        for page in pages {
            guard let imagePath = page["imagePath"] as? String,
                  let regions = page["regions"] as? [[String: Any]] else {
                XCTFail("Malformed detector page entry")
                return
            }

            let imageURL = URL(fileURLWithPath: imagePath)
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                XCTFail("Could not load image at \(imagePath)")
                return
            }

            for (index, region) in regions.enumerated() {
                guard let x = region["x"] as? Double,
                      let y = region["y"] as? Double,
                      let width = region["width"] as? Double,
                      let height = region["height"] as? Double else {
                    XCTFail("Malformed detector region entry")
                    return
                }

                let relativeImagePath: String
                if let examplesRange = imagePath.range(of: "/examples/") {
                    relativeImagePath = String(imagePath[examplesRange.upperBound...])
                } else {
                    relativeImagePath = imageURL.lastPathComponent
                }
                let relativeSamplePath = (relativeImagePath as NSString).deletingPathExtension
                let sampleID = "\(relativeSamplePath)#region-\(String(format: "%03d", index + 1))"
                let rect = CGRect(x: x, y: y, width: width, height: height)
                let result = try recognizer.recognizeText(in: cgImage, region: rect)
                records.append([
                    "sample_id": sampleID,
                    "image_path": imagePath,
                    "crop_box": [x, y, width, height],
                    "text": result.text,
                ])
            }
        }

        let paritySwiftOutputJSONPath = FileManager.default.temporaryDirectory.appendingPathComponent("paddle-swift-production-examples.json")
        try FileManager.default.createDirectory(
            at: paritySwiftOutputJSONPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let outputData = try JSONSerialization.data(
            withJSONObject: ["records": records],
            options: [.prettyPrinted, .sortedKeys]
        )
        try outputData.write(to: paritySwiftOutputJSONPath, options: .atomic)
        print("Swift production parity export wrote \(records.count) records to \(paritySwiftOutputJSONPath.path)")
        XCTAssertFalse(records.isEmpty)
    }

    func testTraceProductionParityBlockers() throws {
        executionTimeAllowance = 20 * 60

        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping")
            return
        }

        let targetIDs = [
            "book1/007#region-010",
            "book1/007#region-012",
            "book1/007#region-014",
            "book1/007#region-015",
            "book1/011#region-006",
            "book1/001#region-001",
            "book1/003#region-002",
        ]

        let detectorSamples = try loadDetectorSamples()
        let verifyTexts = try loadVerifyTexts()
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: resolvedDir)
        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        var traced = 0

        for sampleID in targetIDs {
            guard let sample = detectorSamples[sampleID] else {
                XCTFail("Missing detector sample for \(sampleID)")
                continue
            }

            let imageURL = URL(fileURLWithPath: sample.imagePath)
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let debugCrop = expandedCropImage(for: sample.region, in: cgImage) else {
                XCTFail("Could not prepare crop for \(sampleID)")
                continue
            }

            let debugTrace = try engine.inferDebug(image: debugCrop)
            let production = try recognizer.recognizeText(in: cgImage, region: sample.region)
            let verifyText = verifyTexts[sampleID] ?? "<missing>"
            traced += 1

            print("BLOCKER TRACE \(sampleID)")
            print("  verifyText: \(String(reflecting: verifyText))")
            print("  productionText: \(String(reflecting: production.text))")
            print("  debugRawText: \(String(reflecting: debugTrace.rawText))")
            print("  debugTrimmedText: \(String(reflecting: debugTrace.trimmedText))")
            print("  tokens: \(debugTrace.generatedTokens)")
            print("  terminationToken: \(String(describing: debugTrace.terminationToken))")
            let firstStepTopTokens = debugTrace.firstStepTopTokens.map { token in
                "tokenId=\(token.tokenId), logit=\(token.logit)"
            }.joined(separator: "; ")
            print("  firstStepTopTokens: [\(firstStepTopTokens)]")
        }

        XCTAssertEqual(traced, targetIDs.count)
    }

    func testComparePromptVariantsOnKeyBlockers() throws {
        executionTimeAllowance = 20 * 60

        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping")
            return
        }

        let targetIDs = [
            "book1/007#region-010",
            "book1/007#region-012",
            "book1/007#region-014",
            "book1/007#region-015",
            "book1/011#region-006",
            "book1/001#region-001",
            "book1/003#region-002",
        ]

        let detectorSamples = try loadDetectorSamples()
        let verifyTexts = try loadVerifyTexts()
        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        let currentPrompt = "Perform OCR on this manga image. Output only the text, no explanation."
        let vendorOCRPrompt = "OCR:"
        var compared = 0

        for sampleID in targetIDs {
            guard let sample = detectorSamples[sampleID] else {
                XCTFail("Missing detector sample for \(sampleID)")
                continue
            }

            let imageURL = URL(fileURLWithPath: sample.imagePath)
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let debugCrop = expandedCropImage(for: sample.region, in: cgImage) else {
                XCTFail("Could not prepare crop for \(sampleID)")
                continue
            }

            let currentTrace = try engine.inferDebug(image: debugCrop, promptOverride: currentPrompt)
            let vendorTrace = try engine.inferDebug(image: debugCrop, promptOverride: vendorOCRPrompt)
            let verifyText = verifyTexts[sampleID] ?? "<missing>"
            compared += 1

            print("PROMPT TRACE \(sampleID)")
            print("  verifyText: \(String(reflecting: verifyText))")
            print("  currentPromptRaw: \(String(reflecting: currentTrace.rawText))")
            print("  currentPromptTokens: \(currentTrace.generatedTokens)")
            print("  currentPromptTermination: \(String(describing: currentTrace.terminationToken))")
            let currentTop = currentTrace.firstStepTopTokens.map { "tokenId=\($0.tokenId), logit=\($0.logit)" }.joined(separator: "; ")
            print("  currentPromptFirstStepTopTokens: [\(currentTop)]")
            print("  vendorPromptRaw: \(String(reflecting: vendorTrace.rawText))")
            print("  vendorPromptTokens: \(vendorTrace.generatedTokens)")
            print("  vendorPromptTermination: \(String(describing: vendorTrace.terminationToken))")
            let vendorTop = vendorTrace.firstStepTopTokens.map { "tokenId=\($0.tokenId), logit=\($0.logit)" }.joined(separator: "; ")
            print("  vendorPromptFirstStepTopTokens: [\(vendorTop)]")
        }

        XCTAssertEqual(compared, targetIDs.count)
    }

    private func loadDetectorSamples() throws -> [String: DetectorRegionSample] {
        let detectorData = try Data(contentsOf: parityDetectorJSONPath)
        guard let payload = try JSONSerialization.jsonObject(with: detectorData) as? [String: Any],
              let pages = payload["pages"] as? [[String: Any]] else {
            throw NSError(domain: "PaddleOCRProductionParityDiagnosticTests", code: 1)
        }

        var samples: [String: DetectorRegionSample] = [:]
        for page in pages {
            guard let imagePath = page["imagePath"] as? String,
                  let regions = page["regions"] as? [[String: Any]] else {
                continue
            }

            let relativeImagePath: String
            if let examplesRange = imagePath.range(of: "/examples/") {
                relativeImagePath = String(imagePath[examplesRange.upperBound...])
            } else {
                relativeImagePath = URL(fileURLWithPath: imagePath).lastPathComponent
            }
            let relativeSamplePath = (relativeImagePath as NSString).deletingPathExtension

            for (index, region) in regions.enumerated() {
                guard let x = region["x"] as? Double,
                      let y = region["y"] as? Double,
                      let width = region["width"] as? Double,
                      let height = region["height"] as? Double else {
                    continue
                }

                let sampleID = "\(relativeSamplePath)#region-\(String(format: "%03d", index + 1))"
                samples[sampleID] = DetectorRegionSample(
                    sampleID: sampleID,
                    imagePath: imagePath,
                    region: CGRect(x: x, y: y, width: width, height: height)
                )
            }
        }

        return samples
    }

    private func loadVerifyTexts() throws -> [String: String] {
        let verifyData = try Data(contentsOf: parityVerifyJSONPath)
        guard let payload = try JSONSerialization.jsonObject(with: verifyData) as? [String: Any],
              let records = payload["records"] as? [[String: Any]] else {
            throw NSError(domain: "PaddleOCRProductionParityDiagnosticTests", code: 2)
        }

        var texts: [String: String] = [:]
        for record in records {
            guard let sampleID = record["sample_id"] as? String else {
                continue
            }
            texts[sampleID] = (record["quantized_text"] as? String) ?? ""
        }
        return texts
    }

    private func expandedCropImage(for region: CGRect, in image: CGImage) -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropPaddingRatio: CGFloat = 0.18
        let minimumHorizontalPadding: CGFloat = 10
        let minimumVerticalPadding: CGFloat = 6
        let elongatedBubbleThreshold: CGFloat = 1.6
        let tallBubbleThreshold: CGFloat = 0.7
        let elongatedHorizontalBoostRatio: CGFloat = 0.08
        let tallVerticalBoostRatio: CGFloat = 0.08

        guard region.width > 0 && region.height > 0 else { return nil }

        let aspectRatio = region.width / region.height
        var horizontalPadding = max(minimumHorizontalPadding, region.width * cropPaddingRatio)
        var verticalPadding = max(minimumVerticalPadding, region.height * cropPaddingRatio)

        if aspectRatio >= elongatedBubbleThreshold {
            horizontalPadding += region.width * elongatedHorizontalBoostRatio
        } else if aspectRatio <= tallBubbleThreshold {
            verticalPadding += region.height * tallVerticalBoostRatio
        }

        let expanded = region.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        let clamped = expanded.intersection(imageBounds).integral
        guard clamped.width > 0 && clamped.height > 0 else { return nil }
        return image.cropping(to: clamped)
    }
}
#endif
