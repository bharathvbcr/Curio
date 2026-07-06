import Foundation
import os

// ---------------------------------------------------------------------------
// Result / config value types (CONVENTIONS §1: owned by this file; the AI module's
// `TextGenerator` consumes them). Direct port of the `data class`es in `data/XAiAnalyzer.kt`.
// ---------------------------------------------------------------------------

/// Tuning for a single analysis request. Port of `AnalysisConfig`.
struct AnalysisConfig: Sendable, Equatable {
    /// When `true`, skip the cloud call and run the offline keyword classifier.
    let forceLocal: Bool

    init(forceLocal: Bool = false) {
        self.forceLocal = forceLocal
    }
}

/// Structured bookmark analysis. Port of `AnalysisResult`.
struct AnalysisResult: Sendable, Equatable {
    let summary: String
    let tags: [String]
    let category: String
    /// JSON: `{models:[], methods:[], datasets:[], metrics:[]}`.
    let entities: String?
    let usedLocalAnalysis: Bool

    init(summary: String, tags: [String], category: String, entities: String?, usedLocalAnalysis: Bool) {
        self.summary = summary
        self.tags = tags
        self.category = category
        self.entities = entities
        self.usedLocalAnalysis = usedLocalAnalysis
    }
}

/// A chat reply plus any source URLs xAI Live Search grounded it in. Port of `ChatResponse`.
struct ChatResponse: Sendable, Equatable {
    let text: String
    let citations: [String]

    init(text: String, citations: [String] = []) {
        self.text = text
        self.citations = citations
    }
}

/// Long-form deep analysis. Port of `DeepAnalysisResult` (incl. its `formatted()` markdown).
struct DeepAnalysisResult: Sendable, Equatable {
    let contribution: String
    let significance: String
    let caveats: String

    /// Mirrors the Kotlin `formatted()`: `appendLine` adds a trailing `\n`, the final `append`
    /// does not, and the whole thing is `trim()`-med. Blank sections are skipped.
    func formatted() -> String {
        var result = ""
        if !contribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result += "**Contribution:** \(contribution)\n"
        }
        if !significance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result += "**Significance:** \(significance)\n"
        }
        if !caveats.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result += "**Caveats:** \(caveats)"
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Resolves the runtime xAI API key + "is configured" check.
///
/// The Android analyzer reads the process-global `XaiKeyStore` directly. To keep the Networking
/// module dependent only on Domain (CONVENTIONS §2 constructor injection), the analyzer takes a
/// resolver; the Auth module's `XaiKeyStore` conforms to it. `isConfigured()` mirrors the Android
/// rule (BYOK): a non-blank user-supplied key has been saved in Settings.
protocol XaiKeyResolving: Sendable {
    func resolve() -> String
    func isConfigured() -> Bool
}

// ---------------------------------------------------------------------------
// XAiAnalyzer — cloud bookmark analysis + image vision + chat + digest.
// Direct port of `class XAiAnalyzer(private val xAiApi: XAiApi)`.
// ---------------------------------------------------------------------------

/// Cloud (xAI Grok) analysis engine: structured bookmark analysis (text + vision), deep analysis,
/// chat responses (with optional Live Search grounding) and the weekly digest. All work runs off
/// the main actor. Errors are propagated from `analyzeBookmark` / `deepAnalyzeBookmark` /
/// `generateWeeklyDigest` (the caller surfaces a clear state); `analyzeImageBookmark` and
/// `generateChatResponse` swallow failures with text-only / message fallbacks, byte-faithful to the
/// Kotlin original.
final class XAiAnalyzer: Sendable {

    private let xAiApi: XAiApi
    private let keyResolver: XaiKeyResolving
    private static let logger = Logger(subsystem: "com.curio.app", category: "XAiAnalyzer")

    init(xAiApi: XAiApi, keyResolver: XaiKeyResolving) {
        self.xAiApi = xAiApi
        self.keyResolver = keyResolver
    }

    // MARK: - Prompt constants (verbatim from Kotlin `trimIndent()`)

