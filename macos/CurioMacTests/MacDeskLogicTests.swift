import Foundation
import Testing
@testable import Curio

/// Property and fuzz tests for the desk's pure logic: sorting, exports, and editing rules.
@Suite("Mac desk logic")
struct MacDeskLogicTests {

    // MARK: - Sorting and scopes

    @Test("each sort is total and stable across shuffles")
    func sortsAreDeterministic() {
        var generator = SeededGenerator(seed: 7)
        let names = ["ada", "Ada", "Émile", "zoe", "", "bob", "ÅSA"]
        var items: [Bookmark] = []
        for index in 0..<400 {
            let title: String? = index % 5 == 0 ? nil : names[index % names.count] + " title"
            let author: String? = index % 3 == 0 ? nil : names[(index * 7) % names.count]
            let id = "id" + String(1000 + index)
            items.append(item(id: id, text: "post \(index % 17)", createdAt: Int64(index % 23), title: title, authorName: author))
        }
        for sort in DeskSort.allCases {
            let reference = MacDeskLibrary.sorted(items, by: sort).map(\.id)
            #expect(Set(reference).count == items.count)
            for _ in 0..<5 {
                let again = MacDeskLibrary.sorted(items.shuffled(using: &generator), by: sort).map(\.id)
                #expect(again == reference, "\(sort) is not stable")
            }
        }
        let oldest = MacDeskLibrary.visible(items, scope: .library, query: "", sort: .oldest)
        #expect(oldest.first?.createdAt == 0)
        let byAuthor = MacDeskLibrary.sorted(items, by: .author)
        // Bookmarks with no author sink to the end.
        let firstBlank = byAuthor.firstIndex { MacDeskLibrary.byline($0) == nil } ?? byAuthor.count
        #expect(byAuthor[firstBlank...].allSatisfy { MacDeskLibrary.byline($0) == nil })
    }

    @Test("ten thousand bookmarks sort and filter quickly")
    func largeLibrary() {
        var items: [Bookmark] = []
        for index in 0..<10_000 {
            let created = Int64(index * 7 % 9_973)
            items.append(item(id: "b\(index)", text: "text \(index) about topic \(index % 50)", createdAt: created, title: "Title \(index % 997)"))
        }
        let start = Date()
        for sort in DeskSort.allCases {
            _ = MacDeskLibrary.visible(items, scope: .library, query: "topic 7", sort: sort)
        }
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test("the notes scope only holds bookmarks with a real note")
    func annotatedScope() {
        let items = [
            item(id: "a", notes: "keep"),
            item(id: "b", notes: "   \n"),
            item(id: "c", notes: nil)
        ]
        #expect(MacDeskLibrary.visible(items, scope: .annotated, query: "").map(\.id) == ["a"])
        #expect(MacDeskLibrary.count(items, scope: .annotated) == 1)
        #expect(MacDeskLibrary.scopeTitle(.annotated, spaces: []) == "With Notes")
        #expect(DeskScope.sidebar.contains(.annotated))
    }

    // MARK: - Editing rules

    @Test("space names are trimmed, bounded, and unique ignoring case")
    func spaceNames() {
        let spaces = [
            Space(id: "1", userId: "u", name: "Papers", color: 0, icon: "folder", createdAt: 0),
            Space(id: "2", userId: "u", name: "Café", color: 0, icon: "folder", createdAt: 0)
        ]
        #expect(MacDeskLibrary.normalizedSpaceName("  Deep \n\t Learning  ") == "Deep Learning")
        #expect(MacDeskLibrary.normalizedSpaceName(" \n ") == nil)
        #expect(MacDeskLibrary.spaceNameProblem("", existing: spaces) != nil)
        #expect(MacDeskLibrary.spaceNameProblem(" papers ", existing: spaces) != nil)
        #expect(MacDeskLibrary.spaceNameProblem("cafe", existing: spaces) != nil)
        #expect(MacDeskLibrary.spaceNameProblem("Papers", existing: spaces, excluding: "1") == nil)
        #expect(MacDeskLibrary.spaceNameProblem(String(repeating: "x", count: 61), existing: spaces) != nil)
        #expect(MacDeskLibrary.spaceNameProblem("Robotics", existing: spaces) == nil)
    }

    @Test("every icon the desk offers resolves to its own symbol")
    func spaceIconsResolve() {
        for key in MacDeskLibrary.spaceIcons where key != "workspaces" {
            #expect(spaceIcon(key) != spaceIcon("definitely-unknown"), "\(key) falls back to the generic icon")
        }
        #expect(Set(MacDeskLibrary.spaceIcons).count == MacDeskLibrary.spaceIcons.count)
    }

    @Test("new bookmark text, notes, selection, and bulk toggles")
    func editingHelpers() {
        #expect(MacDeskLibrary.normalizedNewBookmark("  https://a.test  ") == "https://a.test")
        #expect(MacDeskLibrary.normalizedNewBookmark(" \n ") == nil)
        #expect(MacDeskLibrary.normalizedNewBookmark(String(repeating: "a", count: MacDeskLibrary.maxNewBookmarkLength + 1)) == nil)

        #expect(MacDeskLibrary.notesChanged(draft: "a ", saved: "a") == false)
        #expect(MacDeskLibrary.notesChanged(draft: "", saved: nil) == false)
        #expect(MacDeskLibrary.notesChanged(draft: "b", saved: "a"))
        #expect(MacDeskLibrary.notesChanged(draft: " ", saved: "a"))

        #expect(MacDeskLibrary.reconciledSelection(["a", "b", "z"], visibleIds: ["a", "b", "c"]) == ["a", "b"])
        #expect(MacDeskLibrary.reconciledSelection([], visibleIds: ["a"]).isEmpty)

        let starred = item(id: "s", favorite: true)
        let plain = item(id: "p")
        #expect(MacDeskLibrary.bulkFavoriteTarget([starred, plain]))
        #expect(MacDeskLibrary.bulkFavoriteTarget([starred]) == false)
        #expect(MacDeskLibrary.bulkLaterTarget([plain]))
        #expect(MacDeskLibrary.counted(1, "bookmark") == "1 bookmark")
        #expect(MacDeskLibrary.counted(2, "bookmark") == "2 bookmarks")
    }

    @Test("only web links from a model can be opened")
    func safeLinks() {
        #expect(MacDeskLibrary.safeWebURL("https://example.com/a?b=1") != nil)
        #expect(MacDeskLibrary.safeWebURL(" http://example.com ") != nil)
        for hostile in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,hi", "https://", "ftp://x.test", "", "x-apple.systempreferences:", "curio-oauth://callback"] {
            #expect(MacDeskLibrary.safeWebURL(hostile) == nil, "\(hostile)")
        }
    }

