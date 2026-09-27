import Darwin
import Foundation
import SwiftData
import Testing
@testable import Curio

@Suite("MacDeskStressTests")
struct MacDeskStressTests {

    // MARK: - Helpers

    private func makeBookmark(
        id: String,
        text: String = "Bookmark body",
        createdAt: Int64 = 1_000,
        title: String? = nil,
        url: String? = nil,
        summary: String? = nil,
        sourceType: SourceType? = nil,
        sourceTitle: String? = nil,
        favorite: Bool = false,
        later: Bool = false,
        authorName: String? = nil,
        authorUsername: String? = nil,
        spaceId: String? = nil
    ) -> Bookmark {
        Bookmark(
            id: id,
            text: text,
            createdAt: createdAt,
            userId: "stress-user",
            title: title,
            url: url,
            summary: summary,
            sourceType: sourceType,
            sourceTitle: sourceTitle,
            isFavorite: favorite,
            isSavedForLater: later,
            authorName: authorName,
            authorUsername: authorUsername,
            spaceId: spaceId
        )
    }

    private func makeSpace(
        id: String,
        name: String,
        pinned: Bool = false,
        sort: Int = 0
    ) -> Space {
        Space(
            id: id,
            userId: "stress-user",
            name: name,
            color: 0xFF1E88E5,
            icon: "folder",
            createdAt: 100,
            isPinned: pinned,
            sortIndex: sort
        )
    }

    // MARK: - 1. High-Volume Collection & Invariant Verification

    @Test("5,000 bookmarks sort strictly newest-first with deterministic ID tie-breaking")
    func massiveBookmarkCollectionSortAndFilterStress() {
        var items: [Bookmark] = []
        items.reserveCapacity(5_000)

        // Generate 5,000 bookmarks with deliberate duplicate timestamps to stress tie-breakers
        for i in 0..<5_000 {
            let timestamp = Int64(i / 5) // Groups of 5 have identical timestamps
            let id = String(format: "bm_%05d", i)
            let isFav = (i % 7 == 0)
            let isLater = (i % 11 == 0)
            let spaceId = (i % 4 == 0) ? nil : "space_\(i % 10)"
            items.append(makeBookmark(
                id: id,
                text: "Post content for item \(i) discussing artificial intelligence and systems",
                createdAt: timestamp,
                favorite: isFav,
                later: isLater,
                spaceId: spaceId
            ))
        }

        // 1. Check all visible
        let visible = MacDeskLibrary.visible(items, scope: .library, query: "")
        #expect(visible.count == 5_000)

        // Verify sorting invariant: newest first, tie broken by id ascending
        for idx in 0..<(visible.count - 1) {
            let curr = visible[idx]
            let next = visible[idx + 1]
            if curr.createdAt == next.createdAt {
                #expect(curr.id < next.id, "Tie breaker failed for identical createdAt: \(curr.id) vs \(next.id)")
            } else {
                #expect(curr.createdAt > next.createdAt, "Order violation: \(curr.createdAt) should be > \(next.createdAt)")
            }
        }

        // 2. Check scoped counts and filtering
        let favCount = MacDeskLibrary.count(items, scope: .favorites)
        let favVisible = MacDeskLibrary.visible(items, scope: .favorites, query: "")
        #expect(favCount == favVisible.count)
        let allFavs = favVisible.allSatisfy { $0.isFavorite }
        #expect(allFavs)

        let unfiledCount = MacDeskLibrary.count(items, scope: .unfiled)
        let unfiledVisible = MacDeskLibrary.visible(items, scope: .unfiled, query: "")
        #expect(unfiledCount == unfiledVisible.count)
        let allUnfiled = unfiledVisible.allSatisfy { $0.spaceId == nil }
        #expect(allUnfiled)

        let space3Visible = MacDeskLibrary.visible(items, scope: .space("space_3"), query: "")
        let allSpace3 = space3Visible.allSatisfy { $0.spaceId == "space_3" }
        #expect(allSpace3)

        // 3. Search precision
        let searchResults = MacDeskLibrary.visible(items, scope: .library, query: "systems")
        #expect(searchResults.count == 5_000)

        let specificSearch = MacDeskLibrary.visible(items, scope: .library, query: "bm_00042")
        #expect(specificSearch.count == 1)
        #expect(specificSearch.first?.id == "bm_00042")
    }

    // MARK: - 2. Adversarial & Malformed Inputs

