// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DetectorExportTools",
    platforms: [
        .macOS(.v11),
    ],
    products: [
        .executable(
            name: "DetectorExportCLI",
            targets: ["DetectorExportCLI"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "onnxruntime",
            path: ".xcodebuild-env/SourcePackages/artifacts/onnxruntime-swift-package-manager/onnxruntime/onnxruntime.xcframework"
        ),
        .target(
            name: "OnnxRuntimeBindings",
            dependencies: ["onnxruntime"],
            path: ".xcodebuild-env/SourcePackages/checkouts/onnxruntime-swift-package-manager/objectivec",
            exclude: [
                "ReadMe.md",
                "format_objc.sh",
                "test",
                "docs",
                "ort_checkpoint.mm",
                "ort_checkpoint_internal.h",
                "ort_training_session_internal.h",
                "ort_training_session.mm",
                "include/ort_checkpoint.h",
                "include/ort_training_session.h",
                "include/onnxruntime_training.h",
            ],
            cxxSettings: [
                .define("SPM_BUILD"),
            ]
        ),
        .target(
            name: "DetectorExportCore",
            dependencies: ["OnnxRuntimeBindings"],
            path: "MangaTranslator/Services",
            exclude: [
                "BubbleDetector.swift",
                "CacheService.swift",
                "ComicTextDetectorExportCommand.swift",
                "CopilotEnvironment.swift",
                "CopilotTranslationService.swift",
                "DeepLTranslationService.swift",
                "DeviceCapabilityService.swift",
                "FileInputService.swift",
                "GlossaryService.swift",
                "GlossarySubstitution.swift",
                "GoogleTranslationService.swift",
                "KeychainService.swift",
                "LLMPrompt.swift",
                "MangaOCRRecognizer.swift",
                "MangaOCRService.swift",
                "MangaOCRTokenizer.swift",
                "ModelDownloadService.swift",
                "OCRRecognizing.swift",
                "OCRRouter.swift",
                "OpenAITranslationService.swift",
                "PaddleOCRError.swift",
                "PaddleOCRErrorUIMapping.swift",
                "PreferencesService.swift",
                "ReadingOrderSorter.swift",
                "TranslationError.swift",
                "UpdateChecker.swift",
                "VisionOCRService.swift",
            ],
            sources: [
                "ComicTextDetectorService.swift",
                "OCRError.swift",
            ]
        ),
        .executableTarget(
            name: "DetectorExportCLI",
            dependencies: ["DetectorExportCore"],
            path: "DetectorExportCLI",
            sources: ["main.swift"]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
