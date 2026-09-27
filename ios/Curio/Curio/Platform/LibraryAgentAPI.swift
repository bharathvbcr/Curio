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

    /// Trimmed, non-empty, first occurrence wins.
    static func distinctIds(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in ids {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty || seen.contains(id) { continue }
            seen.insert(id)
            result.append(id)
        }
        return result
    }

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

    /// Sources other than the on-device library. `"library"` is grounding, not an xAI live source.
    static func liveSources(_ sources: [String]) -> [String] {
        sources.filter { source in
            let name = source.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty && name.caseInsensitiveCompare("library") != .orderedSame
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
    func brief(question: String, bookmarks: [Bookmark], privateMode: Bool, sources: [String]) async -> AgentToolResult
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
    func setSavedForLater(id: String, isSavedForLater: Bool) async
    func saveResearch(_ card: ResearchCard) async throws
    func researchCard(id: String) async -> ResearchCard?
}

extension AgentLibrary {
    /// Libraries that predate Read Later for agents keep compiling; the tool then changes nothing.
    func setSavedForLater(id: String, isSavedForLater: Bool) async {}
}

/// Bounds on what an agent can write in one call.
enum AgentLimits {
    static let maxBookmarkCharacters = 100_000
    static let maxNoteCharacters = 20_000
    static let maxIdsPerCall = 500
    static let maxQuestionCharacters = 4_000
}

struct LibraryAgentAPI: Sendable {
    var library: any AgentLibrary
    var synthesizer: any ResearchSynthesizer
    var privateContextBudget: Int
    var liveAllowed: @Sendable () -> Bool

    init(
        library: any AgentLibrary,
        synthesizer: any ResearchSynthesizer,
        privateContextBudget: Int,
        liveAllowed: @escaping @Sendable () -> Bool = LibraryAgentAPI.platformLiveAllowed
    ) {
        self.library = library
        self.synthesizer = synthesizer
        self.privateContextBudget = privateContextBudget
        self.liveAllowed = liveAllowed
    }

    /// Mac live research is a user switch. Other platforms leave the caller's `privateMode` in charge.
    static func platformLiveAllowed() -> Bool {
        #if os(macOS)
        MacAgentPreferences.liveResearchAllowed()
        #else
        true
        #endif
    }

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
        case "set_read_later":
            return await setReadLater(id: args.string("id") ?? "", later: args.bool("later") ?? args.bool("readLater") ?? true)
        case "file_in_space":
            return await file(ids: args.strings("ids"), spaceId: args.string("spaceId"))
        case "save_research":
            return await saveResearch(question: args.string("question") ?? "", answer: args.string("answer") ?? "", ids: args.strings("ids"))
        case "read_resource":
            return await readResource(uri: args.string("uri") ?? "")
        case "get_prompt":
            return prompt(name: args.string("name") ?? args.string("uri") ?? "", arguments: args)
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
        let live = AgentLookup.liveSources(sources)
        if privateMode && !live.isEmpty { return .failure(.privateMode) }
        let wantsLive = !privateMode || !live.isEmpty
        if wantsLive && !liveAllowed() {
            return .failure(.privateMode, payload: "live_research_disabled")
        }
        let retrieved = await semantic(query: question, limit: limit, anchorId: nil)
        let bookmarks: [Bookmark]
        let allowedIds: Set<String>
        if retrieved.ok {
            let all = await library.allBookmarks(userId: userId)
            allowedIds = Set(AgentJSON.ids(in: retrieved.payload))
            bookmarks = all.filter { allowedIds.contains($0.id) }
            if privateMode && AgentLookup.tokenEstimate(bookmarks) > privateContextBudget {
                return .failure(.contextExceeded, payload: AgentJSON.ids(bookmarks.map(\.id)))
            }
        } else if privateMode || live.isEmpty {
            return retrieved
        } else {
            bookmarks = []
            allowedIds = []
        }
        if !privateMode {
            let configured = await library.xaiConfigured()
            if !configured { return .failure(.keyMissing) }
        }
        let synthesized = await synthesizer.brief(question: question, bookmarks: bookmarks, privateMode: privateMode, sources: live)
        guard synthesized.ok, let brief = ResearchBrief(json: synthesized.payload) else { return synthesized }
        let unknown = AgentLookup.unknownCitations(claimIds: brief.claimBookmarkIds, allowed: allowedIds)
        if !unknown.isEmpty {
            return .failure(.citationRejected, payload: AgentJSON.ids(unknown))
        }
        return .success(brief.jsonText(), tier: brief.tier)
    }

    private func getBookmark(id: String) async -> AgentToolResult {
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        guard let bookmark = await ownedBookmark(id: id, userId: userId) else { return .failure(.notFound, payload: "not_found") }
        return .success(AgentJSON.bookmark(bookmark))
    }

    /// A bookmark this signed-in user owns. Another account's rows on the same device are invisible.
    private func ownedBookmark(id: String, userId: String) async -> Bookmark? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let bookmark = await library.bookmark(id: trimmed), bookmark.userId == userId else { return nil }
        return bookmark
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.invalidArguments, payload: "text is empty") }
        guard trimmed.count <= AgentLimits.maxBookmarkCharacters else {
            return .failure(.invalidArguments, payload: "text is longer than \(AgentLimits.maxBookmarkCharacters) characters")
        }
        let text = trimmed
        do {
            let saved = try await library.addBookmark(userId: userId, text: text)
            return .success(AgentJSON.bookmark(saved))
        } catch {
            return .failure(.unknownTool, payload: error.localizedDescription)
        }
    }

    private func addNote(id: String, note: String) async -> AgentToolResult {
        if let denied = await requireWrites() { return denied }
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        guard let bookmark = await ownedBookmark(id: id, userId: userId) else { return .failure(.notFound, payload: "not_found") }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= AgentLimits.maxNoteCharacters else {
            return .failure(.invalidArguments, payload: "note is longer than \(AgentLimits.maxNoteCharacters) characters")
        }
        await library.updateNotes(id: bookmark.id, notes: trimmed.isEmpty ? nil : trimmed)
        return .success(AgentJSON.object(["id": bookmark.id]))
    }

    private func setFavorite(id: String, favorite: Bool) async -> AgentToolResult {
        if let denied = await requireWrites() { return denied }
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        guard let bookmark = await ownedBookmark(id: id, userId: userId) else { return .failure(.notFound, payload: "not_found") }
        await library.setFavorite(id: bookmark.id, isFavorite: favorite)
        return .success(AgentJSON.object(["id": bookmark.id, "favorite": favorite]))
    }

    private func setReadLater(id: String, later: Bool) async -> AgentToolResult {
        if let denied = await requireWrites() { return denied }
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        guard let bookmark = await ownedBookmark(id: id, userId: userId) else { return .failure(.notFound, payload: "not_found") }
        await library.setSavedForLater(id: bookmark.id, isSavedForLater: later)
        return .success(AgentJSON.object(["id": bookmark.id, "later": later]))
    }

    /// Only this user's bookmarks, and only into a space that exists. A dangling space id would
    /// hide the bookmarks from every space and from Unfiled.
    private func file(ids: [String], spaceId: String?) async -> AgentToolResult {
        if let denied = await requireWrites() { return denied }
        guard let userId = await library.currentUserId() else { return .failure(.notSignedIn) }
        let wanted = AgentLookup.distinctIds(ids)
        guard !wanted.isEmpty else { return .failure(.invalidArguments, payload: "ids is empty") }
        guard wanted.count <= AgentLimits.maxIdsPerCall else {
            return .failure(.invalidArguments, payload: "at most \(AgentLimits.maxIdsPerCall) ids per call")
        }
        let target = spaceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let space = (target?.isEmpty ?? true) ? nil : target
        if let space {
            let known = await library.spaces(userId: userId).contains { $0.id == space }
            guard known else { return .failure(.notFound, payload: "space_not_found") }
        }
        let owned = Set(await library.allBookmarks(userId: userId).map(\.id))
        let filed = wanted.filter { owned.contains($0) }
        let missing = wanted.filter { !owned.contains($0) }
        guard !filed.isEmpty else { return .failure(.notFound, payload: AgentJSON.ids(missing)) }
        await library.assignToSpace(ids: filed, spaceId: space)
        var result: [String: Any] = ["ids": filed, "spaceId": space ?? ""]
        if !missing.isEmpty { result["missing"] = missing }
        return .success(AgentJSON.object(result))
    }

    private func saveResearch(question: String, answer: String, ids: [String]) async -> AgentToolResult {
        if let denied = await requireWrites() { return denied }
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidArguments, payload: "answer is empty")
        }
        guard question.count <= AgentLimits.maxQuestionCharacters, answer.count <= AgentLimits.maxBookmarkCharacters else {
            return .failure(.invalidArguments, payload: "question or answer is too long")
        }
        let brief = ResearchBrief(answer: answer, claimBookmarkIds: ids, caveats: "", readingList: [], citationURLs: [], tier: "saved")
        let card = ResearchCard(id: "research_\(UUID().uuidString)", question: question, brief: brief, createdAt: Int64(Date().timeIntervalSince1970 * 1000))
        do {
            try await library.saveResearch(card)
            return .success(card.jsonText())
        } catch {
            return .failure(.unknownTool, payload: error.localizedDescription)
        }
    }

    private func prompt(name: String, arguments: AgentArguments) -> AgentToolResult {
        let subject = arguments.string("topic")
            ?? arguments.string("question")
            ?? arguments.childString("topic")
            ?? arguments.childString("question")
            ?? ""
        let focus = subject.isEmpty ? "" : " on \(subject)"
        let text: String
        switch name {
        case "research-brief":
            text = "Ask Curio for a grounded research brief\(focus). Call research_topic. Stay in private mode unless live research is enabled."
        case "compare-sources":
            text = "Compare the bookmarks the user names\(focus). Load each one with get_bookmark and cite only those ids."
        case "reading-queue":
            text = "Summarize the reading queue returned by reading_queue. Do not add items that the tool did not return."
        default:
            return .failure(.unknownTool, payload: name)
        }
        return .success(text)
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
            guard let card = await library.researchCard(id: id) else { return .failure(.notFound, payload: "not_found") }
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
    /// Whole numbers only. A fraction, NaN, or a value past Int's range (1e300) is nil
    /// rather than a trap.
    func int(_ key: String) -> Int? {
        guard let number = object[key] as? NSNumber, !AgentArguments.isBool(number) else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value.rounded() == value,
              value >= -9_007_199_254_740_992, value <= 9_007_199_254_740_992 else { return nil }
        return Int(value)
    }
    func bool(_ key: String) -> Bool? {
        guard let number = object[key] as? NSNumber, AgentArguments.isBool(number) else { return nil }
        return number.boolValue
    }
    static func isBool(_ number: NSNumber) -> Bool {
        String(cString: number.objCType) == "c"
    }
    func strings(_ key: String) -> [String] {
        if let many = object[key] as? [Any] { return many.compactMap { $0 as? String } }
        if let one = object[key] as? String { return [one] }
        return []
    }
    func childString(_ key: String) -> String? {
        guard let child = object["arguments"] as? [String: Any] else { return nil }
        return child[key] as? String
    }
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