    @Test("Adversarial strings, complex grapheme clusters, and multi-byte Unicode do not crash or corrupt presentation")
    func adversarialAndMalformedInputsStress() {
        let extremeInputs: [String] = [
            "",
            "   \t\r\n   ",
            String(repeating: "A", count: 100_000), // 100KB string
            String(repeating: "👨‍👩‍👧‍👦", count: 500), // Multi-ZWJ grapheme clusters
            "🇺🇸🇩🇪🇯🇵🇬🇧🇫🇷", // Regional indicator flags
            "مرحبا بالعالم كيف الحال؟", // RTL Arabic
            "שלום עולם! מה שלומך?", // RTL Hebrew
            "🎉🔥🚀✨🎯💡🧪📦⚙️🏷️",
            "\u{0000}\u{0001}\u{0002}\u{001F}\u{007F}", // Control chars
            "Line 1\n\n\n\n\nLine 2\r\nLine 3\rLine 4",
            "https://sub.example.com:8080/path/to/resource?query=1&b=2#frag",
            "not-a-valid-url-at-all",
            "ftp://files.repo.org/package.tar.gz",
            "javascript:alert('xss')",
            "data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg=="
        ]

        for (idx, input) in extremeInputs.enumerated() {
            let bm = makeBookmark(
                id: "adv_\(idx)",
                text: input,
                title: input,
                url: input,
                summary: input,
                sourceTitle: input,
                authorName: input,
                authorUsername: input
            )

            // Test all library formatters - must not throw, fatalError, or hang
            let title = MacDeskLibrary.title(bm)
            #expect(!title.isEmpty)
            #expect(title.count <= 85) // 80 chars + "…" or "Untitled"

            let excerpt = MacDeskLibrary.excerpt(bm)
            #expect(excerpt.count <= 190) // bounded

            let byline = MacDeskLibrary.byline(bm)
            let _ = byline

            let link = MacDeskLibrary.link(bm)
            let _ = link

            let host = MacDeskLibrary.host(bm)
            let _ = host

            let symbol = MacDeskLibrary.symbol(for: bm)
            #expect(!symbol.isEmpty)

            let meta = MacDeskLibrary.metaParts(bm)
            #expect(!meta.isEmpty)

            let share = MacDeskLibrary.shareText(bm)
            #expect(!share.isEmpty)

            let a11y = MacDeskLibrary.accessibilityLabel(bm, spaceName: "Space")
            #expect(!a11y.isEmpty)

            let bibtex = MacDeskLibrary.bibtexCitation(bm)
            let _ = bibtex
        }
    }

    // MARK: - 3. Search ReDoS & Fuzz Queries

