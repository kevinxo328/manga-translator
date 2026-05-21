import Foundation
@testable import MangaTranslator

/// `URLProtocol` stub used by translation-provider non-2xx tests.
///
/// Each test calls ``makeSession(handler:)`` to get a fresh `URLSession`
/// pre-configured with a per-session UUID injected into every outgoing
/// request via `URLSessionConfiguration.httpAdditionalHeaders`. The protocol
/// stores handlers in a class-level dictionary keyed by that UUID, so test
/// instances running in parallel never see each other's handlers and no
/// cross-suite lock is required.
final class ProviderHTTPMockURLProtocol: URLProtocol {

    typealias Handler = (URLRequest) -> (HTTPURLResponse, Data)

    static let sessionHeaderName = "X-Provider-Mock-Session-ID"

    private static let lock = NSLock()
    private static var handlers: [String: Handler] = [:]

    /// Creates a `URLSession` whose every request will be served by `handler`.
    /// The returned session owns its handler entry until the caller invokes
    /// ``releaseSession(_:)``.
    static func makeSession(handler: @escaping Handler) -> URLSession {
        let id = UUID().uuidString
        lock.lock()
        handlers[id] = handler
        lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProviderHTTPMockURLProtocol.self]
        config.httpAdditionalHeaders = [sessionHeaderName: id]
        return URLSession(configuration: config)
    }

    /// Removes the handler entry for a session created by ``makeSession``.
    /// Idempotent; safe to call from `defer` even if the session was already
    /// released.
    static func releaseSession(_ session: URLSession) {
        guard
            let id = session.configuration.httpAdditionalHeaders?[sessionHeaderName] as? String
        else { return }
        lock.lock()
        handlers.removeValue(forKey: id)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard
            let id = request.value(forHTTPHeaderField: Self.sessionHeaderName)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        Self.lock.lock()
        let handler = Self.handlers[id]
        Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - KeychainService test factory

extension KeychainService {
    /// Builds a `KeychainService` that returns the given value for every
    /// `retrieve(for:)` call. The static keychain cache is class-shared, but
    /// the value returned by the mocked closure does not affect correctness
    /// in provider HTTP tests because the mocked URL session ignores the
    /// supplied credential — so cross-test races on the cache are benign.
    static func mocked(returning value: String) -> KeychainService {
        var service = KeychainService()
        let valueData = Data(value.utf8) as CFData
        service.secItemCopyMatching = { _, resultPtr in
            resultPtr?.pointee = valueData
            return errSecSuccess
        }
        return service
    }
}