    /// `SYSTEM_INSTRUCTION` — kept byte-identical (the JSON-contract wording is load-bearing).
    private static let systemInstruction = """
    You are a specialized AI/ML research curator for Curio. Analyze the provided research content and
    return ONLY a valid JSON object with exactly these fields:
    - "summary": concise TL;DR one-liner (max 100 chars)
    - "category": one value from ["architectures","training","inference-opt","datasets","evals","agents","multimodal","theory","systems","other"]
    - "tags": array of 1-4 specific lowercase tags (e.g. "mamba", "state-space-model", "flash-attention-3")
    - "entities": object with four arrays: "models" (model/arch names), "methods" (algorithmic methods), "datasets" (dataset/benchmark names), "metrics" (performance metrics)
    Return only JSON. No markdown.
    """

    /// `CATEGORY_GUIDE` — kept byte-identical.
    private static let categoryGuide = """
    category guide:
    - architectures: attention, SSMs/Mamba/S4/Hyena, linear attention, MoE, transformer variants
    - training: pretraining, RLHF, DPO, PPO, SFT, distillation, quantization, LoRA, QLoRA, fine-tuning
    - inference-opt: KV-cache, speculative decoding, FlashAttention, vLLM, PagedAttention, batching, kernels
    - datasets: training corpora, benchmark datasets, evaluation suites
    - evals: model evaluations, benchmarks, leaderboards, capability studies
    - agents: agentic workflows, tool-use, function-calling, autonomous agents, RAG, orchestration
    - multimodal: vision-language models, image/audio/video generation, VLMs, CLIP
    - theory: mathematical analysis, convergence, generalization, optimization theory
    - systems: distributed training, serving infrastructure, MLOps, hardware accelerators
    """

    /// Stop words for the offline keyword tag extraction — verbatim from the Kotlin `stopWords` set.
    private static let stopWords: Set<String> = [
        "about", "their", "there", "would", "bookmark", "https", "tweet",
        "thread", "paper", "model", "models", "using", "neural", "learning", "which"
    ]

    // MARK: - analyzeBookmark

    /// Structured text analysis. When `config.forceLocal` is set, runs the offline simulation;
    /// otherwise calls xAI (throwing when the key is missing or the call fails — the caller surfaces
    /// the state). Port of `analyzeBookmark`.
    func analyzeBookmark(
        text: String,
        ocrText: String?,
        config: AnalysisConfig,
        sourceAbstract: String? = nil
    ) async throws -> AnalysisResult {
        if config.forceLocal {
            return localSimulate(text: text, ocrText: ocrText)
        }

        Self.logger.debug("Calling xAI API for analysis...")
        let apiKey = keyResolver.resolve()
        guard keyResolver.isConfigured() else {
            throw XAiAnalyzerError.missingKey("xAI API key is missing. Add your key in Settings.")
        }

        var content = ""
        if let abstract = sourceAbstract, !abstract.isBlank {
            content += "Abstract: \(abstract)\n\n"
        }
        content += "Content: \(text)"
        if let ocr = ocrText, !ocr.isBlank {
            content += "\n\nOCR: \(ocr)"
        }

        let prompt = "\(Self.categoryGuide)\n\nAnalyze:\n\(content)"
        let request = XAiRequest(
            model: GrokModels.analysis,
            messages: [
                XAiMessage(role: "system", content: Self.systemInstruction),
                XAiMessage(role: "user", content: prompt)
            ],
            temperature: 0.3,
            responseFormat: .jsonObject,
            // Cheap, fast structured extraction — no deep reasoning needed.
            reasoningEffort: GrokReasoning.low
        )

        do {
            let response = try await xAiApi.chatCompletions(authorization: "Bearer \(apiKey)", request: request)
            guard let jsonText = response.choices?.first?.message.content else {
                throw XAiAnalyzerError.emptyResponse("Empty response from xAI")
            }
            return parseAnalysisResult(Self.cleanJsonFence(jsonText))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("xAI analysis error")
            throw error
        }
    }

    // MARK: - analyzeImageBookmark

