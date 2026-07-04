import Foundation
import os

/// Parsed arXiv paper metadata. Port of `data class ArxivMeta`.
struct ArxivMeta: Sendable, Equatable {
    let id: String
    let title: String
    let authors: [String]
    let abstract: String
    /// `"2023-12-01"` (≤10 chars, may be shorter/blank).
    let published: String
    let categories: [String]
}

/// Fetches arXiv Atom XML metadata. Ports `class ArxivClient` in `data/remote/ArxivClient.kt`.
///
/// `fetchPaper` strips the trailing version (`v\d+$`), queries `export.arxiv.org/api/query`, retries
/// up to 3× (503 → `2000ms*(n+1)`, other error → `1000ms*(n+1)`), then parses the Atom feed with an
/// `XMLParser` state machine mirroring the Kotlin `XmlPullParser` (inEntry/inAuthor + tag stack).
/// Resilient: logs and returns `nil` on any failure; rethrows `CancellationError`.
actor ArxivClient {

    static let defaultBaseURL = "https://export.arxiv.org/api/query"

    private let http: HTTPClient
    private let baseUrl: String
    private static let logger = Logger(subsystem: "com.curio.app", category: "ArxivClient")

    init(http: HTTPClient, baseUrl: String = ArxivClient.defaultBaseURL) {
        self.http = http
        self.baseUrl = baseUrl
    }

    /// Port of `suspend fun fetchPaper`. The `repeat(3)` loop: a 503 sleeps and continues; a hard
    /// non-success returns nil; a success parses the body; an exception sleeps and retries (nil on
    /// the 3rd attempt). Cancellation is rethrown.
    func fetchPaper(_ arxivId: String) async -> ArxivMeta? {
        let cleanId = arxivId
            .replacing(Self.versionSuffixRegex, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(baseUrl)?id_list=\(cleanId)&max_results=1") else { return nil }

        for attempt in 0..<3 {
            do {
                let request = HTTPClient.jsonRequest(url: url, method: "GET")
                let (data, _) = try await http.data(for: request, session: .metadata)
                let body = String(data: data, encoding: .utf8) ?? ""
                return Self.parseAtom(body)
            } catch let apiError as APIError {
                if apiError.statusCode == 503 {
                    Self.logger.warning("arXiv HTTP 503 (attempt \(attempt + 1))")
                    try? await Task.sleep(for: .milliseconds(2000 * (attempt + 1)))
                    continue
                }
                // Any other non-success status → give up immediately (matches `!isSuccessful`).
                Self.logger.warning("arXiv HTTP \(apiError.statusCode ?? -1)")
                return nil
            } catch is CancellationError {
                return nil
            } catch {
                if attempt == 2 { return nil }
                try? await Task.sleep(for: .milliseconds(1000 * (attempt + 1)))
            }
        }
        return nil
    }

    // MARK: - Atom parsing

    /// Port of `parseAtom`. Mirrors the Kotlin tag-stack state machine exactly, then applies the
    /// same post-processing (blank-title → nil, id regex → canonical id, whitespace collapse, ≤10
    /// published, category filter).
    static func parseAtom(_ xml: String) -> ArxivMeta? {
        guard let data = xml.data(using: .utf8) else { return nil }
        let delegate = AtomDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        // Process namespaces off so element names are the local names ("entry", "id", …),
        // matching the Kotlin parser which read `parser.name` after enabling namespace processing
        // (XmlPullParser strips the prefix; XMLParser with shouldProcessNamespaces=false keeps the
        // unqualified local name for these unprefixed Atom elements).
        parser.shouldProcessNamespaces = false

        guard parser.parse(), !delegate.failed else {
            if delegate.failed {
                logger.error("Parse error")
            }
            return nil
        }

        if delegate.titleBuilder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }

        let rawId = delegate.rawId
        let canonicalId: String
        if let match = rawId.firstMatch(of: arxivAbsRegex) {
            canonicalId = String(match.1).replacing(versionSuffixRegex, with: "")
        } else {
            canonicalId = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ArxivMeta(
            id: canonicalId,
            title: collapseWhitespace(delegate.titleBuilder.trimmingCharacters(in: .whitespacesAndNewlines)),
            authors: delegate.authors,
            abstract: collapseWhitespace(delegate.abstractBuilder.trimmingCharacters(in: .whitespacesAndNewlines)),
            published: String(delegate.published.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10)),
            categories: delegate.categories.filter { (try? categoryRegex.wholeMatch(in: $0)) != nil }
        )
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.replacing(whitespaceRunRegex, with: " ")
    }

    // MARK: - Regexes (byte-identical to the Kotlin patterns)

    /// `arxiv.org/abs/([\w.]+)` — extracts the canonical id from the Atom `<id>`.
    private nonisolated(unsafe) static let arxivAbsRegex = /arxiv\.org\/abs\/([\w.]+)/
    /// `v\d+$` — trailing version suffix.
    private nonisolated(unsafe) static let versionSuffixRegex = /v\d+$/
    /// `\s+` — whitespace runs (collapsed to a single space).
    private nonisolated(unsafe) static let whitespaceRunRegex = /\s+/
    /// `[a-zA-Z-]+\.[A-Z]+` — valid arXiv category term filter.
    private nonisolated(unsafe) static let categoryRegex = /[a-zA-Z-]+\.[A-Z]+/

    /// `(?:arxiv\.org|ar5iv\.org)/(?:abs|pdf)/([\d.]+(?:v\d+)?)` — id inside an arXiv/ar5iv URL.
    nonisolated(unsafe) static let arxivIdRegex = /(?:arxiv\.org|ar5iv\.org)\/(?:abs|pdf)\/([\d.]+(?:v\d+)?)/
    /// `\b(\d{4}\.\d{4,5}(?:v\d+)?)\b` — a bare arXiv id token.
    nonisolated(unsafe) static let arxivBareRegex = /\b(\d{4}\.\d{4,5}(?:v\d+)?)\b/
}

/// `XMLParserDelegate` reproducing the Kotlin `XmlPullParser` walk: only text inside `<entry>` is
/// accumulated, dispatched by the innermost open tag; `<author><name>` text is gathered separately,
/// `<category term=…>` collected on the start tag.
private final class AtomDelegate: NSObject, XMLParserDelegate {
    var inEntry = false
    var inAuthor = false
    var tagStack: [String] = []

    var rawId = ""
    var titleBuilder = ""
    var abstractBuilder = ""
    var published = ""
    var authors: [String] = []
    var authorNameBuilder = ""
    var categories: [String] = []
    var failed = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        tagStack.append(elementName)
        if elementName == "entry" {
            inEntry = true
        } else if elementName == "author" && inEntry {
            inAuthor = true
            authorNameBuilder = ""
        } else if elementName == "category" && inEntry {
            if let term = attributeDict["term"] {
                categories.append(term)
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inEntry else { return }
        switch tagStack.last {
        case "id":
            rawId += string
        case "title":
            titleBuilder += string
        case "summary":
            abstractBuilder += string
        case "published":
            published += string
        case "name":
            if inAuthor { authorNameBuilder += string }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "entry" {
            inEntry = false
        } else if elementName == "author" {
            let name = authorNameBuilder.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { authors.append(name) }
            inAuthor = false
        }
        if !tagStack.isEmpty { tagStack.removeLast() }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        failed = true
    }
}
