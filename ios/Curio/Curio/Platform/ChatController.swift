import Foundation
import Observation
import os

/// Owns the Research Assistant chat: message list, loading state, selected grounding sources, and the
/// RAG retrieval + Live Search send path. Ported 1:1 from `ui/ChatController.kt`.
///
/// Extracted from `BookmarkViewModel` to keep its chat API independent of the feed's filtering graph.
/// `rawBookmarks` / `currentUserId` are suppliers reading the VM's live state, so the controller stays
/// a thin collaborator rather than duplicating ownership of the library.
///
/// CONVENTIONS §4: `@MainActor @Observable final class`; `scope.launch` → `Task`; `UUID().uuidString`
/// for message ids; cancellation rethrown, never swallowed.
@MainActor
@Observable
final class ChatController {

    // MARK: - Injected dependencies

    @ObservationIgnored private let aiAnalyzer: XAiAnalyzer
    @ObservationIgnored private let embeddingService: EmbeddingProvider
    @ObservationIgnored private let repository: BookmarkRepository
    @ObservationIgnored private let semanticLayer: OnDeviceSemanticLayer
    @ObservationIgnored private let rawBookmarks: @MainActor () -> [Bookmark]
    @ObservationIgnored private let currentUserId: @MainActor () -> String?

    // MARK: - Published chat state

    private(set) var chatMessages: [ChatMessage] = []

    private(set) var isChatLoading: Bool = false

    /// Grounding sources the user has toggled on. `ChatSource.library` is on by default. Backed by an
    /// insertion-ordered set so live-source iteration order (labels / `groundedIn`) is deterministic,
    /// matching Kotlin's `LinkedHashSet` semantics for `setOf(...)`.
    private(set) var chatSources: OrderedChatSourceSet = OrderedChatSourceSet([.library])

    @ObservationIgnored private var sendTask: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.curio.app", category: "ChatController")

    init(
        aiAnalyzer: XAiAnalyzer,
        embeddingService: EmbeddingProvider,
        repository: BookmarkRepository,
        semanticLayer: OnDeviceSemanticLayer,
        rawBookmarks: @escaping @MainActor () -> [Bookmark],
        currentUserId: @escaping @MainActor () -> String?
    ) {
        self.aiAnalyzer = aiAnalyzer
        self.embeddingService = embeddingService
        self.repository = repository
        self.semanticLayer = semanticLayer
        self.rawBookmarks = rawBookmarks
        self.currentUserId = currentUserId
    }

    /// Toggles a grounding source. Removing the last source snaps back to `{library}` so the chat is
    /// never grounded in nothing. Port of `toggleSource` (`add ? keep : remove`, `ifEmpty { LIBRARY }`).
    func toggleSource(_ source: ChatSource) {
        var next = chatSources
        if next.contains(source) {
            next.remove(source)
        } else {
            next.insert(source)
        }
        chatSources = next.isEmpty ? OrderedChatSourceSet([.library]) : next
    }

    /// Resets the conversation back to the empty welcome state. Port of `clear()`.
    func clear() {
        chatMessages = []
        isChatLoading = false
    }

    /// Cancels the in-flight send, if any. On Android the send coroutine ran in `viewModelScope`
    /// and was cancelled structurally when the VM cleared; the owning VM's `close()` calls this to
    /// reproduce that teardown (otherwise the xAI request runs to completion after the screen dies).
    func close() {
        sendTask?.cancel()
        sendTask = nil
    }

