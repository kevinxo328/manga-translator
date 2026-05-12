import XCTest
@testable import MangaTranslator
import AppKit
import Foundation
import CoreGraphics

#if arch(arm64)
@testable import MangaTranslatorMLX

@MainActor
final class PaddleOCRProductionParityDiagnosticTests: XCTestCase {
    private var parityDetectorJSONPath: URL {
        diagnosticInputURL(
            filename: "paddle-detector-examples.json",
            specificPathEnv: "PADDLEOCR_DETECTOR_JSON_PATH"
        )
    }

    private var parityVerifyJSONPath: URL {
        diagnosticInputURL(
            filename: "paddle-verify-examples.json",
            specificPathEnv: "PADDLEOCR_VERIFY_JSON_PATH"
        )
    }

    private var prefillStageBlockersJSONPath: URL {
        diagnosticOutputURL(
            filename: "paddle-prefill-stage-blockers.json",
            specificPathEnv: "PADDLEOCR_PREFILL_STAGE_OUTPUT_PATH"
        )
    }

    private var prefillStageSelectedJSONPath: URL {
        diagnosticOutputURL(
            filename: "paddle-prefill-stage-selected.json",
            specificPathEnv: "PADDLEOCR_SELECTED_PREFILL_STAGE_OUTPUT_PATH"
        )
    }

    private var selectedSampleIDsPath: URL {
        diagnosticInputURL(
            filename: "paddle-target-samples.txt",
            specificPathEnv: "PADDLEOCR_TARGET_SAMPLE_IDS_PATH"
        )
    }

    private var verifyPrefillStageSelectedJSONPath: URL {
        diagnosticInputURL(
            filename: "verify-prefill-selected.json",
            specificPathEnv: "PADDLEOCR_VERIFY_PREFILL_STAGE_PATH"
        )
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let envEnabled = ProcessInfo.processInfo.environment["ENABLE_PADDLEOCR_DIAGNOSTIC_TESTS"] == "1"
        let artifactsAvailable = FileManager.default.fileExists(atPath: parityDetectorJSONPath.path)
            && FileManager.default.fileExists(atPath: parityVerifyJSONPath.path)
        guard envEnabled || artifactsAvailable else {
            throw XCTSkip(
                """
                Set ENABLE_PADDLEOCR_DIAGNOSTIC_TESTS=1, or provide parity JSON artifacts via \
                PADDLEOCR_DETECTOR_JSON_PATH / PADDLEOCR_VERIFY_JSON_PATH, or place them in a supported diagnostics artifact directory.
                """
            )
        }
        logResolvedDiagnosticPaths()
    }

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