    @Test("Adversarial search queries execute swiftly without ReDoS or regex crash")
    func searchReDoSAndFuzzQueriesStress() {
        let corpus = [
            makeBookmark(id: "1", text: "aaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            makeBookmark(id: "2", text: "abc 123 !@#$%^&*()_+"),
            makeBookmark(id: "3", text: "The quick brown fox jumps over the lazy dog"),
            makeBookmark(id: "4", text: "http://example.com/api/v1/search?q=test")
        ]

        let evilQueries = [
            "(a+)+$",
            "a?b?c?d?e?f?g?",
            ".*.*.*.*.*.*.*.*.*a",
            "[[[[[[[[[[",
            "((((((((((",
            "\\\\\\\\\\\\",
            "?*+^${}()|[]",
            "\u{0000}",
            "<script>alert(1)</script>",
            "' OR '1'='1' --",
            String(repeating: "x", count: 10_000)
        ]

        for query in evilQueries {
            let start = Date()
            let results = MacDeskLibrary.visible(corpus, scope: .library, query: query)
            let elapsed = Date().timeIntervalSince(start)
            #expect(elapsed < 0.1, "Query '\(query.prefix(20))' took too long: \(elapsed)s (possible ReDoS)")
            let _ = results
        }
    }

    // MARK: - 4. Space Ordering & Tie-Breaker Stress

    @Test("1,000 spaces maintain pinned > sortIndex > name > id invariant")
    func extremeSpaceSortingAndTieBreakerStress() {
        var spaces: [Space] = []
        spaces.reserveCapacity(1_000)

        for i in 0..<1_000 {
            let isPinned = (i % 5 == 0)
            let sortIndex = (i % 3 == 0) ? -50 : (i % 7) // mixed negative and duplicate indices
            let name = (i % 2 == 0) ? "Archive" : "Research Space \(i)"
            spaces.append(makeSpace(
                id: String(format: "sp_%04d", i),
                name: name,
                pinned: isPinned,
                sort: sortIndex
            ))
        }

        let ordered = MacDeskLibrary.orderedSpaces(spaces)
        #expect(ordered.count == 1_000)

        // Verify invariant
        var seenUnpinned = false
        for idx in 0..<(ordered.count - 1) {
            let a = ordered[idx]
            let b = ordered[idx + 1]

            if !a.isPinned { seenUnpinned = true }
            if seenUnpinned {
                #expect(!b.isPinned, "Pinned space appeared after unpinned space at index \(idx + 1)")
            }

            if a.isPinned == b.isPinned {
                if a.sortIndex != b.sortIndex {
                    #expect(a.sortIndex < b.sortIndex, "SortIndex order violation: \(a.sortIndex) vs \(b.sortIndex)")
                } else {
                    let nameOrder = a.name.localizedCaseInsensitiveCompare(b.name)
                    if nameOrder == .orderedSame {
                        #expect(a.id < b.id, "ID tie-break violation: \(a.id) vs \(b.id)")
                    } else {
                        #expect(nameOrder == .orderedAscending, "Name order violation: \(a.name) vs \(b.name)")
                    }
                }
            }
        }
    }

    // MARK: - 5. BibTeX Citation Hardening

    @Test("BibTeX generation handles LaTeX specials, weird characters, and missing metadata")
    func bibtexCitationAdversarialEscapesStress() {
        // Special LaTeX characters: { } \ % & $ # _ ^ ~
        let weirdBookmark = makeBookmark(
            id: "weird/id:123@#$%",
            text: "Article body with LaTeX % & $ # _ { } ~ ^ \\ characters",
            createdAt: 1_700_000_000_000,
            title: "Exploring {Special} & % Characters: $E=mc^2$",
            url: "https://example.com/paper?id=1&name=test#section",
            authorName: "Dr. Jane Doe, Jr.",
            authorUsername: "janedoe"
        )

        guard let citation = MacDeskLibrary.bibtexCitation(weirdBookmark) else {
            Issue.record("Expected bibtex citation to be generated")
            return
        }

        #expect(citation.contains("@misc{") || citation.contains("@article{"))
        #expect(citation.contains("weirdid123") || citation.contains("weird_id_123") || citation.contains("curio_item"))
        #expect(citation.contains("https://example.com/paper"))

        // Bookmark without URL or source link yields nil
        let noUrlBookmark = makeBookmark(id: "plain", text: "Plain thought without links")
        #expect(MacDeskLibrary.bibtexCitation(noUrlBookmark) == nil)

        // Bookmark with empty ID falls back cleanly to a valid key
        let emptyIdBookmark = makeBookmark(id: "", text: "empty id", url: "https://example.com")
        let fallbackCitation = MacDeskLibrary.bibtexCitation(emptyIdBookmark)
        #expect(fallbackCitation?.contains("@misc{curio_item") == true)
    }

    // MARK: - 6. Socket Flooding & Slot Exhaustion

    @Test("Agent socket survives high-concurrency burst and slot exhaustion without crashing")
    func agentSocketFloodingAndSlotExhaustionStress() async throws {
        let root = URL(fileURLWithPath: "/tmp/curio-flood-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sock = root.appendingPathComponent("agent.sock")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = FakeStressLibrary()
        let api = LibraryAgentAPI(
            library: library,
            synthesizer: ScriptedStressSynthesizer(),
            privateContextBudget: 1_500
        )
        let listener = AgentSocketListener(
            api: api,
            socketURL: sock,
            accessEnabled: { true },
            token: { "flood-token" }
        )
        #expect(listener.start() == true)
        defer { listener.stop() }

        // Blast 36 concurrent connections (AgentSocketListener.maxInFlight is 32)
        let totalClients = 36
        let results = await withTaskGroup(of: String.self) { group in
            for i in 0..<totalClients {
                // Blocking client I/O runs on its own thread, as a separate process would.
                group.addTask { await ListenerRig.onThread {
                    let fd = AgentSocketIO.openClient(at: sock)
                    guard fd >= 0 else { return "refused" }
                    defer { close(fd) }

                    // Set 1-second timeout so tests never deadlock on cooperative pool
                    var tv = timeval(tv_sec: 1, tv_usec: 0)
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                    if i % 4 == 0 {
                        // Immediate close without data
                        return "closed_immediately"
                    } else if i % 4 == 1 {
                        // Malformed non-JSON data
                        let _ = AgentSocketIO.writeLine("MALFORMED_GARBAGE_\(i)", fd: fd)
                        let resp = AgentSocketIO.readLine(fd: fd)
                        return (resp?.contains("malformed") == true) ? "malformed_handled" : "other"
                    } else if i % 4 == 2 {
                        // Bad token
                        let req = AgentLine.request(token: "wrong-token", tool: "ping", argumentsJSON: "{}")
                        let _ = AgentSocketIO.writeLine(req, fd: fd)
                        let resp = AgentSocketIO.readLine(fd: fd)
                        return (resp?.contains("bad_token") == true) ? "bad_token_handled" : "other"
                    } else {
                        // Valid request
                        let req = AgentLine.request(token: "flood-token", tool: "search_bookmarks", argumentsJSON: "{\"query\":\"test\"}")
                        let _ = AgentSocketIO.writeLine(req, fd: fd)
                        let resp = AgentSocketIO.readLine(fd: fd)
                        return (resp?.contains("ok") == true) ? "valid_handled" : "other"
                    }
                } }
            }

            var outcomes: [String] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }

        #expect(results.count == totalClients)

        // Give the listener a moment to finalize in-flight handlers and release slots
        try? await Task.sleep(for: .milliseconds(150))

        // After the flood finishes, verify listener is completely responsive and healthy
        let verifyFd = AgentSocketIO.openClient(at: sock)
        #expect(verifyFd >= 0)
        defer { close(verifyFd) }
        var verifyTv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(verifyFd, SOL_SOCKET, SO_RCVTIMEO, &verifyTv, socklen_t(MemoryLayout<timeval>.size))
        let validReq = AgentLine.request(token: "flood-token", tool: "search_bookmarks", argumentsJSON: "{\"query\":\"test\"}")
        #expect(AgentSocketIO.writeLine(validReq, fd: verifyFd))
        let verifyResp = AgentSocketIO.readLine(fd: verifyFd)
        #expect(verifyResp?.contains("\"ok\":true") == true)
    }

    // MARK: - 7. Concurrent SwiftData Mutation

    @Test("Concurrent async operations on BookmarkStore execute safely without corruption")
    func concurrentSwiftDataMutationStress() async throws {
        let schema = Schema([BookmarkModel.self, SpaceModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let store = BookmarkStore(modelContainer: container)

        let iterations = 30
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let bm = Bookmark(
                        id: "async_\(i)",
                        text: "Concurrent bookmark content \(i)",
                        createdAt: Int64(i * 10),
                        userId: "stress-user"
                    )
                    await store.insertBookmarks([bm])
                    await store.updateFavorite(id: "async_\(i)", isFavorite: (i % 2 == 0))
                    await store.updateSavedForLater(id: "async_\(i)", isSavedForLater: (i % 3 == 0))
                    await store.updateNotes(id: "async_\(i)", notes: "Note \(i)")
                    _ = await store.getBookmarkById(id: "async_\(i)")
                }
            }
        }

        let all = await store.getAllBookmarksDirect()
        #expect(all.count == iterations)
    }
}

// MARK: - Test Doubles for Socket Stress

private final class FakeStressLibrary: AgentLibrary, @unchecked Sendable {
    func currentUserId() async -> String? { "stress-user" }
    func allBookmarks(userId: String) async -> [Bookmark] { [] }
    func bookmark(id: String) async -> Bookmark? { nil }
    func embeddings(userId: String) async -> [(String, Data)] { [] }
    func embedQuery(_ query: String) async -> [Float]? { [1, 0] }
    var embeddingModelInstalled: Bool { true }
    func spaces(userId: String) async -> [Space] { [] }
    func writesAllowed() async -> Bool { false }
    func xaiConfigured() async -> Bool { false }
    func secrets() async -> [String] { [] }
    func addBookmark(userId: String, text: String) async throws -> Bookmark {
        Bookmark(id: "new", text: text, createdAt: 0, userId: userId)
    }
    func updateNotes(id: String, notes: String?) async {}
    func setFavorite(id: String, isFavorite: Bool) async {}
    func assignToSpace(ids: [String], spaceId: String?) async {}
    func saveResearch(_ card: ResearchCard) async throws {}
    func researchCard(id: String) async -> ResearchCard? { nil }
}

private struct ScriptedStressSynthesizer: ResearchSynthesizer {
    func brief(question: String, bookmarks: [Bookmark], privateMode: Bool, sources: [String]) async -> AgentToolResult {
        .success("{\"answer\":\"done\"}", tier: "desk")
    }
}