    func send(_ textInput: String, includeUserMessage: Bool = true) {
        if textInput.isBlankChat { return }
        let sources = chatSources
        if includeUserMessage {
            let userMsg = ChatMessage(id: UUID().uuidString, sender: .user, text: textInput)
            chatMessages.append(userMsg)
        }
        isChatLoading = true
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                let uid = self.currentUserId()
                let useLibrary = sources.contains(.library)

                // Prompt + system-instruction + Live Search params are built in the data layer
                // (ChatPromptBuilder). ChatSource is a UI concept; map it to data-layer primitives.
                let liveApiTypes = sources.elements.compactMap { $0.apiType }
                let liveLabels = sources.elements
                    .filter { $0 != .library }
                    .map { $0.label }
                    .joined(separator: "/")

                let semanticEnabled = self.semanticLayer.isEnabled()
                // Only cache answers that don't depend on Live Search (those are time-sensitive).
                let cacheable = semanticEnabled && liveApiTypes.isEmpty

                // Embed the query once and reuse the vector for retrieval, cache, and compression.
                let needEmbedding = semanticEnabled || (useLibrary && uid != nil)
                let queryEmbedding = needEmbedding ? await self.embeddingService.embedQuery(textInput) : nil

                let scored: [(bookmark: Bookmark, embedding: [Float])]
                if useLibrary {
                    if let uid {
                        scored = await self.retrieveRagContextScored(queryEmbedding: queryEmbedding, userId: uid)
                    } else {
                        scored = Array(self.rawBookmarks().prefix(15)).map { ($0, []) }
                    }
                } else {
                    scored = []
                }

                // 1. Semantic cache lookup — serve a past answer and skip xAI entirely.
                if cacheable, let cached = await self.semanticLayer.lookup(query: textInput, queryEmbedding: queryEmbedding, userId: uid),
                   !cached.response.isEmpty {
                    Self.logger.debug("cache hit tier=\(cached.modelTier, privacy: .public)")
                    let libraryCitations = useLibrary ? scored.compactMap { self.citationUrl($0.bookmark) } : []
                    self.chatMessages.append(
                        ChatMessage(
                            id: UUID().uuidString,
                            sender: .ai,
                            text: cached.response,
                            citations: libraryCitations,
                            groundedIn: sources.elements,
                            semanticCacheEntryId: cached.entryId,
                            semanticSimilarity: cached.similarity > 0 ? cached.similarity : nil,
                            semanticCacheHit: true,
                            semanticModelTier: cached.modelTier
                        )
                    )
                    self.isChatLoading = false
                    return
                }

                // 2. Compress retrieved context (MMR) before building the prompt.
                let contextItems = semanticEnabled
                    ? self.semanticLayer.compress(queryEmbedding: queryEmbedding, scored: scored)
                    : scored.map { $0.bookmark }
                let libraryCitations = useLibrary ? contextItems.compactMap { self.citationUrl($0) } : []

                // 3. Route reasoning effort by query complexity.
                let route = semanticEnabled ? self.semanticLayer.route(textInput) : nil

                let parts = ChatPromptBuilder.build(
                    userQuery: textInput,
                    contextItems: contextItems,
                    useLibrary: useLibrary,
                    liveSourceApiTypes: liveApiTypes,
                    liveLabels: liveLabels
                )

                let aiResponse = await self.aiAnalyzer.generateChatResponse(
                    contextPrompt: parts.contextPrompt,
                    systemInstruction: parts.systemInstruction,
                    searchParameters: parts.searchParameters,
                    reasoningEffort: route?.reasoningEffort
                )

                // 4. Write-through store (cacheable answers only).
                let cacheEntryId: String? = cacheable
                    ? await self.semanticLayer.store(query: textInput, queryEmbedding: queryEmbedding, response: aiResponse.text, userId: uid, modelTier: route?.tier ?? "")
                    : nil

                // Surface retrieved library items as citations too (Live Search citations only cover
                // web/x/news).
                let mergedCitations = (aiResponse.citations + libraryCitations).distinctPreservingOrder()
                self.chatMessages.append(
                    ChatMessage(
                        id: UUID().uuidString,
                        sender: .ai,
                        text: aiResponse.text,
                        citations: mergedCitations,
                        groundedIn: sources.elements,
                        semanticCacheEntryId: cacheEntryId,
                        semanticCacheHit: false,
                        semanticModelTier: route?.tier
                    )
                )
            } catch {
                self.chatMessages.append(
                    ChatMessage(
                        id: UUID().uuidString,
                        sender: .ai,
                        text: humanReadableError(error, context: .ai),
                        isError: true,
                        retryPrompt: textInput
                    )
                )
            }
            self.isChatLoading = false
        }
    }

    func retryMessage(_ failedMessageId: String) {
        guard let failedIndex = chatMessages.firstIndex(where: { $0.id == failedMessageId }) else { return }
        let failed = chatMessages[failedIndex]
        guard let prompt = failed.retryPrompt else { return }
        chatMessages.remove(at: failedIndex)
        send(prompt, includeUserMessage: false)
    }

    func submitSemanticFeedback(messageId: String, accepted: Bool) {
        Task { [weak self] in
            guard let self else { return }
            guard let msg = self.chatMessages.first(where: { $0.id == messageId }) else { return }
            guard let entryId = msg.semanticCacheEntryId, msg.semanticFeedbackAccepted == nil else { return }
            // Thumbs-down evicts the offending cache entry and nudges the hit threshold up (on-device).
            await self.semanticLayer.feedback(
                entryId: entryId,
                accepted: accepted,
                similarity: msg.semanticSimilarity ?? 0
            )
            // Re-find in case the list changed during the await.
            guard let index = self.chatMessages.firstIndex(where: { $0.id == messageId }) else { return }
            let current = self.chatMessages[index]
            self.chatMessages[index] = ChatMessage(
                id: current.id,
                sender: current.sender,
                text: current.text,
                citations: current.citations,
                groundedIn: current.groundedIn,
                isError: current.isError,
                retryPrompt: current.retryPrompt,
                semanticCacheEntryId: current.semanticCacheEntryId,
                semanticSimilarity: current.semanticSimilarity,
                semanticCacheHit: current.semanticCacheHit,
                semanticModelTier: current.semanticModelTier,
                semanticFeedbackAccepted: accepted
            )
        }
    }

    /// Canonical URL for a retrieved library item, used to cite library-grounded chat replies. Port of
    /// `citationUrl(b)` — the exact source-type URL templates.
    private func citationUrl(_ b: Bookmark) -> String? {
        switch b.sourceType {
        case .ARXIV: return "https://arxiv.org/abs/\(stringifyId(b.sourceId))"
        case .GITHUB: return "https://github.com/\(stringifyId(b.sourceId))"
        case .HUGGING_FACE: return "https://huggingface.co/\(stringifyId(b.sourceId))"
        case .DOI: return "https://doi.org/\(stringifyId(b.sourceId))"
        default: return b.url
        }
    }

    /// Mirrors Kotlin string interpolation of a nullable `sourceId` (`"...${b.sourceId}"` prints
    /// `"null"` when nil) inside the citation templates.
    private func stringifyId(_ value: String?) -> String { value ?? "null" }

    /// Semantically retrieves the top-k library context for `queryEmbedding`, paired with each
    /// bookmark's embedding so the semantic compressor can MMR-rank them. Falls back to the 15
    /// most-recent bookmarks (no embeddings) whenever the query can't be embedded / nothing is
    /// indexed yet. Reuses the already-computed `queryEmbedding` (embed-once).
    private func retrieveRagContextScored(
        queryEmbedding: [Float]?,
        userId: String
    ) async -> [(bookmark: Bookmark, embedding: [Float])] {
        guard let queryEmbedding else {
            return Array(rawBookmarks().prefix(15)).map { ($0, []) }
        }
        let stored = await repository.getBookmarksWithEmbeddings(userId: userId)
        let allEmbeddings: [(String, [Float])] = stored.map { (id, bytes) in
            (id, VectorSearch.dataToFloatArray(bytes))
        }
        if allEmbeddings.isEmpty { return Array(rawBookmarks().prefix(15)).map { ($0, []) } }
        let embById = Dictionary(allEmbeddings, uniquingKeysWith: { _, last in last })
        let topScored = VectorSearch.topKScored(query: queryEmbedding, candidates: allEmbeddings, k: 15)
        let bookmarkMap = Dictionary(rawBookmarks().map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return topScored.compactMap { pair in
            bookmarkMap[pair.0].map { ($0, embById[pair.0] ?? []) }
        }
    }
}

