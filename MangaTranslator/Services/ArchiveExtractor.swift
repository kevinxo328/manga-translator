import Foundation

/// Safe extraction boundary for user-imported ZIP/CBZ archives. The extractor
/// validates archive entries through `/usr/bin/zipinfo -l` before invoking
/// `/usr/bin/unzip`, then re-validates the extracted filesystem against the
/// same limits. Failures throw a precise `ArchiveExtractor.Error`; callers
/// (currently `FileInputService.extractArchive(_:)`) own the per-import
/// temporary directory lifecycle. Diagnostics flow through `DebugLogger`,
/// which wraps `os.Logger` and redacts sensitive metadata.
enum ArchiveExtractor {
    struct Limits: Equatable {
        var maxFiles: Int = 500
        var maxSingleFileBytes: Int64 = 25 * 1024 * 1024
        var maxTotalBytes: Int64 = 500 * 1024 * 1024

        static let `default` = Limits()
    }

    enum UnsafePathReason: String, Equatable {
        case absolutePath
        case traversalComponent
        case destinationEscape
    }

    enum EntryTypeCategory: String, Equatable {
        case symbolicLink
        case hardlink
        case specialFile
        case unknownType
    }

    enum PostExtractionReason: String, Equatable {
        case nonRegularFile
        case destinationEscape
        case singleFileSizeLimitExceeded
        case totalSizeLimitExceeded
        case hardlinkDetected
    }

    enum Error: Swift.Error, Equatable {
        case unsafePath(UnsafePathReason)
        case unsupportedEntryType(EntryTypeCategory)
        case unparseableMetadata
        case fileCountLimitExceeded(observed: Int, limit: Int)
        case singleFileSizeLimitExceeded(observedBytes: Int64, limit: Int64)
        case totalSizeLimitExceeded(observedBytes: Int64, limit: Int64)
        case extractionProcessFailed
        case postExtractionValidationFailed(PostExtractionReason)
    }

    /// Extracts `archiveURL` into `destinationRoot` after pre-extraction
    /// validation, then re-validates the resulting filesystem. The caller MUST
    /// supply an already-created destination directory and is responsible for
    /// removing that directory on failure.
    static func extract(
        archiveURL: URL,
        into destinationRoot: URL,
        limits: Limits = .default
    ) throws {
        let archiveTag = archiveURL.lastPathComponent
        let entries = try listEntries(archiveURL: archiveURL, archiveTag: archiveTag)
        try validatePreExtraction(
            entries: entries,
            destinationRoot: destinationRoot,
            limits: limits,
            archiveTag: archiveTag
        )
        try runUnzip(archiveURL: archiveURL, destinationRoot: destinationRoot, archiveTag: archiveTag)
        try validatePostExtraction(
            destinationRoot: destinationRoot,
            limits: limits,
            archiveTag: archiveTag
        )
    }

    // MARK: - Parsed entry

    struct ParsedEntry: Equatable {
        let name: String
        let permissions: String
        let declaredUncompressedSize: Int64
        var firstChar: Character { permissions.first ?? "?" }
    }

    // MARK: - Entry listing

    private static func listEntries(archiveURL: URL, archiveTag: String) throws -> [ParsedEntry] {
        let data = try runProcessCapturingStandardOutput(
            executable: URL(fileURLWithPath: "/usr/bin/zipinfo"),
            arguments: ["-l", archiveURL.path],
            spawnFailureLogCategory: "listing_spawn_failed",
            nonzeroExitLogCategory: "listing_nonzero_exit",
            archiveTag: archiveTag
        )

        guard let output = String(data: data, encoding: .utf8) else {
            logRejection(category: "listing_non_utf8", archiveTag: archiveTag)
            throw Error.unparseableMetadata
        }

        return try parseZipInfoOutput(output, archiveTag: archiveTag)
    }

