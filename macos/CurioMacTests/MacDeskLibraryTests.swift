import Foundation
import Testing
@testable import Curio

@Suite struct MacDeskLibraryTests {
    @Test func newestBookmarksComeFirstAndTiesBreakById() {
        let items = [
            mark(id: "b", createdAt: 20),
            mark(id: "c", createdAt: 10),
            mark(id: "a", createdAt: 20)
        ]
        let visible = MacDeskLibrary.visible(items, scope: .library, query: "  ")
        #expect(visible.map(\.id) == ["a", "b", "c"])
    }

    @Test func scopesComposeWithSearch() {
        let items = [
            mark(id: "star", text: "transformers", favorite: true, authorUsername: "ada"),
            mark(id: "later", text: "transformers", later: true),
            mark(id: "loose", text: "other", spaceId: nil),
            mark(id: "filed", text: "transformers", spaceId: "lab"),
            mark(id: "paper", text: "x", url: "https://example.com/papers", sourceTitle: "Attention")
        ]
        #expect(MacDeskLibrary.visible(items, scope: .favorites, query: "transformers").map(\.id) == ["star"])
        #expect(MacDeskLibrary.visible(items, scope: .later, query: "").map(\.id) == ["later"])
        #expect(MacDeskLibrary.visible(items, scope: .unfiled, query: "other").map(\.id) == ["loose"])
        #expect(MacDeskLibrary.visible(items, scope: .space("lab"), query: "nope").isEmpty)
        #expect(MacDeskLibrary.visible(items, scope: .library, query: "ada").map(\.id) == ["star"])
        #expect(MacDeskLibrary.visible(items, scope: .library, query: "example.com").map(\.id) == ["paper"])
        #expect(MacDeskLibrary.visible(items, scope: .library, query: "attention").map(\.id) == ["paper"])
        #expect(MacDeskLibrary.count(items, scope: .favorites) == 1)
        #expect(MacDeskLibrary.count(items, scope: .space("lab")) == 1)
    }

    @Test func titlesFallThroughAndTruncateTheFirstLine() {
        #expect(MacDeskLibrary.title(mark(id: "1", title: "  ")) == "body")
        #expect(MacDeskLibrary.title(mark(id: "1", text: "   ", title: "  ", sourceTitle: " Paper ")) == "Paper")
        #expect(MacDeskLibrary.title(mark(id: "1", text: "  \n")) == "Untitled")
        let long = String(repeating: "a", count: 90)
        #expect(MacDeskLibrary.title(mark(id: "1", text: long)) == String(repeating: "a", count: 80) + "…")
        #expect(MacDeskLibrary.excerpt(mark(id: "1", text: "Headline\n\nThe rest of it.", title: nil)) == "The rest of it.")
        #expect(MacDeskLibrary.excerpt(mark(id: "1", text: "Full body", title: "Named", summary: " Short ")) == "Short")
    }

    @Test func linksHostsAndBylines() {
        let web = mark(id: "99", url: "https://www.Example.com/a", authorName: "Ada Lovelace", authorUsername: "ada")
        #expect(MacDeskLibrary.host(web) == "example.com")
        #expect(MacDeskLibrary.link(web) == "https://www.Example.com/a")
        #expect(MacDeskLibrary.byline(web) == "Ada Lovelace · @ada")
        #expect(MacDeskLibrary.byline(mark(id: "same", authorName: "Ada", authorUsername: "ada")) == "Ada")
        let post = mark(id: "99", text: "hi", authorUsername: "@Ada")
        #expect(MacDeskLibrary.link(post) == "https://x.com/Ada/status/99")
        #expect(MacDeskLibrary.host(post) == "x.com")
        #expect(MacDeskLibrary.symbol(for: mark(id: "g", sourceType: .GITHUB)) == "chevron.left.forwardslash.chevron.right")
        #expect(MacDeskLibrary.symbol(for: mark(id: "plain", text: "note")) == "bookmark")
        #expect(MacDeskLibrary.shareText(web).contains("https://www.Example.com/a"))
    }

    @Test func spacesPinThenSortThenName() {
        let spaces = [
            space(id: "c", name: "zeta"),
            space(id: "b", name: "alpha", sort: 2),
            space(id: "a", name: "Alpha", pinned: true, sort: 9),
            space(id: "d", name: "alpha", sort: 2)
        ]
        #expect(MacDeskLibrary.orderedSpaces(spaces).map(\.id) == ["a", "c", "b", "d"])
        #expect(MacDeskLibrary.scopeTitle(.space("missing"), spaces: spaces) == "Space")
        #expect(MacDeskLibrary.scopePhrase(.library, spaces: spaces) == "the library")
        #expect(MacDeskLibrary.librarySummary(bookmarks: [mark(id: "1")], spaces: spaces) == "1 bookmark · 0 starred · 0 to read · 4 spaces")
    }

    @Test func researchPresentationReadsTheBriefAndHidesIdPayloads() {
        let brief = ResearchBrief(
            answer: " Yes ",
            claimBookmarkIds: ["a"],
            caveats: "Small sample",
            readingList: [" Read a "],
            citationURLs: ["https://example.com"],
            tier: "local"
        )
        let shown = DeskResearchPresentation.from(ok: true, code: nil, payload: brief.jsonText())
        #expect(shown.answer == "Yes")
        #expect(shown.caveats == "Small sample")
        #expect(shown.readingList == ["Read a"])
        #expect(shown.failure == nil)
        #expect(shown.hasBody)

        let missing = DeskResearchPresentation.from(ok: false, code: AgentFailure.keyMissing.rawValue, payload: "")
        #expect(missing.failure == "Add an xAI key to research on the web.")
        let blob = DeskResearchPresentation.from(ok: false, code: "nope", payload: "[\"a\"]")
        #expect(blob.failure == "Research could not finish.")
        let prose = DeskResearchPresentation.from(ok: false, code: nil, payload: " model down ")
        #expect(prose.failure == "model down")
    }
}

private func mark(
    id: String,
    text: String = "body",
    createdAt: Int64 = 0,
    title: String? = nil,
    url: String? = nil,
    summary: String? = nil,
    sourceTitle: String? = nil,
    sourceType: SourceType? = nil,
    favorite: Bool = false,
    later: Bool = false,
    authorName: String? = nil,
    authorUsername: String? = nil,
    spaceId: String? = nil
) -> Bookmark {
    Bookmark(
        id: id,
        text: text,
        createdAt: createdAt,
        userId: "u",
        title: title,
        url: url,
        summary: summary,
        sourceType: sourceType,
        sourceTitle: sourceTitle,
        isFavorite: favorite,
        isSavedForLater: later,
        authorName: authorName,
        authorUsername: authorUsername,
        spaceId: spaceId
    )
}

private func space(id: String, name: String, pinned: Bool = false, sort: Int = 0) -> Space {
    Space(
        id: id,
        userId: "u",
        name: name,
        color: 0,
        icon: "folder",
        createdAt: 0,
        isPinned: pinned,
        sortIndex: sort
    )
}
