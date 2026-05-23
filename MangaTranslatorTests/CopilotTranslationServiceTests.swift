import Testing
import Foundation
@testable import MangaTranslator

@Suite("CopilotTranslationService")
struct CopilotTranslationServiceTests {

    @Test("engine is githubCopilot")
    func engineIsGithubCopilot() {
        let service = CopilotTranslationService(model: "gpt-5-mini")
        #expect(service.engine == .githubCopilot)
    }

    @Test("translate throws missingAPIKey when Copilot CLI absent")
    func throwsMissingAPIKeyWhenUnavailable() async throws {
        guard case .notInstalled = CopilotEnvironment.check() else {
            return // copilot is installed, skip this assertion path
        }
        let service = CopilotTranslationService(model: "gpt-5-mini")
        await #expect(throws: TranslationError.self) {
            _ = try await service.translate(
                bubbles: [],
                from: .ja, to: .zhHant,
                context: .empty
            )
        }
    }
}

// MARK: - Non-2xx provider error tests

@Suite("CopilotTranslationService non-2xx")
struct CopilotTranslationServiceErrorTests {

    private func makeService(session: URLSession) -> CopilotTranslationService {
        CopilotTranslationService(model: "gpt-5-mini", urlSession: session)
    }

    @Test("OpenAI-compatible body yields sanitized error")
    func openAICompatibleBody() async throws {
        let body = Data(#"""
        {"error":{"message":"Model not found gpt-5-experimental","type":"invalid_request_error","code":"model_not_found"}}
        """#.utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.callAPI(systemPrompt: "sys", userPrompt: "user", token: "copilot-token-test")
            Issue.record("Expected throw")
        } catch let TranslationError.apiError(sanitized) {
            #expect(sanitized.provider == "GitHub Copilot")
            #expect(sanitized.statusCode == 404)
            #expect(sanitized.code == "model_not_found")
            #expect(sanitized.message == "Model not found gpt-5-experimental")
        } catch {
            Issue.record("Expected TranslationError.apiError, got \(error)")
        }
    }

    @Test("generic fallback body yields sanitized error without raw payload")
    func genericFallbackBody() async throws {
        let body = Data("<html>Service Unavailable, retry after 30s</html>".utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.callAPI(systemPrompt: "sys", userPrompt: "user", token: "copilot-token-test")
            Issue.record("Expected throw")
        } catch let TranslationError.apiError(sanitized) {
            #expect(sanitized.provider == "GitHub Copilot")
            #expect(sanitized.statusCode == 503)
            if let message = sanitized.message {
                #expect(message.count <= APIErrorSanitizer.maxMessageLength)
            }
        } catch {
            Issue.record("Expected TranslationError.apiError, got \(error)")
        }
    }

    @Test("localizedDescription excludes raw bearer tokens and emails")
    func excludesSensitiveContent() async throws {
        let body = Data(#"""
        {"error":{"message":"Authorization: Bearer ghu_secret1234567890abcdef1234567890 user a@b.com","code":"unauthorized"}}
        """#.utf8)
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        do {
            _ = try await service.callAPI(systemPrompt: "sys", userPrompt: "user", token: "copilot-token-test")
            Issue.record("Expected throw")
        } catch let error as TranslationError {
            let description = try #require(error.errorDescription)
            #expect(description.contains("GitHub Copilot"))
            #expect(description.contains("401"))
            #expect(!description.contains("ghu_secret1234567890abcdef1234567890"))
            #expect(!description.contains("a@b.com"))
        }
    }
}

// MARK: - Multi-page batch tests

/// Thread-safe counter for tracking mock request attempts.
final class BatchRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var _capturedBodies: [Data] = []
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    var capturedBodies: [Data] {
        lock.lock(); defer { lock.unlock() }
        return _capturedBodies
    }
    func record(body: Data) -> Int {
        lock.lock(); defer { lock.unlock() }
        _count += 1
        _capturedBodies.append(body)
        return _count
    }
}

private func makeBatchBubble(index: Int, text: String = "src") -> BubbleCluster {
    var b = BubbleCluster(
        boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10),
        text: text,
        observations: []
    )
    b.index = index
    return b
}

private func makeBatchInputs(_ pageIds: [String]) -> [BatchPageInput] {
    pageIds.map { BatchPageInput(pageId: $0, bubbles: [makeBatchBubble(index: 0, text: "src-\($0)")]) }
}

private func validMultiPageResponseBody(translations: [(pageId: String, text: String)]) -> Data {
    let pages = translations
        .map { "{\"page_id\":\"\($0.pageId)\",\"bubbles\":[{\"index\":0,\"translation\":\"\($0.text)\"}]}" }
        .joined(separator: ",")
    let content = "{\"pages\":[\(pages)]}"
    // Escape the content for embedding in the OpenAI-compatible choices.message.content field.
    let escaped = content
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return Data("{\"choices\":[{\"message\":{\"content\":\"\(escaped)\"}}]}".utf8)
}

@Suite("CopilotTranslationService translateBatch")
struct CopilotTranslationServiceBatchTests {

    private func makeService(session: URLSession) -> CopilotTranslationService {
        CopilotTranslationService(model: "gpt-5-mini", urlSession: session)
    }

    @Test("translateBatch sends multi-page request with recent context block")
    func sendsMultiPageRequest() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(body: request.readMockBody())
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, validMultiPageResponseBody(translations: [("1", "T1"), ("2", "T2")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let priorContext = TranslationContext(glossaryTerms: [], recentPageSummaries: ["page-A-summary"])
        let inputs = makeBatchInputs(["1", "2"])

        _ = try await service.translateBatch(
            pageInputs: inputs,
            from: .ja,
            to: .en,
            priorContext: priorContext,
            token: "copilot-token-test"
        )

        let body = try #require(counter.capturedBodies.first)
        let bodyString = String(decoding: body, as: UTF8.self)
        #expect(bodyString.contains("page_id"))
        #expect(bodyString.contains("Recent context"))
        #expect(bodyString.contains("page-A-summary"))
    }

    @Test("translateBatch returns outputs in requested order regardless of response order")
    func returnsOutputsInRequestedOrder() async throws {
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            // Response intentionally shuffled
            return (resp, validMultiPageResponseBody(translations: [("3", "T3"), ("1", "T1"), ("2", "T2")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let outputs = try await service.translateBatch(
            pageInputs: makeBatchInputs(["1", "2", "3"]),
            from: .ja,
            to: .en,
            priorContext: .empty,
            token: "copilot-token-test"
        )

        #expect(outputs.map { $0.pageId } == ["1", "2", "3"])
    }

    @Test("translateBatch retries once on HTTP 500 then succeeds")
    func retriesOnceOnHTTP500() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            let attempt = counter.record(body: request.readMockBody())
            if attempt == 1 {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (resp, Data("internal error".utf8))
            } else {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, validMultiPageResponseBody(translations: [("1", "T1")]))
            }
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let outputs = try await service.translateBatch(
            pageInputs: makeBatchInputs(["1"]),
            from: .ja,
            to: .en,
            priorContext: .empty,
            token: "copilot-token-test"
        )

        #expect(outputs.count == 1)
        #expect(counter.count == 2)
    }

    @Test("translateBatch throws after second HTTP 500 (fallback trigger)")
    func throwsAfterSecondHTTP500() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(body: request.readMockBody())
            let resp = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (resp, Data("internal error".utf8))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        var caught: Error?
        do {
            _ = try await service.translateBatch(
                pageInputs: makeBatchInputs(["1"]),
                from: .ja,
                to: .en,
                priorContext: .empty,
                token: "copilot-token-test"
            )
            Issue.record("Expected throw")
        } catch {
            caught = error
        }

        #expect(counter.count == 2)
        let error = try #require(caught)
        // Non-cancellation error = fallback trigger
        #expect(!(error is CancellationError))
        if let urlError = error as? URLError {
            #expect(urlError.code != .cancelled)
        }
    }

    @Test("translateBatch throws on missing page id after retry (fallback trigger)")
    func throwsOnMissingPageId() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(body: request.readMockBody())
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            // Missing page "2"
            return (resp, validMultiPageResponseBody(translations: [("1", "T1"), ("3", "T3")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        var caught: Error?
        do {
            _ = try await service.translateBatch(
                pageInputs: makeBatchInputs(["1", "2", "3"]),
                from: .ja,
                to: .en,
                priorContext: .empty,
                token: "copilot-token-test"
            )
            Issue.record("Expected throw")
        } catch {
            caught = error
        }

        #expect(counter.count == 2)
        let parseError = try #require(caught as? LLMResponseParser.MultiPageParseError)
        if case .missingPage(let id) = parseError {
            #expect(id == "2")
        } else {
            Issue.record("Expected .missingPage, got \(parseError)")
        }
    }

    @Test("translateBatch accepts any 2xx response status (e.g. 201)")
    func acceptsAny2xxStatus() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request in
            _ = counter.record(body: request.readMockBody())
            // 201 is still a 2xx; the spec accepts the whole 200–299 range.
            let resp = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (resp, validMultiPageResponseBody(translations: [("1", "T1")]))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        let outputs = try await service.translateBatch(
            pageInputs: makeBatchInputs(["1"]),
            from: .ja,
            to: .en,
            priorContext: .empty,
            token: "copilot-token-test"
        )

        #expect(outputs.count == 1)
        #expect(counter.count == 1)
    }

    @Test("translateBatch propagates cancellation without retry or fallback")
    func doesNotRetryOrFallbackOnCancellation() async throws {
        let counter = BatchRequestCounter()
        let session = ProviderHTTPMockURLProtocol.makeSession { request -> Result<(HTTPURLResponse, Data), URLError> in
            _ = counter.record(body: request.readMockBody())
            return .failure(URLError(.cancelled))
        }
        defer { ProviderHTTPMockURLProtocol.releaseSession(session) }

        let service = makeService(session: session)
        var caught: Error?
        do {
            _ = try await service.translateBatch(
                pageInputs: makeBatchInputs(["1"]),
                from: .ja,
                to: .en,
                priorContext: .empty,
                token: "copilot-token-test"
            )
            Issue.record("Expected throw")
        } catch {
            caught = error
        }

        #expect(counter.count == 1)
        let urlError = try #require(caught as? URLError)
        #expect(urlError.code == .cancelled)
    }
}
