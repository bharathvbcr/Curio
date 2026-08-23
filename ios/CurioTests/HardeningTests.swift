import Foundation
import SwiftData
import os
import Testing
@testable import Curio

/// Hardening tests for the fixes surfaced by the cross-platform audit:
/// - `withTimeout` must not report a cancelled caller as a "timeout" (the sleep child swallows
///   its own cancellation, so the `.timeout` branch needs an explicit re-check).
/// - `LinkSweeper` deletes only on a dead link confirmed by BOTH HEAD and GET — some servers
///   answer 404 to HEAD while serving GET fine, and deletion is irreversible.
@Suite("Hardening")
struct HardeningTests {

    // MARK: - withTimeout

    @Test("Operation finishing inside budget returns its value")
    func valueWins() async throws {
        let value = try await withTimeout(5_000) { () -> Int in
            try? await Task.sleep(for: .milliseconds(10))
            return 42
        }
        #expect(value == 42)
    }

    @Test("Operation outliving the budget yields nil")
    func timeoutYieldsNil() async throws {
        let value = try await withTimeout(50) { () -> Int in
            try await Task.sleep(for: .seconds(5))
            return 42
        }
        #expect(value == nil)
    }

    @Test("Cancelling the caller surfaces CancellationError, never a fake timeout")
    func cancellationNotMasked() async {
        // Both group children wake on the same cancel tick, so which one `next()` sees first is
        // nondeterministic — repeat and require that NO iteration reports "cancelled" as nil.
        for _ in 0..<10 {
            let outcome = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
                let inner = Task.detached {
                    do {
                        let v = try await withTimeout(60_000) { () -> Int in
                            try await Task.sleep(for: .seconds(60))
                            return 1
                        }
                        cont.resume(returning: v == nil ? "masked-as-timeout" : "value")
                    } catch is CancellationError {
                        cont.resume(returning: "cancelled")
                    } catch {
                        cont.resume(returning: "error:\(error)")
                    }
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    inner.cancel()
                }
            }
            #expect(outcome != "masked-as-timeout", "cancellation was reported as timeout")
        }
    }

    // MARK: - LinkSweeper

    private let uid = "u1"

    private func makeStore() throws -> BookmarkStore {
        let schema = Schema([BookmarkModel.self, SpaceModel.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return BookmarkStore(modelContainer: container)
    }

    private func bookmark(_ id: String, url: String?) -> Bookmark {
        Bookmark(id: id, text: "text \(id)", createdAt: 1_700_000_000_000, userId: uid, url: url)
    }

    @Test("HEAD says 404 but GET serves content — bookmark kept")
    func headFalsePositiveKeepsBookmark() async throws {
        let store = try makeStore()
        await store.insertBookmarks([bookmark("keep1", url: "https://example.com/head-liar")])
        StubURLProtocol.handler = { request in
            request.httpMethod == "HEAD" ? .status(404) : .status(200)
        }
        defer { StubURLProtocol.handler = nil }

        let mirror = MirrorSpy()
        let sweeper = LinkSweeper(store: store, cloudMirror: mirror, session: Self.stubbedSession())
        await sweeper.runOneCycle()

        let all = await store.getAllBookmarksDirect()
        #expect(all.contains { $0.id == "keep1" }, "HEAD-only verdict must not delete")
        #expect(mirror.deleted.isEmpty)
    }

    @Test("Confirmed dead link (404 on HEAD and GET) deletes and mirrors")
    func confirmedDeadLinkDeletes() async throws {
        let store = try makeStore()
        await store.insertBookmarks([bookmark("dead1", url: "https://example.com/gone")])
        StubURLProtocol.handler = { _ in .status(404) }
        defer { StubURLProtocol.handler = nil }

        let mirror = MirrorSpy()
        let sweeper = LinkSweeper(store: store, cloudMirror: mirror, session: Self.stubbedSession())
        await sweeper.runOneCycle()

        let all = await store.getAllBookmarksDirect()
        #expect(!all.contains { $0.id == "dead1" })
        #expect(mirror.deleted == ["dead1"])
    }

    @Test("Transport failure keeps the bookmark")
    func transportFailureKeepsBookmark() async throws {
        let store = try makeStore()
        await store.insertBookmarks([bookmark("offline1", url: "https://example.com/offline")])
        StubURLProtocol.handler = { _ in .fail(URLError(.notConnectedToInternet)) }
        defer { StubURLProtocol.handler = nil }

        let mirror = MirrorSpy()
        let sweeper = LinkSweeper(store: store, cloudMirror: mirror, session: Self.stubbedSession())
        await sweeper.runOneCycle()

        let all = await store.getAllBookmarksDirect()
        #expect(all.contains { $0.id == "offline1" }, "transient errors are not deletions")
        #expect(mirror.deleted.isEmpty)
    }

    @Test("Healthy link and URL-less rows are untouched")
    func healthyAndUrllessRowsUntouched() async throws {
        let store = try makeStore()
        await store.insertBookmarks([
            bookmark("ok1", url: "https://example.com/fine"),
            bookmark("nourl", url: nil),
        ])
        StubURLProtocol.handler = { _ in .status(200) }
        defer { StubURLProtocol.handler = nil }

        let mirror = MirrorSpy()
        let sweeper = LinkSweeper(store: store, cloudMirror: mirror, session: Self.stubbedSession())
        await sweeper.runOneCycle()

        let all = await store.getAllBookmarksDirect()
        #expect(all.count == 2)
        #expect(mirror.deleted.isEmpty)
    }

    private static func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }
}

// MARK: - Test doubles

/// URLProtocol stub mapping each request to a canned reply. Handler state is lock-guarded for
/// Swift 6 strict concurrency; requests arrive on URLSession's internal queues.
final class StubURLProtocol: URLProtocol {

    enum Reply {
        case status(Int)
        case fail(URLError) // transport failure
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (URLRequest) -> Reply)?

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Reply)? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let reply = Self.handler?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        switch reply {
        case .fail(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .status(let code):
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let response = HTTPURLResponse(
                url: url, statusCode: code, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "0"]
            )
            client?.urlProtocol(self, didReceive: response!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// Records cloud deletions without touching Firestore. OSAllocatedUnfairLock's `withLock` is
/// the async-context-safe primitive Swift 6 complete checking requires here.
final class MirrorSpy: LinkSweeper.CloudMirror, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [String]())

    var deleted: [String] {
        state.withLock { $0 }
    }

    func deleteBookmarks(ids: [String]) async {
        state.withLock { $0 += ids }
    }
}
