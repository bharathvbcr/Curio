import Foundation

/// What the desk is showing. `library` is the whole collection on this Mac.
enum DeskScope: Hashable, Sendable {
    case library
    case favorites
    case later
    case unfiled
    case annotated
    case space(String)

    static let sidebar: [DeskScope] = [.library, .favorites, .later, .unfiled, .annotated]
}

/// Order of the bookmark list. Every order ends in an id tie-break so it never shuffles.
enum DeskSort: String, CaseIterable, Identifiable, Sendable {
    case newest
    case oldest
    case title
    case author

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "Newest First"
        case .oldest: return "Oldest First"
        case .title: return "Title"
        case .author: return "Author"
        }
    }
}

/// File formats the desk can export a selection or scope to.
enum DeskExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case bibtex
    case ris
    case cslJson
    case json
    case csv

    var id: String { rawValue }

    var label: String {
        switch self {
        case .markdown: return "Markdown"
        case .bibtex: return "BibTeX"
        case .ris: return "RIS"
        case .cslJson: return "CSL-JSON"
        case .json: return "JSON (full backup)"
        case .csv: return "CSV"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .bibtex: return "bib"
        case .ris: return "ris"
        case .cslJson: return "json"
        case .json: return "json"
        case .csv: return "csv"
        }
    }
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
    static func visible(_ bookmarks: [Bookmark], scope: DeskScope, query: String, sort: DeskSort = .newest) -> [Bookmark] {
        sorted(bookmarks.filter { matches($0, scope: scope) && matchesQuery($0, query: query) }, by: sort)
    }

    static func sorted(_ bookmarks: [Bookmark], by sort: DeskSort) -> [Bookmark] {
        switch sort {
        case .newest:
            return bookmarks.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id < rhs.id
            }
        case .oldest:
            return bookmarks.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id < rhs.id
            }
        case .title, .author:
            // Keys are computed once; titles can be long and comparisons are locale-aware.
            let keyed = bookmarks.map { bookmark -> (String, Bookmark) in
                let key = sort == .title ? title(bookmark) : (byline(bookmark) ?? "")
                return (key, bookmark)
            }
            return keyed.sorted { lhs, rhs in
                // Bookmarks without an author sink to the end.
                if lhs.0.isEmpty != rhs.0.isEmpty { return !lhs.0.isEmpty }
                let order = lhs.0.localizedCaseInsensitiveCompare(rhs.0)
                if order != .orderedSame { return order == .orderedAscending }
                if lhs.1.createdAt != rhs.1.createdAt { return lhs.1.createdAt > rhs.1.createdAt }
                return lhs.1.id < rhs.1.id
            }.map(\.1)
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
        case .annotated:
            return nonempty(bookmark.notes) != nil
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
        case .annotated: return "With Notes"
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
        case .annotated: return "note.text"
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

    /// A resolved source's own entry, else an `@misc` for anything with a link. Every field is
    /// LaTeX-escaped so a stray `%` or `}` in a post cannot break the .bib file.
    static func bibtexCitation(_ bookmark: Bookmark) -> String? {
        if let citation = BibtexExporter.toBibtex(bookmark) {
            return citation
        }
        guard let url = link(bookmark) else { return nil }
        let asciiId = bookmark.id.unicodeScalars.filter {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-")
        }
        let entryKey = asciiId.isEmpty ? "curio_item" : "curio_" + String(String.UnicodeScalarView(asciiId.prefix(40)))
        let author = nonempty(bookmark.authorName)
            ?? nonempty(bookmark.authorUsername).map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }
            ?? "Curio"
        let safeURL = url
            .replacingOccurrences(of: "{", with: "%7B")
            .replacingOccurrences(of: "}", with: "%7D")
            .replacingOccurrences(of: "\\", with: "%5C")
            .replacingOccurrences(of: " ", with: "%20")
            .filter { !$0.isNewline }
        return """
        @misc{\(entryKey),
          author       = {\(latexEscaped(author))},
          title        = {{\(latexEscaped(title(bookmark)))}},
          howpublished = {\\url{\(safeURL)}},
          year         = {\(year(bookmark.createdAt))},
          note         = {Saved \(isoDay(bookmark.createdAt))}
        }
        """
    }

    /// Escapes the ten LaTeX specials and flattens line breaks. Backslash goes first so the
    /// escapes it introduces are not escaped again.
    static func latexEscaped(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)
        for character in raw {
            switch character {
            case "\\": out += "\\textbackslash{}"
            case "{": out += "\\{"
            case "}": out += "\\}"
            case "&": out += "\\&"
            case "%": out += "\\%"
            case "$": out += "\\$"
            case "#": out += "\\#"
            case "_": out += "\\_"
            case "~": out += "\\textasciitilde{}"
            case "^": out += "\\textasciicircum{}"
            default:
                if character.isNewline {
                    out += " "
                } else if !character.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) {
                    out.append(character)
                }
            }
        }
        return out
    }

    /// `createdAt` is epoch milliseconds; an older epoch-seconds value is detected and scaled.
    static func date(_ createdAt: Int64) -> Date {
        let seconds = abs(createdAt) > 100_000_000_000 ? Double(createdAt) / 1000 : Double(createdAt)
        return Date(timeIntervalSince1970: seconds)
    }

    static func isoDay(_ createdAt: Int64) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date(createdAt))
    }

    static func year(_ createdAt: Int64) -> String {
        String(isoDay(createdAt).prefix(4))
    }

    // MARK: - Export

    static func exportText(_ bookmarks: [Bookmark], format: DeskExportFormat, spaces: [Space]) -> String {
        switch format {
        case .markdown: return markdownExport(bookmarks, spaces: spaces)
        case .bibtex: return bookmarks.compactMap(bibtexCitation).joined(separator: "\n\n") + (bookmarks.isEmpty ? "" : "\n")
        case .ris: return BibtexExporter.toRisList(bookmarks)
        case .cslJson: return BibtexExporter.toCslJsonList(bookmarks)
        case .json: return jsonExport(bookmarks)
        case .csv: return csvExport(bookmarks)
        }
    }

    /// How many of `bookmarks` a format can represent. RIS and CSL-JSON cover resolved sources only.
    static func exportableCount(_ bookmarks: [Bookmark], format: DeskExportFormat) -> Int {
        switch format {
        case .markdown, .json, .csv: return bookmarks.count
        case .bibtex: return bookmarks.filter { bibtexCitation($0) != nil }.count
        case .ris: return bookmarks.filter { BibtexExporter.toRis($0) != nil }.count
        case .cslJson: return bookmarks.filter { BibtexExporter.toCslJson($0) != nil }.count
        }
    }

    static func exportFilename(scopeTitle: String, format: DeskExportFormat) -> String {
        let base = scopeTitle.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == " " ? Character(scalar) : "-"
        }
        let collapsed = String(base).split(separator: " ").joined(separator: " ")
        let name = collapsed.isEmpty ? "Curio" : String(collapsed.prefix(60))
        return "Curio – \(name).\(format.fileExtension)"
    }

    static func markdownExport(_ bookmarks: [Bookmark], spaces: [Space]) -> String {
        var lines: [String] = []
        for bookmark in bookmarks {
            let heading = markdownEscaped(title(bookmark))
            if let url = link(bookmark) {
                lines.append("- [\(heading)](\(url.replacingOccurrences(of: ")", with: "%29").replacingOccurrences(of: " ", with: "%20")))")
            } else {
                lines.append("- \(heading)")
            }
            var meta: [String] = []
            if let by = byline(bookmark) { meta.append(markdownEscaped(by)) }
            if let spaceId = bookmark.spaceId, let name = spaces.first(where: { $0.id == spaceId })?.name { meta.append(markdownEscaped(name)) }
            if bookmark.isFavorite { meta.append("★") }
            meta.append(isoDay(bookmark.createdAt))
            lines.append("  \(meta.joined(separator: " · "))")
            if let summary = nonempty(bookmark.summary) {
                lines.append("  " + collapsed(markdownEscaped(summary), limit: 400))
            }
            if let notes = nonempty(bookmark.notes) {
                lines.append("  > " + notes.split(whereSeparator: \.isNewline).map { markdownEscaped(String($0)) }.joined(separator: "\n  > "))
            }
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    static func markdownEscaped(_ raw: String) -> String {
        var out = ""
        for character in raw {
            if "\\`*_[]<>|".contains(character) { out.append("\\") }
            out.append(character.isNewline ? " " : character)
        }
        return out
    }

    /// Full-fidelity backup: every field of the domain model, sorted keys, ISO-8601 friendly.
    static func jsonExport(_ bookmarks: [Bookmark]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(bookmarks), let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text + "\n"
    }

    /// RFC 4180: every field quoted, quotes doubled, line breaks kept inside the quotes.
    static func csvExport(_ bookmarks: [Bookmark]) -> String {
        func field(_ raw: String?) -> String {
            "\"" + (raw ?? "").replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var rows = ["id,title,url,author,created,favorite,read_later,space_id,tags,summary,notes,text"]
        for bookmark in bookmarks {
            rows.append([
                field(bookmark.id),
                field(title(bookmark)),
                field(link(bookmark)),
                field(byline(bookmark)),
                field(isoDay(bookmark.createdAt)),
                bookmark.isFavorite ? "true" : "false",
                bookmark.isSavedForLater ? "true" : "false",
                field(bookmark.spaceId),
                field(bookmark.tags.joined(separator: ";")),
                field(bookmark.summary),
                field(bookmark.notes),
                field(bookmark.text)
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - Editing rules

    static let maxSpaceNameLength = 60
    static let maxNewBookmarkLength = 20_000

    /// Trimmed, single-spaced name, or nil when it is empty.
    static func normalizedSpaceName(_ raw: String) -> String? {
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// Why a space name cannot be used, or nil when it can. Names are unique ignoring case;
    /// `excluding` is the space being renamed.
    static func spaceNameProblem(_ raw: String, existing: [Space], excluding: String? = nil) -> String? {
        guard let name = normalizedSpaceName(raw) else { return "Give the space a name." }
        if name.count > maxSpaceNameLength { return "Keep the name under \(maxSpaceNameLength) characters." }
        let clash = existing.contains { space in
            space.id != excluding && space.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        return clash ? "A space named “\(name)” already exists." : nil
    }

    /// Trimmed text for a new bookmark, or nil when there is nothing to save or it is too long.
    static func normalizedNewBookmark(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxNewBookmarkLength else { return nil }
        return trimmed
    }

    /// True when saving `draft` would change the stored note (whitespace-only edits do not count).
    static func notesChanged(draft: String, saved: String?) -> Bool {
        let next = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = (saved ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return next != current
    }

    /// Keeps only ids that are still on screen, so a hidden bookmark is never acted on.
    static func reconciledSelection(_ selection: Set<String>, visibleIds: [String]) -> Set<String> {
        selection.intersection(visibleIds)
    }

    /// Bulk star: star all unless every one is already starred, then unstar all.
    static func bulkFavoriteTarget(_ bookmarks: [Bookmark]) -> Bool {
        !bookmarks.allSatisfy(\.isFavorite)
    }

    static func bulkLaterTarget(_ bookmarks: [Bookmark]) -> Bool {
        !bookmarks.allSatisfy(\.isSavedForLater)
    }

    /// http(s) only, for links that come back from a model rather than from the library.
    static func safeWebURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Words for a count: "1 bookmark", "3 bookmarks".
    static func counted(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : (plural ?? singular + "s"))"
    }

    /// Icon keys shared with iOS (`spaceIconKeys`). Raw SF Symbol names would show as the
    /// generic grid on both platforms, since `spaceIcon(_:)` resolves keys, not symbols.
    static var spaceIcons: [String] { spaceIconKeys }

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

    private static func collapsed(_ raw: String, limit: Int) -> String {
        let squashed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if squashed.count <= limit { return squashed }
        let end = squashed.index(squashed.startIndex, offsetBy: limit)
        return String(squashed[..<end]) + "…"
    }
}
