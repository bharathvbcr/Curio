package com.example.data.remote

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST

// ---------------------------------------------------------------------------
// Chat completions — messages
// ---------------------------------------------------------------------------

@JsonClass(generateAdapter = true)
data class XAiMessage(
    @Json(name = "role") val role: String,
    @Json(name = "content") val content: String? = null,
    // Populated on assistant responses that request tool calls.
    @Json(name = "tool_calls") val toolCalls: List<XAiToolCall>? = null,
    // Set on a role="tool" reply to bind it back to the originating call.
    @Json(name = "tool_call_id") val toolCallId: String? = null,
    @Json(name = "name") val name: String? = null,
    // Streamed/echoed chain-of-thought on reasoning models (read-only).
    @Json(name = "reasoning_content") val reasoningContent: String? = null
)

// --- Vision (image understanding): content is an array of parts ------------

@JsonClass(generateAdapter = true)
data class XAiImageUrl(
    @Json(name = "url") val url: String,            // https URL or data:image/...;base64,<…> URI
    @Json(name = "detail") val detail: String? = null // "auto" | "low" | "high"
)

@JsonClass(generateAdapter = true)
data class XAiContentPart(
    @Json(name = "type") val type: String,          // "text" | "image_url"
    @Json(name = "text") val text: String? = null,
    @Json(name = "image_url") val imageUrl: XAiImageUrl? = null
) {
    companion object {
        fun text(value: String) = XAiContentPart(type = "text", text = value)
        fun image(url: String, detail: String = "high") =
            XAiContentPart(type = "image_url", imageUrl = XAiImageUrl(url, detail))
    }
}

@JsonClass(generateAdapter = true)
data class XAiVisionMessage(
    @Json(name = "role") val role: String,
    @Json(name = "content") val content: List<XAiContentPart>
)

@JsonClass(generateAdapter = true)
data class XAiVisionRequest(
    @Json(name = "model") val model: String,
    @Json(name = "messages") val messages: List<XAiVisionMessage>,
    @Json(name = "temperature") val temperature: Float? = null,
    @Json(name = "max_completion_tokens") val maxCompletionTokens: Int? = null,
    @Json(name = "search_parameters") val searchParameters: XAiSearchParameters? = null
)

// ---------------------------------------------------------------------------
// Structured outputs (response_format)
// ---------------------------------------------------------------------------

@JsonClass(generateAdapter = true)
data class XAiJsonSchema(
    @Json(name = "name") val name: String,
    @Json(name = "schema") val schema: Map<String, Any?>,
    @Json(name = "strict") val strict: Boolean = true
)

@JsonClass(generateAdapter = true)
data class XAiResponseFormat(
    @Json(name = "type") val type: String,                       // "text" | "json_object" | "json_schema"
    @Json(name = "json_schema") val jsonSchema: XAiJsonSchema? = null
) {
    companion object {
        val JSON_OBJECT = XAiResponseFormat(type = "json_object")
        fun jsonSchema(name: String, schema: Map<String, Any?>) =
            XAiResponseFormat(type = "json_schema", jsonSchema = XAiJsonSchema(name, schema))
    }
}

// ---------------------------------------------------------------------------
// Function / server-side tools
// ---------------------------------------------------------------------------

@JsonClass(generateAdapter = true)
data class XAiFunctionDef(
    @Json(name = "name") val name: String,
    @Json(name = "description") val description: String? = null,
    @Json(name = "parameters") val parameters: Map<String, Any?>? = null // JSON Schema object
)

/**
 * A tool entry. For client-defined functions use [function]. For xAI's server-side built-in tools
 * pass just a [type] of "web_search" / "x_search" / "code_interpreter" plus the relevant optional
 * config fields below (unused fields are omitted from the wire by Moshi).
 */
