import Foundation
import Testing
@testable import Curio

/// Citation-export tests.
///
/// Port of `app/src/test/java/com/example/BibtexExporterTest.kt` (JUnit + Robolectric — Robolectric
/// only supplied `org.json` there; on iOS the exporter is pure Foundation). Implementation under
/// test: `Curio/Intelligence/BibtexExporter.swift`, which claims **byte-faithful** output parity
/// with the Kotlin `data/export/BibtexExporter.kt` (CONVENTIONS §10 export byte-fidelity), so every
/// expected substring below — including the exact column-alignment padding — is carried over from
/// the Android test verbatim. A divergence caught here is signal, not a reason to weaken the test.
@Suite("BibtexExporter (mirrors BibtexExporterTest.kt)")
struct BibtexExporterTests {

    /// Mirrors the Kotlin `arxiv()` fixture.
    private func arxiv() -> Bookmark {
        Bookmark(
            id: "t1", text: "great paper", createdAt: 1_700_000_000_000, userId: "u1",
            sourceType: .ARXIV, sourceId: "2312.00752",
            sourceTitle: "Mamba: Linear-Time Sequence Modeling",
            sourceAuthors: "Albert Gu, Tri Dao",
            sourceAbstract: "We introduce a selective state space model.",
            sourceExtra: #"{"published":"2023-12-01","categories":["cs.LG","cs.AI"]}"#
        )
    }

    /// Mirrors the Kotlin `doi()` fixture.
    private func doi() -> Bookmark {
        Bookmark(
            id: "t2", text: "doi paper", createdAt: 1_700_000_000_000, userId: "u1",
            sourceType: .DOI, sourceId: "10.1038/s41586-021-03819-2",
            sourceTitle: "Highly accurate protein structure prediction with AlphaFold",
            sourceAuthors: "John Jumper, Demis Hassabis",
            sourceAbstract: "AlphaFold predicts structures.",
            sourceExtra: #"{"doi":"10.1038/s41586-021-03819-2","published":"2021-07-15","container":"Nature"}"#
        )
    }

    /// Kotlin: `arxiv bibtex includes enriched fields`.
    @Test("arxiv bibtex includes enriched fields")
    func arxivBibtexIncludesEnrichedFields() throws {
        let b = try #require(BibtexExporter.toBibtex(arxiv()))
        #expect(b.contains("@article{"))
        #expect(b.contains("eprint        = {2312.00752}"))
        #expect(b.contains("archivePrefix = {arXiv}"))
        #expect(b.contains("primaryClass  = {cs.LG}"))
        #expect(b.contains("month         = {dec}"))
        #expect(b.contains("author        = {Albert Gu and Tri Dao}"))
        #expect(b.contains("abstract      = {"))
        #expect(b.contains("year          = {2023}"))
    }

    /// Kotlin: `doi bibtex uses journal and doi`.
    @Test("doi bibtex uses journal and doi")
    func doiBibtexUsesJournalAndDoi() throws {
        let b = try #require(BibtexExporter.toBibtex(doi()))
        #expect(b.contains("journal = {Nature}"))
        #expect(b.contains("doi     = {10.1038/s41586-021-03819-2}"))
        #expect(b.contains("https://doi.org/10.1038/s41586-021-03819-2"))
        #expect(b.contains("year    = {2021}"))
    }

    /// Kotlin: `ris export marks papers as journal articles`.
    @Test("ris export marks papers as journal articles")
    func risExportMarksPapersAsJournalArticles() throws {
        let ris = try #require(BibtexExporter.toRis(arxiv()))
        #expect(ris.hasPrefix("TY  - JOUR"))
        #expect(ris.contains("AU  - Albert Gu"))
        #expect(ris.contains("AU  - Tri Dao"))
        #expect(ris.contains("UR  - https://arxiv.org/abs/2312.00752"))
        // Kotlin `ris.trimEnd().endsWith("ER  -")` (leading trim is a no-op — the RIS starts "TY").
        #expect(ris.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("ER  -"))
    }

    /// Kotlin: `csl json carries split author names and doi`.
    @Test("csl json carries split author names and doi")
    func cslJsonCarriesSplitAuthorNamesAndDoi() throws {
        let csl = try #require(BibtexExporter.toCslJson(doi()))
        #expect(csl.contains(#""family": "Jumper""#))
        #expect(csl.contains(#""given": "John""#))
        #expect(csl.contains(#""DOI": "10.1038/s41586-021-03819-2""#))
        #expect(csl.contains(#""type": "article-journal""#))
    }

    /// Kotlin: `markdown export is a single linked bullet`.
    @Test("markdown export is a single linked bullet")
    func markdownExportIsASingleLinkedBullet() throws {
        let md = try #require(BibtexExporter.toMarkdown(arxiv()))
        #expect(md.hasPrefix("- "))
        #expect(md.contains("(2023)"))
        #expect(md.contains("[Mamba: Linear-Time Sequence Modeling](https://arxiv.org/abs/2312.00752)"))
    }

    /// Kotlin: `tweets and unresolved bookmarks have no citation`.
    @Test("tweets and unresolved bookmarks have no citation")
    func tweetsAndUnresolvedBookmarksHaveNoCitation() {
        let tweet = Bookmark(id: "x", text: "just a tweet", createdAt: 1_700_000_000_000, userId: "u1")
        #expect(BibtexExporter.toBibtex(tweet) == nil)
        #expect(BibtexExporter.toRis(tweet) == nil)
        #expect(BibtexExporter.toMarkdown(tweet) == nil)
    }

    /// Kotlin: `list export concatenates and skips non-sources`.
    @Test("list export concatenates and skips non-sources")
    func listExportConcatenatesAndSkipsNonSources() {
        let tweet = Bookmark(id: "x", text: "tweet", createdAt: 1_700_000_000_000, userId: "u1")
        let list = BibtexExporter.toBibtexList([arxiv(), tweet, doi()])
        // Kotlin: Regex("@article\\{").findAll(list).count() == 2.
        let occurrences = list.components(separatedBy: "@article{").count - 1
        #expect(occurrences == 2)
    }
}