    // MARK: - Exports

    @Test("CSV survives quotes, commas, and line breaks")
    func csvRoundTrip() throws {
        var generator = SeededGenerator(seed: 99)
        let pieces = ["\"", ",", "\n", "\r\n", "é", "😀", " ", "a", "b", ";", "\t", "=cmd"]
        var items: [Bookmark] = []
        for index in 0..<60 {
            var text = ""
            for _ in 0..<Int.random(in: 0..<20, using: &generator) {
                text += pieces.randomElement(using: &generator)!
            }
            let note: String? = text.isEmpty ? nil : text
            items.append(item(id: "id,\(index)\"", text: text, title: "T" + String(text.prefix(5)), notes: note))
        }
        let rows = parseCSV(MacDeskLibrary.csvExport(items))
        #expect(rows.count == items.count + 1)
        #expect(rows.first?.count == 12)
        for (row, bookmark) in zip(rows.dropFirst(), items) {
            #expect(row.count == 12)
            #expect(row[0] == bookmark.id)
            #expect(row[11] == bookmark.text)
            #expect(row[10] == (bookmark.notes ?? ""))
        }
    }

    @Test("JSON backup round-trips every field")
    func jsonRoundTrip() throws {
        let items = [
            item(id: "a", text: "quote \" and \\ slash / and 😀", title: "T", url: "https://a.test/x?y=1", notes: "n", spaceId: "s", favorite: true),
            item(id: "b", text: "", createdAt: -5)
        ]
        let text = MacDeskLibrary.jsonExport(items)
        let decoded = try JSONDecoder().decode([Bookmark].self, from: Data(text.utf8))
        #expect(decoded == items)
        #expect(MacDeskLibrary.jsonExport([]).trimmingCharacters(in: .whitespacesAndNewlines) == "[\n\n]" || MacDeskLibrary.jsonExport([]).contains("[]"))
    }

