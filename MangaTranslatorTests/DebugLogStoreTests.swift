import XCTest
@testable import MangaTranslator

final class DebugLogStoreTests: XCTestCase {
    private var store: DebugLogStore!
    private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        store = DebugLogStore(databaseURL: tempURL)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    // MARK: 4.1 Schema initialization and migration failure fallback

    func testSchemaInitializesSuccessfully() async {
        let isAvailable = await store.isAvailable
        XCTAssertTrue(isAvailable, "Store should be available after successful schema init")
    }

    func testMigrationFailureMakesStoreUnavailable() async {
        let badURL = URL(fileURLWithPath: "/nonexistent/path/db.sqlite")
        let badStore = DebugLogStore(databaseURL: badURL)
        let isAvailable = await badStore.isAvailable
        XCTAssertFalse(isAvailable, "Store with invalid path should be unavailable")
    }

    func testUnavailableStoreAcceptsInsertsSilently() async {
        let badURL = URL(fileURLWithPath: "/nonexistent/path/db.sqlite")
        let badStore = DebugLogStore(databaseURL: badURL)
        let entry = makeEntry(message: "test")
        await badStore.insert(entry)
        let results = await badStore.query(filter: DebugLogFilter())
        XCTAssertTrue(results.isEmpty)
    }

    func testOSLoggerContinuesWhenStoreUnavailable() async {
        // Verifies that DebugLogger still emits to os.Logger when store is unavailable
        let badURL = URL(fileURLWithPath: "/nonexistent/path/db.sqlite")
        let badStore = DebugLogStore(databaseURL: badURL)
        let logger = DebugLogger(store: badStore)
        // Should not crash
        logger.log("test message", level: .info, category: .cache)
    }

    // MARK: 4.2 Insert / query / filter / pagination

