import Foundation
import Testing
@testable import Curio

/// Pure formatting helpers used across the feed/cards.
///
/// Port of `app/src/test/java/com/example/CurioFormatTest.kt` (JUnit + Robolectric). The iOS
/// implementation under test is `Curio/Screens/CurioFormat.swift`, which claims byte-faithful
/// parity with the Kotlin `ui/CurioFormat.kt` helpers — every expected value below is carried
/// over from the Android test verbatim.
@Suite("CurioFormat (mirrors CurioFormatTest.kt)")
struct CurioFormatTests {

    /// Mirrors the Kotlin `bm(...)` factory: only the fields the formatting helpers inspect.
    private func bm(
        sourceType: SourceType? = nil,
        authorName: String? = nil,
        url: String? = nil
    ) -> Bookmark {
        Bookmark(
            id: "1", text: "t", createdAt: 1_700_000_000_000, userId: "u",
            url: url, sourceType: sourceType, authorName: authorName
        )
    }

    /// Mirrors Kotlin `words(n)` — n copies of "word" joined by single spaces.
    private func words(_ n: Int) -> String {
        (1...n).map { _ in "word" }.joined(separator: " ")
    }

    /// Kotlin: `readingTime null for short posts, scales by word count`.
    @Test("readingTime nil for short posts, scales by word count")
    func readingTimeScalesByWordCount() {
        #expect(CurioFormat.readingTime("a short note") == nil)
        #expect(CurioFormat.readingTime(words(39)) == nil)
        // 50/200 -> round 0 -> floored to 1
        #expect(CurioFormat.readingTime(words(50)) == "1 min read")
        // 600/200 -> 3
        #expect(CurioFormat.readingTime(words(600)) == "3 min read")
    }

    /// Kotlin: `cleanSnippet strips urls but keeps a pure-url post intact`.
    @Test("cleanSnippet strips urls but keeps a pure-url post intact")
    func cleanSnippetStripsUrls() {
        let s = CurioFormat.cleanSnippet("read this https://example.com/x/y now")
        #expect(s.contains("read this"))
        #expect(s.contains("now"))
        #expect(!s.contains("http"))
        // Stripping a URL-only post would blank it, so it falls back to the original.
        #expect(CurioFormat.cleanSnippet("https://example.com") == "https://example.com")
    }

    /// Kotlin: `sourceDisplayName maps known sources and falls back to host`.
    @Test("sourceDisplayName maps known sources and falls back to host")
    func sourceDisplayNameMapsKnownSources() {
        #expect(CurioFormat.sourceDisplayName(bm(sourceType: .ARXIV)) == "arXiv")
        #expect(CurioFormat.sourceDisplayName(bm(sourceType: .GITHUB)) == "GitHub")
        #expect(CurioFormat.sourceDisplayName(bm(sourceType: .HUGGING_FACE)) == "Hugging Face")
        #expect(CurioFormat.sourceDisplayName(bm(sourceType: .DOI)) == "DOI")
        #expect(CurioFormat.sourceDisplayName(bm(url: "https://www.example.com/post/1")) == "example.com")
        #expect(CurioFormat.sourceDisplayName(bm()) == "Curio")
    }

    /// Kotlin: `authorInitial only for tweet-like entries`.
    @Test("authorInitial only for tweet-like entries")
    func authorInitialOnlyForTweets() {
        #expect(CurioFormat.authorInitial(bm(sourceType: .ARXIV, authorName: "Albert Gu")) == nil)
        #expect(CurioFormat.authorInitial(bm(authorName: "elon")) == Character("E"))
        #expect(CurioFormat.authorInitial(bm()) == nil) // no author
    }

    /// Kotlin: `displayAuthor prefers real author then source`.
    @Test("displayAuthor prefers real author then source")
    func displayAuthorPrefersRealAuthor() {
        #expect(CurioFormat.displayAuthor(bm(authorName: "Ada Lovelace")) == "Ada Lovelace")
        #expect(CurioFormat.displayAuthor(bm(sourceType: .GITHUB)) == "GitHub")
    }
}
