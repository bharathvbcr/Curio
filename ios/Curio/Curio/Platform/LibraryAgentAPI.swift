import Foundation

struct ResearchBrief: Sendable, Equatable, Codable {
    var answer: String
    var claimBookmarkIds: [String]
    var caveats: String
    var readingList: [String]
    var citationURLs: [String]
    var tier: String
}

struct ResearchCard: Sendable, Equatable, Codable {
    var id: String
    var question: String
    var brief: ResearchBrief
    var createdAt: Int64
}

/// Decisions that do not need the database. Tests lock these so a missing embedding index cannot
/// come back as "the 15 newest bookmarks".
enum AgentLookup {
    static func clampLimit(_ limit: Int) -> Int { min(max(limit, 1), 50) }

    static func contains(_ field: String?, _ query: String) -> Bool {
        guard let field, !query.isEmpty else { return false }
        return field.range(of: query, options: [.caseInsensitive]) != nil
    }

    /// Four fields `BookmarkStore.search` already scans, plus tags and notes.
    static func keywordMatches(_ bookmark: Bookmark, query: String) -> Bool {
        if query.isEmpty { return true }
        if contains(bookmark.text, query) || contains(bookmark.title, query)
            || contains(bookmark.summary, query) || contains(bookmark.ocrText, query)
            || contains(bookmark.notes, query) {
            return true
        }
        return bookmark.tags.contains { contains($0, query) }
    }

    static func keywordHits(_ bookmarks: [Bookmark], query: String, limit: Int) -> [Bookmark] {
        let cap = clampLimit(limit)
        return Array(bookmarks.filter { keywordMatches($0, query: query) }.prefix(cap))
    }

    /// `nil` means the search may rank. A failure means the caller must not substitute recency.
    static func semanticGate(modelInstalled: Bool, storedCount: Int, queryEmbedded: Bool) -> AgentFailure? {
        if !modelInstalled || !queryEmbedded { return .embeddingModelMissing }
        if storedCount == 0 { return .indexEmpty }
        return nil
    }

    static func unknownCitations(claimIds: [String], allowed: Set<String>) -> [String] {
        claimIds.filter { !allowed.contains($0) }
    }

    static func tokenEstimate(_ bookmarks: [Bookmark]) -> Int {
        bookmarks.reduce(0) { partial, bookmark in
            let body = bookmark.text.count + (bookmark.summary?.count ?? 0) + (bookmark.deepSummary?.count ?? 0)
            return partial + max(1, body / 4)
        }
    }

    static func citationURL(_ bookmark: Bookmark) -> String? {
        switch bookmark.sourceType {
        case .ARXIV: return "https://arxiv.org/abs/\(bookmark.sourceId ?? "null")"
        case .GITHUB: return "https://github.com/\(bookmark.sourceId ?? "null")"
        case .HUGGING_FACE: return "https://huggingface.co/\(bookmark.sourceId ?? "null")"
        case .DOI: return "https://doi.org/\(bookmark.sourceId ?? "null")"
        case .TWEET, nil: return bookmark.url
        }
    }
}

protocol ResearchSynthesizer: Sendable {
    func brief(question: String, bookmarks: [Bookmark], privateMode: Bool) async -> AgentToolResult
}

protocol AgentLibrary: Sendable {
    func currentUserId() async -> String?
    func allBookmarks(userId: String) async -> [Bookmark]
    func bookmark(id: String) async -> Bookmark?
    func embeddings(userId: String) async -> [(String, Data)]
    func embedQuery(_ query: String) async -> [Float]?
    var embeddingModelInstalled: Bool { get }
    func spaces(userId: String) async -> [Space]
    func writesAllowed() async -> Bool
    func xaiConfigured() async -> Bool
    func secrets() async -> [String]
    func addBookmark(userId: String, text: String) async throws -> Bookmark
    func updateNotes(id: String, notes: String?) async
    func setFavorite(id: String, isFavorite: Bool) async
    func assignToSpace(ids: [String], spaceId: String?) async
    func saveResearch(_ card: ResearchCard) async throws
    func researchCard(id: String) async -> ResearchCard?
}

struct LibraryAgentAPI: Sendable {
    var library: any AgentLibrary
    var synthesizer: any ResearchSynthesizer
    var privateContextBudget: Int

