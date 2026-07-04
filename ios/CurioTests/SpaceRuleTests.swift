import Foundation
import Testing
@testable import Curio

/// Tests the Smart Spaces auto-filing predicate (`SpaceRule`/`SpaceRules`) and its JSON codec.
/// This logic decides which bookmarks get filed into a Space, so correctness matters.
///
/// Port of `app/src/test/java/com/example/SpaceRuleTest.kt` (JUnit + Robolectric — Robolectric
/// only supplied the real `org.json` there; on iOS the codec is `JSONSerialization`, so the whole
/// suite is pure). Implementation under test: `Curio/Domain/SpaceRule.swift`.
///
/// Naming note: Kotlin `SpaceRules.EMPTY` is `SpaceRules.empty` on iOS (Swift constant style).
@Suite("SpaceRule (mirrors SpaceRuleTest.kt)")
struct SpaceRuleTests {

    /// Mirrors the Kotlin `bm(...)` factory covering every field the rule engine inspects.
    private func bm(
        text: String = "",
        title: String? = nil,
        summary: String? = nil,
        ocrText: String? = nil,
        sourceTitle: String? = nil,
        sourceAbstract: String? = nil,
        tags: [String] = [],
        category: String? = nil,
        sourceType: SourceType? = nil,
        authorName: String? = nil,
        authorUsername: String? = nil,
        sourceAuthors: String? = nil,
        url: String? = nil
    ) -> Bookmark {
        Bookmark(
            id: "1", text: text, createdAt: 1_700_000_000_000, userId: "u",
            title: title, url: url, summary: summary, tags: tags, category: category,
            ocrText: ocrText, sourceType: sourceType, sourceTitle: sourceTitle,
            sourceAuthors: sourceAuthors, sourceAbstract: sourceAbstract,
            authorName: authorName, authorUsername: authorUsername
        )
    }

    /// Kotlin: `keyword contains is case-insensitive across text fields`.
    @Test("keyword contains is case-insensitive across text fields")
    func keywordContainsIsCaseInsensitive() {
        let rule = SpaceRule(field: .KEYWORD, op: .CONTAINS, value: "Diffusion")
        #expect(rule.matches(bm(text: "a paper on latent diffusion models")))
        #expect(rule.matches(bm(sourceAbstract: "We study DIFFUSION sampling")))
        #expect(!rule.matches(bm(text: "a paper on transformers")))
    }

    /// Kotlin: `blank value never matches`.
    @Test("blank value never matches")
    func blankValueNeverMatches() {
        #expect(!SpaceRule(field: .KEYWORD, op: .CONTAINS, value: "   ").matches(bm(text: "anything")))
    }

    /// Kotlin: `each field is inspected`.
    @Test("each field is inspected")
    func eachFieldIsInspected() {
        #expect(SpaceRule(field: .TAG, op: .EQUALS, value: "mamba").matches(bm(tags: ["ssm", "Mamba"])))
        #expect(SpaceRule(field: .CATEGORY, op: .EQUALS, value: "architectures").matches(bm(category: "Architectures")))
        #expect(SpaceRule(field: .SOURCE, op: .EQUALS, value: "arxiv").matches(bm(sourceType: .ARXIV)))
        #expect(SpaceRule(field: .AUTHOR, op: .CONTAINS, value: "gu").matches(bm(sourceAuthors: "Albert Gu, Tri Dao")))
        #expect(SpaceRule(field: .URL, op: .STARTS_WITH, value: "https://github").matches(bm(url: "https://github.com/x/y")))
    }

    /// Kotlin: `ops behave distinctly`.
    @Test("ops behave distinctly")
    func opsBehaveDistinctly() {
        let b = bm(title: "FlashAttention")
        #expect(SpaceRule(field: .KEYWORD, op: .STARTS_WITH, value: "flash").matches(b))
        #expect(!SpaceRule(field: .KEYWORD, op: .EQUALS, value: "flash").matches(b))
        #expect(SpaceRule(field: .KEYWORD, op: .EQUALS, value: "flashattention").matches(b))
    }

    /// Kotlin: `rule set ANY vs ALL`.
    @Test("rule set ANY vs ALL")
    func ruleSetAnyVsAll() {
        let r1 = SpaceRule(field: .TAG, op: .EQUALS, value: "rag")
        let r2 = SpaceRule(field: .CATEGORY, op: .EQUALS, value: "agents")
        let b = bm(tags: ["rag"], category: "evals") // matches r1 only
        #expect(SpaceRules(match: .ANY, autoFile: true, rules: [r1, r2]).matches(b))
        #expect(!SpaceRules(match: .ALL, autoFile: true, rules: [r1, r2]).matches(b))
    }

    /// Kotlin: `match score prefers more specific smart space`.
    @Test("match score prefers more specific smart space")
    func matchScorePrefersMoreSpecificSmartSpace() {
        let broad = SpaceRule(field: .CATEGORY, op: .EQUALS, value: "agents")
        let narrow1 = SpaceRule(field: .TAG, op: .EQUALS, value: "rag")
        let narrow2 = SpaceRule(field: .CATEGORY, op: .EQUALS, value: "agents")
        let b = bm(tags: ["rag"], category: "agents")
        let broadRules = SpaceRules(match: .ANY, autoFile: true, rules: [broad])
        let narrowRules = SpaceRules(match: .ALL, autoFile: true, rules: [narrow1, narrow2])
        #expect(broadRules.matches(b))
        #expect(narrowRules.matches(b))
        #expect(broadRules.matchScore(b) == 1)
        #expect(narrowRules.matchScore(b) == 2)
    }

    /// Kotlin: `inactive when all rules are drafts`.
    @Test("inactive when all rules are drafts")
    func inactiveWhenAllRulesAreDrafts() {
        let draftsOnly = SpaceRules(match: .ANY, autoFile: true, rules: [SpaceRule(field: .TAG, op: .EQUALS, value: "")])
        #expect(!draftsOnly.isActive)
        #expect(!draftsOnly.matches(bm(tags: ["anything"])))
        #expect(!SpaceRules.empty.matches(bm(text: "x")))
    }

    /// Kotlin: `json round-trips and parsing is tolerant`.
    @Test("json round-trips and parsing is tolerant")
    func jsonRoundTripsAndParsingIsTolerant() {
        let rules = SpaceRules(
            match: .ALL, autoFile: false,
            rules: [
                SpaceRule(field: .KEYWORD, op: .CONTAINS, value: "diffusion"),
                SpaceRule(field: .SOURCE, op: .EQUALS, value: "ARXIV")
            ]
        )
        let restored = SpaceRules.fromJson(rules.toJson())
        #expect(restored.match == .ALL)
        #expect(!restored.autoFile)
        #expect(restored.rules.count == 2)
        #expect(restored.rules[0].value == "diffusion")

        // Tolerant: blank/garbage/unknown-enum inputs degrade to `.empty` or skip the bad rule.
        #expect(SpaceRules.fromJson(nil) == SpaceRules.empty)
        #expect(SpaceRules.fromJson("not json") == SpaceRules.empty)
        #expect(SpaceRules.fromJson(#"{"m":"ANY","a":true,"r":[{"f":"BOGUS","o":"EQUALS","v":"x"}]}"#).rules.isEmpty)
    }
}