    @Test("BibTeX fallback entries keep braces balanced for any input")
    func bibtexFuzz() {
        var generator = SeededGenerator(seed: 5)
        let alphabet = Array("{}\\%$&#_~^ab \n\"@,=😀é")
        for index in 0..<500 {
            var noise = ""
            for _ in 0..<Int.random(in: 0..<30, using: &generator) {
                noise.append(alphabet.randomElement(using: &generator)!)
            }
            let bookmark = item(
                id: noise.isEmpty ? "" : "\(index)\(noise)",
                text: noise,
                title: noise,
                url: "https://example.com/\(noise.filter { !$0.isWhitespace })",
                authorName: noise
            )
            guard let entry = MacDeskLibrary.bibtexCitation(bookmark) else {
                Issue.record("expected an entry for a bookmark with a link")
                continue
            }
            #expect(bracesBalance(entry), "unbalanced: \(entry)")
            let key = entry.dropFirst("@misc{".count).prefix { $0 != "," }
            #expect(key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
            #expect(entry.split(separator: "\n").count == 7, "a field broke across lines")
        }
    }

    @Test("LaTeX escaping covers every special character")
    func latexEscaping() {
        #expect(MacDeskLibrary.latexEscaped("50% of $x & #1_a~b^c{d}\\") ==
                "50\\% of \\$x \\& \\#1\\_a\\textasciitilde{}b\\textasciicircum{}c\\{d\\}\\textbackslash{}")
        #expect(MacDeskLibrary.latexEscaped("line\nbreak\u{0}") == "line break")
    }

    @Test("Markdown export keeps one bullet per bookmark")
    func markdownExport() {
        let items = [
            item(id: "1", text: "x", title: "A [weird] *title*\nsecond line", url: "https://a.test/(paren) x", notes: "one\ntwo"),
            item(id: "2", text: "plain")
        ]
        let text = MacDeskLibrary.markdownExport(items, spaces: [])
        let bullets = text.split(separator: "\n").filter { $0.hasPrefix("- ") }
        #expect(bullets.count == 2)
        #expect(text.contains("\\[weird\\]"))
        #expect(text.contains("%29"))
        #expect(text.contains("  > one\n  > two"))
    }

    @Test("export filenames cannot escape the chosen folder")
    func exportNames() {
        let name = MacDeskLibrary.exportFilename(scopeTitle: "../../etc/passwd", format: .bibtex)
        #expect(!name.contains("/"))
        #expect(name.hasSuffix(".bib"))
        #expect(MacDeskLibrary.exportFilename(scopeTitle: "   ", format: .json) == "Curio – Curio.json")
        for format in DeskExportFormat.allCases {
            #expect(MacDeskLibrary.exportableCount([], format: format) == 0)
            _ = MacDeskLibrary.exportText([], format: format, spaces: [])
        }
        let plain = [item(id: "p", text: "no link here")]
        #expect(MacDeskLibrary.exportableCount(plain, format: .markdown) == 1)
        #expect(MacDeskLibrary.exportableCount(plain, format: .bibtex) == 0)
    }

    @Test("dates read epoch milliseconds and older epoch seconds alike")
    func dates() {
        #expect(MacDeskLibrary.isoDay(1_700_000_000_000) == "2023-11-14")
        #expect(MacDeskLibrary.isoDay(1_700_000_000) == "2023-11-14")
        #expect(MacDeskLibrary.year(0) == "1970")
    }

    // MARK: - Helpers

    private func item(
        id: String,
        text: String = "body",
        createdAt: Int64 = 1,
        title: String? = nil,
        url: String? = nil,
        notes: String? = nil,
        spaceId: String? = nil,
        favorite: Bool = false,
        authorName: String? = nil
    ) -> Bookmark {
        Bookmark(
            id: id, text: text, createdAt: createdAt, userId: "u", title: title, url: url,
            isFavorite: favorite, authorName: authorName, spaceId: spaceId, notes: notes
        )
    }

    /// Unescaped `{` and `}` must pair up.
    private func bracesBalance(_ text: String) -> Bool {
        var depth = 0
        var escaped = false
        for character in text {
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1; if depth < 0 { return false } }
        }
        return depth == 0
    }

    /// Minimal RFC 4180 reader for the round-trip check.
    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                row.append(field)
                field = ""
            } else if character == "\r\n" || character == "\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        characters.removeAll()
        return rows
    }
}