// MARK: - Chat value types (owned here; the VM/UI read them)
//
// DESIGN slots `ChatMessage`/`ChatSender`/`ChatSource` onto the BookmarkViewModel surface, but they
// are wholly consumed by the chat controller, so they live here once. `BookmarkViewModel.swift` must
// NOT redefine them.

/// Who authored a chat message. Port of `enum ChatSender { USER, AI }`.
enum ChatSender: String, Sendable, Hashable {
    case user = "USER"
    case ai = "AI"
}

/// A grounding source the user can toggle for the Research Assistant. Port of
/// `enum ChatSource(val label: String, val apiType: String?)`.
///
/// `apiType` is the xAI Live Search source id (`"web"`/`"x"`/`"news"`); `library` has none (it is the
/// local RAG library, handled via `useLibrary`, never a live source).
enum ChatSource: String, CaseIterable, Sendable, Hashable {
    case library = "LIBRARY"
    case web = "WEB"
    case x = "X"
    case news = "NEWS"

    /// Human label for the system instruction / chips. Verbatim from the Kotlin enum constructor.
    var label: String {
        switch self {
        case .library: return "Library"
        case .web: return "Web"
        case .x: return "X"
        case .news: return "News"
        }
    }

    /// xAI Live Search source id, or `nil` for the local library (never a live source).
    var apiType: String? {
        switch self {
        case .library: return nil
        case .web: return "web"
        case .x: return "x"
        case .news: return "news"
        }
    }
}