    /// Vision-grounded analysis: lets Grok actually SEE the image, then returns the same
    /// ``AnalysisResult``. Falls back to text-only ``analyzeBookmark(text:ocrText:config:sourceAbstract:)``
    /// when the key is missing or the vision call fails, so callers never lose the analysis entirely.
    /// Port of `analyzeImageBookmark`.
    func analyzeImageBookmark(
        imageUrl: String,
        text: String,
        ocrText: String?,
        sourceAbstract: String? = nil
    ) async throws -> AnalysisResult {
        let apiKey = keyResolver.resolve()
        guard keyResolver.isConfigured() else {
            return try await analyzeBookmark(
                text: text, ocrText: ocrText, config: AnalysisConfig(forceLocal: false), sourceAbstract: sourceAbstract
            )
        }
        do {
            var content = ""
            if let abstract = sourceAbstract, !abstract.isBlank {
                content += "Abstract: \(abstract)\n\n"
            }
            content += "Content: \(text)"
            if let ocr = ocrText, !ocr.isBlank {
                content += "\n\nOCR: \(ocr)"
            }
            let prompt = "\(Self.categoryGuide)\n\nRead the attached image and analyze together with:\n\(content)"
            let request = XAiVisionRequest(
                model: GrokModels.vision,
                messages: [
                    XAiVisionMessage(role: "system", content: [XAiContentPart.text(Self.systemInstruction)]),
                    XAiVisionMessage(
                        role: "user",
                        content: [
                            XAiContentPart.image(imageUrl, detail: "high"),
                            XAiContentPart.text(prompt)
                        ]
                    )
                ],
                temperature: 0.3
            )
            let response = try await xAiApi.visionCompletions(authorization: "Bearer \(apiKey)", request: request)
            guard let jsonText = response.choices?.first?.message.content else {
                throw XAiAnalyzerError.emptyResponse("Empty vision response from xAI")
            }
            return parseAnalysisResult(Self.cleanJsonFence(jsonText))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("xAI vision analysis failed; falling back to text")
            return try await analyzeBookmark(
                text: text, ocrText: ocrText, config: AnalysisConfig(forceLocal: false), sourceAbstract: sourceAbstract
            )
        }
    }

    // MARK: - deepAnalyzeBookmark

    /// Long-form contribution/significance/caveats. Throws when the key is missing. Port of
    /// `deepAnalyzeBookmark`.
    func deepAnalyzeBookmark(
        text: String,
        ocrText: String?,
        sourceAbstract: String?
    ) async throws -> DeepAnalysisResult {
        let apiKey = keyResolver.resolve()
        guard keyResolver.isConfigured() else {
            throw XAiAnalyzerError.missingKey("xAI API key required for deep analysis")
        }

        var content = ""
        if let abstract = sourceAbstract, !abstract.isBlank {
            content += "Abstract: \(abstract)\n\n"
        }
        content += "Tweet/Content: \(text)"
        if let ocr = ocrText, !ocr.isBlank {
            content += "\n\nOCR: \(ocr)"
        }

        // Verbatim from the Kotlin `trimIndent()` block (interpolated `content` appended at the end).
        let prompt = """
        Analyze this AI/ML research item. Return JSON with exactly 3 fields:
        - "contribution": the specific technical contribution (1-2 sentences)
        - "significance": why this matters for the field (1-2 sentences)
        - "caveats": limitations or open questions (1 sentence)

        Content:
        \(content)
        """

        let request = XAiRequest(
            model: GrokModels.deepAnalysis,
            messages: [
                XAiMessage(role: "system", content: "You are an AI/ML research analyst. Return only valid JSON."),
                XAiMessage(role: "user", content: prompt)
            ],
            temperature: 0.3,
            responseFormat: .jsonObject,
            // Deep synthesis benefits from full reasoning.
            reasoningEffort: GrokReasoning.high
        )

        let response = try await xAiApi.chatCompletions(authorization: "Bearer \(apiKey)", request: request)
        guard let jsonText = response.choices?.first?.message.content else {
            throw XAiAnalyzerError.emptyResponse("Empty response from xAI")
        }

        let obj = Self.parseObject(Self.cleanJsonFence(jsonText))
        return DeepAnalysisResult(
            contribution: Self.optString(obj, "contribution"),
            significance: Self.optString(obj, "significance"),
            caveats: Self.optString(obj, "caveats")
        )
    }

    // MARK: - generateChatResponse

