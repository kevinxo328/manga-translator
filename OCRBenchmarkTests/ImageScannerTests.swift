import XCTest

final class ImageScannerTests: XCTestCase {
    let scanner = ImageScanner()

    // Task 3.1 - finds images at multiple depths, skips non-images
    func testFindsImagesAtMultipleDepths() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let subDir = tmpDir.appendingPathComponent("sub")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try Data("img".utf8).write(to: tmpDir.appendingPathComponent("a.jpg"))
        try Data("img".utf8).write(to: subDir.appendingPathComponent("b.png"))
        try Data("txt".utf8).write(to: tmpDir.appendingPathComponent("readme.txt"))

        let images = scanner.findImages(in: tmpDir)
        XCTAssertEqual(images.count, 2)
        XCTAssertFalse(images.contains { $0.lastPathComponent == "readme.txt" })
    }

    func testCaseInsensitiveExtensions() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try Data("img".utf8).write(to: tmpDir.appendingPathComponent("a.JPG"))
        try Data("img".utf8).write(to: tmpDir.appendingPathComponent("b.JPEG"))

        let images = scanner.findImages(in: tmpDir)
        XCTAssertEqual(images.count, 2)
    }

    // Task 3.3 - empty directory returns empty results
    func testEmptyDirectoryReturnsEmpty() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let images = scanner.findImages(in: tmpDir)
        XCTAssertEqual(images.count, 0)
    }
}
