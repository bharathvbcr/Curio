import Foundation

/// Citation export for resolved primary sources — BibTeX, RIS, CSL-JSON and Markdown. Ports
/// `object BibtexExporter` from `data/export/BibtexExporter.kt`. Caseless namespace enum
/// (CONVENTIONS §1).
///
/// CONVENTIONS §10 (export byte-fidelity — downstream LaTeX/Zotero parsers are whitespace-sensitive):
/// - LaTeX escaping of `& % $ # _` (in that order);
/// - double-braced GitHub/HF titles (`{{…}}`);
/// - RIS two-space-dash tags (`"TY  - "`, `"TI  - "`, …);
/// - deterministic cite keys: cleaned lastname (`[a-z0-9]`, ≤12) + year + first title word (>3 chars,
///   all-lowercase-letters, else `"work"`);
/// - year from `sourceExtra.published` (`"published":"YYYY` regex) else `Calendar` year from
///   `createdAt`, disambiguating epoch-ms vs epoch-s by the `1e12` threshold.
///
/// Every helper mirrors the Kotlin `buildString { appendLine(...) }` output exactly: `appendLine`
/// appends the line **plus a trailing `\n`** (reproduced here by `+ "\n"`).
enum BibtexExporter {

    // MARK: - BibTeX

    /// Port of `toBibtex(bookmark)`. Returns nil for an unresolved / unsupported source type.
    static func toBibtex(_ bookmark: Bookmark) -> String? {
        switch bookmark.sourceType {
        case .ARXIV: return arxivBibtex(bookmark)
        case .GITHUB: return githubBibtex(bookmark)
        case .HUGGING_FACE: return hfBibtex(bookmark)
        case .DOI: return doiBibtex(bookmark)
        default: return nil
        }
    }

    private static func doiBibtex(_ bookmark: Bookmark) -> String? {
        guard let doi = bookmark.sourceId else { return nil }
        guard let title = bookmark.sourceTitle else { return nil }
        let year = extractYear(bookmark)
        let authors = formatAuthors(bookmark.sourceAuthors)
        let container = extra(bookmark)?.optString("container").nonBlank
        let month = extractMonth(bookmark)
        var s = ""
        s += "@article{\(generateKey(bookmark, year: year)),\n"
        s += "  title   = {\(escapeLatex(title))},\n"
        if !authors.isEmpty { s += "  author  = {\(authors)},\n" }
        if let container { s += "  journal = {\(escapeLatex(container))},\n" }
        s += "  year    = {\(year)},\n"
        if let month { s += "  month   = {\(month)},\n" }
        s += "  doi     = {\(doi)},\n"
        if let abstract = bookmark.sourceAbstract, !abstract.isBlank {
            s += "  abstract= {\(escapeLatex(abstract))},\n"
        }
        s += "  url     = {https://doi.org/\(doi)}"
        s += "\n}"
        return s
    }

    private static func arxivBibtex(_ bookmark: Bookmark) -> String? {
        guard let id = bookmark.sourceId else { return nil }
        guard let title = bookmark.sourceTitle else { return nil }
        let year = extractYear(bookmark)
        let key = generateKey(bookmark, year: year)
        let authors = formatAuthors(bookmark.sourceAuthors)
        let primaryClass = extractPrimaryClass(bookmark)
        let month = extractMonth(bookmark)
        let doi = extractDoi(bookmark)
        var s = ""
        s += "@article{\(key),\n"
        s += "  title         = {\(escapeLatex(title))},\n"
        if !authors.isEmpty { s += "  author        = {\(authors)},\n" }
        s += "  journal       = {arXiv preprint arXiv:\(id)},\n"
        s += "  year          = {\(year)},\n"
        if let month { s += "  month         = {\(month)},\n" }
        s += "  eprint        = {\(id)},\n"
        s += "  archivePrefix = {arXiv},\n"
        if let primaryClass { s += "  primaryClass  = {\(primaryClass)},\n" }
        if let doi { s += "  doi           = {\(doi)},\n" }
        if let abstract = bookmark.sourceAbstract, !abstract.isBlank {
            s += "  abstract      = {\(escapeLatex(abstract))},\n"
        }
        s += "  url           = {https://arxiv.org/abs/\(id)}"
        s += "\n}"
        return s
    }