    /// Generates a chat reply. When `searchParameters` is non-nil, xAI Live Search is enabled (the
    /// model can ground in real-time Web / X / News and return citations). Never throws — connection
    /// failures map to a user-facing message string. Port of `generateChatResponse`.
    ///
    /// (DESIGN names the prompt parameter `contextPrompt`; the Kotlin caller passes
    /// `ChatPromptBuilder.Parts.contextPrompt` here.)
    func generateChatResponse(
        contextPrompt: String,
        systemInstruction: String = "You are a helpful AI assistant.",
        searchParameters: XAiSearchParameters? = nil,
        reasoningEffort: String? = nil
    ) async -> ChatResponse {
        let apiKey = keyResolver.resolve()
        guard keyResolver.isConfigured() else {
            return ChatResponse(text: "xAI API key is missing. Add your key in Settings.")
        }
        let request = XAiRequest(
            model: GrokModels.chat,
            messages: [
                XAiMessage(role: "system", content: systemInstruction),
                XAiMessage(role: "user", content: contextPrompt)
            ],
            temperature: 0.7,
            reasoningEffort: reasoningEffort,
            searchParameters: searchParameters
        )
        do {
            let response = try await xAiApi.chatCompletions(authorization: "Bearer \(apiKey)", request: request)
            let text = response.choices?.first?.message.content ?? "No response generated by xAI assistant."
            return ChatResponse(text: text, citations: response.citations ?? [])
        } catch let error {
            let detail = (error as? LocalizedError)?.errorDescription
                ?? (error as NSError).localizedDescription
            let message = detail.isEmpty ? "Unknown networking error" : detail
            return ChatResponse(text: "Connection failed: \(message). Check your xAI API key in Settings.")
        }
    }

    // MARK: - generateWeeklyDigest