    func testInsertAndQuery() async throws {
        let entry = makeEntry(message: "Hello debug")
        await store.insert(entry)
        let results = await store.query(filter: DebugLogFilter())
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.message, "Hello debug")
    }

    func testQueryReturnsNewestFirst() async throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        await store.insert(makeEntry(message: "older", timestamp: base))
        await store.insert(makeEntry(message: "newer", timestamp: base.addingTimeInterval(10)))
        let results = await store.query(filter: DebugLogFilter())
        XCTAssertEqual(results.first?.message, "newer")
        XCTAssertEqual(results.last?.message, "older")
    }

    func testFilterByLevel() async {
        await store.insert(makeEntry(message: "err", level: .error))
        await store.insert(makeEntry(message: "inf", level: .info))
        var filter = DebugLogFilter()
        filter.level = .error
        let results = await store.query(filter: filter)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.level, .error)
    }

    func testFilterByCategory() async {
        await store.insert(makeEntry(message: "cache msg", category: .cache))
        await store.insert(makeEntry(message: "keychain msg", category: .keychain))
        var filter = DebugLogFilter()
        filter.category = .cache
        let results = await store.query(filter: filter)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.category, .cache)
    }

    func testFilterByKind() async {
        await store.insert(makeEntry(message: "op", kind: .operational))
        await store.insert(makeEntry(message: "content text", kind: .content))
        var filter = DebugLogFilter()
        filter.kind = .content
        let results = await store.query(filter: filter)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .content)
    }

    func testFilterBySession() async {
        await store.insert(makeEntry(message: "session a", sessionID: "session-A"))
        await store.insert(makeEntry(message: "session b", sessionID: "session-B"))
        var filter = DebugLogFilter()
        filter.sessionIDFilter = .session("session-A")
        let results = await store.query(filter: filter)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.sessionID, "session-A")
    }

    func testFilterByTextQuery() async {
        await store.insert(makeEntry(message: "OCR detected 5 bubbles"))
        await store.insert(makeEntry(message: "Translation succeeded"))
        var filter = DebugLogFilter()
        filter.textQuery = "OCR"
        let results = await store.query(filter: filter)
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first?.message.contains("OCR") == true)
    }

    func testFilterByTimeRange() async {
        let base = Date(timeIntervalSince1970: 1_000_000)
        await store.insert(makeEntry(message: "old", timestamp: base.addingTimeInterval(-100)))
        await store.insert(makeEntry(message: "in range", timestamp: base))
        await store.insert(makeEntry(message: "future", timestamp: base.addingTimeInterval(100)))
        var filter = DebugLogFilter()
        filter.startDate = base.addingTimeInterval(-10)
        filter.endDate = base.addingTimeInterval(10)
        let results = await store.query(filter: filter)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.message, "in range")
    }

    func testPaginationReturnsPageSize() async {
        for i in 0..<150 {
            await store.insert(makeEntry(message: "entry \(i)"))
        }
        let page1 = await store.query(filter: DebugLogFilter(), offset: 0)
        XCTAssertEqual(page1.count, DebugLogStore.pageSize)
    }

    func testPaginationOffset() async {
        // Use recent timestamps to avoid triggering age-based rotation
        let base = Date()
        for i in 0..<105 {
            let ts = base.addingTimeInterval(Double(i))
            await store.insert(makeEntry(message: "entry \(i)", timestamp: ts))
        }
        let page1 = await store.query(filter: DebugLogFilter(), offset: 0)
        let page2 = await store.query(filter: DebugLogFilter(), offset: 100)
        XCTAssertEqual(page1.count, 100)
        XCTAssertEqual(page2.count, 5)
        let page1IDs = Set(page1.map(\.id))
        let page2IDs = Set(page2.map(\.id))
        XCTAssertTrue(page1IDs.intersection(page2IDs).isEmpty, "Pages must not overlap")
    }

    // MARK: 4.3 Retention

    func testRetentionByAge() async {
        let old = Date().addingTimeInterval(-Double(DebugLogStore.retentionDays + 1) * 86400)
        await store.insert(makeEntry(message: "old entry", timestamp: old))
        await store.insert(makeEntry(message: "new entry"))
        await store.runRotation()
        let results = await store.queryAll(filter: DebugLogFilter())
        XCTAssertFalse(results.contains { $0.message == "old entry" })
        XCTAssertTrue(results.contains { $0.message == "new entry" })
    }

    func testRetentionByCount() async {
        let limit = DebugLogStore.retentionMaxCount
        for i in 0..<(limit + 5) {
            let ts = Date(timeIntervalSince1970: Double(i))
            await store.insert(makeEntry(message: "entry \(i)", timestamp: ts))
        }
        await store.runRotation()
        let count = await store.count(filter: DebugLogFilter())
        XCTAssertLessThanOrEqual(count, limit)
    }

    func testRotationTriggeredAfter100Inserts() async {
        let old = Date().addingTimeInterval(-Double(DebugLogStore.retentionDays + 1) * 86400)
        await store.insert(makeEntry(message: "old entry", timestamp: old))

        for _ in 0..<DebugLogStore.rotationInsertInterval {
            await store.insert(makeEntry(message: "new"))
        }

        let results = await store.queryAll(filter: DebugLogFilter())
        XCTAssertFalse(results.contains { $0.message == "old entry" },
                       "Rotation should have run after \(DebugLogStore.rotationInsertInterval) inserts")
    }

    // MARK: 4.4 Content logs

    func testContentLogIsPersisted() async {
        await store.insert(makeEntry(message: "Japanese text here", kind: .content))
        var filter = DebugLogFilter()
        filter.kind = .content
        let results = await store.query(filter: filter)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.message, "Japanese text here")
    }

    func testContentLogIsExported() async {
        await store.insert(makeEntry(message: "OCR source", kind: .content))
        var filter = DebugLogFilter()
        filter.kind = .content
        let ndjson = await store.exportNDJSON(filter: filter)
        XCTAssertTrue(ndjson.contains("OCR source"))
    }

    func testContentLogsUsesSameRetentionAsOperational() async {
        let old = Date().addingTimeInterval(-Double(DebugLogStore.retentionDays + 1) * 86400)
        await store.insert(makeEntry(message: "old content", kind: .content, timestamp: old))
        await store.insert(makeEntry(message: "old operational", kind: .operational, timestamp: old))
        await store.runRotation()
        let results = await store.queryAll(filter: DebugLogFilter())
        XCTAssertTrue(results.isEmpty, "Both content and operational old logs should be evicted")
    }

    // MARK: 4.5 Credential / raw-response exclusion

    func testCredentialMetadataIsRedacted() {
        let metadata = ["authorization": "Bearer sk-secret123", "endpoint": "/v1/chat"]
        let redacted = redactMetadata(metadata)
        XCTAssertEqual(redacted["authorization"], "[REDACTED]")
        XCTAssertEqual(redacted["endpoint"], "/v1/chat")
    }

    func testTokenMetadataIsRedacted() {
        let metadata = ["token": "abc123", "status": "200"]
        let redacted = redactMetadata(metadata)
        XCTAssertEqual(redacted["token"], "[REDACTED]")
        XCTAssertEqual(redacted["status"], "200")
    }

    func testAPIKeyMetadataIsRedacted() {
        let metadata = ["api_key": "key-123", "model": "gpt-4"]
        let redacted = redactMetadata(metadata)
        XCTAssertEqual(redacted["api_key"], "[REDACTED]")
        XCTAssertEqual(redacted["model"], "gpt-4")
    }

    func testFacadeRedactsCredentialsBeforeStoringEntry() async {
        let logger = DebugLogger(store: store)
        logger.log(
            "API call",
            level: .info,
            category: .translationOpenAI,
            metadata: ["authorization": "Bearer secret", "status_code": "200"]
        )
        await logger.flush()
        let results = await store.queryAll(filter: DebugLogFilter())
        let entry = results.first
        XCTAssertNotNil(entry)
        XCTAssertTrue(entry?.metadataJSON.contains("[REDACTED]") == true)
        XCTAssertFalse(entry?.metadataJSON.contains("Bearer secret") == true)
        XCTAssertTrue(entry?.metadataJSON.contains("200") == true)
    }

    func testNormalizedKeyVariantsAreRedacted() {
        let variants: [String: String] = [
            "AuthorizationHeader": "Bearer tok",
            "responseBody": "{\"choices\":[]}",
            "rawResponse": "HTTP 200",
            "access-token": "at-xyz",
            "API_KEY": "key-123",
            "AccessToken": "at-456",
            "clientSecret": "s3cr3t",
            "requestPayload": "payload data"
        ]
        let redacted = redactMetadata(variants)
        for key in variants.keys {
            XCTAssertEqual(redacted[key], "[REDACTED]", "\(key) should be redacted")
        }
    }

    func testSubstringMatchIsConservativeByDesign() {
        // These keys are redacted due to substring matching — intentionally conservative.
        // "auth" catches oauth/authentication variants (OAuth tokens are credentials).
        // "body" catches requestBody/responseBody variants (request payloads may contain PII).
        let conservative: [String: String] = [
            "oauth_provider": "github",    // "oauth" contains "auth" → redacted
            "requestBody": "some payload", // "requestBody" contains "body" → redacted
        ]
        let redacted = redactMetadata(conservative)
        XCTAssertEqual(redacted["oauth_provider"], "[REDACTED]",
                       "oauth_provider is redacted because 'oauth' contains 'auth' — conservative by design")
        XCTAssertEqual(redacted["requestBody"], "[REDACTED]",
                       "requestBody is redacted because it contains 'body' — conservative by design")
    }

    func testNonSensitiveKeysAreNotRedacted() {
        let safe: [String: String] = [
            "status": "200",
            "model": "gpt-4",
            "endpoint": "/v1/chat",
            "duration_ms": "120",
            "source": "OCRService"
        ]
        let redacted = redactMetadata(safe)
        for (key, value) in safe {
            XCTAssertEqual(redacted[key], value, "\(key) should NOT be redacted")
        }
    }

    func testLogAPIDiagnosticSanitizesEndpointQueryString() async {
        let logger = DebugLogger(store: store)
        logger.logAPIDiagnostic(
            "Request sent",
            category: .translationOpenAI,
            endpoint: "https://api.openai.com/v1/chat/completions?api_key=sk-secret&version=2"
        )
        await logger.flush()
        let results = await store.queryAll(filter: DebugLogFilter())
        let entry = try! XCTUnwrap(results.first)
        let metadata = try! XCTUnwrap(metadataDictionary(from: entry))
        XCTAssertFalse(entry.metadataJSON.contains("sk-secret"), "Query string credential must be stripped")
        XCTAssertFalse(entry.metadataJSON.contains("api_key"), "Query parameter name must be stripped")
        XCTAssertEqual(metadata["endpoint"], "https://api.openai.com/v1/chat/completions")
    }

    func testLogAPIDiagnosticSanitizesEndpointFragment() async {
        let logger = DebugLogger(store: store)
        logger.logAPIDiagnostic(
            "Request",
            category: .translationOpenAI,
            endpoint: "https://host/path?q=1#section"
        )
        await logger.flush()
        let results = await store.queryAll(filter: DebugLogFilter())
        let entry = try! XCTUnwrap(results.first)
        XCTAssertFalse(entry.metadataJSON.contains("section"))
        XCTAssertFalse(entry.metadataJSON.contains("q=1"))
        XCTAssertTrue(entry.metadataJSON.contains("/path"))
    }

    func testLogAPIDiagnosticSanitizesEmbeddedCredentials() async {
        let logger = DebugLogger(store: store)
        logger.logAPIDiagnostic(
            "Request",
            category: .translationOpenAI,
            endpoint: "https://user:password@host/v1/models"
        )
        await logger.flush()
        let results = await store.queryAll(filter: DebugLogFilter())
        let entry = try! XCTUnwrap(results.first)
        let metadata = try! XCTUnwrap(metadataDictionary(from: entry))
        XCTAssertFalse(entry.metadataJSON.contains("password"))
        XCTAssertFalse(entry.metadataJSON.contains("user:"))
        XCTAssertEqual(metadata["endpoint"], "https://host/v1/models")
    }

    func testLogAPIDiagnosticDoesNotPersistResponseBody() async {
        let logger = DebugLogger(store: store)
        logger.logAPIDiagnostic(
            "Translation complete",
            category: .translationOpenAI,
            statusCode: 200,
            model: "gpt-4o",
            endpoint: "/v1/chat/completions"
        )
        await logger.flush()
        let results = await store.queryAll(filter: DebugLogFilter())
        let entry = try! XCTUnwrap(results.first)
        XCTAssertFalse(entry.metadataJSON.contains("choices"), "Raw response body must not be persisted")
        XCTAssertTrue(entry.metadataJSON.contains("200"), "Status code should be included")
        XCTAssertTrue(entry.metadataJSON.contains("gpt-4o"), "Model should be included")
    }

    func testExportSkipsNonExportableEntries() async {
        await store.insert(makeEntry(message: "visible entry", exportable: true))
        await store.insert(makeEntry(message: "private entry", exportable: false))
        let ndjson = await store.exportNDJSON(filter: DebugLogFilter())
        XCTAssertTrue(ndjson.contains("visible entry"))
        XCTAssertFalse(ndjson.contains("private entry"), "Non-exportable entries must be excluded from export")
    }

    func testResponseBodyMetadataIsRedacted() {
        let metadata = ["response_body": "{\"choices\":[{\"text\":\"hello\"}]}", "status": "200"]
        let redacted = redactMetadata(metadata)
        XCTAssertEqual(redacted["response_body"], "[REDACTED]")
        XCTAssertEqual(redacted["status"], "200")
    }

    func testRawResponseMetadataIsRedacted() {
        let metadata = ["raw_response": "HTTP/1.1 200 OK\n...", "model": "gpt-4"]
        let redacted = redactMetadata(metadata)
        XCTAssertEqual(redacted["raw_response"], "[REDACTED]")
        XCTAssertEqual(redacted["model"], "gpt-4")
    }

    func testPayloadMetadataIsRedacted() {
        let metadata = ["payload": "{\"messages\":[...]}", "endpoint": "/v1/chat"]
        let redacted = redactMetadata(metadata)
        XCTAssertEqual(redacted["payload"], "[REDACTED]")
        XCTAssertEqual(redacted["endpoint"], "/v1/chat")
    }

    // MARK: Flush

    func testFlushDrainsPendingInserts() async {
        let logger = DebugLogger(store: store)
        for i in 0..<10 {
            logger.log("entry \(i)", level: .info, category: .cache)
        }
        await logger.flush()
        let results = await store.queryAll(filter: DebugLogFilter())
        XCTAssertEqual(results.count, 10, "All inserts should be persisted after flush()")
    }

    func testAwaitInitialRotationCompletes() async {
        await store.awaitInitialRotation()
        let isAvailable = await store.isAvailable
        XCTAssertTrue(isAvailable)
    }

    func testAwaitInitialRotationRemovesOldEntriesBeforeFirstQuery() async {
        // Seed old entries directly into a fresh store to verify rotation runs
        let old = Date().addingTimeInterval(-Double(DebugLogStore.retentionDays + 1) * 86400)
        let freshURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        let freshStore = DebugLogStore(databaseURL: freshURL)
        await freshStore.insert(makeEntry(message: "old entry", timestamp: old))
        await freshStore.insert(makeEntry(message: "new entry"))

        await freshStore.awaitInitialRotation()
        let results = await freshStore.queryAll(filter: DebugLogFilter())
        XCTAssertFalse(results.contains { $0.message == "old entry" },
                       "Old entries should be removed before first query")
        XCTAssertTrue(results.contains { $0.message == "new entry" })
        try? FileManager.default.removeItem(at: freshURL)
    }

    // MARK: 4.6 DB failure fallback to os.Logger

    func testFacadeLogsToOSLoggerWhenStoreUnavailable() async {
        let badURL = URL(fileURLWithPath: "/nonexistent/path/db.sqlite")
        let badStore = DebugLogStore(databaseURL: badURL)
        let logger = DebugLogger(store: badStore)
        // Should not crash; os.Logger emission happens synchronously
        logger.log("fallback message", level: .error, category: .cache)
        // No assertion needed beyond "did not crash"
    }

    // MARK: Export

    func testExportNDJSONContainsAllRequiredFields() async {
        await store.insert(makeEntry(
            message: "test msg",
            level: .warning,
            category: .export,
            kind: .operational,
            sessionID: "sess-123",
            source: "ExportService.swift",
            filePath: "/tmp/test.png"
        ))
        let ndjson = await store.exportNDJSON(filter: DebugLogFilter())
        XCTAssertFalse(ndjson.isEmpty)
        let line = ndjson.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(line.utf8)
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj?["id"])
        XCTAssertNotNil(obj?["timestamp"])
        XCTAssertEqual(obj?["level"] as? String, "warning")
        XCTAssertEqual(obj?["category"] as? String, "export")
        XCTAssertEqual(obj?["kind"] as? String, "operational")
        XCTAssertEqual(obj?["message"] as? String, "test msg")
        XCTAssertNotNil(obj?["metadata"])
        XCTAssertEqual(obj?["session_id"] as? String, "sess-123")
        XCTAssertNotNil(obj?["source"])
        XCTAssertEqual(obj?["file_path"] as? String, "/tmp/test.png")
    }

    func testExportDoesNotTriggerRotation() async {
        let old = Date().addingTimeInterval(-Double(DebugLogStore.retentionDays + 1) * 86400)
        await store.insert(makeEntry(message: "old entry", timestamp: old))
        let ndjson = await store.exportNDJSON(filter: DebugLogFilter())
        XCTAssertTrue(ndjson.contains("old entry"), "Export should not run rotation first")
    }

    func testExportRespectsActiveFilter() async {
        await store.insert(makeEntry(message: "error log", level: .error))
        await store.insert(makeEntry(message: "info log", level: .info))
        var filter = DebugLogFilter()
        filter.level = .error
        let ndjson = await store.exportNDJSON(filter: filter)
        XCTAssertTrue(ndjson.contains("error log"))
        XCTAssertFalse(ndjson.contains("info log"))
    }

    func testExportPreservesQueryOrder() async {
        let base = Date(timeIntervalSince1970: 1_000_000)
        await store.insert(makeEntry(message: "older", timestamp: base))
        await store.insert(makeEntry(message: "newer", timestamp: base.addingTimeInterval(10)))
        let ndjson = await store.exportNDJSON(filter: DebugLogFilter())
        let lines = ndjson.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("newer"), "First line should be the newest entry")
    }

    // MARK: - Helper

    private func makeEntry(
        message: String,
        level: DebugLogLevel = .info,
        category: DebugLogCategory = .cache,
        kind: DebugLogKind = .operational,
        sessionID: String = "test-session",
        source: String = "TestFile.swift",
        filePath: String? = nil,
        timestamp: Date = Date(),
        exportable: Bool = true
    ) -> DebugLogEntry {
        DebugLogEntry(
            id: 0,
            timestamp: timestamp,
            level: level,
            category: category,
            kind: kind,
            message: message,
            metadataJSON: "{}",
            sessionID: sessionID,
            sourceFileOrComponent: source,
            filePath: filePath,
            exportable: exportable
        )
    }

    private func metadataDictionary(from entry: DebugLogEntry) -> [String: String]? {
        guard let data = entry.metadataJSON.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }
}
