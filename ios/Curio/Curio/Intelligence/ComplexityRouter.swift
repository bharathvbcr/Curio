import Foundation

/// Router decision: `tier` is surfaced in the chat UI, `reasoningEffort` is fed to xAI.
struct RouteDecision: Sendable {
    let tier: String            // "fast" | "deep"
    let reasoningEffort: String // GrokReasoning.*
    let complexityScore: Float
}

/// Query-complexity router. The app generates via a single xAI flagship model, so complexity maps
/// to xAI's `reasoning_effort` (thinking-token budget) rather than a model tier. Port of the Kotlin
/// `ComplexityRouter` (length + syntax + lexical richness; the embedding "domain" signal is dropped).
struct ComplexityRouter: Sendable {
    var complexityThreshold: Float = 0.45
    var lengthSaturationTokens: Int = 100
    var richnessSaturationTokens: Int = 60

    func route(_ query: String) -> RouteDecision {
        let tokens = query.split { $0.isWhitespace }.map(String.init)
        let length = min(Float(tokens.count) / Float(lengthSaturationTokens), 1)

        var syntax: Float = 0
        if Self.matches(Self.codePattern, in: query) { syntax += 0.6 }
        if Self.matches(Self.multiStepPattern, in: query) { syntax += 0.4 }
        syntax = min(syntax, 1)

        let distinct = Set(tokens.map { $0.lowercased() }).count
        let richness = min(Float(distinct) / Float(richnessSaturationTokens), 1)

        // Weights (0.30/0.40/0.30) redistribute the Python model's domain weight; they sum to 1.
        let score = 0.30 * length + 0.40 * syntax + 0.30 * richness

        if score >= complexityThreshold {
            return RouteDecision(tier: "deep", reasoningEffort: GrokReasoning.high, complexityScore: score)
        }
        return RouteDecision(tier: "fast", reasoningEffort: GrokReasoning.low, complexityScore: score)
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let codePattern = "```|def |class |function |import |SELECT |for \\(|while \\("
    private static let multiStepPattern =
        "\\b(step \\d|first,|second,|then |finally |compare |analyze |explain why|prove )\\b"
}