/// A single chat turn. Port of `data class ChatMessage`.
struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: String
    let sender: ChatSender
    let text: String
    /// Source URLs the reply is grounded in (Live Search + library citations).
    let citations: [String]
    /// Which grounding sources produced this reply (for the chip strip).
    let groundedIn: [ChatSource]
    let isError: Bool
    let retryPrompt: String?
    let semanticCacheEntryId: String?
    let semanticSimilarity: Float?
    let semanticCacheHit: Bool
    let semanticModelTier: String?
    let semanticFeedbackAccepted: Bool?

    init(
        id: String,
        sender: ChatSender,
        text: String,
        citations: [String] = [],
        groundedIn: [ChatSource] = [],
        isError: Bool = false,
        retryPrompt: String? = nil,
        semanticCacheEntryId: String? = nil,
        semanticSimilarity: Float? = nil,
        semanticCacheHit: Bool = false,
        semanticModelTier: String? = nil,
        semanticFeedbackAccepted: Bool? = nil
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.citations = citations
        self.groundedIn = groundedIn
        self.isError = isError
        self.retryPrompt = retryPrompt
        self.semanticCacheEntryId = semanticCacheEntryId
        self.semanticSimilarity = semanticSimilarity
        self.semanticCacheHit = semanticCacheHit
        self.semanticModelTier = semanticModelTier
        self.semanticFeedbackAccepted = semanticFeedbackAccepted
    }

    var showsSemanticFeedback: Bool {
        semanticCacheEntryId != nil && semanticFeedbackAccepted == nil
    }
}

// MARK: - Insertion-ordered ChatSource set
//
// Reproduces Kotlin `LinkedHashSet` (the backing of `setOf(...)`/`toMutableSet()`): membership +
// stable insertion order. The order is load-bearing — `liveLabels` joins live sources in order and
// `groundedIn` carries the order to the UI.

struct OrderedChatSourceSet: Sendable, Equatable {
    private(set) var elements: [ChatSource]

    init(_ initial: [ChatSource] = []) {
        var seen = Set<ChatSource>()
        var ordered: [ChatSource] = []
        for s in initial where seen.insert(s).inserted { ordered.append(s) }
        elements = ordered
    }

    var isEmpty: Bool { elements.isEmpty }

    var count: Int { elements.count }

    func contains(_ source: ChatSource) -> Bool { elements.contains(source) }

    func contains(where predicate: (ChatSource) -> Bool) -> Bool { elements.contains(where: predicate) }

    mutating func insert(_ source: ChatSource) {
        if !elements.contains(source) { elements.append(source) }
    }

    mutating func remove(_ source: ChatSource) {
        elements.removeAll { $0 == source }
    }
}

// MARK: - Local helpers

private extension Array where Element: Hashable {
    /// Kotlin `List.distinct()` — keeps first occurrence, preserves order (citations merge order).
    func distinctPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        var result: [Element] = []
        for e in self where seen.insert(e).inserted { result.append(e) }
        return result
    }
}

private extension Error {
    /// Mirrors Kotlin `Throwable.localizedMessage` for the "Failed to respond: …" fallback.
    var localizedMessage: String {
        (self as? LocalizedError)?.errorDescription ?? (self as NSError).localizedDescription
    }
}

private extension String {
    /// Mirrors Kotlin `String.isBlank()` (whitespace-only ⇒ blank). Named distinctly to avoid
    /// colliding with blank helpers in sibling modules.
    var isBlankChat: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