        let paritySwiftOutputJSONPath = diagnosticOutputURL(
            filename: "paddle-swift-production-examples.json",
            specificPathEnv: "PADDLEOCR_SWIFT_PRODUCTION_OUTPUT_PATH"
        )
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
            "book1/009#region-006",
            "book1/014#region-007",
            "book2/001#region-010",
            "book2/006#region-005",
            "book2/010#region-009",
            "book2/012#region-008",
            "book3/001#region-010",
            "book3/006#region-005",
            "book3/010#region-009",
            "book3/012#region-008",
        ]

        let detectorSamples = try loadDetectorSamples()
        let verifyTexts = try loadVerifyTexts()
        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        let currentPrompt = "Perform OCR on this manga image. Output only the text, no explanation."
        let vendorOCRPrompt = "OCR:"
        var compared = 0
        var records: [[String: Any]] = []

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

            records.append([
                "sample_id": sampleID,
                "verify_text": verifyText,
                "current_prompt_raw": currentTrace.rawText,
                "current_prompt_trimmed": currentTrace.trimmedText,
                "current_prompt_tokens": currentTrace.generatedTokens,
                "current_prompt_termination": currentTrace.terminationToken ?? NSNull(),
                "vendor_prompt_raw": vendorTrace.rawText,
                "vendor_prompt_trimmed": vendorTrace.trimmedText,
                "vendor_prompt_tokens": vendorTrace.generatedTokens,
                "vendor_prompt_termination": vendorTrace.terminationToken ?? NSNull(),
            ])
        }

        let outputURL = diagnosticOutputURL(
            filename: "paddle-prompt-variant-blockers.json",
            specificPathEnv: "PADDLEOCR_PROMPT_VARIANT_OUTPUT_PATH"
        )
        let outputData = try JSONSerialization.data(
            withJSONObject: ["records": records],
            options: [.prettyPrinted, .sortedKeys]
        )
        try outputData.write(to: outputURL, options: .atomic)
        print("Prompt variant diagnostics wrote \(records.count) records to \(outputURL.path)")
        XCTAssertEqual(compared, targetIDs.count)
    }

    func testCompareRoutingOnResidualEmptyCases() throws {
        executionTimeAllowance = 20 * 60

        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping")
            return
        }

        let targetIDs = [
            "book1/007#region-010",
            "book1/009#region-006",
            "book1/011#region-005",
            "book1/014#region-007",
        ]

        let detectorSamples = try loadDetectorSamples()
        let verifyTexts = try loadVerifyTexts()
        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        var records: [[String: Any]] = []

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

            let autoTrace = try engine.inferDebug(image: debugCrop, routeOverride: .automatic)
            let smartResizeTrace = try engine.inferDebug(image: debugCrop, routeOverride: .smartResize)
            let tiledTrace = try engine.inferDebug(image: debugCrop, routeOverride: .tiled)

            records.append([
                "sample_id": sampleID,
                "verify_text": verifyTexts[sampleID] ?? "<missing>",
                "auto_trimmed": autoTrace.trimmedText,
                "auto_tokens": autoTrace.generatedTokens,
                "smart_resize_trimmed": smartResizeTrace.trimmedText,
                "smart_resize_tokens": smartResizeTrace.generatedTokens,
                "tiled_trimmed": tiledTrace.trimmedText,
                "tiled_tokens": tiledTrace.generatedTokens,
            ])
        }

        let outputURL = diagnosticOutputURL(
            filename: "paddle-routing-empty-cases.json",
            specificPathEnv: "PADDLEOCR_ROUTING_EMPTY_OUTPUT_PATH"
        )
        let outputData = try JSONSerialization.data(
            withJSONObject: ["records": records],
            options: [.prettyPrinted, .sortedKeys]
        )
        try outputData.write(to: outputURL, options: .atomic)
        print("Routing diagnostics wrote \(records.count) records to \(outputURL.path)")
        XCTAssertEqual(records.count, targetIDs.count)
    }

    func testCompareRoutingOnShortTextCases() throws {
        executionTimeAllowance = 20 * 60

        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping")
            return
        }

        let targetIDs = [
            "book1/007#region-010",
            "book1/009#region-006",
            "book1/011#region-005",
            "book1/014#region-007",
            "book2/001#region-010",
            "book2/006#region-005",
            "book2/010#region-009",
            "book3/001#region-010",
            "book3/006#region-005",
            "book3/010#region-009",
        ]

        let detectorSamples = try loadDetectorSamples()
        let verifyTexts = try loadVerifyTexts()
        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        var records: [[String: Any]] = []

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

            let autoTrace = try engine.inferDebug(image: debugCrop, routeOverride: .automatic)
            let smartResizeTrace = try engine.inferDebug(image: debugCrop, routeOverride: .smartResize)
            let tiledTrace = try engine.inferDebug(image: debugCrop, routeOverride: .tiled)

            records.append([
                "sample_id": sampleID,
                "verify_text": verifyTexts[sampleID] ?? "<missing>",
                "auto_trimmed": autoTrace.trimmedText,
                "auto_tokens": autoTrace.generatedTokens,
                "smart_resize_trimmed": smartResizeTrace.trimmedText,
                "smart_resize_tokens": smartResizeTrace.generatedTokens,
                "tiled_trimmed": tiledTrace.trimmedText,
                "tiled_tokens": tiledTrace.generatedTokens,
            ])
        }

        let outputURL = diagnosticOutputURL(
            filename: "paddle-routing-short-text-cases.json",
            specificPathEnv: "PADDLEOCR_ROUTING_SHORT_TEXT_OUTPUT_PATH"
        )
        let outputData = try JSONSerialization.data(
            withJSONObject: ["records": records],
            options: [.prettyPrinted, .sortedKeys]
        )
        try outputData.write(to: outputURL, options: .atomic)
        print("Short-text routing diagnostics wrote \(records.count) records to \(outputURL.path)")
        XCTAssertEqual(records.count, targetIDs.count)
    }

    func testExportRoutingParityComparisonForVerifyExamples() throws {
        executionTimeAllowance = 30 * 60

        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping")
            return
        }

        let detectorSamples = try loadDetectorSamples()
        let verifyTexts = try loadVerifyTexts()
        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        let sampleIDs = detectorSamples.keys.sorted()
        var records: [[String: Any]] = []

        for sampleID in sampleIDs {
            guard let sample = detectorSamples[sampleID] else {
                continue
            }

            let imageURL = URL(fileURLWithPath: sample.imagePath)
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let debugCrop = expandedCropImage(for: sample.region, in: cgImage) else {
                XCTFail("Could not prepare crop for \(sampleID)")
                return
            }

            let smartResizeTrace = try engine.inferDebug(image: debugCrop, routeOverride: .smartResize)
            let tiledTrace = try engine.inferDebug(image: debugCrop, routeOverride: .tiled)

            records.append([
                "sample_id": sampleID,
                "verify_text": verifyTexts[sampleID] ?? "",
                "crop_width": debugCrop.width,
                "crop_height": debugCrop.height,
                "smart_resize_trimmed": smartResizeTrace.trimmedText,
                "smart_resize_tokens": smartResizeTrace.generatedTokens,
                "tiled_trimmed": tiledTrace.trimmedText,
                "tiled_tokens": tiledTrace.generatedTokens,
            ])
        }

        let outputURL = diagnosticOutputURL(
            filename: "paddle-routing-parity-examples.json",
            specificPathEnv: "PADDLEOCR_ROUTING_PARITY_OUTPUT_PATH"
        )
        let outputData = try JSONSerialization.data(
            withJSONObject: ["records": records],
            options: [.prettyPrinted, .sortedKeys]
        )
        try outputData.write(to: outputURL, options: .atomic)
        print("Routing parity comparison wrote \(records.count) records to \(outputURL.path)")
        XCTAssertEqual(records.count, sampleIDs.count)
    }

    func testExactMatchParityWithBaseline() throws {
        executionTimeAllowance = 30 * 60

        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping parity exact-match")
            return
        }

        let detectorSamples = try loadDetectorSamples()
        let verifyTexts = try loadVerifyTexts()
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: resolvedDir)
        var tested = 0

        for (sampleID, sample) in detectorSamples {
            let imageURL = URL(fileURLWithPath: sample.imagePath)
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }

            let result = try recognizer.recognizeText(in: cgImage, region: sample.region)
            let expectedText = verifyTexts[sampleID] ?? ""
            
            // The parity gate: exact match assertion
            XCTAssertEqual(
                result.text,
                expectedText,
                "Output for \(sampleID) must match baseline exactly to ensure zero regression."
            )
            tested += 1
        }
        
        print("Verified exact parity for \(tested) benchmark samples.")
        XCTAssertGreaterThan(tested, 0)
    }

    func testExactMatchParityForSelectedSamples() throws {
        executionTimeAllowance = 30 * 60

        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping parity exact-match")
            return
        }

        let selectedSampleIDs = selectedSampleIDsFromEnvironment()
        guard selectedSampleIDs.isEmpty == false else {
            throw XCTSkip("Set PADDLEOCR_TARGET_SAMPLE_IDS to run selected-sample parity checks.")
        }

        let detectorSamples = try loadDetectorSamples()
        let verifyTexts = try loadVerifyTexts()
        let recognizer = PaddleOCRVLRecognizer(modelDirectory: resolvedDir)
        var tested = 0

        for sampleID in selectedSampleIDs {
            guard let sample = detectorSamples[sampleID] else {
                XCTFail("Missing detector sample for \(sampleID)")
                continue
            }

            let imageURL = URL(fileURLWithPath: sample.imagePath)
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                XCTFail("Could not load image at \(sample.imagePath)")
                continue
            }

            let result = try recognizer.recognizeText(in: cgImage, region: sample.region)
            let expectedText = verifyTexts[sampleID] ?? ""

            XCTAssertEqual(
                result.text,
                expectedText,
                "Output for \(sampleID) must match baseline exactly to ensure zero regression."
            )
            tested += 1
        }

        print("Verified exact parity for \(tested) selected samples.")
        XCTAssertEqual(tested, selectedSampleIDs.count)
    }

    func testExportPrefillStageSummariesForVerifyBlockers() throws {
        executionTimeAllowance = 20 * 60

        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping prefill stage summary export")
            return
        }

        let targetIDs = [
            "book1/001#region-001",
            "book1/001#region-003",
            "book1/001#region-004",
            "book1/002#region-010",
            "book1/003#region-002",
            "book1/007#region-010",
            "book1/007#region-012",
            "book1/007#region-014",
            "book1/007#region-015",
            "book1/011#region-006",
        ]

        let detectorSamples = try loadDetectorSamples()
        let verifyTexts = try loadVerifyTexts()
        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        var records: [[String: Any]] = []

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

            let smartResizeSummary = try engine.inferPrefillStageSummaries(
                image: debugCrop,
                routeOverride: .smartResize
            )
            let tiledSummary = try engine.inferPrefillStageSummaries(
                image: debugCrop,
                routeOverride: .tiled
            )

            records.append([
                "sample_id": sampleID,
                "verify_text": verifyTexts[sampleID] ?? "<missing>",
                "crop_width": debugCrop.width,
                "crop_height": debugCrop.height,
                "smart_resize": serialize(summary: smartResizeSummary),
                "tiled": serialize(summary: tiledSummary),
            ])
        }

        let outputURL = prefillStageBlockersJSONPath
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let outputData = try JSONSerialization.data(
            withJSONObject: ["records": records],
            options: [.prettyPrinted, .sortedKeys]
        )
        try outputData.write(to: outputURL, options: .atomic)
        print("Prefill stage diagnostics wrote \(records.count) records to \(outputURL.path)")
        XCTAssertEqual(records.count, targetIDs.count)
    }

    func testExportPrefillStageSummariesForSelectedSamples() throws {
        executionTimeAllowance = 20 * 60

        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping prefill stage summary export")
            return
        }

        let selectedSampleIDs = selectedSampleIDsFromEnvironment()
        guard selectedSampleIDs.isEmpty == false else {
            throw XCTSkip("Provide selected sample IDs via diagnostics artifact or PADDLEOCR_TARGET_SAMPLE_IDS.")
        }

        let detectorSamples = try loadDetectorSamples()
        let verifyTexts = try loadVerifyTexts()
        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        var records: [[String: Any]] = []

        for sampleID in selectedSampleIDs {
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

            let smartResizeSummary = try engine.inferPrefillStageSummaries(
                image: debugCrop,
                routeOverride: .smartResize
            )
            let tiledSummary = try engine.inferPrefillStageSummaries(
                image: debugCrop,
                routeOverride: .tiled
            )

            records.append([
                "sample_id": sampleID,
                "verify_text": verifyTexts[sampleID] ?? "<missing>",
                "crop_width": debugCrop.width,
                "crop_height": debugCrop.height,
                "smart_resize": serialize(summary: smartResizeSummary),
                "tiled": serialize(summary: tiledSummary),
            ])
        }

        let outputURL = prefillStageSelectedJSONPath
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let outputData = try JSONSerialization.data(
            withJSONObject: ["records": records],
            options: [.prettyPrinted, .sortedKeys]
        )
        try outputData.write(to: outputURL, options: .atomic)
        print("Selected prefill stage diagnostics wrote \(records.count) records to \(outputURL.path)")
        XCTAssertEqual(records.count, selectedSampleIDs.count)
    }

    func testCompareSelectedPrefillStageSummariesAgainstVerify() throws {
        executionTimeAllowance = 20 * 60

        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping selected parity comparison")
            return
        }

        let selectedSampleIDs = selectedSampleIDsFromEnvironment()
        guard selectedSampleIDs.isEmpty == false else {
            throw XCTSkip("Provide selected sample IDs via diagnostics artifact or PADDLEOCR_TARGET_SAMPLE_IDS.")
        }

        let detectorSamples = try loadDetectorSamples()
        let verifyTexts = try loadVerifyTexts()
        let verifyPrefillRecords = try loadVerifyPrefillRecords()
        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        var compared = 0

        for sampleID in selectedSampleIDs {
            guard let sample = detectorSamples[sampleID] else {
                XCTFail("Missing detector sample for \(sampleID)")
                continue
            }
            guard let verifyRecord = verifyPrefillRecords[sampleID] else {
                XCTFail("Missing verify prefill record for \(sampleID)")
                continue
            }

            let imageURL = URL(fileURLWithPath: sample.imagePath)
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let debugCrop = expandedCropImage(for: sample.region, in: cgImage) else {
                XCTFail("Could not prepare crop for \(sampleID)")
                continue
            }

            let swiftSummary = try engine.inferPrefillStageSummaries(
                image: debugCrop,
                routeOverride: .smartResize
            )

            print("SELECTED PREFILL PARITY \(sampleID)")
            print("  verifyText: \(String(reflecting: verifyTexts[sampleID] ?? "<missing>"))")
            print("  verifyGeneratedTokens: \(verifyRecord.generatedTokens)")
            print("  swiftGeneratedTokens: \(swiftSummary.generatedTokens)")
            print("  firstStepTopToken verify=\(verifyRecord.firstStepTopTokens.first?.tokenId ?? -1) swift=\(swiftSummary.firstStepTopTokens.first?.tokenId ?? -1)")
            print("  pixelValues l2 verify=\(verifyRecord.pixelValues.l2) swift=\(swiftSummary.pixelValues.l2)")
            print("  visionPatchEmbeddings l2 verify=\(verifyRecord.visionPatchEmbeddings.l2) swift=\(swiftSummary.visionPatchEmbeddings.l2)")
            print("  visionPositionEmbeddings l2 verify=\(verifyRecord.visionPositionEmbeddings.l2) swift=\(swiftSummary.visionPositionEmbeddings.l2)")
            print("  visionInputEmbeddings l2 verify=\(verifyRecord.visionInputEmbeddings.l2) swift=\(swiftSummary.visionInputEmbeddings.l2)")
            print("  visionFirstLayerOutput l2 verify=\(verifyRecord.visionFirstLayerOutput.l2) swift=\(swiftSummary.visionFirstLayerOutput.l2)")
            print("  encodedVisionFeatures l2 verify=\(verifyRecord.encodedVisionFeatures.l2) swift=\(swiftSummary.encodedVisionFeatures.l2)")
            print("  projectedImageFeatures l2 verify=\(verifyRecord.projectedImageFeatures.l2) swift=\(swiftSummary.projectedImageFeatures.l2)")
            print("  mergedEmbeddings l2 verify=\(verifyRecord.mergedEmbeddings.l2) swift=\(swiftSummary.mergedEmbeddings.l2)")
            print("  firstStepLogits l2 verify=\(verifyRecord.firstStepLogits.l2) swift=\(swiftSummary.firstStepLogits.l2)")
            compared += 1
        }

        XCTAssertEqual(compared, selectedSampleIDs.count)
    }

    func testCompareRoutingForSelectedSamples() throws {
        executionTimeAllowance = 20 * 60

        let modelRoot = ModelDownloadService.defaultModelDirectory()
        guard let resolvedDir = ModelDownloadService.resolvedModelDirectory(in: modelRoot) else {
            print("PaddleOCR model not available — skipping selected route comparison")
            return
        }

        let selectedSampleIDs = selectedSampleIDsFromEnvironment()
        guard selectedSampleIDs.isEmpty == false else {
            throw XCTSkip("Provide selected sample IDs via diagnostics artifact or PADDLEOCR_TARGET_SAMPLE_IDS.")
        }

        let detectorSamples = try loadDetectorSamples()
        let engine = try DefaultPaddleOCREngine(modelDirectory: resolvedDir)
        var compared = 0

        for sampleID in selectedSampleIDs {
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

            let automaticTrace = try engine.inferDebug(image: debugCrop, routeOverride: .automatic)
            let smartResizeTrace = try engine.inferDebug(image: debugCrop, routeOverride: .smartResize)
            let tiledTrace = try engine.inferDebug(image: debugCrop, routeOverride: .tiled)

            print("SELECTED ROUTE PARITY \(sampleID)")
            print("  automatic: \(String(reflecting: automaticTrace.trimmedText)) tokens=\(automaticTrace.generatedTokens)")
            print("  smartResize: \(String(reflecting: smartResizeTrace.trimmedText)) tokens=\(smartResizeTrace.generatedTokens)")
            print("  tiled: \(String(reflecting: tiledTrace.trimmedText)) tokens=\(tiledTrace.generatedTokens)")
            compared += 1
        }

        XCTAssertEqual(compared, selectedSampleIDs.count)
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

    private struct VerifyPrefillRecord {
        struct VisionLayerSubstepRecord {
            let layerIndex: Int
            let inputHiddenStates: PaddleOCRTensorSummary
            let postLayerNorm1: PaddleOCRTensorSummary
            let preRotaryQueries: PaddleOCRTensorSummary
            let preRotaryKeys: PaddleOCRTensorSummary
            let postRotaryQueries: PaddleOCRTensorSummary
            let postRotaryKeys: PaddleOCRTensorSummary
            let values: PaddleOCRTensorSummary
            let attentionOutput: PaddleOCRTensorSummary
            let postAttentionResidual: PaddleOCRTensorSummary
            let postLayerNorm2: PaddleOCRTensorSummary
            let fc1Output: PaddleOCRTensorSummary
            let geluOutput: PaddleOCRTensorSummary
            let mlpOutput: PaddleOCRTensorSummary
            let outputHiddenStates: PaddleOCRTensorSummary
        }

        let generatedTokens: [Int]
        let firstStepTopTokens: [PaddleOCRDebugToken]
        let pixelValues: PaddleOCRTensorSummary
        let visionPatchEmbeddings: PaddleOCRTensorSummary
        let visionPositionEmbeddings: PaddleOCRTensorSummary
        let visionInputEmbeddings: PaddleOCRTensorSummary
        let visionFirstLayerOutput: PaddleOCRTensorSummary
        let visionLayerOutputs: [PaddleOCRTensorSummary]
        let visionTargetLayerSubsteps: [VisionLayerSubstepRecord]
        let encodedVisionFeatures: PaddleOCRTensorSummary
        let projectedImageFeatures: PaddleOCRTensorSummary
        let mergedEmbeddings: PaddleOCRTensorSummary
        let firstStepLogits: PaddleOCRTensorSummary
    }

    private func loadVerifyPrefillRecords() throws -> [String: VerifyPrefillRecord] {
        let data = try Data(contentsOf: verifyPrefillStageSelectedJSONPath)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = payload["records"] as? [[String: Any]] else {
            throw NSError(domain: "PaddleOCRProductionParityDiagnosticTests", code: 3)
        }

        var result: [String: VerifyPrefillRecord] = [:]
        for record in records {
            guard let sampleID = record["sample_id"] as? String,
                  let generatedTokens = record["generated_tokens"] as? [Int],
                  let firstStepTopTokensRaw = record["first_step_top_tokens"] as? [[String: Any]],
                  let pixelValuesRaw = record["pixel_values"] as? [String: Any],
                  let visionPatchEmbeddingsRaw = record["vision_patch_embeddings"] as? [String: Any],
                  let visionPositionEmbeddingsRaw = record["vision_position_embeddings"] as? [String: Any],
                  let visionInputEmbeddingsRaw = record["vision_input_embeddings"] as? [String: Any],
                  let visionFirstLayerOutputRaw = record["vision_first_layer_output"] as? [String: Any],
                  let visionLayerOutputsRaw = record["vision_layer_outputs"] as? [[String: Any]],
                  let visionTargetLayerSubstepsRaw = record["vision_target_layer_substeps"] as? [[String: Any]],
                  let encodedVisionFeaturesRaw = record["encoded_vision_features"] as? [String: Any],
                  let projectedImageFeaturesRaw = record["projected_image_features"] as? [String: Any],
                  let mergedEmbeddingsRaw = record["merged_embeddings"] as? [String: Any],
                  let firstStepLogitsRaw = record["first_step_logits"] as? [String: Any] else {
                continue
            }

            result[sampleID] = VerifyPrefillRecord(
                generatedTokens: generatedTokens,
                firstStepTopTokens: firstStepTopTokensRaw.compactMap { token in
                    guard let tokenId = token["token_id"] as? Int,
                          let logit = token["logit"] as? Double else {
                        return nil
                    }
                    return PaddleOCRDebugToken(tokenId: tokenId, logit: Float(logit))
                },
                pixelValues: try parseTensorSummary(pixelValuesRaw),
                visionPatchEmbeddings: try parseTensorSummary(visionPatchEmbeddingsRaw),
                visionPositionEmbeddings: try parseTensorSummary(visionPositionEmbeddingsRaw),
                visionInputEmbeddings: try parseTensorSummary(visionInputEmbeddingsRaw),
                visionFirstLayerOutput: try parseTensorSummary(visionFirstLayerOutputRaw),
                visionLayerOutputs: try visionLayerOutputsRaw.map(parseTensorSummary),
                visionTargetLayerSubsteps: try parseVisionLayerSubsteps(visionTargetLayerSubstepsRaw),
                encodedVisionFeatures: try parseTensorSummary(encodedVisionFeaturesRaw),
                projectedImageFeatures: try parseTensorSummary(projectedImageFeaturesRaw),
                mergedEmbeddings: try parseTensorSummary(mergedEmbeddingsRaw),
                firstStepLogits: try parseTensorSummary(firstStepLogitsRaw)
            )
        }

        return result
    }

    private func parseTensorSummary(_ payload: [String: Any]) throws -> PaddleOCRTensorSummary {
        guard let dtype = payload["dtype"] as? String,
              let shape = payload["shape"] as? [Int],
              let min = payload["min"] as? Double,
              let max = payload["max"] as? Double,
              let mean = payload["mean"] as? Double,
              let std = payload["std"] as? Double,
              let l2 = payload["l2"] as? Double,
              let prefix = payload["prefix"] as? [Double] else {
            throw NSError(domain: "PaddleOCRProductionParityDiagnosticTests", code: 4)
        }
        let tokenRowPrefixes = (payload["token_row_prefixes"] as? [[Double]] ?? []).map { $0.map(Float.init) }

        return PaddleOCRTensorSummary(
            dtype: dtype,
            shape: shape,
            min: Float(min),
            max: Float(max),
            mean: Float(mean),
            std: Float(std),
            l2: Float(l2),
            prefix: prefix.map(Float.init),
            tokenRowPrefixes: tokenRowPrefixes
        )
    }

    private func parseVisionLayerSubsteps(_ payloads: [[String: Any]]) throws -> [VerifyPrefillRecord.VisionLayerSubstepRecord] {
        try payloads.map { payload in
            guard let layerIndex = payload["layer_index"] as? Int,
                  let inputHiddenStatesRaw = payload["input_hidden_states"] as? [String: Any],
                  let postLayerNorm1Raw = payload["post_layer_norm1"] as? [String: Any],
                  let preRotaryQueriesRaw = payload["pre_rotary_queries"] as? [String: Any],
                  let preRotaryKeysRaw = payload["pre_rotary_keys"] as? [String: Any],
                  let postRotaryQueriesRaw = payload["post_rotary_queries"] as? [String: Any],
                  let postRotaryKeysRaw = payload["post_rotary_keys"] as? [String: Any],
                  let valuesRaw = payload["values"] as? [String: Any],
                  let attentionOutputRaw = payload["attention_output"] as? [String: Any],
                  let postAttentionResidualRaw = payload["post_attention_residual"] as? [String: Any],
                  let postLayerNorm2Raw = payload["post_layer_norm2"] as? [String: Any],
                  let fc1OutputRaw = payload["fc1_output"] as? [String: Any],
                  let geluOutputRaw = payload["gelu_output"] as? [String: Any],
                  let mlpOutputRaw = payload["mlp_output"] as? [String: Any],
                  let outputHiddenStatesRaw = payload["output_hidden_states"] as? [String: Any] else {
                throw NSError(domain: "PaddleOCRProductionParityDiagnosticTests", code: 5)
            }

            return VerifyPrefillRecord.VisionLayerSubstepRecord(
                layerIndex: layerIndex,
                inputHiddenStates: try parseTensorSummary(inputHiddenStatesRaw),
                postLayerNorm1: try parseTensorSummary(postLayerNorm1Raw),
                preRotaryQueries: try parseTensorSummary(preRotaryQueriesRaw),
                preRotaryKeys: try parseTensorSummary(preRotaryKeysRaw),
                postRotaryQueries: try parseTensorSummary(postRotaryQueriesRaw),
                postRotaryKeys: try parseTensorSummary(postRotaryKeysRaw),
                values: try parseTensorSummary(valuesRaw),
                attentionOutput: try parseTensorSummary(attentionOutputRaw),
                postAttentionResidual: try parseTensorSummary(postAttentionResidualRaw),
                postLayerNorm2: try parseTensorSummary(postLayerNorm2Raw),
                fc1Output: try parseTensorSummary(fc1OutputRaw),
                geluOutput: try parseTensorSummary(geluOutputRaw),
                mlpOutput: try parseTensorSummary(mlpOutputRaw),
                outputHiddenStates: try parseTensorSummary(outputHiddenStatesRaw)
            )
        }
    }

    private func serialize(summary: PaddleOCRPrefillStageSummaries) -> [String: Any] {
        [
            "route": routeLabel(summary.route),
            "input_ids_count": summary.inputIds.count,
            "input_ids_prefix": Array(summary.inputIds.prefix(16)),
            "target_width": summary.targetWidth,
            "target_height": summary.targetHeight,
            "generated_tokens": summary.generatedTokens,
            "termination_token": summary.terminationToken ?? NSNull(),
            "first_step_top_tokens": summary.firstStepTopTokens.map { token in
                [
                    "token_id": token.tokenId,
                    "logit": token.logit,
                ]
            },
            "pixel_values": serialize(tensor: summary.pixelValues),
            "vision_patch_embeddings": serialize(tensor: summary.visionPatchEmbeddings),
            "vision_position_embeddings": serialize(tensor: summary.visionPositionEmbeddings),
            "vision_input_embeddings": serialize(tensor: summary.visionInputEmbeddings),
            "vision_first_layer_output": serialize(tensor: summary.visionFirstLayerOutput),
            "vision_layer_outputs": summary.visionLayerOutputs.map { serialize(tensor: $0) },
            "vision_target_layer_substeps": summary.visionTargetLayerSubsteps.map { layer in
                [
                    "layer_index": layer.layerIndex,
                    "input_hidden_states": serialize(tensor: layer.inputHiddenStates),
                    "post_layer_norm1": serialize(tensor: layer.postLayerNorm1),
                    "pre_rotary_queries": serialize(tensor: layer.preRotaryQueries),
                    "pre_rotary_keys": serialize(tensor: layer.preRotaryKeys),
                    "post_rotary_queries": serialize(tensor: layer.postRotaryQueries),
                    "post_rotary_keys": serialize(tensor: layer.postRotaryKeys),
                    "values": serialize(tensor: layer.values),
                    "attention_output": serialize(tensor: layer.attentionOutput),
                    "post_attention_residual": serialize(tensor: layer.postAttentionResidual),
                    "post_layer_norm2": serialize(tensor: layer.postLayerNorm2),
                    "fc1_output": serialize(tensor: layer.fc1Output),
                    "gelu_output": serialize(tensor: layer.geluOutput),
                    "mlp_output": serialize(tensor: layer.mlpOutput),
                    "output_hidden_states": serialize(tensor: layer.outputHiddenStates),
                ]
            },
            "encoded_vision_features": serialize(tensor: summary.encodedVisionFeatures),
            "projected_image_features": serialize(tensor: summary.projectedImageFeatures),
            "merged_embeddings": serialize(tensor: summary.mergedEmbeddings),
            "first_step_logits": serialize(tensor: summary.firstStepLogits),
        ]
    }

    private func serialize(tensor: PaddleOCRTensorSummary) -> [String: Any] {
        [
            "dtype": tensor.dtype,
            "shape": tensor.shape,
            "min": tensor.min,
            "max": tensor.max,
            "mean": tensor.mean,
            "std": tensor.std,
            "l2": tensor.l2,
            "prefix": tensor.prefix,
            "token_row_prefixes": tensor.tokenRowPrefixes,
        ]
    }

    private func routeLabel(_ route: PaddleOCRDebugRoute) -> String {
        switch route {
        case .automatic:
            return "automatic"
        case .smartResize:
            return "smart_resize"
        case .tiled:
            return "tiled"
        }
    }

    private func diagnosticInputURL(filename: String, specificPathEnv: String) -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let explicitPath = environment[specificPathEnv], explicitPath.isEmpty == false {
            return URL(fileURLWithPath: explicitPath)
        }

        for candidate in diagnosticInputCandidates(filename: filename) {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return diagnosticInputCandidates(filename: filename)[0]
    }

    private func diagnosticInputCandidates(filename: String) -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [URL] = []

        if let directory = environment["PADDLEOCR_DIAGNOSTIC_INPUT_DIR"], directory.isEmpty == false {
            candidates.append(URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(filename))
        }

        candidates.append(diagnosticDirectoryURL().appendingPathComponent(filename))

        let repoRoot = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        candidates.append(
            repoRoot
                .appendingPathComponent(".artifacts", isDirectory: true)
                .appendingPathComponent("paddleocr", isDirectory: true)
                .appendingPathComponent(filename)
        )

        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        candidates.append(
            workingDirectory
                .appendingPathComponent(".artifacts", isDirectory: true)
                .appendingPathComponent("paddleocr", isDirectory: true)
                .appendingPathComponent(filename)
        )
        candidates.append(FileManager.default.temporaryDirectory.appendingPathComponent(filename))
        candidates.append(URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(filename))

        return candidates
    }

    private func diagnosticOutputURL(filename: String, specificPathEnv: String) -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let explicitPath = environment[specificPathEnv], explicitPath.isEmpty == false {
            return URL(fileURLWithPath: explicitPath)
        }

        if let explicitDirectory = environment["PADDLEOCR_DIAGNOSTIC_OUTPUT_DIR"], explicitDirectory.isEmpty == false {
            return URL(fileURLWithPath: explicitDirectory, isDirectory: true).appendingPathComponent(filename)
        }

        return diagnosticDirectoryURL().appendingPathComponent(filename)
    }

    private func diagnosticDirectoryURL() -> URL {
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("MangaTranslator", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private func logResolvedDiagnosticPaths() {
        print("PaddleOCR diagnostics input detector path: \(parityDetectorJSONPath.path)")
        print("PaddleOCR diagnostics input verify path: \(parityVerifyJSONPath.path)")
        print("PaddleOCR diagnostics selected sample path: \(selectedSampleIDsPath.path)")
        print("PaddleOCR diagnostics verify prefill path: \(verifyPrefillStageSelectedJSONPath.path)")
        print("PaddleOCR diagnostics output directory: \(diagnosticDirectoryURL().path)")
        print("PaddleOCR diagnostics blockers output path: \(prefillStageBlockersJSONPath.path)")
        print("PaddleOCR diagnostics selected output path: \(prefillStageSelectedJSONPath.path)")
    }

    private func selectedSampleIDsFromEnvironment() -> [String] {
        guard let rawValue = ProcessInfo.processInfo.environment["PADDLEOCR_TARGET_SAMPLE_IDS"],
              rawValue.isEmpty == false else {
            return selectedSampleIDsFromArtifact()
        }

        return rawValue
            .split { $0 == "," || $0 == "\n" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private func selectedSampleIDsFromArtifact() -> [String] {
        guard FileManager.default.fileExists(atPath: selectedSampleIDsPath.path),
              let rawValue = try? String(contentsOf: selectedSampleIDsPath, encoding: .utf8) else {
            return []
        }

        return rawValue
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && $0.hasPrefix("#") == false }
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
