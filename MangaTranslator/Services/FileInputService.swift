import Foundation

enum FileInputService {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif"]

    static func scanFolder(_ url: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var imageURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            // Skip __MACOSX metadata folder commonly found in zip archives
            if fileURL.pathComponents.contains("__MACOSX") { continue }
            if imageExtensions.contains(fileURL.pathExtension.lowercased()) {
                imageURLs.append(fileURL)
            }
        }

        return imageURLs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func extractArchive(_ archiveURL: URL) throws -> URL {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("MangaTranslator")
            .appendingPathComponent(UUID().uuidString)

        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", archiveURL.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw FileInputError.extractionFailed
        }

        return tempDir
    }
}

enum FileInputError: LocalizedError {
    case extractionFailed

    var errorDescription: String? {
        switch self {
        case .extractionFailed: return "Failed to extract archive"
        }
    }
}
