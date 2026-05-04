import Foundation

struct ImageScanner {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png"]

    func findImages(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        var images: [URL] = []
        for case let url as URL in enumerator {
            if Self.imageExtensions.contains(url.pathExtension.lowercased()) {
                images.append(url)
            }
        }
        return images.sorted { $0.path < $1.path }
    }
}