    func call(tool: String, argumentsJSON: String) async -> String {
        let args = AgentArguments(json: argumentsJSON)
        let result = await dispatch(tool: tool, args: args)
        let redacted = AgentToolResult(
            ok: result.ok,
            code: result.code,
            payload: AgentRedactor.redact(result.payload, secrets: await library.secrets()),
            tier: result.tier
        )
        return redacted.jsonText()
    }

    private func dispatch(tool: String, args: AgentArguments) async -> AgentToolResult {
        switch tool {
        case "search_bookmarks":
            return await search(query: args.string("query") ?? "", limit: args.int("limit") ?? 10)
        case "semantic_search":
            return await semantic(query: args.string("query") ?? "", limit: args.int("limit") ?? 10, anchorId: nil)
        case "related_bookmarks":
            guard let id = args.string("id") else { return .failure(.unknownTool, payload: "id required") }
            return await semantic(query: "", limit: args.int("limit") ?? 10, anchorId: id)
        case "get_bookmark":
            return await getBookmark(id: args.string("id") ?? "")
        case "list_spaces":
            return await listSpaces()
        case "list_space_bookmarks":
            return await listSpace(id: args.string("spaceId") ?? args.string("id") ?? "")
        case "reading_queue":
            return await readingQueue(limit: args.int("limit") ?? 20)
        case "library_overview":
            return await overview()
        case "export_citations":
            return await export(ids: args.strings("ids"), format: args.string("format") ?? "bibtex")
        case "research_topic":
            return await research(
                question: args.string("question") ?? args.string("query") ?? "",
                privateMode: args.bool("private") ?? true,
                sources: args.strings("sources"),
                limit: args.int("limit") ?? 8
            )
        case "save_bookmark":
            return await saveBookmark(text: args.string("text") ?? "")
        case "add_note":
            return await addNote(id: args.string("id") ?? "", note: args.string("note") ?? "")
        case "set_favorite":
            return await setFavorite(id: args.string("id") ?? "", favorite: args.bool("favorite") ?? true)
        case "file_in_space":
            return await file(ids: args.strings("ids"), spaceId: args.string("spaceId"))
        case "save_research":
            return await saveResearch(question: args.string("question") ?? "", answer: args.string("answer") ?? "", ids: args.strings("ids"))
        case "read_resource":
            return await readResource(uri: args.string("uri") ?? "")
        default:
            return .failure(.unknownTool, payload: tool)
        }
    }

    func search(query: String, limit: Int) async -> AgentToolResult {
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        let all = await library.allBookmarks(userId: userId)
        let hits = AgentLookup.keywordHits(all, query: query, limit: limit)
        return .success(AgentJSON.bookmarks(hits))
    }

    func semantic(query: String, limit: Int, anchorId: String?) async -> AgentToolResult {
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        guard library.embeddingModelInstalled else { return .failure(.embeddingModelMissing) }
        let stored = await library.embeddings(userId: userId)
        if stored.isEmpty { return .failure(.indexEmpty) }
        let queryVector: [Float]?
        if let anchorId {
            queryVector = stored.first { $0.0 == anchorId }.map { VectorSearch.dataToFloatArray($0.1) }
        } else {
            queryVector = await library.embedQuery(query)
        }
        guard let queryVector else { return .failure(.embeddingModelMissing) }
        let candidates = stored.map { ($0.0, VectorSearch.dataToFloatArray($0.1)) }
        let cap = AgentLookup.clampLimit(limit)
        let ranked = VectorSearch.topK(query: queryVector, candidates: candidates, k: cap + (anchorId == nil ? 0 : 1))
            .filter { $0 != anchorId }
        let byId = Dictionary(uniqueKeysWithValues: (await library.allBookmarks(userId: userId)).map { ($0.id, $0) })
        let hits = ranked.prefix(cap).compactMap { byId[$0] }
        return .success(AgentJSON.bookmarks(hits))
    }