    private static func githubBibtex(_ bookmark: Bookmark) -> String? {
        guard let id = bookmark.sourceId else { return nil }
        guard let title = bookmark.sourceTitle else { return nil }
        let year = extractYear(bookmark)
        let owner = substringBefore(id, "/")
        let formatted = formatAuthors(bookmark.sourceAuthors)
        let author = formatted.isEmpty ? owner : formatted
        let key = buildKey(owner, year: year, title: title)
        var s = ""
        s += "@misc{\(key),\n"
        s += "  title  = {{\(escapeLatex(title))}},\n"
        s += "  author = {\(escapeLatex(author))},\n"
        s += "  year   = {\(year)},\n"
        s += "  url    = {https://github.com/\(id)},\n"
        s += "  note   = {GitHub repository}"
        s += "\n}"
        return s
    }

    private static func hfBibtex(_ bookmark: Bookmark) -> String? {
        guard let id = bookmark.sourceId else { return nil }
        guard let title = bookmark.sourceTitle else { return nil }
        let year = extractYear(bookmark)
        let formatted = formatAuthors(bookmark.sourceAuthors)
        let author = formatted.isEmpty ? substringBefore(id, "/") : formatted
        let key = buildKey(substringBefore(id, "/"), year: year, title: title)
        var s = ""
        s += "@misc{\(key),\n"
        s += "  title  = {{\(escapeLatex(title))}},\n"
        s += "  author = {\(escapeLatex(author))},\n"
        s += "  year   = {\(year)},\n"
        s += "  url    = {https://huggingface.co/\(id)},\n"
        s += "  note   = {HuggingFace model/dataset}"
        s += "\n}"
        return s
    }

    // MARK: - RIS

    /// Port of `toRis(bookmark)`. Note the Kotlin order-of-operations: `id`/`title` are required first,
    /// then `paper` is computed, then a redundant `sourceType == null` guard (always false once a
    /// type-bearing bookmark passes the title check, but preserved for fidelity).
    static func toRis(_ bookmark: Bookmark) -> String? {
        guard let id = bookmark.sourceId else { return nil }
        guard let title = bookmark.sourceTitle else { return nil }
        let paper = isPaper(bookmark.sourceType)
        if bookmark.sourceType == nil { return nil }
        var s = ""
        s += (paper ? "TY  - JOUR" : "TY  - COMP") + "\n"
        s += "TI  - \(title)\n"
        if let authorsStr = bookmark.sourceAuthors {
            let authors = authorsStr.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for a in authors { s += "AU  - \(a)\n" }
        }
        if bookmark.sourceType == .ARXIV { s += "T2  - arXiv preprint arXiv:\(id)\n" }
        s += "PY  - \(extractYear(bookmark))\n"
        if let doi = extractDoi(bookmark) { s += "DO  - \(doi)\n" }
        s += "UR  - \(sourceUrl(bookmark))\n"
        if let abstract = bookmark.sourceAbstract, !abstract.isBlank {
            s += "N2  - \(String(abstract.prefix(500)))\n"
        }
        s += "ER  - \n"
        return s
    }

    // MARK: - CSL-JSON

    /// CSL-JSON (a JSON array of one item) — consumable by Zotero, citeproc and pandoc. Port of
    /// `toCslJson(bookmark)`; output uses `org.json` 2-space pretty printing.
    static func toCslJson(_ bookmark: Bookmark) -> String? {
        guard let title = bookmark.sourceTitle else { return nil }
        guard let type = bookmark.sourceType else { return nil }
        let year = Int(extractYear(bookmark))

        var item = OrderedJSON()
        item.put("id", bookmark.sourceId ?? bookmark.id)
        item.put("type", isPaper(type) ? "article-journal" : "software")
        item.put("title", title)

        let authors: [String]? = bookmark.sourceAuthors?
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let authors, !authors.isEmpty {
            var arr = OrderedJSONArray()
            for name in authors { arr.add(.object(cslName(name))) }
            item.put("author", .array(arr))
        }
        if let year {
            var issued = OrderedJSON()
            var dateParts = OrderedJSONArray()
            var inner = OrderedJSONArray()
            inner.add(.int(year))
            dateParts.add(.array(inner))
            issued.put("date-parts", .array(dateParts))
            item.put("issued", .object(issued))
        }
        if let doi = extractDoi(bookmark) { item.put("DOI", doi) }
        item.put("URL", sourceUrl(bookmark))
        if let abstract = bookmark.sourceAbstract, !abstract.isBlank {
            item.put("abstract", abstract)
        }
        if type == .ARXIV {
            item.put("container-title", "arXiv")
            if let sid = bookmark.sourceId { item.put("number", sid) }
        } else if type == .DOI {
            if let container = extra(bookmark)?.optString("container").nonBlank {
                item.put("container-title", container)
            }
        }
        return item.toString(indentFactor: 2, indent: 0)
    }

