import Foundation

/// What the desk is showing. `library` is the whole collection on this Mac.
enum DeskScope: Hashable, Sendable {
    case library
    case favorites
    case later
    case unfiled
    case space(String)

    static let sidebar: [DeskScope] = [.library, .favorites, .later, .unfiled]
}

/// How a research result is shown. A failed call keeps the sentence and drops the raw payload
/// when that payload is an id list rather than something a person can read.
struct DeskResearchPresentation: Equatable, Sendable {
    var answer: String
    var caveats: String
    var readingList: [String]
    var citations: [String]
    var failure: String?

    var hasBody: Bool {
        !answer.isEmpty || !caveats.isEmpty || !readingList.isEmpty || !citations.isEmpty
    }

    static func from(ok: Bool, code: String?, payload: String) -> DeskResearchPresentation {
        if ok, let brief = ResearchBrief(json: payload) {
            return DeskResearchPresentation(
                answer: trimmed(brief.answer),
                caveats: trimmed(brief.caveats),
                readingList: brief.readingList.map(trimmed).filter { !$0.isEmpty },
                citations: brief.citationURLs.map(trimmed).filter { !$0.isEmpty },
                failure: nil
            )
        }
        return DeskResearchPresentation(
            answer: "",
            caveats: "",
            readingList: [],
            citations: [],
            failure: failureMessage(code: code, payload: payload)
        )
    }

    static func failureMessage(code: String?, payload: String) -> String {
        switch code {
        case AgentFailure.notSignedIn.rawValue:
            return "Sign in with X before researching."
        case AgentFailure.keyMissing.rawValue:
            return "Add an xAI key to research on the web."
        case AgentFailure.embeddingModelMissing.rawValue:
            return "Install the on-device model before researching this library."
        case AgentFailure.indexEmpty.rawValue:
            return "This library has no indexed bookmarks to research yet."
        case AgentFailure.privateMode.rawValue:
            return "Live web research is turned off in Agent settings."
        case AgentFailure.contextExceeded.rawValue:
            return "That question pulls in more of the library than one pass can hold. Narrow it and try again."
        case AgentFailure.modelUnavailable.rawValue:
            return "The research model is unavailable right now."
        case AgentFailure.citationRejected.rawValue:
            return "The answer cited bookmarks outside this library, so it was not shown."
        default:
            let text = trimmed(payload)
            if text.isEmpty || text.hasPrefix("{") || text.hasPrefix("[") {
                return "Research could not finish."
            }
            return text
        }
    }

