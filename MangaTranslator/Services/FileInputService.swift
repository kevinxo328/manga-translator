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

    static func extractArchive(
        _ archiveURL: URL,
        limits: ArchiveExtractor.Limits = .default,
        tempDirBase: URL? = nil
    ) throws -> URL {
        let fm = FileManager.default
        let base = tempDirBase ?? fm.temporaryDirectory.appendingPathComponent("MangaTranslator")
        let tempDir = base.appendingPathComponent(UUID().uuidString)

        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        do {
            try ArchiveExtractor.extract(archiveURL: archiveURL, into: tempDir, limits: limits)
            return tempDir
        } catch {
            try? fm.removeItem(at: tempDir)
            throw FileInputError.extractionFailed
        }
    }

    static func copyToTemp(_ url: URL) throws -> URL {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("MangaTranslator")
            .appendingPathComponent(UUID().uuidString)
        
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let destURL = tempDir.appendingPathComponent(url.lastPathComponent)
        try fm.copyItem(at: url, to: destURL)
        
        return destURL
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
