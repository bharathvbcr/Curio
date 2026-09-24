import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

actor ResearchCardFileStore {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save(_ card: ResearchCard) throws {
        let url = directory.appendingPathComponent("\(card.id).json")
        let data = try JSONEncoder().encode(card)
        try data.write(to: url, options: .atomic)
    }

    func load(id: String) -> ResearchCard? {
        let url = directory.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ResearchCard.self, from: data)
    }
}

struct CurioResearchSynthesizer: ResearchSynthesizer {
    let analyzer: XAiAnalyzer
    let availability: GenAiAvailability

    func brief(question: String, bookmarks: [Bookmark], privateMode: Bool) async -> AgentToolResult {
        if privateMode {
            return await privateBrief(question: question, bookmarks: bookmarks)
        }
        let parts = ChatPromptBuilder.build(
            userQuery: question,
            contextItems: bookmarks,
            useLibrary: true,
            liveSourceApiTypes: [],
            liveLabels: ""
        )
        let response = await analyzer.generateChatResponse(
            contextPrompt: parts.contextPrompt,
            systemInstruction: parts.systemInstruction,
            searchParameters: nil,
            reasoningEffort: nil
        )
        if response.text.hasPrefix("xAI API key is missing") {
            return .failure(.keyMissing)
        }
        let brief = ResearchBrief(
            answer: response.text,
            claimBookmarkIds: bookmarks.map(\.id),
            caveats: "",
            readingList: bookmarks.compactMap { $0.title ?? $0.sourceTitle },
            citationURLs: bookmarks.compactMap { AgentLookup.citationURL($0) },
            tier: "grok"
        )
        return .success(brief.jsonText(), tier: brief.tier)
    }

    private func privateBrief(question: String, bookmarks: [Bookmark]) async -> AgentToolResult {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *), availability.isNanoUsable() {
            let lines = bookmarks.map { bookmark in
                "- \(bookmark.id): \(bookmark.title ?? bookmark.sourceTitle ?? "Untitled") — \(bookmark.summary ?? String(bookmark.text.prefix(180)))"
            }.joined(separator: "\n")
            let instructions = """
            You are Curio's on-device research librarian. Answer only from the bookmarks listed. \
            Return a JSON object with keys answer, claimBookmarkIds, caveats, readingList. \
            claimBookmarkIds must be ids from the list. Do not invent ids.
            """
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(to: "Question: \(question)\n\nBookmarks:\n\(lines)")
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if var brief = ResearchBrief(json: Self.jsonObject(in: text)) {
                    brief.tier = "apple-intelligence"
                    brief.citationURLs = bookmarks.compactMap { AgentLookup.citationURL($0) }
                    return .success(brief.jsonText(), tier: brief.tier)
                }
                let brief = ResearchBrief(
                    answer: text,
                    claimBookmarkIds: bookmarks.map(\.id),
                    caveats: "",
                    readingList: [],
                    citationURLs: bookmarks.compactMap { AgentLookup.citationURL($0) },
                    tier: "apple-intelligence"
                )
                return .success(brief.jsonText(), tier: brief.tier)
            } catch {
                return .failure(.modelUnavailable, payload: error.localizedDescription)
            }
        }
        #endif
        return .failure(.modelUnavailable)
    }

    private static func jsonObject(in text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return text }
        return String(text[start...end])
    }
}

final class RepositoryAgentLibrary: AgentLibrary, @unchecked Sendable {
    private let repository: any BookmarkRepository
    private let spaceStore: SpaceStore
    private let embedder: any EmbeddingProvider
    let embeddingModelInstalled: Bool
    private let tokenStore: TokenStore
    private let keyConfigured: @Sendable () -> Bool
    private let writes: @Sendable () async -> Bool
    private let cards: ResearchCardFileStore

    init(
        repository: any BookmarkRepository,
        spaceStore: SpaceStore,
        embedder: any EmbeddingProvider,
        embeddingModelInstalled: Bool,
        tokenStore: TokenStore,
        keyConfigured: @escaping @Sendable () -> Bool,
        writes: @escaping @Sendable () async -> Bool,
        cards: ResearchCardFileStore
    ) {
        self.repository = repository
        self.spaceStore = spaceStore
        self.embedder = embedder
        self.embeddingModelInstalled = embeddingModelInstalled
        self.tokenStore = tokenStore
        self.keyConfigured = keyConfigured
        self.writes = writes
        self.cards = cards
    }

    func currentUserId() async -> String? { await tokenStore.getUserId() }

    func allBookmarks(userId: String) async -> [Bookmark] {
        await repository.searchBookmarks(userId: userId, query: "")
    }

    func bookmark(id: String) async -> Bookmark? { await repository.getBookmarkById(id: id) }

    func embeddings(userId: String) async -> [(String, Data)] {
        await repository.getBookmarksWithEmbeddings(userId: userId)
    }

    func embedQuery(_ query: String) async -> [Float]? { await embedder.embedQuery(query) }

    func spaces(userId: String) async -> [Space] { await spaceStore.getSpaces(userId: userId) }

    func writesAllowed() async -> Bool { await writes() }

    func xaiConfigured() async -> Bool { keyConfigured() }

    func secrets() async -> [String] {
        var values: [String] = []
        if let key = await tokenStore.getXaiKey(), !key.isEmpty { values.append(key) }
        if let token = await tokenStore.getHuggingFaceToken(), !token.isEmpty { values.append(token) }
        return values
    }

    func addBookmark(userId: String, text: String) async throws -> Bookmark {
        try await repository.addBookmark(userId: userId, text: text)
    }

    func updateNotes(id: String, notes: String?) async {
        await repository.updateNotes(id: id, notes: notes)
    }

    func setFavorite(id: String, isFavorite: Bool) async {
        await repository.setFavorite(id: id, isFavorite: isFavorite)
    }

    func assignToSpace(ids: [String], spaceId: String?) async {
        await repository.assignToSpace(ids: ids, spaceId: spaceId)
    }

    func saveResearch(_ card: ResearchCard) async throws { try await cards.save(card) }

    func researchCard(id: String) async -> ResearchCard? { await cards.load(id: id) }
}