    func research(question: String, privateMode: Bool, sources: [String], limit: Int) async -> AgentToolResult {
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        let live = sources.filter { $0 != "library" && $0 != "LIBRARY" }
        if privateMode && !live.isEmpty { return .failure(.privateMode) }
        let retrieved = await semantic(query: question, limit: limit, anchorId: nil)
        if !retrieved.ok { return retrieved }
        let all = await library.allBookmarks(userId: userId)
        let allowedIds = Set(AgentJSON.ids(in: retrieved.payload))
        let bookmarks = all.filter { allowedIds.contains($0.id) }
        if privateMode && AgentLookup.tokenEstimate(bookmarks) > privateContextBudget {
            return .failure(.contextExceeded, payload: AgentJSON.ids(bookmarks.map(\.id)))
        }
        if !privateMode {
            let configured = await library.xaiConfigured()
            if !configured { return .failure(.keyMissing) }
        }
        let synthesized = await synthesizer.brief(question: question, bookmarks: bookmarks, privateMode: privateMode)
        guard synthesized.ok, let brief = ResearchBrief(json: synthesized.payload) else { return synthesized }
        let unknown = AgentLookup.unknownCitations(claimIds: brief.claimBookmarkIds, allowed: allowedIds)
        if !unknown.isEmpty {
            return .failure(.citationRejected, payload: AgentJSON.ids(unknown))
        }
        return .success(brief.jsonText(), tier: brief.tier)
    }

    private func getBookmark(id: String) async -> AgentToolResult {
        guard await library.currentUserId() != nil else { return .failure(.notSignedIn) }
        guard let bookmark = await library.bookmark(id: id) else { return .failure(.unknownTool, payload: "not_found") }
        return .success(AgentJSON.bookmark(bookmark))
    }

    private func listSpaces() async -> AgentToolResult {
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        let spaces = await library.spaces(userId: userId)
        let payload = spaces.map { ["id": $0.id, "name": $0.name, "count": $0.count, "pinned": $0.isPinned] as [String: Any] }
        return .success(AgentJSON.objectList(payload))
    }

    private func listSpace(id: String) async -> AgentToolResult {
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        let hits = await library.allBookmarks(userId: userId).filter { $0.spaceId == id }
        return .success(AgentJSON.bookmarks(hits))
    }

    private func readingQueue(limit: Int) async -> AgentToolResult {
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        let all = await library.allBookmarks(userId: userId)
        let queued = all.filter(\.isSavedForLater) + all.filter { $0.isFavorite && !$0.isSavedForLater }
        return .success(AgentJSON.bookmarks(Array(queued.prefix(AgentLookup.clampLimit(limit)))))
    }

    private func overview() async -> AgentToolResult {
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        let all = await library.allBookmarks(userId: userId)
        let embedded = await library.embeddings(userId: userId).count
        let payload: [String: Any] = [
            "bookmarks": all.count,
            "favorites": all.filter(\.isFavorite).count,
            "savedForLater": all.filter(\.isSavedForLater).count,
            "unenriched": all.filter { !$0.isAnalyzed || ($0.summary ?? "").isEmpty }.count,
            "embeddings": embedded,
            "embeddingModelInstalled": library.embeddingModelInstalled
        ]
        return .success(AgentJSON.object(payload))
    }

    private func export(ids: [String], format: String) async -> AgentToolResult {
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        let all = await library.allBookmarks(userId: userId)
        let selected = ids.isEmpty ? all : all.filter { ids.contains($0.id) }
        let text: String
        switch format.lowercased() {
        case "ris": text = BibtexExporter.toRisList(selected)
        case "csl", "csl-json": text = BibtexExporter.toCslJsonList(selected)
        case "markdown", "md": text = BibtexExporter.toMarkdownList(selected)
        default: text = BibtexExporter.toBibtexList(selected)
        }
        return .success(text)
    }

    private func requireWrites() async -> AgentToolResult? {
        guard await library.currentUserId() != nil else { return .failure(.notSignedIn) }
        guard await library.writesAllowed() else { return .failure(.writesDisabled) }
        return nil
    }

    private func saveBookmark(text: String) async -> AgentToolResult {
        if let denied = await requireWrites() { return denied }
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        do {
            let saved = try await library.addBookmark(userId: userId, text: text)
            return .success(AgentJSON.bookmark(saved))
        } catch {
            return .failure(.unknownTool, payload: error.localizedDescription)
        }
    }

    private func addNote(id: String, note: String) async -> AgentToolResult {
        if let denied = await requireWrites() { return denied }
        await library.updateNotes(id: id, notes: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note)
        return .success(AgentJSON.object(["id": id]))
    }

    private func setFavorite(id: String, favorite: Bool) async -> AgentToolResult {
        if let denied = await requireWrites() { return denied }
        await library.setFavorite(id: id, isFavorite: favorite)
        return .success(AgentJSON.object(["id": id, "favorite": favorite]))
    }