    /// Splits "Firstname Lastname" into CSL family/given parts (best-effort). Port of `cslName(name)`.
    private static func cslName(_ name: String) -> OrderedJSON {
        let parts = name.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
        var obj = OrderedJSON()
        if parts.count > 1 {
            obj.put("family", parts.last ?? "")
            obj.put("given", parts.dropLast().joined(separator: " "))
        } else {
            obj.put("literal", name)
        }
        return obj
    }

    // MARK: - Markdown

    /// Human-readable Markdown citation (one bullet). Port of `toMarkdown(bookmark)`.
    static func toMarkdown(_ bookmark: Bookmark) -> String? {
        guard let title = bookmark.sourceTitle else { return nil }
        let formatted = formatAuthors(bookmark.sourceAuthors)
        let authors: String? = formatted.isEmpty ? nil : formatted
        let year = extractYear(bookmark)
        let url = sourceUrl(bookmark)
        var s = ""
        s += "- "
        if let authors { s += "\(authors) " }
        s += "(\(year)). [\(title)](\(url))"
        if let doi = extractDoi(bookmark) { s += " doi:\(doi)" }
        return s
    }

    // MARK: - List variants

    static func toBibtexList(_ bookmarks: [Bookmark]) -> String {
        bookmarks.compactMap { toBibtex($0) }.joined(separator: "\n\n")
    }

    static func toRisList(_ bookmarks: [Bookmark]) -> String {
        bookmarks.compactMap { toRis($0) }.joined(separator: "\n")
    }

    static func toMarkdownList(_ bookmarks: [Bookmark]) -> String {
        bookmarks.compactMap { toMarkdown($0) }.joined(separator: "\n")
    }

    static func toCslJsonList(_ bookmarks: [Bookmark]) -> String {
        "[\n" + bookmarks.compactMap { toCslJson($0) }.joined(separator: ",\n") + "\n]"
    }

    // MARK: - Helpers

    private static func sourceUrl(_ bookmark: Bookmark) -> String {
        switch bookmark.sourceType {
        case .ARXIV: return "https://arxiv.org/abs/\(bookmark.sourceId ?? "")"
        case .GITHUB: return "https://github.com/\(bookmark.sourceId ?? "")"
        case .HUGGING_FACE: return "https://huggingface.co/\(bookmark.sourceId ?? "")"
        case .DOI: return "https://doi.org/\(bookmark.sourceId ?? "")"
        default: return bookmark.url ?? ""
        }
    }

    private static func isPaper(_ type: SourceType?) -> Bool {
        type == .ARXIV || type == .DOI
    }

    /// Reads `sourceExtra` JSON (nil when blank/unparseable). Port of `extra(bookmark)`.
    private static func extra(_ bookmark: Bookmark) -> ParsedExtra? {
        guard let raw = bookmark.sourceExtra, !raw.isBlank else { return nil }
        guard
            let data = raw.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return ParsedExtra(obj)
    }

    private static func extractDoi(_ bookmark: Bookmark) -> String? {
        extra(bookmark)?.optString("doi").nonBlank
    }

    private static func extractPrimaryClass(_ bookmark: Bookmark) -> String? {
        guard let cats = extra(bookmark)?.optJSONArray("categories") else { return nil }
        guard !cats.isEmpty else { return nil }
        return optStringElement(cats, 0)?.nonBlank
    }

