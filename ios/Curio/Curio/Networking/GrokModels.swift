import Foundation

/// Central registry of xAI Grok model IDs and capability tiers — the single source of truth so the
/// rest of the app never hardcodes a model string. Direct port of `object GrokModels` in
/// `data/remote/GrokModels.kt`.
///
/// xAI retired the grok-3 / grok-4 generation on 2026-05-15 (old IDs still resolve but are billed
/// at — and behave like — their successors), so the defaults below target the current `grok-4.3`
/// flagship. Swap a constant here to re-tune the whole stack; nothing else needs to change.
///
/// Caseless namespace enum (CONVENTIONS §1 "Enums as namespaces").
enum GrokModels {
    /// Flagship general model: 1M-token context, native vision (image input), reasoning, function
    /// calling and structured outputs. Cost/latency is tuned per-call with ``GrokReasoning``.
    static let flagship = "grok-4.3"

    /// Lightweight coding-tuned model (256k ctx), successor to grok-code-fast-1.
    static let coding = "grok-build-0.1"

    /// Image generation model served from `/v1/images/generations`. ($0.02/image)
    static let image = "grok-imagine-image"
    /// Higher-fidelity image generation model. ($0.05/image)
    static let imageQuality = "grok-imagine-image-quality"

    /// Structured bookmark analysis (JSON-schema enforced).
    static let analysis = flagship
    /// Long-form contribution/significance/caveats.
    static let deepAnalysis = flagship
    /// RAG + Live-Search research assistant.
    static let chat = flagship
    /// Image understanding (OCR-adjacent, figure reading).
    static let vision = flagship

    /// Text-embedding model. NOTE: as of 2026-06 xAI exposes embeddings only internally (behind the
    /// Collections feature) and ships NO public `/v1/embeddings` REST endpoint, so this call is
    /// best-effort and will typically return `nil` — the embedding provider selector already
    /// degrades to on-device EmbeddingGemma / recency fallback when that happens.
    static let embedding = "grok-embedding-small"
}

/// Allowed values for the `reasoning_effort` request field on reasoning-capable Grok models.
/// Ports `object GrokReasoning`.
enum GrokReasoning {
    static let none = "none"     // skip thinking tokens entirely — cheapest/fastest
    static let low = "low"       // default
    static let medium = "medium"
    static let high = "high"     // deepest reasoning, highest cost
}

/// Allowed values for `XAiSearchParameters.mode` (Live Search grounding). Ports `object
/// GrokSearchMode`.
enum GrokSearchMode {
    static let off = "off"   // never search
    static let auto = "auto" // let the model decide
    static let on = "on"     // always search
}