@JsonClass(generateAdapter = true)
data class XAiTool(
    @Json(name = "type") val type: String,
    @Json(name = "function") val function: XAiFunctionDef? = null,
    // web_search config
    @Json(name = "allowed_domains") val allowedDomains: List<String>? = null,
    @Json(name = "excluded_domains") val excludedDomains: List<String>? = null,
    @Json(name = "from_date") val fromDate: String? = null,
    @Json(name = "to_date") val toDate: String? = null,
    // x_search config
    @Json(name = "allowed_x_handles") val allowedXHandles: List<String>? = null,
    @Json(name = "excluded_x_handles") val excludedXHandles: List<String>? = null
) {
    companion object {
        fun webSearch(
            allowedDomains: List<String>? = null,
            excludedDomains: List<String>? = null,
            fromDate: String? = null,
            toDate: String? = null
        ) = XAiTool("web_search", allowedDomains = allowedDomains, excludedDomains = excludedDomains,
            fromDate = fromDate, toDate = toDate)

        fun xSearch(
            allowedXHandles: List<String>? = null,
            excludedXHandles: List<String>? = null
        ) = XAiTool("x_search", allowedXHandles = allowedXHandles, excludedXHandles = excludedXHandles)

        fun function(name: String, description: String?, parameters: Map<String, Any?>?) =
            XAiTool("function", function = XAiFunctionDef(name, description, parameters))
    }
}

@JsonClass(generateAdapter = true)
data class XAiToolFunctionCall(
    @Json(name = "name") val name: String,
    // JSON-ENCODED STRING of arguments — parse separately, it is not a nested object.
    @Json(name = "arguments") val arguments: String
)

@JsonClass(generateAdapter = true)
data class XAiToolCall(
    @Json(name = "id") val id: String,
    @Json(name = "type") val type: String,
    @Json(name = "function") val function: XAiToolFunctionCall
)

// ---------------------------------------------------------------------------
// Live Search (grounding) — search_parameters
// ---------------------------------------------------------------------------

/**
 * A single Live Search source. One flat type covers all four source kinds (web / x / news / rss);
 * only the fields relevant to [type] are set and Moshi omits the rest. Use the factory helpers.
 */
@JsonClass(generateAdapter = true)
data class XAiSearchSource(
    @Json(name = "type") val type: String,
    @Json(name = "country") val country: String? = null,
    @Json(name = "allowed_websites") val allowedWebsites: List<String>? = null,   // web only, max 5
    @Json(name = "excluded_websites") val excludedWebsites: List<String>? = null, // web/news, max 5
    @Json(name = "safe_search") val safeSearch: Boolean? = null,                  // web only
    @Json(name = "included_x_handles") val includedXHandles: List<String>? = null, // x only, max 10
    @Json(name = "excluded_x_handles") val excludedXHandles: List<String>? = null, // x only, max 10
    @Json(name = "post_favorite_count") val postFavoriteCount: Int? = null,        // x only
    @Json(name = "post_view_count") val postViewCount: Int? = null,                // x only
    @Json(name = "links") val links: List<String>? = null                          // rss only, max 1
) {
    companion object {
        fun web(
            country: String? = null,
            allowedWebsites: List<String>? = null,
            excludedWebsites: List<String>? = null,
            safeSearch: Boolean? = null
        ) = XAiSearchSource("web", country, allowedWebsites, excludedWebsites, safeSearch)

        fun x(
            includedHandles: List<String>? = null,
            excludedHandles: List<String>? = null,
            minFavorites: Int? = null,
            minViews: Int? = null
        ) = XAiSearchSource("x", includedXHandles = includedHandles, excludedXHandles = excludedHandles,
            postFavoriteCount = minFavorites, postViewCount = minViews)

        fun news(country: String? = null, excludedWebsites: List<String>? = null) =
            XAiSearchSource("news", country = country, excludedWebsites = excludedWebsites)

        fun rss(link: String) = XAiSearchSource("rss", links = listOf(link))
    }
}

@JsonClass(generateAdapter = true)
data class XAiSearchParameters(
    @Json(name = "mode") val mode: String = GrokSearchMode.AUTO,
    @Json(name = "return_citations") val returnCitations: Boolean = true,
    @Json(name = "from_date") val fromDate: String? = null,   // YYYY-MM-DD
    @Json(name = "to_date") val toDate: String? = null,       // YYYY-MM-DD
    @Json(name = "max_search_results") val maxSearchResults: Int? = null, // 1..30
    @Json(name = "sources") val sources: List<XAiSearchSource>? = null
)

