package com.example.data.remote

/**
 * Central registry of xAI Grok model IDs and capability tiers — the single source of truth so the
 * rest of the app never hardcodes a model string. xAI retired the grok-3 / grok-4 generation on
 * 2026-05-15 (old IDs still resolve but are billed at — and behave like — their successors), so the
 * defaults below target the current `grok-4.3` flagship. Swap a constant here to re-tune the whole
 * stack; nothing else needs to change.
 *
 * Source: https://docs.x.ai/docs/models (verified 2026-06-18).
 */
object GrokModels {
    /**
     * Flagship general model: 1M-token context, native vision (image input), reasoning, function
     * calling and structured outputs. Cost/latency is tuned per-call with [GrokReasoning], so this
     * one model covers what grok-4, grok-4-fast and grok-3-mini used to span.
     */
    const val FLAGSHIP = "grok-4.3"

    /** Lightweight coding-tuned model (256k ctx), successor to grok-code-fast-1. */
    const val CODING = "grok-build-0.1"

    /** Image generation models served from `/v1/images/generations`. */
    const val IMAGE = "grok-imagine-image"               // $0.02/image
    const val IMAGE_QUALITY = "grok-imagine-image-quality" // $0.05/image, higher fidelity

    /** Task-specific defaults (all map onto the flagship today; centralised for easy retuning). */
    const val ANALYSIS = FLAGSHIP        // structured bookmark analysis (JSON-schema enforced)
    const val DEEP_ANALYSIS = FLAGSHIP   // long-form contribution/significance/caveats
    const val CHAT = FLAGSHIP            // RAG + Live-Search research assistant
    const val VISION = FLAGSHIP          // image understanding (OCR-adjacent, figure reading)

    /**
     * Text-embedding model. NOTE: as of 2026-06 xAI exposes embeddings only internally (behind the
     * Collections feature) and ships NO public `/v1/embeddings` REST endpoint, so this call is
     * best-effort and will typically return null — Curio's [com.example.data.embedding.EmbeddingProviderSelector]
     * already degrades to on-device EmbeddingGemma / recency fallback when that happens.
     */
    const val EMBEDDING = "grok-embedding-small"

    /** Legacy IDs kept for reference; these auto-redirect server-side. Do not use for new calls. */
    object Legacy {
        const val GROK_3 = "grok-3"
        const val GROK_3_MINI = "grok-3-mini"
        const val GROK_4 = "grok-4"
        const val GROK_2_IMAGE = "grok-2-image"
    }
}

/** Allowed values for the `reasoning_effort` request field on reasoning-capable Grok models. */
object GrokReasoning {
    const val NONE = "none"     // skip thinking tokens entirely — cheapest/fastest
    const val LOW = "low"       // default
    const val MEDIUM = "medium"
    const val HIGH = "high"     // deepest reasoning, highest cost
}

/** Allowed values for [XAiSearchParameters.mode] (Live Search grounding). */
object GrokSearchMode {
    const val OFF = "off"   // never search
    const val AUTO = "auto" // let the model decide
    const val ON = "on"     // always search
}
