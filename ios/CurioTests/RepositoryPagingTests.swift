import Foundation
import Testing
@testable import Curio

/// A request-recording `URLProtocol` stub for the paging tests — the same MockWebServer stand-in
/// pattern as `MockURLProtocol` (SourceResolverTests.swift), extended with a request log so the
/// Kotlin `server.requestCount` / recorded-request assertions can be mirrored.
///
/// This is deliberately a SEPARATE class (not a reuse of `MockURLProtocol`): a `URLProtocol`
/// handler is process-global static state, and Swift Testing runs *suites* in parallel —
/// `.serialized` only serializes tests *within* a suite. Sharing one static handler across two
/// suites would let `SourceClientTests` and this suite race each other's canned responses. With a
/// distinct protocol class per suite (each session config registers only its own class), the two
/// serialized suites stay isolated however the runner schedules them.
final class RecordingMockURLProtocol: URLProtocol {
    /// Canned response factory. `nonisolated(unsafe)` for the same reason as `MockURLProtocol`:
    /// `URLProtocol` offers no injection seam other than a static; the owning suite is
    /// `.serialized`, and within one test every request is awaited before the next is issued, so
    /// there is no concurrent mutation.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (statusCode: Int, headers: [String: String], body: Data))?

    /// Every request answered so far (Kotlin `server.requestCount` / `takeRequest()`). Guarded by a
    /// lock because `startLoading` runs on URLSession's private queue while the test thread reads.
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []
    private static let lock = NSLock()

    static var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    /// Clears the handler and the request log (run in each test's `defer`).
    static func reset() {
        lock.withLock { recordedRequests = [] }
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.recordedRequests.append(request) }
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (statusCode, headers, body) = handler(request)
        let response = HTTPURLResponse(
            url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// X bookmarks pagination + 429 rate-limit handling against a stubbed URL-loading layer.
///
/// Port of `app/src/test/java/com/example/RepositoryPagingTest.kt` (JUnit + Robolectric +
/// MockWebServer), NARROWED from the repository level to the `XBookmarksApi` level:
///
/// The Kotlin test wired a full `BookmarkRepositoryImpl(api, dao, spaceDao, tokenStore,
/// FirebaseSyncManager(context), authApi)` and asserted on `repo.syncBookmarks(...)`. On iOS that
/// initializer requires the CONCRETE `FirebaseSyncManager` actor — there is no protocol seam, and
/// its `init` calls `FirebaseApp.configure()` / `Firestore.firestore()` (crashes without a
/// `GoogleService-Info.plist`, then every sync phase would hit real Google auth endpoints from a
/// unit test). `TokenStore` is likewise the concrete real-Keychain actor. Faking either cleanly
/// would require touching app sources, which this port must not do — so, per the sanctioned
/// fallback, these tests exercise `XBookmarksApiClient` (the exact client `syncBookmarks` calls)
/// through the same `HTTPClient` + mock-session path, and drive the same `meta.next_token` loop the
/// repository runs:
/// - **pagination**: two mocked pages with byte-identical bodies to the Kotlin test; asserts the
///   same `{a, b}` id set and 2-request count, plus (stronger than Kotlin) that the follow-up
///   request actually carried `pagination_token=TOK2`.
/// - **429**: the Kotlin `RateLimitException` is minted by repository-private code from the typed
///   `APIError` this layer throws; here we assert the typed `APIError` surfaces status 429 with the
///   `x-rate-limit-reset` header the repository's mapping reads (the un-narrowed remainder — header
///   → `RateLimitError.resetTimeSeconds` math — is repository-private and untestable without seams).
///
/// `.serialized` because `RecordingMockURLProtocol.handler` is process-global state.
@Suite("RepositoryPaging (mirrors RepositoryPagingTest.kt, narrowed to XBookmarksApi)", .serialized)
struct RepositoryPagingTests {

    private let uid = "u1"

    /// Builds an `HTTPClient` whose sessions are answered entirely by `RecordingMockURLProtocol`
    /// (the `server.url("/")` analogue — same injection seam as SourceClientTests).
    private func stubbedHTTPClient() -> HTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingMockURLProtocol.self]
        let session = URLSession(configuration: config)
        return HTTPClient(primarySession: session, metadataSession: session)
    }