// ---------------------------------------------------------------------------
// Chat completions — request
// ---------------------------------------------------------------------------

@JsonClass(generateAdapter = true)
data class XAiRequest(
    @Json(name = "model") val model: String,
    @Json(name = "messages") val messages: List<XAiMessage>,
    @Json(name = "temperature") val temperature: Float? = null,
    @Json(name = "max_completion_tokens") val maxCompletionTokens: Int? = null,
    @Json(name = "response_format") val responseFormat: XAiResponseFormat? = null,
    @Json(name = "reasoning_effort") val reasoningEffort: String? = null,
    @Json(name = "search_parameters") val searchParameters: XAiSearchParameters? = null,
    @Json(name = "tools") val tools: List<XAiTool>? = null,
    @Json(name = "tool_choice") val toolChoice: String? = null, // "auto" | "required" | "none"
    @Json(name = "seed") val seed: Int? = null,
    @Json(name = "stream") val stream: Boolean? = null
)

// ---------------------------------------------------------------------------
// Chat completions — response (incl. usage + cached/reasoning tokens + citations)
// ---------------------------------------------------------------------------

@JsonClass(generateAdapter = true)
data class XAiPromptTokensDetails(
    @Json(name = "text_tokens") val textTokens: Int? = null,
    @Json(name = "image_tokens") val imageTokens: Int? = null,
    @Json(name = "audio_tokens") val audioTokens: Int? = null,
    @Json(name = "cached_tokens") val cachedTokens: Int? = null
)

@JsonClass(generateAdapter = true)
data class XAiCompletionTokensDetails(
    @Json(name = "reasoning_tokens") val reasoningTokens: Int? = null,
    @Json(name = "accepted_prediction_tokens") val acceptedPredictionTokens: Int? = null,
    @Json(name = "rejected_prediction_tokens") val rejectedPredictionTokens: Int? = null
)

@JsonClass(generateAdapter = true)
data class XAiUsage(
    @Json(name = "prompt_tokens") val promptTokens: Int? = null,
    @Json(name = "completion_tokens") val completionTokens: Int? = null,
    @Json(name = "total_tokens") val totalTokens: Int? = null,
    @Json(name = "num_sources_used") val numSourcesUsed: Int? = null,
    @Json(name = "prompt_tokens_details") val promptTokensDetails: XAiPromptTokensDetails? = null,
    @Json(name = "completion_tokens_details") val completionTokensDetails: XAiCompletionTokensDetails? = null
)

@JsonClass(generateAdapter = true)
data class XAiChoice(
    @Json(name = "index") val index: Int? = null,
    @Json(name = "message") val message: XAiMessage,
    @Json(name = "finish_reason") val finishReason: String? = null
)

@JsonClass(generateAdapter = true)
data class XAiResponse(
    @Json(name = "id") val id: String? = null,
    @Json(name = "model") val model: String? = null,
    @Json(name = "choices") val choices: List<XAiChoice>? = null,
    // Live Search returns a TOP-LEVEL array of source URLs (sibling of choices/usage).
    @Json(name = "citations") val citations: List<String>? = null,
    @Json(name = "usage") val usage: XAiUsage? = null
)

// ---------------------------------------------------------------------------
// Embeddings (OpenAI-compatible shape; see GrokModels.EMBEDDING caveat)
// ---------------------------------------------------------------------------

@JsonClass(generateAdapter = true)
data class XAiEmbeddingRequest(
    @Json(name = "model") val model: String = GrokModels.EMBEDDING,
    @Json(name = "input") val input: String
)

@JsonClass(generateAdapter = true)
data class XAiEmbeddingData(
    @Json(name = "embedding") val embedding: List<Float>,
    @Json(name = "index") val index: Int = 0
)

@JsonClass(generateAdapter = true)
data class XAiEmbeddingResponse(
    @Json(name = "data") val data: List<XAiEmbeddingData>? = null
)

/**
 * Response of GET /v1/embedding-models. xAI has used both `{"models":[…]}` and an OpenAI-style
 * `{"data":[…]}` envelope across surfaces, so accept either; an entry may name itself `id` or `name`.
 */