    private static func trimmed(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Sorting, search, and labels for the Mac desk. Category is never part of a label:
/// it only seeds Spaces and must not appear in the UI.
enum MacDeskLibrary {
    static func visible(_ bookmarks: [Bookmark], scope: DeskScope, query: String) -> [Bookmark] {
        bookmarks
            .filter { matches($0, scope: scope) && matchesQuery($0, query: query) }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id < rhs.id
            }
    }

    static func matches(_ bookmark: Bookmark, scope: DeskScope) -> Bool {
        switch scope {
        case .library:
            return true
        case .favorites:
            return bookmark.isFavorite
        case .later:
            return bookmark.isSavedForLater
        case .unfiled:
            return bookmark.spaceId == nil
        case .space(let id):
            return bookmark.spaceId == id
        }
    }

    static func matchesQuery(_ bookmark: Bookmark, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if AgentLookup.keywordMatches(bookmark, query: trimmed) { return true }
        if AgentLookup.contains(bookmark.id, trimmed) { return true }
        if AgentLookup.contains(bookmark.sourceTitle, trimmed) { return true }
        if AgentLookup.contains(bookmark.authorName, trimmed) { return true }
        if AgentLookup.contains(bookmark.authorUsername, trimmed) { return true }
        if AgentLookup.contains(bookmark.sourceAuthors, trimmed) { return true }
        if AgentLookup.contains(bookmark.url, trimmed) { return true }
        return false
    }

    static func count(_ bookmarks: [Bookmark], scope: DeskScope) -> Int {
        bookmarks.reduce(into: 0) { total, bookmark in
            if matches(bookmark, scope: scope) { total += 1 }
        }
    }

    /// Pinned spaces float, then manual order, then name. Equal names break ties by id
    /// so the sidebar does not reorder itself between reloads.
    static func orderedSpaces(_ spaces: [Space]) -> [Space] {
        spaces.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    static func scopeTitle(_ scope: DeskScope, spaces: [Space]) -> String {
        switch scope {
        case .library: return "All Bookmarks"
        case .favorites: return "Favorites"
        case .later: return "Read Later"
        case .unfiled: return "Unfiled"
        case .space(let id):
            return spaces.first { $0.id == id }?.name ?? "Space"
        }
    }

    static func scopePhrase(_ scope: DeskScope, spaces: [Space]) -> String {
        switch scope {
        case .library: return "the library"
        default: return scopeTitle(scope, spaces: spaces)
        }
    }

    static func scopeSymbol(_ scope: DeskScope, spaces: [Space]) -> String {
        switch scope {
        case .library: return "books.vertical.fill"
        case .favorites: return "star.fill"
        case .later: return "bookmark.fill"
        case .unfiled: return "tray"
        case .space(let id):
            return spaceIcon(spaces.first { $0.id == id }?.icon)
        }
    }

    static func title(_ bookmark: Bookmark) -> String {
        let raw: String
        if let explicit = nonempty(bookmark.title) {
            raw = explicit
        } else if let source = nonempty(bookmark.sourceTitle) {
            raw = source
        } else {
            let first = bookmark.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            raw = first
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled" }
        if trimmed.count <= 80 { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 80)
        return String(trimmed[..<end]) + "…"
    }

    static func excerpt(_ bookmark: Bookmark) -> String {
        if let summary = nonempty(bookmark.summary) {
            return collapsed(summary, limit: 180)
        }
        if nonempty(bookmark.title) != nil || nonempty(bookmark.sourceTitle) != nil {
            return collapsed(bookmark.text, limit: 180)
        }
        let lines = bookmark.text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        return collapsed(lines.dropFirst().joined(separator: " "), limit: 180)
    }

    static func byline(_ bookmark: Bookmark) -> String? {
        let name = nonempty(bookmark.authorName)
        let handle = nonempty(bookmark.authorUsername).map { raw in
            raw.hasPrefix("@") ? raw : "@\(raw)"
        }
        if let name, let handle,
           name.caseInsensitiveCompare(handle) != .orderedSame,
           name.caseInsensitiveCompare(String(handle.dropFirst())) != .orderedSame {
            return "\(name) · \(handle)"
        }
        return name ?? handle
    }

    static func link(_ bookmark: Bookmark) -> String? {
        if let url = nonempty(bookmark.url) { return url }
        return CurioFormat.tweetUrl(bookmark)
    }

    static func host(_ bookmark: Bookmark) -> String? {
        guard let raw = link(bookmark) else { return nil }
        let normalized = (raw.hasPrefix("http://") || raw.hasPrefix("https://")) ? raw : "https://\(raw)"
        guard let host = URL(string: normalized)?.host?.lowercased(), !host.isEmpty else { return nil }
        let stripped = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return stripped.isEmpty ? nil : stripped
    }

    static func symbol(for bookmark: Bookmark) -> String {
        switch bookmark.sourceType {
        case .ARXIV: return "doc.text"
        case .GITHUB: return "chevron.left.forwardslash.chevron.right"
        case .HUGGING_FACE: return "square.stack.3d.up"
        case .TWEET: return "bubble.left"
        case .DOI: return "text.book.closed"
        case nil:
            return link(bookmark) == nil ? "bookmark" : "link"
        }
    }

    static func sourceLabel(_ type: SourceType?) -> String? {
        switch type {
        case .ARXIV: return "arXiv"
        case .GITHUB: return "GitHub"
        case .HUGGING_FACE: return "Hugging Face"
        case .TWEET: return "Post"
        case .DOI: return "DOI"
        case nil: return nil
        }
    }

    static func metaParts(_ bookmark: Bookmark) -> [String] {
        var parts: [String] = []
        if let host = host(bookmark) { parts.append(host) }
        if let source = sourceLabel(bookmark.sourceType) { parts.append(source) }
        parts.append(CurioFormat.relativeTime(bookmark.createdAt))
        if let reading = CurioFormat.readingTime(bookmark.text) { parts.append(reading) }
        return parts
    }

    static func shareText(_ bookmark: Bookmark) -> String {
        var lines = [title(bookmark)]
        if let link = link(bookmark) { lines.append(link) }
        let body = bookmark.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty && body != lines[0] { lines.append(body) }
        return lines.joined(separator: "\n\n")
    }

    static func accessibilityLabel(_ bookmark: Bookmark, spaceName: String?) -> String {
        var parts = [title(bookmark)]
        if bookmark.isFavorite { parts.append("starred") }
        if bookmark.isSavedForLater { parts.append("read later") }
        if let spaceName { parts.append(spaceName) }
        if let host = host(bookmark) { parts.append(host) }
        return parts.joined(separator: ", ")
    }

    static func librarySummary(bookmarks: [Bookmark], spaces: [Space]) -> String {
        let saved = bookmarks.count
        let noun = saved == 1 ? "bookmark" : "bookmarks"
        let starred = bookmarks.filter(\.isFavorite).count
        let later = bookmarks.filter(\.isSavedForLater).count
        return "\(saved) \(noun) · \(starred) starred · \(later) to read · \(spaces.count) spaces"
    }

    static func nonempty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func bibtexCitation(_ bookmark: Bookmark) -> String? {
        if let citation = BibtexExporter.toBibtex(bookmark) {
            return citation
        }
        guard let url = link(bookmark) else { return nil }
        let rawId = bookmark.id.isEmpty ? "curio_item" : bookmark.id
        let cleanId = rawId.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" }
        let entryKey = cleanId.isEmpty ? "curio_item" : String(cleanId)
        let citeTitle = title(bookmark).replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        let author = byline(bookmark) ?? "Curio"
        return """
        @misc{\(entryKey),
          author       = {\(author)},
          title        = {{\(citeTitle)}},
          howpublished = {\\url{\(url)}},
          note         = {Accessed: \(CurioFormat.relativeTime(bookmark.createdAt))}
        }
        """
    }

    static let spaceColorPalette: [(name: String, color: Int64)] = [
        ("Blue", 0xFF1E88E5),
        ("Orange", 0xFFFF9800),
        ("Deep Orange", 0xFFFF5722),
        ("Green", 0xFF43A047),
        ("Indigo", 0xFF3F51B5),
        ("Purple", 0xFF8E24AA),
        ("Teal", 0xFF00BCD4),
        ("Deep Purple", 0xFF673AB7),
        ("Blue Grey", 0xFF607D8B),
        ("Rose", 0xFFE91E63)
    ]

    static let spaceIcons: [String] = [
        "folder", "tag", "bookmark", "star", "books.vertical",
        "cpu", "brain", "lightbulb", "globe", "sparkles"
    ]

    private static func collapsed(_ raw: String, limit: Int) -> String {
        let squashed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if squashed.count <= limit { return squashed }
        let end = squashed.index(squashed.startIndex, offsetBy: limit)
        return String(squashed[..<end]) + "…"
    }
}