    static func runProcessCapturingStandardOutput(
        executable: URL,
        arguments: [String],
        spawnFailureLogCategory: String,
        nonzeroExitLogCategory: String,
        archiveTag: String
    ) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logRejection(category: spawnFailureLogCategory, archiveTag: archiveTag)
            throw Error.extractionProcessFailed
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            logRejection(category: nonzeroExitLogCategory, archiveTag: archiveTag)
            throw Error.extractionProcessFailed
        }

        return data
    }

    /// Parses `zipinfo -l` output. Entry lines start with a 10-character
    /// permissions string (`-rwxrwxrwx`, `drwxr-xr-x`, `lrwxr-xr-x`, etc.).
    /// Header (`Archive:`, `Zip file size:`) and footer (`N files, ...`) lines
    /// are skipped. Lines that look like entries but cannot be parsed into the
    /// expected fields raise `.unparseableMetadata`.
    static func parseZipInfoOutput(_ output: String, archiveTag: String) throws -> [ParsedEntry] {
        var entries: [ParsedEntry] = []
        let validFirstChars: Set<Character> = ["-", "d", "l", "b", "c", "p", "s", "w", "?"]

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("Archive:") { continue }
            if trimmed.hasPrefix("Zip file size:") { continue }
            // Footer summary lines like "3 files, 16 bytes uncompressed, ..."
            if isFooterLine(trimmed) { continue }

            guard let first = trimmed.first, validFirstChars.contains(first) else {
                continue
            }

            let entry = try parseEntryLine(trimmed, archiveTag: archiveTag)
            entries.append(entry)
        }

        return entries
    }

    private static func isFooterLine(_ trimmed: String) -> Bool {
        // Matches lines such as "3 files, 16 bytes uncompressed, 16 bytes compressed:  0.0%".
        let pattern = #"^\d+\s+files?,\s+\d+\s+bytes"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private static func parseEntryLine(_ line: String, archiveTag: String) throws -> ParsedEntry {
        // Expected layout (whitespace-separated):
        // perms version host uncompr-size flags compr-size method date time name...
        // The name MAY contain spaces; we therefore split the leading 9 fields
        // and rejoin the remainder as the name.
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count >= 10 else {
            logRejection(category: "unparseable_line", archiveTag: archiveTag)
            throw Error.unparseableMetadata
        }
        let permissions = parts[0]
        guard permissions.count == 10 else {
            logRejection(category: "unparseable_permissions", archiveTag: archiveTag)
            throw Error.unparseableMetadata
        }
        guard let declared = Int64(parts[3]) else {
            logRejection(category: "unparseable_size", archiveTag: archiveTag)
            throw Error.unparseableMetadata
        }
        let name = parts[9...].joined(separator: " ")
        guard !name.isEmpty else {
            logRejection(category: "unparseable_name", archiveTag: archiveTag)
            throw Error.unparseableMetadata
        }
        return ParsedEntry(
            name: name,
            permissions: permissions,
            declaredUncompressedSize: declared
        )
    }

    // MARK: - Pre-extraction validation

    static func validatePreExtraction(
        entries: [ParsedEntry],
        destinationRoot: URL,
        limits: Limits,
        archiveTag: String
    ) throws {
        let standardizedRoot = destinationRoot.standardizedFileURL.resolvingSymlinksInPath().path
        var regularFileCount = 0
        var declaredTotal: Int64 = 0
        var seenNormalizedRegularPaths = Set<String>()

        for entry in entries {
            try validateEntryType(entry, archiveTag: archiveTag)

            let isDirectory = entry.firstChar == "d"
            try validatePathSafety(
                name: entry.name,
                isDirectory: isDirectory,
                standardizedRoot: standardizedRoot,
                destinationRoot: destinationRoot,
                archiveTag: archiveTag
            )

            if isDirectory { continue }

            // Regular file: enforce duplicate-path (hardlink-like overwrite) safety.
            let normalized = (entry.name as NSString).standardizingPath
            if !seenNormalizedRegularPaths.insert(normalized).inserted {
                logRejection(category: "duplicate_entry_path", archiveTag: archiveTag)
                throw Error.unsupportedEntryType(.hardlink)
            }

            regularFileCount += 1
            if regularFileCount > limits.maxFiles {
                logRejection(
                    category: "too_many_files",
                    archiveTag: archiveTag,
                    observed: "\(regularFileCount)",
                    limit: "\(limits.maxFiles)"
                )
                throw Error.fileCountLimitExceeded(observed: regularFileCount, limit: limits.maxFiles)
            }

            if entry.declaredUncompressedSize > limits.maxSingleFileBytes {
                logRejection(
                    category: "declared_single_file_too_large",
                    archiveTag: archiveTag,
                    observed: "\(entry.declaredUncompressedSize)",
                    limit: "\(limits.maxSingleFileBytes)"
                )
                throw Error.singleFileSizeLimitExceeded(
                    observedBytes: entry.declaredUncompressedSize,
                    limit: limits.maxSingleFileBytes
                )
            }

            declaredTotal &+= entry.declaredUncompressedSize
            if declaredTotal > limits.maxTotalBytes {
                logRejection(
                    category: "declared_total_too_large",
                    archiveTag: archiveTag,
                    observed: "\(declaredTotal)",
                    limit: "\(limits.maxTotalBytes)"
                )
                throw Error.totalSizeLimitExceeded(
                    observedBytes: declaredTotal,
                    limit: limits.maxTotalBytes
                )
            }
        }
    }

    private static func validateEntryType(_ entry: ParsedEntry, archiveTag: String) throws {
        switch entry.firstChar {
        case "-", "d":
            return
        case "?":
            // Some ZIP producers (Python zipfile defaults, certain Windows tools)
            // emit entries whose external attributes do not encode Unix file-type
            // bits, which zipinfo renders as `?`. Treat these as regular-file
            // candidates: the authoritative type check is the post-extraction
            // `lstat` pass, which rejects symlinks, special files, and anything
            // that is not a regular file.
            return
        case "l":
            logRejection(category: "symlink_entry", archiveTag: archiveTag)
            throw Error.unsupportedEntryType(.symbolicLink)
        case "b", "c", "p", "s", "w":
            logRejection(category: "special_file_entry", archiveTag: archiveTag)
            throw Error.unsupportedEntryType(.specialFile)
        default:
            logRejection(category: "unknown_entry_type", archiveTag: archiveTag)
            throw Error.unsupportedEntryType(.unknownType)
        }
    }

    private static func validatePathSafety(
        name: String,
        isDirectory: Bool,
        standardizedRoot: String,
        destinationRoot: URL,
        archiveTag: String
    ) throws {
        if name.hasPrefix("/") {
            logRejection(category: "absolute_path_entry", archiveTag: archiveTag)
            throw Error.unsafePath(.absolutePath)
        }

        // Path traversal: any `..` path component is rejected outright.
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains(where: { $0 == ".." }) {
            logRejection(category: "path_traversal_entry", archiveTag: archiveTag)
            throw Error.unsafePath(.traversalComponent)
        }

        // Final containment check after standardization against the destination root.
        let joined = destinationRoot.appendingPathComponent(name)
        let resolvedPath = joined.standardizedFileURL.path
        let rootWithSlash = standardizedRoot.hasSuffix("/") ? standardizedRoot : standardizedRoot + "/"
        let rootMatches = resolvedPath == standardizedRoot || resolvedPath.hasPrefix(rootWithSlash)
        if !rootMatches {
            logRejection(category: "destination_escape", archiveTag: archiveTag)
            throw Error.unsafePath(.destinationEscape)
        }
        // Suppress unused-warning for isDirectory; it remains in the signature to
        // document that directory entries also pass through the same checks.
        _ = isDirectory
    }

    // MARK: - Extraction

    private static func runUnzip(
        archiveURL: URL,
        destinationRoot: URL,
        archiveTag: String
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", archiveURL.path, "-d", destinationRoot.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logRejection(category: "unzip_spawn_failed", archiveTag: archiveTag)
            throw Error.extractionProcessFailed
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            logRejection(category: "unzip_nonzero_exit", archiveTag: archiveTag)
            throw Error.extractionProcessFailed
        }
    }

    // MARK: - Post-extraction validation

    static func validatePostExtraction(
        destinationRoot: URL,
        limits: Limits,
        archiveTag: String
    ) throws {
        let fm = FileManager.default
        let standardizedRootPath = destinationRoot.standardizedFileURL.resolvingSymlinksInPath().path

        guard let enumerator = fm.enumerator(
            at: destinationRoot,
            includingPropertiesForKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey
            ],
            options: []
        ) else {
            logRejection(category: "post_enumeration_failed", archiveTag: archiveTag)
            throw Error.postExtractionValidationFailed(.nonRegularFile)
        }

        var totalBytes: Int64 = 0
        for case let url as URL in enumerator {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
            let rootWithSlash = standardizedRootPath.hasSuffix("/")
                ? standardizedRootPath
                : standardizedRootPath + "/"
            if resolved != standardizedRootPath && !resolved.hasPrefix(rootWithSlash) {
                logRejection(category: "post_destination_escape", archiveTag: archiveTag)
                throw Error.postExtractionValidationFailed(.destinationEscape)
            }

            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey
            ])
            if values.isSymbolicLink == true {
                logRejection(category: "post_symlink_present", archiveTag: archiveTag)
                throw Error.postExtractionValidationFailed(.nonRegularFile)
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else {
                logRejection(category: "post_non_regular_file", archiveTag: archiveTag)
                throw Error.postExtractionValidationFailed(.nonRegularFile)
            }

            // Hardlink detection: regular files extracted from a ZIP should have a
            // single link. Anything more suggests a hardlink was reconstructed.
            if let nlink = linkCount(at: url), nlink > 1 {
                logRejection(category: "post_hardlink_detected", archiveTag: archiveTag)
                throw Error.postExtractionValidationFailed(.hardlinkDetected)
            }

            let size = Int64(values.fileSize ?? 0)
            if size > limits.maxSingleFileBytes {
                logRejection(
                    category: "post_single_file_too_large",
                    archiveTag: archiveTag,
                    observed: "\(size)",
                    limit: "\(limits.maxSingleFileBytes)"
                )
                throw Error.postExtractionValidationFailed(.singleFileSizeLimitExceeded)
            }
            totalBytes &+= size
            if totalBytes > limits.maxTotalBytes {
                logRejection(
                    category: "post_total_too_large",
                    archiveTag: archiveTag,
                    observed: "\(totalBytes)",
                    limit: "\(limits.maxTotalBytes)"
                )
                throw Error.postExtractionValidationFailed(.totalSizeLimitExceeded)
            }
        }
    }

    private static func linkCount(at url: URL) -> Int? {
        var stbuf = stat()
        if lstat(url.path, &stbuf) != 0 { return nil }
        return Int(stbuf.st_nlink)
    }

    // MARK: - Diagnostics

    private static func logRejection(
        category: String,
        archiveTag: String,
        observed: String? = nil,
        limit: String? = nil
    ) {
        // Inline the structured fields so the os.Logger emission carries the same
        // diagnostics as DebugLogStore. Full absolute paths and full entry paths
        // are never included; the archive tag is `lastPathComponent` only.
        let safeTag = sanitizedTag(archiveTag)
        var message = "archive_rejected category=\(category) archive=\(safeTag)"
        if let observed = observed { message += " observed=\(observed)" }
        if let limit = limit { message += " limit=\(limit)" }

        var metadata: [String: String] = [
            "rejection_category": category,
            "archive": safeTag
        ]
        if let observed = observed { metadata["observed"] = observed }
        if let limit = limit { metadata["limit"] = limit }
        DebugLogger.shared.log(
            message,
            level: .warning,
            category: .fileInput,
            metadata: metadata
        )
    }

    private static func sanitizedTag(_ tag: String) -> String {
        // Strip path separators and truncate to a basename-sized hint.
        let basename = (tag as NSString).lastPathComponent
        return String(basename.prefix(64))
    }
}
