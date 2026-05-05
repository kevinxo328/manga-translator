import AppKit
import DetectorExportCore
import Foundation

private struct DetectorExportCLIError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private struct DetectorExportRequest: Decodable {
    let imagePaths: [String]
}

@main
struct DetectorExportCLI {
    static func main() {
        do {
            let configuration = try parseArguments(Array(CommandLine.arguments.dropFirst()))
            let detector = ComicTextDetectorService(
                modelURLProvider: { URL(fileURLWithPath: configuration.modelPath) }
            )
            let exporter = ComicTextDetectorExporter(detector: detector)
            try exporter.writeJSON(
                pageImagePaths: configuration.imagePaths,
                to: URL(fileURLWithPath: configuration.outputPath)
            )
        } catch {
            fputs("DetectorExportCLI error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func parseArguments(_ arguments: [String]) throws -> (
        modelPath: String,
        outputPath: String,
        imagePaths: [String]
    ) {
        var modelPath: String?
        var outputPath: String?
        var imagePaths = [String]()
        var imageListJSONPath: String?

        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--model-path":
                index += 1
                guard index < arguments.count else {
                    throw DetectorExportCLIError(message: "missing value for --model-path")
                }
                modelPath = arguments[index]
            case "--output":
                index += 1
                guard index < arguments.count else {
                    throw DetectorExportCLIError(message: "missing value for --output")
                }
                outputPath = arguments[index]
            case "--image":
                index += 1
                guard index < arguments.count else {
                    throw DetectorExportCLIError(message: "missing value for --image")
                }
                imagePaths.append(arguments[index])
            case "--image-list-json":
                index += 1
                guard index < arguments.count else {
                    throw DetectorExportCLIError(message: "missing value for --image-list-json")
                }
                imageListJSONPath = arguments[index]
            default:
                throw DetectorExportCLIError(message: "unknown argument: \(arguments[index])")
            }
            index += 1
        }

        guard let modelPath else {
            throw DetectorExportCLIError(message: "--model-path is required")
        }
        guard let outputPath else {
            throw DetectorExportCLIError(message: "--output is required")
        }

        if let imageListJSONPath {
            let data = try Data(contentsOf: URL(fileURLWithPath: imageListJSONPath))
            let request = try JSONDecoder().decode(DetectorExportRequest.self, from: data)
            imagePaths.append(contentsOf: request.imagePaths)
        }

        if imagePaths.isEmpty {
            throw DetectorExportCLIError(message: "at least one --image or --image-list-json entry is required")
        }

        return (modelPath: modelPath, outputPath: outputPath, imagePaths: imagePaths)
    }
}
