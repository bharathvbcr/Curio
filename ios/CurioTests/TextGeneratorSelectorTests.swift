import Foundation
import Testing
@testable import Curio

/// Stub generator that tags its result with a label so we can assert which backend ran.
/// Port of the Kotlin `LabelGenerator` from `TextGeneratorSelectorTest.kt`.
private struct LabelGenerator: TextGenerator {
    let name: String

    init(_ label: String) { self.name = label }

    func analyze(text: String, ocrText: String?, sourceAbstract: String?, imageUrl: String?) async throws -> AnalysisResult {
        AnalysisResult(
            summary: name, tags: [], category: "other", entities: nil,
            usedLocalAnalysis: name == "LOCAL"
        )
    }
}

/// A nano backend that always declines with `NanoUnavailable`, forcing the selector's cloud
/// fallback (see the suite doc comment for why this replaces Robolectric's guaranteed-unavailable
/// AICore).
private struct DecliningNanoGenerator: TextGenerator {
    let name = "NANO"

    func analyze(text: String, ocrText: String?, sourceAbstract: String?, imageUrl: String?) async throws -> AnalysisResult {
        throw NanoUnavailable.message("On-device model not available on this device")
    }
}

/// Backend-selection + language-gate tests.
///
/// Port of `app/src/test/java/com/example/TextGeneratorSelectorTest.kt` (JUnit + Robolectric).
/// Implementations under test: `Curio/AI/TextGenerator.swift` (`TextGeneratorSelector`) and
/// `Curio/AI/LanguageGate.swift`.
///
/// ENVIRONMENT NOTE (API mismatch vs the Android test): on Android, Robolectric guaranteed
/// `GenAiAvailability` reported UNAVAILABLE (no AICore on the JVM), so "Nano unavailable → cloud"
/// was deterministic with plain label stubs. The iOS `GenAiAvailability` is a concrete struct that
/// probes `SystemLanguageModel.default.availability` with **no injection seam**, so the gate's
/// outcome depends on the test host. To keep the ported assertion deterministic, the nano stub here
/// *itself* throws `NanoUnavailable` — the exact error the real on-device generator throws when the
/// gate rejects — so the selector must route to cloud whether the availability gate short-circuits
/// (host without Apple Intelligence) or nano is invoked and declines (host with it). Same contract,
/// both paths land on CLOUD.
@Suite("TextGeneratorSelector (mirrors TextGeneratorSelectorTest.kt)")
struct TextGeneratorSelectorTests {

    /// Mirrors the Kotlin `selector()` factory (see the suite doc for the nano-stub deviation).
    private func selector() -> TextGeneratorSelector {
        TextGeneratorSelector(
            nano: DecliningNanoGenerator(),
            cloud: LabelGenerator("CLOUD"),
            local: LabelGenerator("LOCAL"),
            availability: GenAiAvailability()
        )
    }

    /// Kotlin: `selector picks cloud when nano unavailable`.
    @Test("selector picks cloud when nano unavailable")
    func selectorPicksCloudWhenNanoUnavailable() async throws {
        let result = try await selector().analyze(
            text: "Some English research text", ocrText: nil, sourceAbstract: nil, forceLocal: false
        )
        #expect(result.summary == "CLOUD")
    }

    /// Kotlin: `selector picks local when user forces offline`.
    @Test("selector picks local when user forces offline")
    func selectorPicksLocalWhenUserForcesOffline() async throws {
        let result = try await selector().analyze(
            text: "Some English research text", ocrText: nil, sourceAbstract: nil, forceLocal: true
        )
        #expect(result.summary == "LOCAL")
    }

    /// Kotlin: `language gate detects EN JA KO and rejects others`.
    @Test("language gate detects EN JA KO and rejects others")
    func languageGateDetectsSupportedLanguages() {
        #expect(LanguageGate.detect("Linear-time sequence modeling") == .EN)
        #expect(LanguageGate.detect("これはテストです") == .JA)
        #expect(LanguageGate.detect("이것은 테스트입니다") == .KO)
        #expect(LanguageGate.detect("Это тест на русском") == .OTHER)
    }

    /// Kotlin: `language gate enforces word cap`.
    @Test("language gate enforces word cap")
    func languageGateEnforcesWordCap() {
        let short = String(repeating: "word ", count: 100)
        let long = String(repeating: "word ", count: 4_000)
        #expect(LanguageGate.withinCap(short))
        #expect(!LanguageGate.withinCap(long))
    }
}
