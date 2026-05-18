import Foundation

struct ImageScanner {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png"]

    private func shouldSkipDescendant(url: URL, rootDirectory: URL) -> Bool {
        let rootComponents = rootDirectory.standardizedFileURL.pathComponents
        let pathComponents = url.standardizedFileURL.pathComponents
        guard pathComponents.count > rootComponents.count else { return false }
        let components = pathComponents.dropFirst(rootComponents.count).dropLast()
        return components.contains { component in
            component.hasPrefix(".") || component.hasPrefix("_")
        }
    }

    func findImages(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        var images: [URL] = []
        for case let url as URL in enumerator {
            if shouldSkipDescendant(url: url, rootDirectory: directory) {
                if ((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if Self.imageExtensions.contains(url.pathExtension.lowercased()) {
                images.append(url)
            }
        }
        return images.sorted { $0.path < $1.path }
    }
}
