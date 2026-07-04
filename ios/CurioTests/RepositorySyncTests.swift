import Foundation
import SwiftData
import Testing
@testable import Curio

/// A request-recording `URLProtocol` stub dedicated to the repository-level sync tests.
///
/// This is deliberately a THIRD distinct protocol class (alongside `MockURLProtocol` in
/// SourceResolverTests.swift and `RecordingMockURLProtocol` in RepositoryPagingTests.swift): a
/// `URLProtocol` handler is process-global static state, and Swift Testing runs *suites* in
/// parallel — `.serialized` only serializes tests *within* a suite. Sharing a static handler across
/// suites would let them race each other's canned responses. Each suite's session config registers
/// only its own class, so the suites stay isolated however the runner schedules them.
///
/// Unlike `RecordingMockURLProtocol`, the handler here returns an OPTIONAL response: `nil` (or a
/// `nil` handler) is answered with an empty `404` instead of a load failure. The repository under
/// test is a full production object — if any dependency ever routed an unexpected request through
/// the injected session (e.g. an auth-token endpoint), the mock must tolerate it rather than crash
/// or hang the sync. (Firestore traffic rides its own gRPC channels, not this `URLSession`, so it
/// never reaches this protocol at all.)
final class SyncMockURLProtocol: URLProtocol {
    /// Canned response factory. `nonisolated(unsafe)` for the same reason as the sibling mocks:
    /// `URLProtocol` offers no injection seam other than a static; the owning suite is
    /// `.serialized`, and within one test every sync is awaited before the next begins, so there
    /// is no concurrent mutation. Returning `nil` yields a 404 (unexpected-request tolerance).
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (statusCode: Int, headers: [String: String], body: Data)?)?

    /// Every request answered so far (the Kotlin `server.requestCount` / `takeRequest()` analogue).
    /// Guarded by a lock because `startLoading` runs on URLSession's private queue while the test
    /// thread reads.
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []
    private static let lock = NSLock()

    static var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    /// The subset of recorded requests that hit the X bookmarks endpoint — the only requests the
    /// Kotlin `server.requestCount` could ever have seen (its MockWebServer served nothing else).
    static var bookmarkRequests: [URLRequest] {
        requests.filter { $0.url?.path.hasSuffix("/bookmarks") == true }
    }

    /// Clears the handler and the request log (run in each test's teardown).
    static func reset() {
        lock.withLock { recordedRequests = [] }
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.recordedRequests.append(request) }
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        // Unexpected / unmatched requests get a plain 404 rather than a crash or a transport error:
        // the production repository must be able to shrug them off without derailing the test.
        let (statusCode, headers, body) = Self.handler?(request) ?? (404, [:], Data())
        let response = HTTPURLResponse(
            url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Repository-level sync tests: pagination through `meta.next_token` and 429 rate-limit handling,
/// exercised against the REAL `BookmarkRepositoryImpl`.
///
/// Full-stack port of `app/src/test/java/com/example/RepositoryPagingTest.kt` (JUnit + Robolectric
/// + MockWebServer). Where `RepositoryPagingTests.swift` narrows the same Kotlin file to the
/// `XBookmarksApiClient` layer, this suite keeps the Kotlin wiring intact — the real repository
/// actor over real collaborators:
///
/// - `BookmarkRepositoryImpl(api, dao, spaceDao, tokenStore, FirebaseSyncManager(context), authApi)`
///   → `BookmarkRepositoryImpl(api:store:spaceStore:tokenStore:firebaseSyncManager:authApi:)`.
/// - `Room.inMemoryDatabaseBuilder(...)` → an in-memory `ModelContainer` over the app's exact
///   schema (`Schema([BookmarkModel.self, SpaceModel.self])`), feeding the `@ModelActor`
///   `BookmarkStore` / `SpaceStore` (same pattern as BookmarkStoreTests.swift).
/// - `TokenStore(context)` + `saveTokens("acc", "ref", "u1")` → the REAL Keychain-backed
///   `TokenStore` actor with the same credentials. The Keychain is process-global state shared with
///   the test host app, so each test tears down with `clear()` — which purges ONLY the X-session
///   items; the HF token and xAI key intentionally survive `clear()` by design (TokenStore.swift),
///   so nothing beyond the session slots this suite itself wrote is ever touched.
/// - `FirebaseSyncManager(context)` with UNCONFIGURED Firebase (Robolectric context ⇒ every
///   Firestore op resiliently no-ops) → the real `FirebaseSyncManager()` running against the test
///   host's placeholder `GoogleService-Info.plist`: anonymous auth fails, so `pullBookmarks`
///   fail-softs to `[]` and `pushBookmarks` is swallowed. The repository's 15s `withTimeout`
///   bounds phases 1/3 either way, so worst-case runtime stays bounded. Crucially, sync precedence
///   is X-authoritative — a Firebase pull/push failure can NEVER mask an X error — which is exactly
///   what makes the 429 assertion below valid end-to-end.
/// - MockWebServer → `SyncMockURLProtocol` inside an injected ephemeral `URLSession` feeding
///   `HTTPClient` and both API clients (`baseURL` = `https://mock.test/`).
///
/// The Kotlin file has exactly two tests (no 401→refresh case), both ported here with
/// byte-identical JSON bodies. `.serialized` because `SyncMockURLProtocol.handler` and the Keychain
/// are process-global state.
@Suite("RepositorySync (full-stack port of RepositoryPagingTest.kt)", .serialized)
struct RepositorySyncTests {

    private let store: BookmarkStore
    private let spaceStore: SpaceStore
    private let tokenStore: TokenStore
    private let repo: BookmarkRepositoryImpl

    private let uid = "u1"

    /// Kotlin `@Before setup()`: fresh in-memory database + repository per test (Swift Testing
    /// instantiates the suite struct for every `@Test`). Token seeding is async (actor call), so it
    /// happens inside `withXSession` at the top of each test rather than here.
    init() throws {
        // Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java) — the app's exact schema
        // pair, stored in memory only (dies with the suite value; Kotlin @After db.close()).
        let schema = Schema([BookmarkModel.self, SpaceModel.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        store = BookmarkStore(modelContainer: container)
        spaceStore = SpaceStore(modelContainer: container)

        // The REAL Keychain actor (Kotlin used the real TokenStore over a Robolectric context).
        tokenStore = TokenStore()

        // MockWebServer stand-in: an ephemeral session answered entirely by SyncMockURLProtocol
        // (the `server.url("/")` analogue — same injection seam as the sibling suites).
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SyncMockURLProtocol.self]
        let session = URLSession(configuration: config)
        let http = HTTPClient(primarySession: session, metadataSession: session)
        let baseURL = URL(string: "https://mock.test/")!

        // The REAL repository over real collaborators — the exact Kotlin constructor call:
        // BookmarkRepositoryImpl(api, db.bookmarkDao(), db.spaceDao(), tokenStore,
        //                        FirebaseSyncManager(context), authApi)
        repo = BookmarkRepositoryImpl(
            api: XBookmarksApiClient(http: http, baseURL: baseURL),
            store: store,
            spaceStore: spaceStore,
            tokenStore: tokenStore,
            firebaseSyncManager: FirebaseSyncManager(),
            authApi: XAuthApiClient(http: http, baseURL: baseURL)
        )
    }

    /// Session lifecycle bracket: seeds the Kotlin `@Before` credentials
    /// (`saveTokens(accessToken = "acc", refreshToken = "ref", userId = uid)`), runs the test body,
    /// then ALWAYS tears down — even when the body throws — mirroring the Kotlin `@After`:
    /// - `tokenStore.clear()` so the test host app's Keychain isn't left polluted with the fake
    ///   session (only the X-session slots are purged; HF/xAI keys survive `clear()` by design);
    /// - `repo.close()` cancels the fire-and-forget cloud-mirror tasks (Kotlin `mirrorScope`);
    /// - `SyncMockURLProtocol.reset()` clears the process-global handler + request log
    ///   (Kotlin `server.shutdown()`).
    ///
    /// A helper (not `defer`) because the teardown calls are `await`s into actors, which `defer`
    /// cannot perform.
    private func withXSession(_ body: () async throws -> Void) async throws {
        await tokenStore.saveTokens(accessToken: "acc", refreshToken: "ref", userId: uid)
        var thrown: (any Error)?
        do {
            try await body()
        } catch {
            thrown = error
        }
        await tokenStore.clear()
        await repo.close()
        SyncMockURLProtocol.reset()
        if let thrown { throw thrown }
    }

    /// Kotlin: `paginates through next_token`.
    ///
    /// Bodies are byte-identical to the two `MockResponse` payloads; MockWebServer's enqueue-order
    /// dispatch becomes a dispatch on the `pagination_token` query parameter (page 2 is only served
    /// to the TOK2 follow-up). The full `syncBookmarks` pipeline runs: Firebase pull (fail-soft
    /// `[]`), the paginated X fetch under test, Firebase push (swallowed), and the store writes the
    /// Kotlin test observed through `db.bookmarkDao().getBookmarks(uid).first()`.
    @Test("paginates through next_token")
    func paginatesThroughNextToken() async throws {
        try await withXSession {
            let page1 = #"{"data":[{"id":"a","text":"first","created_at":"2024-01-01T00:00:00.000Z"}],"meta":{"next_token":"TOK2"}}"#
            let page2 = #"{"data":[{"id":"b","text":"second"}],"meta":{}}"#
            SyncMockURLProtocol.handler = { request in
                // Only the X bookmarks endpoint is scripted; anything else (none expected — the
                // unconfigured Firebase never touches this session) falls through to the 404.
                guard request.url?.path.hasSuffix("/bookmarks") == true else { return nil }
                let query = request.url?.query ?? ""
                let body = query.contains("pagination_token=TOK2") ? page2 : page1
                return (statusCode: 200, headers: [:], body: Data(body.utf8))
            }

            // Kotlin: repo.syncBookmarks(uid, fetchNextPage = false) → assertTrue(result.isSuccess).
            // The Kotlin Result<Unit> collapsed to `async throws`, so "isSuccess" = does not throw.
            try await repo.syncBookmarks(userId: uid, fetchNextPage: false)

            // Kotlin: db.bookmarkDao().getBookmarks(uid).first().map { it.id }.toSet(). The store
            // read IS the repository's read path substrate (getBookmarksFlow re-emits exactly
            // store.getBookmarks); reading the store directly avoids racing the publisher's
            // asynchronous seed while asserting the same rows.
            let stored = Set(await store.getBookmarks(userId: uid).map(\.id))
            #expect(stored == Set(["a", "b"]))

            // Two pages requested: page 1 + the next_token follow-up (Kotlin server.requestCount).
            #expect(SyncMockURLProtocol.bookmarkRequests.count == 2)
            // Stronger than Kotlin: the follow-up actually carried page 1's next_token.
            #expect(
                SyncMockURLProtocol.bookmarkRequests.last?.url?.query?
                    .contains("pagination_token=TOK2") == true
            )
        }
    }

    /// Kotlin: `rate limit 429 surfaces RateLimitException`.
    ///
    /// A single 429 with `x-rate-limit-reset: 60` and the exact Kotlin body. 60s reset > the
    /// repository's 30s backoff cap, so it is surfaced immediately with no blocking retry (one
    /// request). Kotlin asserted only the exception type; here we additionally assert
    /// `resetTimeSeconds == 60` — the header is a small relative value (≤ 1_000_000), so the
    /// repository's private header math must pass it through as-is, exercised end-to-end. This
    /// assertion is only valid because sync precedence is X-authoritative: the fail-soft Firebase
    /// pull/push can never mask the X error with a false success.
    @Test("rate limit 429 surfaces RateLimitError")
    func rateLimit429SurfacesRateLimitError() async throws {
        try await withXSession {
            SyncMockURLProtocol.handler = { request in
                guard request.url?.path.hasSuffix("/bookmarks") == true else { return nil }
                return (
                    statusCode: 429,
                    headers: ["x-rate-limit-reset": "60"], // 60s reset > 30s cap → surfaced immediately, no blocking retry
                    body: Data(#"{"title":"Too Many Requests"}"#.utf8)
                )
            }

            // Kotlin: assertTrue(result.isFailure) + exceptionOrNull() is RateLimitException.
            do {
                try await repo.syncBookmarks(userId: uid, fetchNextPage: false)
                Issue.record("expected syncBookmarks to throw RateLimitError")
            } catch let error as RateLimitError {
                // The relative-value branch of the repository's private header math: 60 → 60.
                #expect(error.resetTimeSeconds == 60)
            } catch {
                Issue.record("expected RateLimitError, got \(error)")
            }
            #expect(SyncMockURLProtocol.bookmarkRequests.count == 1)
        }
    }
}
