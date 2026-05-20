import XCTest
@testable import MangaTranslator

final class ArchiveExtractorTests: XCTestCase {
    private var workDir: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ArchiveExtractorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        workDir = base
    }

    override func tearDownWithError() throws {
        if let workDir { try? FileManager.default.removeItem(at: workDir) }
        workDir = nil
    }

    // MARK: - Test scaffolding helpers (Task 1.1, 1.3)

    private func archiveURL(_ name: String) -> URL {
        workDir.appendingPathComponent(name)
    }

    private func makeDestination(_ name: String = "dest") throws -> URL {
        let dest = workDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        return dest
    }

    /// Returns a snapshot of every regular-file path under `workDir`, used to
    /// verify that malicious archives do not create or overwrite files outside
    /// the destination root provided to the extractor.
    private func filesUnder(_ url: URL) -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: []
        ) else { return [] }
        var result = Set<String>()
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                result.insert(item.standardizedFileURL.path)
            }
        }
        return result
    }

    /// Creates a fresh directory under `workDir` used as the per-import temp base
    /// for `FileInputService.extractArchive`. This isolates each cleanup test from
    /// other tests that may run in parallel and create their own UUIDs under the
    /// shared `MangaTranslator/` temp folder.
    private func makeIsolatedTempBase(_ label: String) throws -> URL {
        let base = workDir.appendingPathComponent("import-base-\(label)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Asserts that the isolated per-import base contains no leftover UUID
    /// directories after `FileInputService.extractArchive` failed.
    private func assertIsolatedBaseIsEmpty(_ base: URL, scenario: String = "extraction failure", line: UInt = #line) {
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        XCTAssertTrue(
            leftovers.isEmpty,
            "FileInputService left behind temp dirs after \(scenario): \(leftovers)",
            line: line
        )
    }

    private func assertNoEscape(workSnapshotBefore: Set<String>, destination: URL, line: UInt = #line) {
        // Verify no files exist outside the destination root other than the snapshot taken
        // before the extractor ran. The workDir contains the archive itself plus the
        // destination root; anything new under workDir but outside destination is an escape.
        let allowedPrefix = destination.standardizedFileURL.path + "/"
        let after = filesUnder(workDir)
        let newPaths = after.subtracting(workSnapshotBefore)
        for path in newPaths {
            XCTAssertTrue(
                path == destination.standardizedFileURL.path || path.hasPrefix(allowedPrefix),
                "extractor created file outside destination root: \(path)",
                line: line
            )
        }
    }

    // MARK: - Section 2: Pre-Extraction Safety Tests

    func test_rejectsPathTraversalEntries() throws { // Task 2.1
        let zipURL = archiveURL("traversal.zip")
        try TestZipWriter.write([
            .file("../escape.png", Data("x".utf8))
        ], to: zipURL)
        let dest = try makeDestination()
        let snapshot = filesUnder(workDir)

        XCTAssertThrowsError(try ArchiveExtractor.extract(archiveURL: zipURL, into: dest)) { error in
            XCTAssertEqual(error as? ArchiveExtractor.Error, .unsafePath(.traversalComponent))
        }
        assertNoEscape(workSnapshotBefore: snapshot, destination: dest)
    }

    func test_rejectsAbsolutePathEntries() throws { // Task 2.2
        let zipURL = archiveURL("absolute.zip")
        try TestZipWriter.write([
            .file("/tmp/escape.png", Data("y".utf8))
        ], to: zipURL)
        let dest = try makeDestination()
        let snapshot = filesUnder(workDir)

        XCTAssertThrowsError(try ArchiveExtractor.extract(archiveURL: zipURL, into: dest)) { error in
            XCTAssertEqual(error as? ArchiveExtractor.Error, .unsafePath(.absolutePath))
        }
        assertNoEscape(workSnapshotBefore: snapshot, destination: dest)
    }

    func test_rejectsSymlinkEntries() throws { // Task 2.3
        let zipURL = archiveURL("symlink.zip")
        try TestZipWriter.write([
            .symlink("link.png", target: "../../etc/passwd")
        ], to: zipURL)
        let dest = try makeDestination()
        let snapshot = filesUnder(workDir)

        XCTAssertThrowsError(try ArchiveExtractor.extract(archiveURL: zipURL, into: dest)) { error in
            XCTAssertEqual(error as? ArchiveExtractor.Error, .unsupportedEntryType(.symbolicLink))
        }
        assertNoEscape(workSnapshotBefore: snapshot, destination: dest)
    }

    func test_rejectsHardlinkEntries() throws { // Task 2.4
        // Two regular-file entries declaring the same destination path are rejected as
        // hardlink-like overwrites: two names → one target is precisely how Unix hardlinks
        // behave, and the safety boundary refuses to extract ambiguous overwrites.
        let zipURL = archiveURL("hardlink.zip")
        try TestZipWriter.write([
            .file("page.png", Data("first".utf8)),
            .file("page.png", Data("second".utf8))
        ], to: zipURL)
        let dest = try makeDestination()
        let snapshot = filesUnder(workDir)

        XCTAssertThrowsError(try ArchiveExtractor.extract(archiveURL: zipURL, into: dest)) { error in
            XCTAssertEqual(error as? ArchiveExtractor.Error, .unsupportedEntryType(.hardlink))
        }
        assertNoEscape(workSnapshotBefore: snapshot, destination: dest)
    }

    func test_rejectsUnsupportedSpecialFileEntries() throws { // Task 2.5
        let zipURL = archiveURL("special.zip")
        try TestZipWriter.write([
            .charSpecial("dev_zero")
        ], to: zipURL)
        let dest = try makeDestination()
        let snapshot = filesUnder(workDir)

        XCTAssertThrowsError(try ArchiveExtractor.extract(archiveURL: zipURL, into: dest)) { error in
            XCTAssertEqual(error as? ArchiveExtractor.Error, .unsupportedEntryType(.specialFile))
        }
        assertNoEscape(workSnapshotBefore: snapshot, destination: dest)
    }

    func test_rejectsUnknownOrUnparseableEntries_unknownType() throws { // Task 2.6 (unknown)
        let zipURL = archiveURL("unknown.zip")
        try TestZipWriter.write([
            .unknownType("mystery")
        ], to: zipURL)
        let dest = try makeDestination()
        let snapshot = filesUnder(workDir)

        XCTAssertThrowsError(try ArchiveExtractor.extract(archiveURL: zipURL, into: dest)) { error in
            XCTAssertEqual(error as? ArchiveExtractor.Error, .unsupportedEntryType(.unknownType))
        }
        assertNoEscape(workSnapshotBefore: snapshot, destination: dest)
    }

    func test_rejectsUnknownOrUnparseableEntries_unparseable() throws { // Task 2.6 (unparseable)
        // Looks like an entry (starts with a perm-string char) but lacks required fields.
        let malformed = """
        Archive:  /tmp/fake.zip
        Zip file size: 0 bytes, number of entries: 1
        -rw-r--r--  partial-line
        1 file, 0 bytes uncompressed, 0 bytes compressed:  0.0%
        """
        XCTAssertThrowsError(try ArchiveExtractor.parseZipInfoOutput(malformed, archiveTag: "fake.zip")) { error in
            XCTAssertEqual(error as? ArchiveExtractor.Error, .unparseableMetadata)
        }
    }

    // MARK: - Section 3: Limit Tests

    func test_rejectsTooManyFiles() throws { // Task 3.1
        var entries: [TestZipWriter.Entry] = []
        for i in 0..<(ArchiveExtractor.Limits.default.maxFiles + 1) {
            entries.append(.file("img_\(i).png", Data([UInt8(i & 0xFF)])))
        }
        let zipURL = archiveURL("too-many.zip")
        try TestZipWriter.write(entries, to: zipURL)
        let dest = try makeDestination()
        let snapshot = filesUnder(workDir)

        XCTAssertThrowsError(try ArchiveExtractor.extract(archiveURL: zipURL, into: dest)) { error in
            guard case .fileCountLimitExceeded(let observed, let limit) = (error as? ArchiveExtractor.Error) ?? .unparseableMetadata else {
                return XCTFail("expected fileCountLimitExceeded, got \(error)")
            }
            XCTAssertEqual(limit, ArchiveExtractor.Limits.default.maxFiles)
            XCTAssertGreaterThan(observed, ArchiveExtractor.Limits.default.maxFiles)
        }
        assertNoEscape(workSnapshotBefore: snapshot, destination: dest)
    }

    func test_rejectsSingleUncompressedSizeOverLimit() throws { // Task 3.2
        let zipURL = archiveURL("big-decl.zip")
        // The body is a single byte but the declared uncompressed size exceeds the limit.
        let oversized: UInt32 = UInt32(ArchiveExtractor.Limits.default.maxSingleFileBytes) + 1
        try TestZipWriter.write([
            TestZipWriter.Entry(
                name: "huge.png",
                mode: 0o100644,
                body: Data([0xAA]),
                declaredUncompressedSizeOverride: oversized
            )
        ], to: zipURL)
        let dest = try makeDestination()
        let snapshot = filesUnder(workDir)

        XCTAssertThrowsError(try ArchiveExtractor.extract(archiveURL: zipURL, into: dest)) { error in
            guard case .singleFileSizeLimitExceeded(let observed, let limit) = (error as? ArchiveExtractor.Error) ?? .unparseableMetadata else {
                return XCTFail("expected singleFileSizeLimitExceeded, got \(error)")
            }
            XCTAssertEqual(limit, ArchiveExtractor.Limits.default.maxSingleFileBytes)
            XCTAssertGreaterThan(observed, ArchiveExtractor.Limits.default.maxSingleFileBytes)
        }
        assertNoEscape(workSnapshotBefore: snapshot, destination: dest)
    }

    func test_rejectsTotalUncompressedSizeOverLimit() throws { // Task 3.3
        // Each entry declares 24 MiB; 25 entries total > 500 MiB while each stays
        // under the per-file limit. Bodies remain a single byte so the archive is small.
        let perEntry: UInt32 = 24 * 1024 * 1024
        let count = 25
        var entries: [TestZipWriter.Entry] = []
        for i in 0..<count {
            entries.append(TestZipWriter.Entry(
                name: "p_\(i).png",
                mode: 0o100644,
                body: Data([UInt8(i & 0xFF)]),
                declaredUncompressedSizeOverride: perEntry
            ))
        }
        let zipURL = archiveURL("big-total.zip")
        try TestZipWriter.write(entries, to: zipURL)
        let dest = try makeDestination()
        let snapshot = filesUnder(workDir)

        XCTAssertThrowsError(try ArchiveExtractor.extract(archiveURL: zipURL, into: dest)) { error in
            guard case .totalSizeLimitExceeded(let observed, let limit) = (error as? ArchiveExtractor.Error) ?? .unparseableMetadata else {
                return XCTFail("expected totalSizeLimitExceeded, got \(error)")
            }
            XCTAssertEqual(limit, ArchiveExtractor.Limits.default.maxTotalBytes)
            XCTAssertGreaterThan(observed, ArchiveExtractor.Limits.default.maxTotalBytes)
        }
        assertNoEscape(workSnapshotBefore: snapshot, destination: dest)
    }

    func test_postExtractionRejectsActualSingleFileOverLimit() throws { // Task 3.4
        let dest = try makeDestination("post-single")
        let big = dest.appendingPathComponent("big.png")
        try Data(repeating: 0xFF, count: 1024).write(to: big)
        let limits = ArchiveExtractor.Limits(
            maxFiles: 10,
            maxSingleFileBytes: 100,
            maxTotalBytes: 10_000
        )

        XCTAssertThrowsError(try ArchiveExtractor.validatePostExtraction(
            destinationRoot: dest,
            limits: limits,
            archiveTag: "post-single.zip"
        )) { error in
            XCTAssertEqual(
                error as? ArchiveExtractor.Error,
                .postExtractionValidationFailed(.singleFileSizeLimitExceeded)
            )
        }
    }

    func test_postExtractionRejectsActualTotalOverLimit() throws { // Task 3.5
        let dest = try makeDestination("post-total")
        for i in 0..<4 {
            let url = dest.appendingPathComponent("p_\(i).png")
            try Data(repeating: 0xAA, count: 60).write(to: url)
        }
        let limits = ArchiveExtractor.Limits(
            maxFiles: 10,
            maxSingleFileBytes: 100,
            maxTotalBytes: 200
        )

        XCTAssertThrowsError(try ArchiveExtractor.validatePostExtraction(
            destinationRoot: dest,
            limits: limits,
            archiveTag: "post-total.zip"
        )) { error in
            XCTAssertEqual(
                error as? ArchiveExtractor.Error,
                .postExtractionValidationFailed(.totalSizeLimitExceeded)
            )
        }
    }

    // MARK: - Section 4: Valid Import Regression Tests

    func test_extractsValidCBZAndFileInputServiceScansImages() throws { // Task 4.1
        let zipURL = archiveURL("valid.cbz")
        try TestZipWriter.write([
            .file("page1.png", Data("png-1".utf8)),
            .file("page2.jpg", Data("jpg-2".utf8)),
            .file("notes.txt", Data("ignored".utf8))
        ], to: zipURL)
        let dest = try makeDestination("valid-out")

        try ArchiveExtractor.extract(archiveURL: zipURL, into: dest)

        let scanned = FileInputService.scanFolder(dest).map { $0.lastPathComponent }
        XCTAssertEqual(scanned, ["page1.png", "page2.jpg"])
    }

    func test_validCBZScanningRecursesIntoSubdirectories() throws { // Task 4.2
        let zipURL = archiveURL("nested.cbz")
        try TestZipWriter.write([
            .directory("chapter1"),
            .file("chapter1/p1.png", Data("a".utf8)),
            .directory("chapter1/inner"),
            .file("chapter1/inner/p2.png", Data("b".utf8))
        ], to: zipURL)
        let dest = try makeDestination("nested-out")

        try ArchiveExtractor.extract(archiveURL: zipURL, into: dest)
        let scanned = FileInputService.scanFolder(dest).map { $0.lastPathComponent }
        XCTAssertTrue(scanned.contains("p1.png"))
        XCTAssertTrue(scanned.contains("p2.png"))
    }

    func test_validCBZScanningSkipsMacOSXMetadata() throws { // Task 4.3
        let zipURL = archiveURL("macosx.cbz")
        try TestZipWriter.write([
            .file("good.png", Data("g".utf8)),
            .directory("__MACOSX"),
            .file("__MACOSX/garbage.png", Data("bad".utf8))
        ], to: zipURL)
        let dest = try makeDestination("macosx-out")

        try ArchiveExtractor.extract(archiveURL: zipURL, into: dest)
        let scanned = FileInputService.scanFolder(dest).map { $0.lastPathComponent }
        XCTAssertEqual(scanned, ["good.png"])
    }

    func test_validCBZResultsUseLocalizedStandardCompareSort() throws { // Task 4.4
        let zipURL = archiveURL("sort.cbz")
        try TestZipWriter.write([
            .file("page10.png", Data("10".utf8)),
            .file("page2.png", Data("2".utf8)),
            .file("page1.png", Data("1".utf8))
        ], to: zipURL)
        let dest = try makeDestination("sort-out")

        try ArchiveExtractor.extract(archiveURL: zipURL, into: dest)
        let scanned = FileInputService.scanFolder(dest).map { $0.lastPathComponent }
        XCTAssertEqual(scanned, ["page1.png", "page2.png", "page10.png"])
    }

    func test_fileInputServiceMapsExtractorFailureToExtractionFailed() throws { // Task 4.5
        // A path-traversal archive routed through FileInputService.extractArchive surfaces
        // as the existing FileInputError.extractionFailed and removes the per-import dir.
        let zipURL = archiveURL("bad-via-service.zip")
        try TestZipWriter.write([
            .file("../escape.png", Data("oops".utf8))
        ], to: zipURL)
        let isolatedBase = try makeIsolatedTempBase("mapping")

        XCTAssertThrowsError(try FileInputService.extractArchive(zipURL, tempDirBase: isolatedBase)) { error in
            XCTAssertEqual(error as? FileInputError, .extractionFailed)
        }

        assertIsolatedBaseIsEmpty(isolatedBase)
    }

    func test_fileInputServiceRemovesTempDirOnUnzipProcessFailure() throws {
        // Central directory is well-formed (so pre-validation passes) but the local
        // file header magic is corrupted, forcing /usr/bin/unzip to exit non-zero.
        // This exercises the cleanup path for an extraction-process failure.
        let zipURL = archiveURL("unzip-fail.zip")
        try TestZipWriter.write([
            TestZipWriter.Entry(
                name: "page.png",
                mode: 0o100644,
                body: Data("hello".utf8),
                corruptLocalFileHeaderMagic: true
            )
        ], to: zipURL)
        let isolatedBase = try makeIsolatedTempBase("unzip-fail")

        XCTAssertThrowsError(try FileInputService.extractArchive(zipURL, tempDirBase: isolatedBase)) { error in
            XCTAssertEqual(error as? FileInputError, .extractionFailed)
        }

        assertIsolatedBaseIsEmpty(isolatedBase, scenario: "unzip failure")
    }

    func test_fileInputServiceRemovesTempDirOnPostExtractionValidationFailure() throws {
        // CDH lies that the entry is 1 byte (passes pre-validation against the tight
        // limit), while the local file header and body describe 200 real bytes.
        // unzip extracts 200 bytes, post-extraction validation rejects the actual
        // size, and FileInputService MUST still remove the per-import directory.
        let body = Data(repeating: 0xAA, count: 200)
        let zipURL = archiveURL("post-fail.zip")
        try TestZipWriter.write([
            TestZipWriter.Entry(
                name: "page.png",
                mode: 0o100644,
                body: body,
                declaredUncompressedSizeOverride: 1
            )
        ], to: zipURL)
        let tightLimits = ArchiveExtractor.Limits(
            maxFiles: 10,
            maxSingleFileBytes: 100,
            maxTotalBytes: 10_000
        )
        let isolatedBase = try makeIsolatedTempBase("post-fail")

        XCTAssertThrowsError(
            try FileInputService.extractArchive(zipURL, limits: tightLimits, tempDirBase: isolatedBase)
        ) { error in
            XCTAssertEqual(error as? FileInputError, .extractionFailed)
        }

        assertIsolatedBaseIsEmpty(isolatedBase, scenario: "post-extraction failure")
    }

    // MARK: - Scaffolding self-check (Task 1.3)

    func test_scaffoldingDetectsExtractionOutsideDestinationRoot() throws {
        // Sanity-check the helper: planting a file outside the destination root is detected.
        let dest = try makeDestination("scaffold")
        let snapshot = filesUnder(workDir)
        let outsider = workDir.appendingPathComponent("outsider.png")
        try Data("escaped".utf8).write(to: outsider)
        var failures: [String] = []
        let allowedPrefix = dest.standardizedFileURL.path + "/"
        for path in filesUnder(workDir).subtracting(snapshot) {
            if path != dest.standardizedFileURL.path && !path.hasPrefix(allowedPrefix) {
                failures.append(path)
            }
        }
        XCTAssertFalse(failures.isEmpty, "scaffolding helper failed to detect outside-root file")
    }
}

// MARK: - Test-only ZIP writer (Task 1.2)

/// Minimal ZIP writer used by `ArchiveExtractorTests`. Builds a stored (no
/// compression) archive with arbitrary entry names, Unix mode bits, body
/// content, and declared uncompressed sizes. Supports regular files, directory
/// entries, symlinks, special-file entries, and entries with unknown Unix
/// type bits — enough surface to exercise the extractor's pre-extraction
/// safety boundary without committing binary fixtures.
struct TestZipWriter {
    struct Entry {
        let name: String
        let mode: UInt32 // Upper 4 bits encode Unix file type (S_IFREG, S_IFDIR, etc.).
        let body: Data
        /// When set, overrides the uncompressed-size field of the central
        /// directory entry only. The local file header stays consistent with
        /// `body.count`, so `zipinfo -l` (which reads the central directory)
        /// reports the override while `unzip` (which reads the local header)
        /// still extracts the real body bytes. Used to exercise pre- and
        /// post-extraction limits independently.
        var declaredUncompressedSizeOverride: UInt32?
        /// When `true`, the local file header magic for this entry is written as
        /// a bogus value. `zipinfo -l` reads only the central directory and is
        /// unaffected, while `unzip` aborts with a non-zero exit. Used to
        /// exercise the unzip process-failure cleanup path.
        var corruptLocalFileHeaderMagic: Bool

        init(
            name: String,
            mode: UInt32,
            body: Data,
            declaredUncompressedSizeOverride: UInt32? = nil,
            corruptLocalFileHeaderMagic: Bool = false
        ) {
            self.name = name
            self.mode = mode
            self.body = body
            self.declaredUncompressedSizeOverride = declaredUncompressedSizeOverride
            self.corruptLocalFileHeaderMagic = corruptLocalFileHeaderMagic
        }

        static func file(_ name: String, _ body: Data) -> Entry {
            Entry(name: name, mode: 0o100644, body: body)
        }

        static func directory(_ name: String) -> Entry {
            let normalized = name.hasSuffix("/") ? name : name + "/"
            return Entry(name: normalized, mode: 0o040755, body: Data())
        }

        static func symlink(_ name: String, target: String) -> Entry {
            Entry(name: name, mode: 0o120755, body: Data(target.utf8))
        }

        static func charSpecial(_ name: String) -> Entry {
            Entry(name: name, mode: 0o020644, body: Data())
        }

        static func blockSpecial(_ name: String) -> Entry {
            Entry(name: name, mode: 0o060644, body: Data())
        }

        static func fifo(_ name: String) -> Entry {
            Entry(name: name, mode: 0o010644, body: Data())
        }

        /// Upper 4 bits = 0x9, which `zipinfo -l` renders as `?` — i.e. an
        /// unknown/unsupported Unix file type.
        static func unknownType(_ name: String) -> Entry {
            Entry(name: name, mode: UInt32(0x9 << 12) | 0o644, body: Data())
        }
    }

    static func write(_ entries: [Entry], to url: URL) throws {
        var stream = Data()
        var centralDir = Data()
        for entry in entries {
            let localOffset = UInt32(stream.count)
            let nameBytes = Data(entry.name.utf8)
            let body = entry.body
            let crc = crc32(body)
            let actualSize = UInt32(body.count)
            let centralDirDeclared = entry.declaredUncompressedSizeOverride ?? actualSize

            // Local file header — always uses the actual body size so unzip extracts
            // the real bytes; corruption flag swaps the magic so unzip refuses.
            let lfhMagic: UInt32 = entry.corruptLocalFileHeaderMagic ? 0xDEADBEEF : 0x04034b50
            stream.appendLE32(lfhMagic)
            stream.appendLE16(20)
            stream.appendLE16(0)
            stream.appendLE16(0)
            stream.appendLE16(0)
            stream.appendLE16(0)
            stream.appendLE32(crc)
            stream.appendLE32(actualSize)
            stream.appendLE32(actualSize)
            stream.appendLE16(UInt16(nameBytes.count))
            stream.appendLE16(0)
            stream.append(nameBytes)
            stream.append(body)

            // Central directory header — uncompressed size honours the override so
            // zipinfo reports the lie while the local header remains honest.
            centralDir.appendLE32(0x02014b50)
            centralDir.appendLE16(0x031e) // version made by: Unix (3), 30
            centralDir.appendLE16(20)
            centralDir.appendLE16(0)
            centralDir.appendLE16(0)
            centralDir.appendLE16(0)
            centralDir.appendLE16(0)
            centralDir.appendLE32(crc)
            centralDir.appendLE32(actualSize)
            centralDir.appendLE32(centralDirDeclared)
            centralDir.appendLE16(UInt16(nameBytes.count))
            centralDir.appendLE16(0)
            centralDir.appendLE16(0)
            centralDir.appendLE16(0)
            centralDir.appendLE16(0)
            centralDir.appendLE32(entry.mode << 16) // external attrs: upper 16 = mode
            centralDir.appendLE32(localOffset)
            centralDir.append(nameBytes)
        }
        let cdOffset = UInt32(stream.count)
        let cdSize = UInt32(centralDir.count)
        stream.append(centralDir)
        stream.appendLE32(0x06054b50)
        stream.appendLE16(0)
        stream.appendLE16(0)
        stream.appendLE16(UInt16(entries.count))
        stream.appendLE16(UInt16(entries.count))
        stream.appendLE32(cdSize)
        stream.appendLE32(cdOffset)
        stream.appendLE16(0)
        try stream.write(to: url)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
    mutating func appendLE32(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