    /// BibTeX month from the stored "published" date ("2023-12-01" -> "dec"). Port of `extractMonth`.
    private static func extractMonth(_ bookmark: Bookmark) -> String? {
        guard let published = extra(bookmark)?.optString("published") else { return nil }
        guard let match = published.firstMatch(of: monthRegex) else { return nil }
        guard let m = Int(match.1) else { return nil }
        let idx = m - 1
        guard idx >= 0 && idx < MONTHS.count else { return nil }
        return MONTHS[idx]
    }

    private static func generateKey(_ bookmark: Bookmark, year: String) -> String {
        let firstAuthor = bookmark.sourceAuthors?
            .split(separator: ",", omittingEmptySubsequences: false)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? "anon"
        // Kotlin `firstAuthor.split(" ").last()` — last space-separated token.
        let lastName = firstAuthor.components(separatedBy: " ").last ?? firstAuthor
        return buildKey(lastName, year: year, title: bookmark.sourceTitle ?? "paper")
    }

    private static func buildKey(_ base: String, year: String, title: String) -> String {
        let cleanBase = String(base.lowercased().replacing(nonAlnumRegex, with: "").prefix(12))
        let firstWord = title.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .first(where: { $0.count > 3 && $0.wholeMatch(of: lowerAlphaRegex) != nil }) ?? "work"
        return "\(cleanBase)\(year)\(firstWord)"
    }

    private static func formatAuthors(_ authorsStr: String?) -> String {
        guard let authorsStr, !authorsStr.isBlank else { return "" }
        return authorsStr
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " and ")
    }

    /// LaTeX special-character escaping, applied in the exact Kotlin order (`& % $ # _`). Port of
    /// `escapeLatex(text)`.
    private static func escapeLatex(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "\\&")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "#", with: "\\#")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    /// Year resolution: `sourceExtra."published":"YYYY` regex first, else `Calendar` year from
    /// `createdAt` (epoch-ms when `> 1e12`, else epoch-s). Port of `extractYear(bookmark)`.
    private static func extractYear(_ bookmark: Bookmark) -> String {
        if let raw = bookmark.sourceExtra,
           let match = raw.firstMatch(of: publishedYearRegex) {
            return String(match.1)
        }
        let epochMs = bookmark.createdAt
        let seconds: Int64 = epochMs > 1_000_000_000_000 ? epochMs / 1000 : epochMs
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let year = calendar.component(.year, from: date)
        return String(year)
    }

    private static let MONTHS = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"
    ]

    private static func substringBefore(_ s: String, _ delimiter: String) -> String {
        if let range = s.range(of: delimiter) {
            return String(s[s.startIndex..<range.lowerBound])
        }
        return s
    }

    private static func optStringElement(_ array: [Any], _ index: Int) -> String? {
        guard index < array.count else { return nil }
        let value = array[index]
        if value is NSNull { return nil }
        if let str = value as? String { return str }
        return "\(value)"
    }

    // MARK: - Regexes

    /// `\d{4}-(\d{2})` — month group inside a published date.
    private nonisolated(unsafe) static let monthRegex = /\d{4}-(\d{2})/
    /// `[^a-z0-9]` — non-alphanumeric strip for the cite-key base.
    private nonisolated(unsafe) static let nonAlnumRegex = /[^a-z0-9]/
    /// `[a-z]+` — all-lowercase-letters title-word match.
    private nonisolated(unsafe) static let lowerAlphaRegex = /[a-z]+/
    /// `"published"\s*:\s*"(\d{4})` — year out of the raw `sourceExtra` JSON string.
    private nonisolated(unsafe) static let publishedYearRegex = /"published"\s*:\s*"(\d{4})/
}

// MARK: - org.json-style helpers

private extension String {
    /// Kotlin `takeIf { it.isNotBlank() }` parity. (`isBlank` is provided by CurioComponents.swift.)
    var nonBlank: String? { isBlank ? nil : self }
}

/// Lenient read view over a parsed `sourceExtra` object, mirroring `org.json.JSONObject` `optString`
/// / `optJSONArray` (returns "" / nil for missing or wrong-typed keys; never throws).
private struct ParsedExtra {
    private let obj: [String: Any]
    init(_ obj: [String: Any]) { self.obj = obj }

    func optString(_ key: String) -> String {
        guard let value = obj[key], !(value is NSNull) else { return "" }
        if let s = value as? String { return s }
        if let b = value as? Bool { return b ? "true" : "false" }
        if let n = value as? NSNumber { return n.stringValue }
        return "\(value)"
    }