    /// The client under test, pointed at the mock "server".
    private func stubbedApi() -> XBookmarksApiClient {
        XBookmarksApiClient(http: stubbedHTTPClient(), baseURL: URL(string: "https://mock.test/")!)
    }

    /// Kotlin: `paginates through next_token`. Bodies are byte-identical to the two
    /// `MockResponse` payloads; the enqueue-order dispatch becomes a dispatch on the
    /// `pagination_token` query parameter (page 2 is only served to the TOK2 follow-up).
    @Test("paginates through next_token")
    func paginatesThroughNextToken() async throws {
        let page1 = #"{"data":[{"id":"a","text":"first","created_at":"2024-01-01T00:00:00.000Z"}],"meta":{"next_token":"TOK2"}}"#
        let page2 = #"{"data":[{"id":"b","text":"second"}],"meta":{}}"#
        RecordingMockURLProtocol.handler = { request in
            let query = request.url?.query ?? ""
            let body = query.contains("pagination_token=TOK2") ? page2 : page1
            return (statusCode: 200, headers: [:], body: Data(body.utf8))
        }
        defer { RecordingMockURLProtocol.reset() }

        let api = stubbedApi()

        // Drive the exact loop `syncBookmarks` runs: page 1, then follow `meta.next_token` until
        // exhausted (with the repository's MAX_PAGES_PER_SYNC = 10 safety cap).
        var storedIds: Set<String> = []
        var paginationToken: String? = nil
        var pagesFetched = 0
        repeat {
            let response = try await api.getBookmarks(
                authHeader: "Bearer acc",
                userId: uid,
                maxResults: 100,
                paginationToken: paginationToken
            )
            for dto in response.data ?? [] { storedIds.insert(dto.id) }
            paginationToken = response.meta?.nextToken
            pagesFetched += 1
        } while paginationToken != nil && pagesFetched < 10

        #expect(storedIds == Set(["a", "b"]))
        // Two pages requested: page 1 + the next_token follow-up.
        #expect(RecordingMockURLProtocol.requests.count == 2)
        // The follow-up request carried page 1's next_token.
        #expect(RecordingMockURLProtocol.requests.last?.url?.query?.contains("pagination_token=TOK2") == true)
    }

    /// Kotlin: `rate limit 429 surfaces RateLimitException`. Narrowed (see suite doc): the typed
    /// failure at this layer is `APIError.http(429, ...)` carrying the `x-rate-limit-reset` header —
    /// the exact input the repository turns into `RateLimitError`. The 60s reset value matches the
    /// Kotlin comment: 60s > the 30s backoff cap, so the repository surfaces it immediately with no
    /// blocking retry.
    @Test("rate limit 429 surfaces typed APIError with reset header")
    func rateLimit429SurfacesTypedError() async {
        RecordingMockURLProtocol.handler = { _ in
            (
                statusCode: 429,
                headers: ["x-rate-limit-reset": "60"], // 60s reset > 30s cap → surfaced immediately, no blocking retry
                body: Data(#"{"title":"Too Many Requests"}"#.utf8)
            )
        }
        defer { RecordingMockURLProtocol.reset() }

        let api = stubbedApi()
        do {
            _ = try await api.getBookmarks(
                authHeader: "Bearer acc",
                userId: uid,
                maxResults: 100,
                paginationToken: nil
            )
            Issue.record("expected a 429 APIError to be thrown")
        } catch let error as APIError {
            #expect(error.statusCode == 429)
            // The lower-cased header map the repository reads `x-rate-limit-reset` from.
            #expect(error.headers["x-rate-limit-reset"] == "60")
        } catch {
            Issue.record("expected APIError, got \(error)")
        }
        #expect(RecordingMockURLProtocol.requests.count == 1)
    }
}