@JsonClass(generateAdapter = true)
data class XAiEmbeddingModelsResponse(
    @Json(name = "models") val models: List<XAiModelEntry>? = null,
    @Json(name = "data") val data: List<XAiModelEntry>? = null
) {
    /** First usable embedding-model id, or null if the account has none. */
    fun firstModelId(): String? =
        (models.orEmpty() + data.orEmpty()).firstNotNullOfOrNull { it.id ?: it.name }
}

@JsonClass(generateAdapter = true)
data class XAiModelEntry(
    @Json(name = "id") val id: String? = null,
    @Json(name = "name") val name: String? = null
)

// ---------------------------------------------------------------------------
// Image generation
// ---------------------------------------------------------------------------

@JsonClass(generateAdapter = true)
data class XAiImageRequest(
    @Json(name = "model") val model: String = GrokModels.IMAGE,
    @Json(name = "prompt") val prompt: String,
    @Json(name = "n") val n: Int = 1,
    @Json(name = "response_format") val responseFormat: String = "url", // "url" | "b64_json"
    @Json(name = "aspect_ratio") val aspectRatio: String? = null,        // e.g. "1:1", "16:9"
    @Json(name = "resolution") val resolution: String? = null            // "1k" | "2k"
)

@JsonClass(generateAdapter = true)
data class XAiImageData(
    @Json(name = "url") val url: String? = null,
    @Json(name = "b64_json") val b64Json: String? = null,
    @Json(name = "mime_type") val mimeType: String? = null,
    @Json(name = "revised_prompt") val revisedPrompt: String? = null
)

@JsonClass(generateAdapter = true)
data class XAiImageResponse(
    @Json(name = "data") val data: List<XAiImageData>? = null
)

// ---------------------------------------------------------------------------
// API key introspection — GET /v1/api-key returns metadata about the bearer
// key itself (no tokens consumed). Used to verify a user-pasted BYOK key is
// actually live, not just syntactically present.
// ---------------------------------------------------------------------------

@JsonClass(generateAdapter = true)
data class XAiApiKeyInfo(
    @Json(name = "redacted_api_key") val redactedApiKey: String? = null,
    @Json(name = "name") val name: String? = null,
    @Json(name = "api_key_blocked") val apiKeyBlocked: Boolean? = null,
    @Json(name = "api_key_disabled") val apiKeyDisabled: Boolean? = null,
    @Json(name = "team_blocked") val teamBlocked: Boolean? = null
)

// ---------------------------------------------------------------------------
// Retrofit interface
// ---------------------------------------------------------------------------

interface XAiApi {
    @POST("v1/chat/completions")
    suspend fun chatCompletions(
        @Header("Authorization") authorization: String,
        @Body request: XAiRequest
    ): XAiResponse

    /** Same endpoint, multimodal body (messages carry image_url content parts). */
    @POST("v1/chat/completions")
    suspend fun visionCompletions(
        @Header("Authorization") authorization: String,
        @Body request: XAiVisionRequest
    ): XAiResponse

    @POST("v1/embeddings")
    suspend fun createEmbeddings(
        @Header("Authorization") authorization: String,
        @Body request: XAiEmbeddingRequest
    ): XAiEmbeddingResponse

    @POST("v1/images/generations")
    suspend fun generateImages(
        @Header("Authorization") authorization: String,
        @Body request: XAiImageRequest
    ): XAiImageResponse

    /** Key introspection: cheap liveness check for the bearer key (consumes no tokens). */
    @GET("v1/api-key")
    suspend fun getApiKeyInfo(
        @Header("Authorization") authorization: String
    ): XAiApiKeyInfo

    /**
     * Lists the embedding models provisioned for the authenticating key/team. xAI does not ship a
     * fixed public embedding model name — availability is per-account — so we discover it at runtime
     * instead of hardcoding one that may 404. An empty list means the account has no embedder.
     */
    @GET("v1/embedding-models")
    suspend fun listEmbeddingModels(
        @Header("Authorization") authorization: String
    ): XAiEmbeddingModelsResponse
}