    private func file(ids: [String], spaceId: String?) async -> AgentToolResult {
        if let denied = await requireWrites() { return denied }
        await library.assignToSpace(ids: ids, spaceId: spaceId)
        return .success(AgentJSON.object(["ids": ids]))
    }

    private func saveResearch(question: String, answer: String, ids: [String]) async -> AgentToolResult {
        if let denied = await requireWrites() { return denied }
        let brief = ResearchBrief(answer: answer, claimBookmarkIds: ids, caveats: "", readingList: [], citationURLs: [], tier: "saved")
        let card = ResearchCard(id: "research_\(UUID().uuidString)", question: question, brief: brief, createdAt: Int64(Date().timeIntervalSince1970 * 1000))
        do {
            try await library.saveResearch(card)
            return .success(card.jsonText())
        } catch {
            return .failure(.unknownTool, payload: error.localizedDescription)
        }
    }

    private func readResource(uri: String) async -> AgentToolResult {
        if uri == "curio://library/recent" { return await search(query: "", limit: 20) }
        if uri.hasPrefix("curio://bookmark/") {
            return await getBookmark(id: String(uri.dropFirst("curio://bookmark/".count)))
        }
        if uri.hasPrefix("curio://space/") {
            return await listSpace(id: String(uri.dropFirst("curio://space/".count)))
        }
        if uri.hasPrefix("curio://research/") {
            let id = String(uri.dropFirst("curio://research/".count))
            guard let card = await library.researchCard(id: id) else { return .failure(.unknownTool, payload: "not_found") }
            return .success(card.jsonText())
        }
        return .failure(.unknownTool, payload: uri)
    }
}

extension ResearchBrief {
    func jsonText() -> String {
        let object: [String: Any] = [
            "answer": answer,
            "claimBookmarkIds": claimBookmarkIds,
            "caveats": caveats,
            "readingList": readingList,
            "citationURLs": citationURLs,
            "tier": tier
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answer = object["answer"] as? String else { return nil }
        self.answer = answer
        self.claimBookmarkIds = object["claimBookmarkIds"] as? [String] ?? []
        self.caveats = object["caveats"] as? String ?? ""
        self.readingList = object["readingList"] as? [String] ?? []
        self.citationURLs = object["citationURLs"] as? [String] ?? []
        self.tier = object["tier"] as? String ?? ""
    }
}

extension ResearchCard {
    func jsonText() -> String {
        guard let data = try? JSONEncoder().encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

private struct AgentArguments {
    let object: [String: Any]
    init(json: String) {
        let data = json.data(using: .utf8) ?? Data()
        object = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
    func string(_ key: String) -> String? { object[key] as? String }
    func int(_ key: String) -> Int? {
        if let value = object[key] as? Int { return value }
        if let value = object[key] as? Double { return Int(value) }
        return nil
    }
    func bool(_ key: String) -> Bool? { object[key] as? Bool }
    func strings(_ key: String) -> [String] { object[key] as? [String] ?? [] }
}

private enum AgentJSON {
    static func bookmarks(_ bookmarks: [Bookmark]) -> String {
        objectList(bookmarks.map(fields))
    }

    static func bookmark(_ bookmark: Bookmark) -> String {
        object(fields(bookmark))
    }

    static func fields(_ bookmark: Bookmark) -> [String: Any] {
        [
            "id": bookmark.id,
            "title": bookmark.title ?? "",
            "text": String(bookmark.text.prefix(300)),
            "summary": bookmark.summary ?? "",
            "url": bookmark.url ?? "",
            "tags": bookmark.tags,
            "notes": bookmark.notes ?? "",
            "favorite": bookmark.isFavorite,
            "savedForLater": bookmark.isSavedForLater,
            "spaceId": bookmark.spaceId ?? "",
            "sourceType": bookmark.sourceType?.rawValue ?? "",
            "citation": AgentLookup.citationURL(bookmark) ?? ""
        ]
    }

    static func object(_ fields: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: fields),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    static func objectList(_ rows: [[String: Any]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: rows),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    static func ids(_ ids: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: ids),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    static func ids(in payload: String) -> [String] {
        guard let data = payload.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { $0["id"] as? String }
    }
}