    /// Generates a themed markdown digest of recent saves. `itemsBlock` is a pre-formatted
    /// one-line-per-item list. Throws when the key is absent so the caller can surface a clear
    /// "key required" state. Port of `generateWeeklyDigest`.
    func generateWeeklyDigest(_ itemsBlock: String, count itemCount: Int) async throws -> String {
        let apiKey = keyResolver.resolve()
        guard keyResolver.isConfigured() else {
            throw XAiAnalyzerError.missingKey("xAI API key required for the weekly digest")
        }

        // Verbatim from the Kotlin `trimIndent()` block.
        let prompt = """
        Below are \(itemCount) research items I saved this week. Write a concise weekly digest in markdown:
        - One **TL;DR** line capturing the week's themes.
        - 2–4 `## Theme` sections grouping related items, each a short paragraph on what's notable and how the items connect.
        - A final `## Worth a closer look` list of the 1–3 most significant items and why.
        Keep it tight and skimmable. Do not invent items beyond those listed.

        Items:
        \(itemsBlock)
        """

        let request = XAiRequest(
            model: GrokModels.deepAnalysis,
            messages: [
                XAiMessage(role: "system", content: "You are a research librarian writing a weekly digest. Output only markdown."),
                XAiMessage(role: "user", content: prompt)
            ],
            temperature: 0.5,
            reasoningEffort: GrokReasoning.medium
        )

        let response = try await xAiApi.chatCompletions(authorization: "Bearer \(apiKey)", request: request)
        guard let content = response.choices?.first?.message.content else {
            throw XAiAnalyzerError.emptyResponse("Empty response from xAI")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Parsing

    /// Port of `parseAnalysisResult`. Tolerant `org.json`-style navigation; `tags` may be a JSON
    /// array OR a comma-separated string (both lowercased + trimmed + filtered).
    private func parseAnalysisResult(_ json: String) -> AnalysisResult {
        let obj = Self.parseObject(json)

        let summary = Self.optString(obj, "summary", default: "No summary")

        let tags: [String]
        if let rawArray = obj["tags"] as? [Any] {
            tags = rawArray
                .map { "\($0)".lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else if let rawString = obj["tags"] as? String {
            tags = rawString
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            tags = []
        }

        let category = Self.optString(obj, "category", default: "other")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // entities: serialize the nested object back to a JSON string (or nil when absent/NULL).
        var entitiesJson: String? = nil
        if let entitiesValue = obj["entities"], !(entitiesValue is NSNull) {
            if let data = try? JSONSerialization.data(withJSONObject: entitiesValue, options: []),
               let str = String(data: data, encoding: .utf8) {
                entitiesJson = str
            } else if let scalar = entitiesValue as? String {
                entitiesJson = scalar
            }
        }

        return AnalysisResult(
            summary: summary,
            tags: tags,
            category: category,
            entities: entitiesJson,
            usedLocalAnalysis: false
        )
    }

    /// Port of `localSimulate` — the fully-offline keyword classifier. Summary is intentionally
    /// generic (`"⚡ [Local analysis]"`) so tweet/bookmark text never leaks into logs/UI.
    private func localSimulate(text: String, ocrText: String?) -> AnalysisResult {
        Self.logger.debug("Running local keyword simulation...")
        let combined = (text + " " + (ocrText ?? "")).lowercased()

        func has(_ terms: String...) -> Bool { terms.contains { combined.contains($0) } }

        let category: String
        if has("attention", "transformer", "mamba", "ssm", "state space", "moe",
               "mixture of experts", "linear attention", "hyena", "retention") {
            category = "architectures"
        } else if has("rlhf", "dpo", "ppo", "sft", "lora", "qlora", "fine-tun",
                      "pretraining", "distill", "quantiz", "instruction tun") {
            category = "training"
        } else if has("kv cache", "kv-cache", "speculative", "flashattention",
                      "flash attention", "vllm", "paged", "batching", "kernel") {
            category = "inference-opt"
        } else if has("dataset", "corpus", "benchmark data", "training data") {
            category = "datasets"
        } else if has("benchmark", "eval", "leaderboard", "mmlu", "humaneval", "hellaswag") {
            category = "evals"
        } else if has("agent", "tool use", "function call", "autonomous", "rag", "retrieval-augmented") {
            category = "agents"
        } else if has("multimodal", "vision", "image gen", "audio model", "video", "vlm", "clip", "diffusion") {
            category = "multimodal"
        } else if has("theory", "convergence", "proof", "regret bound", "generalization bound") {
            category = "theory"
        } else if has("distributed", "infrastructure", "serving", "mlops", "hardware", "gpu", "tpu") {
            category = "systems"
        } else if has("android", "kotlin", "compose", "mobile", "app") {
            category = "systems"
        } else {
            category = "other"
        }

        // Kotlin `split(Regex("[^a-zA-Z0-9-]+"))` then length>4, not a stop word, distinct, take 3.
        let rawWords = combined.split(whereSeparator: { ch in
            !(ch.isLetter || ch.isNumber || ch == "-") || ch > "\u{7F}"
        }).map(String.init)
        var seen = Set<String>()
        var words: [String] = []
        for word in rawWords where Self.isAsciiAlnumDash(word) {
            guard word.count > 4, !Self.stopWords.contains(word) else { continue }
            if seen.insert(word).inserted {
                words.append(word)
                if words.count == 3 { break }
            }
        }
        let tags = words.isEmpty ? ["curated"] : words

        return AnalysisResult(
            summary: "⚡ [Local analysis]",
            tags: tags,
            category: category,
            entities: nil,
            usedLocalAnalysis: true
        )
    }

    /// Mirrors Kotlin's `[^a-zA-Z0-9-]+` split: the kept tokens are pure ASCII letters/digits/dash.
    /// Non-ASCII characters are separators in the Kotlin regex, so a token containing any non-ASCII
    /// scalar would have been split — we guard the final tokens to the ASCII alnum/dash alphabet.
    private static func isAsciiAlnumDash(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 0x41 && scalar.value <= 0x5A) // A-Z
                || (scalar.value >= 0x61 && scalar.value <= 0x7A) // a-z
                || (scalar.value >= 0x30 && scalar.value <= 0x39) // 0-9
                || scalar.value == 0x2D // -
        }
    }

    /// Port of `cleanJsonFence` — strips markdown code fences then trims.
    private static func cleanJsonFence(_ raw: String) -> String {
        raw.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - org.json-style helpers

    /// Lenient parse to a dictionary (mirrors `JSONObject(json)` then `optString`/`opt`). Returns
    /// `[:]` when the payload is not a JSON object.
    private static func parseObject(_ json: String) -> [String: Any] {
        guard
            let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any]
        else {
            return [:]
        }
        return obj
    }

    /// Mirrors `JSONObject.optString(key, default)` — a non-string/absent value yields `default`.
    private static func optString(_ obj: [String: Any], _ key: String, default fallback: String = "") -> String {
        if let value = obj[key] {
            if let str = value as? String { return str }
            if value is NSNull { return fallback }
            return "\(value)"
        }
        return fallback
    }
}

/// Errors thrown by ``XAiAnalyzer`` for missing-key / empty-response conditions (mirrors the Kotlin
/// `Exception(...)` messages). `LocalizedError` so callers can surface the message.
enum XAiAnalyzerError: Error, LocalizedError, Equatable {
    case missingKey(String)
    case emptyResponse(String)

    var errorDescription: String? {
        switch self {
        case let .missingKey(message), let .emptyResponse(message):
            return message
        }
    }
}