    func optJSONArray(_ key: String) -> [Any]? {
        obj[key] as? [Any]
    }
}

// MARK: - Ordered JSON for byte-faithful CSL-JSON 2-space output

/// A minimal ordered JSON value/object/array that reproduces `org.json`'s 2-space pretty printer so
/// the CSL-JSON export is byte-stable. (`org.json` backs `JSONObject` with a `HashMap`, so its key
/// order is JVM-implementation-defined; we serialize in **insertion order** instead — JSON objects are
/// semantically unordered and every CSL consumer is order-insensitive. See module risks.)
private enum OrderedJSONValue {
    case string(String)
    case int(Int)
    case object(OrderedJSON)
    case array(OrderedJSONArray)
}

private struct OrderedJSON {
    private(set) var entries: [(String, OrderedJSONValue)] = []

    mutating func put(_ key: String, _ value: String) { entries.append((key, .string(value))) }
    mutating func put(_ key: String, _ value: OrderedJSONValue) { entries.append((key, value)) }

    func toString(indentFactor: Int, indent: Int) -> String {
        if entries.isEmpty { return "{}" }
        var out = "{"
        if entries.count == 1 {
            let (k, v) = entries[0]
            out += quote(k) + ":" + (indentFactor > 0 ? " " : "") + writeValue(v, indentFactor: indentFactor, indent: indent)
        } else {
            let newIndent = indent + indentFactor
            var first = true
            for (k, v) in entries {
                if !first { out += "," }
                if indentFactor > 0 { out += "\n" }
                out += spaces(newIndent)
                out += quote(k) + ":" + (indentFactor > 0 ? " " : "")
                out += writeValue(v, indentFactor: indentFactor, indent: newIndent)
                first = false
            }
            if indentFactor > 0 { out += "\n" }
            out += spaces(indent)
        }
        out += "}"
        return out
    }
}

private struct OrderedJSONArray {
    private(set) var values: [OrderedJSONValue] = []
    mutating func add(_ value: OrderedJSONValue) { values.append(value) }

    func toString(indentFactor: Int, indent: Int) -> String {
        if values.isEmpty { return "[]" }
        var out = "["
        if values.count == 1 {
            out += writeValue(values[0], indentFactor: indentFactor, indent: indent)
        } else {
            let newIndent = indent + indentFactor
            var first = true
            for v in values {
                if !first { out += "," }
                if indentFactor > 0 { out += "\n" }
                out += spaces(newIndent)
                out += writeValue(v, indentFactor: indentFactor, indent: newIndent)
                first = false
            }
            if indentFactor > 0 { out += "\n" }
            out += spaces(indent)
        }
        out += "]"
        return out
    }
}

private func writeValue(_ value: OrderedJSONValue, indentFactor: Int, indent: Int) -> String {
    switch value {
    case let .string(s): return quote(s)
    case let .int(i): return String(i)
    case let .object(o): return o.toString(indentFactor: indentFactor, indent: indent)
    case let .array(a): return a.toString(indentFactor: indentFactor, indent: indent)
    }
}

private func spaces(_ n: Int) -> String { String(repeating: " ", count: max(0, n)) }

/// `org.json.JSONObject.quote` — wraps in double quotes, escaping the JSON control chars plus `/`
/// (org.json escapes `</` as `<\/`; here we escape `/` only when preceded by `<`, matching org.json).
private func quote(_ s: String) -> String {
    var out = "\""
    var previous: Character = "\u{0000}"
    for c in s {
        switch c {
        case "\\", "\"":
            out.append("\\"); out.append(c)
        case "/":
            if previous == "<" { out.append("\\") }
            out.append(c)
        case "\u{08}": out += "\\b"
        case "\t": out += "\\t"
        case "\n": out += "\\n"
        case "\u{0C}": out += "\\f"
        case "\r": out += "\\r"
        default:
            if c < " " || (c >= "\u{0080}" && c < "\u{00a0}") || (c >= "\u{2000}" && c < "\u{2100}") {
                let scalar = c.unicodeScalars.first!.value
                out += String(format: "\\u%04x", scalar)
            } else {
                out.append(c)
            }
        }
        previous = c
    }
    out += "\""
    return out
}
