import Foundation
import os

/// Crossref work metadata. Port of `data class CrossrefMeta`.
struct CrossrefMeta: Sendable, Equatable {
    let doi: String
    let title: String
    let authors: [String]
    let abstract: String?
    /// `"YYYY"` or `"YYYY-MM-DD"` (may be blank).
    let published: String
    /// Journal / proceedings.
    let containerTitle: String?
    /// Crossref work type, e.g. `"journal-article"`.
    let type: String?
}

/// Resolves a DOI to bibliographic metadata via the public Crossref REST API
/// (`https://api.crossref.org/works/{doi}`). Ports `class CrossrefClient` in
/// `data/remote/CrossrefClient.kt`.
///
/// No key required; Crossref asks for a descriptive `User-Agent` so requests land in the "polite
/// pool" — the exact header is preserved. JATS-XML abstracts are tag-stripped. Lenient
/// `JSONSerialization` navigation mirrors `org.json` `optString`/`optJSONArray`; resilient (logs +
/// `nil`), rethrows `CancellationError`.
actor CrossrefClient {

    static let defaultBaseURL = "https://api.crossref.org/works/"

    /// Exact polite-pool User-Agent (preserved byte-for-byte).
    static let userAgent = "Curio/1.0 (Android research index; mailto:curio@example.com)"

    private let http: HTTPClient
    private let baseUrl: String
    private static let logger = Logger(subsystem: "com.curio.app", category: "CrossrefClient")

    init(http: HTTPClient, baseUrl: String = CrossrefClient.defaultBaseURL) {
        self.http = http
        self.baseUrl = baseUrl
    }

    /// Port of `suspend fun fetchWork`. Normalizes the DOI (trim → strip trailing `.` → lowercase),
    /// fetches, parses. Returns nil on blank DOI / non-success / any error.
    func fetchWork(_ doi: String) async -> CrossrefMeta? {
        var clean = doi.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasSuffix(".") { clean.removeLast() }
        clean = clean.lowercased()
        if clean.isEmpty { return nil }

        let urlString = "\(baseUrl)\(clean)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let request = HTTPClient.jsonRequest(
                url: url,
                method: "GET",
                extraHeaders: ["User-Agent": Self.userAgent]
            )
            let (data, _) = try await http.data(for: request, session: .metadata)
            return Self.parse(data)
        } catch is CancellationError {
            return nil
        } catch let apiError as APIError {
            Self.logger.warning("Crossref HTTP \(apiError.statusCode ?? -1) for DOI: \(clean.prefix(50))")
            return nil
        } catch {
            Self.logger.warning("Crossref lookup failed for \(clean)")
            return nil
        }
    }

    // MARK: - Parsing

    /// Port of `parse`. Navigates `message`, requires a non-blank title and DOI.
    static func parse(_ data: Data) -> CrossrefMeta? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            let msg = root["message"] as? [String: Any]
        else { return nil }

        // title = first element of "title" array, trimmed, non-blank, else return nil.
        guard
            let titleArray = msg["title"] as? [Any], !titleArray.isEmpty,
            let firstTitle = optStringElement(titleArray, 0)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !firstTitle.isEmpty
        else { return nil }

        // authors: given+family joined, else "name"; filtered to non-blank.
        var authors: [String] = []
        if let authorArray = msg["author"] as? [Any] {
            for element in authorArray {
                guard let a = element as? [String: Any] else { continue }
                let given = optString(a, "given").trimmingCharacters(in: .whitespacesAndNewlines)
                let family = optString(a, "family").trimmingCharacters(in: .whitespacesAndNewlines)
                var name = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    name = optString(a, "name").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    authors.append(name)
                }
            }
        }

        // abstract: JATS XML → strip tags → collapse whitespace → trim (nil when blank/absent).
        var abstract: String? = nil
        let rawAbstract = optString(msg, "abstract")
        if !rawAbstract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            abstract = rawAbstract
                .replacing(jatsTagRegex, with: " ")
                .replacing(whitespaceRunRegex, with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // container-title: first non-blank element.
        var container: String? = nil
        if let containerArray = msg["container-title"] as? [Any], !containerArray.isEmpty,
           let first = optStringElement(containerArray, 0), !first.isEmpty {
            container = first
        }

        // DOI: required non-blank.
        let doi = optString(msg, "DOI")
        if doi.isEmpty { return nil }

        let type = optString(msg, "type")
        let typeOrNil = type.isEmpty ? nil : type

        return CrossrefMeta(
            doi: doi,
            title: firstTitle.replacing(whitespaceRunRegex, with: " "),
            authors: authors,
            abstract: abstract,
            published: extractPublished(msg),
            containerTitle: container,
            type: typeOrNil
        )
    }

    /// Port of `extractPublished`. Reads `issued` (else `published`) `date-parts[0]`; builds
    /// `"%04d-%02d-%02d"` / `"%04d-%02d"` / `"%d"` depending on present fields.
    static func extractPublished(_ msg: [String: Any]) -> String {
        let dateContainer = (msg["issued"] as? [String: Any]) ?? (msg["published"] as? [String: Any])
        guard
            let dateParts = dateContainer?["date-parts"] as? [Any],
            let firstGroup = dateParts.first as? [Any]
        else { return "" }

        let year = optInt(firstGroup, 0)
        guard year > 0 else { return "" }
        let month = firstGroup.count > 1 ? optInt(firstGroup, 1) : 0
        let day = firstGroup.count > 2 ? optInt(firstGroup, 2) : 0

        if month > 0 && day > 0 {
            return String(format: "%04d-%02d-%02d", year, month, day)
        } else if month > 0 {
            return String(format: "%04d-%02d", year, month)
        } else {
            return String(year)
        }
    }

    // MARK: - org.json-style helpers

    private static func optString(_ obj: [String: Any], _ key: String) -> String {
        guard let value = obj[key], !(value is NSNull) else { return "" }
        if let str = value as? String { return str }
        return "\(value)"
    }

    private static func optStringElement(_ array: [Any], _ index: Int) -> String? {
        guard index < array.count else { return nil }
        let value = array[index]
        if value is NSNull { return nil }
        if let str = value as? String { return str }
        return "\(value)"
    }

    private static func optInt(_ array: [Any], _ index: Int) -> Int {
        guard index < array.count else { return 0 }
        if let number = array[index] as? NSNumber { return number.intValue }
        if let str = array[index] as? String, let value = Int(str) { return value }
        return 0
    }

    // MARK: - Regexes

    /// `<[^>]+>` — JATS/HTML tag strip.
    private nonisolated(unsafe) static let jatsTagRegex = /<[^>]+>/
    /// `\s+` — whitespace run.
    private nonisolated(unsafe) static let whitespaceRunRegex = /\s+/

    /// `\b(10\.\d{4,9}/[-._;()/:A-Za-z0-9]+)` (case-insensitive) — DOI inside a doi.org URL or as a
    /// bare token. Port of `DOI_REGEX`.
    nonisolated(unsafe) static let doiRegex = /\b(10\.\d{4,9}\/[-._;()\/:A-Za-z0-9]+)/.ignoresCase()
}
