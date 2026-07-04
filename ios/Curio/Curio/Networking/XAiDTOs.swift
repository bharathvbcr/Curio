import Foundation

// ---------------------------------------------------------------------------
// xAI Grok wire DTOs — direct port of `data/remote/XAiApi.kt`.
//
// CONVENTIONS §7: every optional field is encoded with `encodeIfPresent` (custom `encode(to:)`)
// so unset fields NEVER reach the wire — this mirrors Moshi's null-omission, which is load-bearing
// for xAI tool/search semantics (a stray explicit `null` changes behavior). DTOs are `Sendable`
// value types; `CodingKeys` carry the exact snake_case wire names.
// ---------------------------------------------------------------------------

// MARK: - Chat completions — messages

/// A chat message. Direct port of `XAiMessage`.
struct XAiMessage: Codable, Sendable {
    let role: String
    let content: String?
    /// Populated on assistant responses that request tool calls.
    let toolCalls: [XAiToolCall]?
    /// Set on a `role="tool"` reply to bind it back to the originating call.
    let toolCallId: String?
    let name: String?
    /// Streamed/echoed chain-of-thought on reasoning models (read-only).
    let reasoningContent: String?

    init(
        role: String,
        content: String? = nil,
        toolCalls: [XAiToolCall]? = nil,
        toolCallId: String? = nil,
        name: String? = nil,
        reasoningContent: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.name = name
        self.reasoningContent = reasoningContent
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
        case name
        case reasoningContent = "reasoning_content"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try c.encodeIfPresent(toolCallId, forKey: .toolCallId)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(reasoningContent, forKey: .reasoningContent)
    }
}

// MARK: - Vision (image understanding)

/// An image reference inside a vision content part. Port of `XAiImageUrl`.
struct XAiImageUrl: Codable, Sendable {
    /// `https` URL or `data:image/...;base64,<…>` URI.
    let url: String
    /// `"auto" | "low" | "high"`.
    let detail: String?

    init(url: String, detail: String? = nil) {
        self.url = url
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey {
        case url
        case detail
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(detail, forKey: .detail)
    }
}

/// A single content part of a multimodal message. Port of `XAiContentPart` + its companion
/// factories `text(_:)` and `image(url:detail:)`.
struct XAiContentPart: Codable, Sendable {
    /// `"text" | "image_url"`.
    let type: String
    let text: String?
    let imageUrl: XAiImageUrl?

    init(type: String, text: String? = nil, imageUrl: XAiImageUrl? = nil) {
        self.type = type
        self.text = text
        self.imageUrl = imageUrl
    }

    static func text(_ value: String) -> XAiContentPart {
        XAiContentPart(type: "text", text: value)
    }

    static func image(_ url: String, detail: String = "high") -> XAiContentPart {
        XAiContentPart(type: "image_url", imageUrl: XAiImageUrl(url: url, detail: detail))
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageUrl = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(imageUrl, forKey: .imageUrl)
    }
}

/// A multimodal message whose `content` is an array of parts. Port of `XAiVisionMessage`.
struct XAiVisionMessage: Codable, Sendable {
    let role: String
    let content: [XAiContentPart]

    init(role: String, content: [XAiContentPart]) {
        self.role = role
        self.content = content
    }
}

/// Vision chat request. Port of `XAiVisionRequest`.
struct XAiVisionRequest: Codable, Sendable {
    let model: String
    let messages: [XAiVisionMessage]
    let temperature: Float?
    let maxCompletionTokens: Int?
    let searchParameters: XAiSearchParameters?

    init(
        model: String,
        messages: [XAiVisionMessage],
        temperature: Float? = nil,
        maxCompletionTokens: Int? = nil,
        searchParameters: XAiSearchParameters? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxCompletionTokens = maxCompletionTokens
        self.searchParameters = searchParameters
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxCompletionTokens = "max_completion_tokens"
        case searchParameters = "search_parameters"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(messages, forKey: .messages)
        try c.encodeIfPresent(temperature, forKey: .temperature)
        try c.encodeIfPresent(maxCompletionTokens, forKey: .maxCompletionTokens)
        try c.encodeIfPresent(searchParameters, forKey: .searchParameters)
    }
}

// MARK: - Structured outputs (response_format)

/// A JSON-Schema spec for structured output. Port of `XAiJsonSchema`. `schema` is a raw JSON object
/// carried as a ``JSONValue`` map (CONVENTIONS §7).
struct XAiJsonSchema: Codable, Sendable {
    let name: String
    let schema: [String: JSONValue]
    let strict: Bool

    init(name: String, schema: [String: JSONValue], strict: Bool = true) {
        self.name = name
        self.schema = schema
        self.strict = strict
    }

    init(name: String, schema: [String: Any?], strict: Bool = true) {
        self.name = name
        var converted: [String: JSONValue] = [:]
        for (key, value) in schema { converted[key] = JSONValue.from(value) }
        self.schema = converted
        self.strict = strict
    }
}

/// `response_format` for chat completions. Port of `XAiResponseFormat` + its companion
/// `JSON_OBJECT` constant and `jsonSchema(name:schema:)` factory.
struct XAiResponseFormat: Codable, Sendable {
    /// `"text" | "json_object" | "json_schema"`.
    let type: String
    let jsonSchema: XAiJsonSchema?

    init(type: String, jsonSchema: XAiJsonSchema? = nil) {
        self.type = type
        self.jsonSchema = jsonSchema
    }

    /// Mirrors `XAiResponseFormat.JSON_OBJECT`.
    static let jsonObject = XAiResponseFormat(type: "json_object")

    static func jsonSchema(name: String, schema: [String: Any?]) -> XAiResponseFormat {
        XAiResponseFormat(type: "json_schema", jsonSchema: XAiJsonSchema(name: name, schema: schema))
    }

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(jsonSchema, forKey: .jsonSchema)
    }
}

// MARK: - Function / server-side tools

/// A client-defined function declaration. Port of `XAiFunctionDef`. `parameters` is a raw JSON
/// Schema object carried as a ``JSONValue`` map.
struct XAiFunctionDef: Codable, Sendable {
    let name: String
    let description: String?
    let parameters: [String: JSONValue]?

    init(name: String, description: String? = nil, parameters: [String: JSONValue]? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    init(name: String, description: String?, parameters: [String: Any?]?) {
        self.name = name
        self.description = description
        if let parameters {
            var converted: [String: JSONValue] = [:]
            for (key, value) in parameters { converted[key] = JSONValue.from(value) }
            self.parameters = converted
        } else {
            self.parameters = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case parameters
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(parameters, forKey: .parameters)
    }
}

/// A tool entry — a client-defined function (`function`) or an xAI server-side built-in tool
/// (`web_search` / `x_search` / `code_interpreter`). Port of `XAiTool` with its companion factories
/// `webSearch`, `xSearch`, `function`. Unused fields are omitted from the wire (Moshi parity).
struct XAiTool: Codable, Sendable {
    let type: String
    let function: XAiFunctionDef?
    // web_search config
    let allowedDomains: [String]?
    let excludedDomains: [String]?
    let fromDate: String?
    let toDate: String?
    // x_search config
    let allowedXHandles: [String]?
    let excludedXHandles: [String]?

    init(
        type: String,
        function: XAiFunctionDef? = nil,
        allowedDomains: [String]? = nil,
        excludedDomains: [String]? = nil,
        fromDate: String? = nil,
        toDate: String? = nil,
        allowedXHandles: [String]? = nil,
        excludedXHandles: [String]? = nil
    ) {
        self.type = type
        self.function = function
        self.allowedDomains = allowedDomains
        self.excludedDomains = excludedDomains
        self.fromDate = fromDate
        self.toDate = toDate
        self.allowedXHandles = allowedXHandles
        self.excludedXHandles = excludedXHandles
    }

    static func webSearch(
        allowedDomains: [String]? = nil,
        excludedDomains: [String]? = nil,
        fromDate: String? = nil,
        toDate: String? = nil
    ) -> XAiTool {
        XAiTool(
            type: "web_search",
            allowedDomains: allowedDomains,
            excludedDomains: excludedDomains,
            fromDate: fromDate,
            toDate: toDate
        )
    }

    static func xSearch(
        allowedXHandles: [String]? = nil,
        excludedXHandles: [String]? = nil
    ) -> XAiTool {
        XAiTool(
            type: "x_search",
            allowedXHandles: allowedXHandles,
            excludedXHandles: excludedXHandles
        )
    }

    static func function(name: String, description: String?, parameters: [String: Any?]?) -> XAiTool {
        XAiTool(type: "function", function: XAiFunctionDef(name: name, description: description, parameters: parameters))
    }

    enum CodingKeys: String, CodingKey {
        case type
        case function
        case allowedDomains = "allowed_domains"
        case excludedDomains = "excluded_domains"
        case fromDate = "from_date"
        case toDate = "to_date"
        case allowedXHandles = "allowed_x_handles"
        case excludedXHandles = "excluded_x_handles"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(function, forKey: .function)
        try c.encodeIfPresent(allowedDomains, forKey: .allowedDomains)
        try c.encodeIfPresent(excludedDomains, forKey: .excludedDomains)
        try c.encodeIfPresent(fromDate, forKey: .fromDate)
        try c.encodeIfPresent(toDate, forKey: .toDate)
        try c.encodeIfPresent(allowedXHandles, forKey: .allowedXHandles)
        try c.encodeIfPresent(excludedXHandles, forKey: .excludedXHandles)
    }
}

/// A function call inside a tool call. Port of `XAiToolFunctionCall`.
/// `arguments` is a JSON-ENCODED STRING — parse separately, it is NOT a nested object (CONVENTIONS
/// §7 "String-not-object fields").
struct XAiToolFunctionCall: Codable, Sendable {
    let name: String
    /// JSON-encoded string of arguments.
    let arguments: String
}

/// A single tool call requested by the assistant. Port of `XAiToolCall`.
struct XAiToolCall: Codable, Sendable {
    let id: String
    let type: String
    let function: XAiToolFunctionCall
}

// MARK: - Live Search (grounding) — search_parameters

/// A single Live Search source. One flat type covers all four source kinds (web / x / news / rss);
/// only the fields relevant to `type` are set and the rest are omitted. Port of `XAiSearchSource`
/// with its companion factories `web`, `x`, `news`, `rss`.
struct XAiSearchSource: Codable, Sendable, Equatable {
    let type: String
    let country: String?
    let allowedWebsites: [String]?   // web only, max 5
    let excludedWebsites: [String]?  // web/news, max 5
    let safeSearch: Bool?            // web only
    let includedXHandles: [String]?  // x only, max 10
    let excludedXHandles: [String]?  // x only, max 10
    let postFavoriteCount: Int?      // x only
    let postViewCount: Int?          // x only
    let links: [String]?             // rss only, max 1

    init(
        type: String,
        country: String? = nil,
        allowedWebsites: [String]? = nil,
        excludedWebsites: [String]? = nil,
        safeSearch: Bool? = nil,
        includedXHandles: [String]? = nil,
        excludedXHandles: [String]? = nil,
        postFavoriteCount: Int? = nil,
        postViewCount: Int? = nil,
        links: [String]? = nil
    ) {
        self.type = type
        self.country = country
        self.allowedWebsites = allowedWebsites
        self.excludedWebsites = excludedWebsites
        self.safeSearch = safeSearch
        self.includedXHandles = includedXHandles
        self.excludedXHandles = excludedXHandles
        self.postFavoriteCount = postFavoriteCount
        self.postViewCount = postViewCount
        self.links = links
    }

    static func web(
        country: String? = nil,
        allowedWebsites: [String]? = nil,
        excludedWebsites: [String]? = nil,
        safeSearch: Bool? = nil
    ) -> XAiSearchSource {
        XAiSearchSource(
            type: "web",
            country: country,
            allowedWebsites: allowedWebsites,
            excludedWebsites: excludedWebsites,
            safeSearch: safeSearch
        )
    }

    static func x(
        includedHandles: [String]? = nil,
        excludedHandles: [String]? = nil,
        minFavorites: Int? = nil,
        minViews: Int? = nil
    ) -> XAiSearchSource {
        XAiSearchSource(
            type: "x",
            includedXHandles: includedHandles,
            excludedXHandles: excludedHandles,
            postFavoriteCount: minFavorites,
            postViewCount: minViews
        )
    }

    static func news(country: String? = nil, excludedWebsites: [String]? = nil) -> XAiSearchSource {
        XAiSearchSource(type: "news", country: country, excludedWebsites: excludedWebsites)
    }

    static func rss(_ link: String) -> XAiSearchSource {
        XAiSearchSource(type: "rss", links: [link])
    }

    enum CodingKeys: String, CodingKey {
        case type
        case country
        case allowedWebsites = "allowed_websites"
        case excludedWebsites = "excluded_websites"
        case safeSearch = "safe_search"
        case includedXHandles = "included_x_handles"
        case excludedXHandles = "excluded_x_handles"
        case postFavoriteCount = "post_favorite_count"
        case postViewCount = "post_view_count"
        case links
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(country, forKey: .country)
        try c.encodeIfPresent(allowedWebsites, forKey: .allowedWebsites)
        try c.encodeIfPresent(excludedWebsites, forKey: .excludedWebsites)
        try c.encodeIfPresent(safeSearch, forKey: .safeSearch)
        try c.encodeIfPresent(includedXHandles, forKey: .includedXHandles)
        try c.encodeIfPresent(excludedXHandles, forKey: .excludedXHandles)
        try c.encodeIfPresent(postFavoriteCount, forKey: .postFavoriteCount)
        try c.encodeIfPresent(postViewCount, forKey: .postViewCount)
        try c.encodeIfPresent(links, forKey: .links)
    }
}

/// Live Search parameters. Port of `XAiSearchParameters`. `mode` defaults to `auto` and
/// `returnCitations` to `true` (both are ALWAYS emitted — they have non-null Kotlin defaults).
struct XAiSearchParameters: Codable, Sendable, Equatable {
    let mode: String
    let returnCitations: Bool
    let fromDate: String?           // YYYY-MM-DD
    let toDate: String?             // YYYY-MM-DD
    let maxSearchResults: Int?      // 1..30
    let sources: [XAiSearchSource]?

    init(
        mode: String = GrokSearchMode.auto,
        returnCitations: Bool = true,
        fromDate: String? = nil,
        toDate: String? = nil,
        maxSearchResults: Int? = nil,
        sources: [XAiSearchSource]? = nil
    ) {
        self.mode = mode
        self.returnCitations = returnCitations
        self.fromDate = fromDate
        self.toDate = toDate
        self.maxSearchResults = maxSearchResults
        self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case returnCitations = "return_citations"
        case fromDate = "from_date"
        case toDate = "to_date"
        case maxSearchResults = "max_search_results"
        case sources
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(returnCitations, forKey: .returnCitations)
        try c.encodeIfPresent(fromDate, forKey: .fromDate)
        try c.encodeIfPresent(toDate, forKey: .toDate)
        try c.encodeIfPresent(maxSearchResults, forKey: .maxSearchResults)
        try c.encodeIfPresent(sources, forKey: .sources)
    }
}

// MARK: - Chat completions — request

/// Chat completions request. Port of `XAiRequest`. Every optional field is omitted when unset.
struct XAiRequest: Codable, Sendable {
    let model: String
    let messages: [XAiMessage]
    let temperature: Float?
    let maxCompletionTokens: Int?
    let responseFormat: XAiResponseFormat?
    let reasoningEffort: String?
    let searchParameters: XAiSearchParameters?
    let tools: [XAiTool]?
    let toolChoice: String?   // "auto" | "required" | "none"
    let seed: Int?
    let stream: Bool?

    init(
        model: String,
        messages: [XAiMessage],
        temperature: Float? = nil,
        maxCompletionTokens: Int? = nil,
        responseFormat: XAiResponseFormat? = nil,
        reasoningEffort: String? = nil,
        searchParameters: XAiSearchParameters? = nil,
        tools: [XAiTool]? = nil,
        toolChoice: String? = nil,
        seed: Int? = nil,
        stream: Bool? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxCompletionTokens = maxCompletionTokens
        self.responseFormat = responseFormat
        self.reasoningEffort = reasoningEffort
        self.searchParameters = searchParameters
        self.tools = tools
        self.toolChoice = toolChoice
        self.seed = seed
        self.stream = stream
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxCompletionTokens = "max_completion_tokens"
        case responseFormat = "response_format"
        case reasoningEffort = "reasoning_effort"
        case searchParameters = "search_parameters"
        case tools
        case toolChoice = "tool_choice"
        case seed
        case stream
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(messages, forKey: .messages)
        try c.encodeIfPresent(temperature, forKey: .temperature)
        try c.encodeIfPresent(maxCompletionTokens, forKey: .maxCompletionTokens)
        try c.encodeIfPresent(responseFormat, forKey: .responseFormat)
        try c.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        try c.encodeIfPresent(searchParameters, forKey: .searchParameters)
        try c.encodeIfPresent(tools, forKey: .tools)
        try c.encodeIfPresent(toolChoice, forKey: .toolChoice)
        try c.encodeIfPresent(seed, forKey: .seed)
        try c.encodeIfPresent(stream, forKey: .stream)
    }
}

// MARK: - Chat completions — response

/// Port of `XAiPromptTokensDetails`.
struct XAiPromptTokensDetails: Codable, Sendable {
    let textTokens: Int?
    let imageTokens: Int?
    let audioTokens: Int?
    let cachedTokens: Int?

    enum CodingKeys: String, CodingKey {
        case textTokens = "text_tokens"
        case imageTokens = "image_tokens"
        case audioTokens = "audio_tokens"
        case cachedTokens = "cached_tokens"
    }
}

/// Port of `XAiCompletionTokensDetails`.
struct XAiCompletionTokensDetails: Codable, Sendable {
    let reasoningTokens: Int?
    let acceptedPredictionTokens: Int?
    let rejectedPredictionTokens: Int?

    enum CodingKeys: String, CodingKey {
        case reasoningTokens = "reasoning_tokens"
        case acceptedPredictionTokens = "accepted_prediction_tokens"
        case rejectedPredictionTokens = "rejected_prediction_tokens"
    }
}

/// Token usage on a response. Port of `XAiUsage`.
struct XAiUsage: Codable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let numSourcesUsed: Int?
    let promptTokensDetails: XAiPromptTokensDetails?
    let completionTokensDetails: XAiCompletionTokensDetails?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case numSourcesUsed = "num_sources_used"
        case promptTokensDetails = "prompt_tokens_details"
        case completionTokensDetails = "completion_tokens_details"
    }
}

/// A single completion choice. Port of `XAiChoice`.
struct XAiChoice: Codable, Sendable {
    let index: Int?
    let message: XAiMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

/// Chat completions response. Port of `XAiResponse`.
/// `citations` is a TOP-LEVEL `[String]?` (sibling of `choices`/`usage`) returned by Live Search
/// (CONVENTIONS §7 "String-not-object fields" / "citations is top-level").
struct XAiResponse: Codable, Sendable {
    let id: String?
    let model: String?
    let choices: [XAiChoice]?
    /// Live Search returns a TOP-LEVEL array of source URLs.
    let citations: [String]?
    let usage: XAiUsage?
}

// MARK: - Embeddings

/// Embeddings request. Port of `XAiEmbeddingRequest`. `model` defaults to ``GrokModels/embedding``.
struct XAiEmbeddingRequest: Codable, Sendable {
    let model: String
    let input: String

    init(model: String = GrokModels.embedding, input: String) {
        self.model = model
        self.input = input
    }
}

/// One embedding vector. Port of `XAiEmbeddingData`.
struct XAiEmbeddingData: Codable, Sendable {
    let embedding: [Float]
    let index: Int

    init(embedding: [Float], index: Int = 0) {
        self.embedding = embedding
        self.index = index
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.embedding = try c.decode([Float].self, forKey: .embedding)
        // Default 0 mirrors the Kotlin `index: Int = 0` so a missing `index` does not fail decoding.
        self.index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case embedding
        case index
    }
}

/// Embeddings response. Port of `XAiEmbeddingResponse`.
struct XAiEmbeddingResponse: Codable, Sendable {
    let data: [XAiEmbeddingData]?
}

/// Response of GET /v1/embedding-models. Port of `XAiEmbeddingModelsResponse`.
struct XAiEmbeddingModelsResponse: Codable, Sendable {
    let models: [XAiModelEntry]?
    let data: [XAiModelEntry]?

    /// First usable embedding-model id, or nil if the account has none.
    var firstModelId: String? {
        for entry in (models ?? []) + (data ?? []) {
            if let id = entry.id ?? entry.name { return id }
        }
        return nil
    }
}

/// One model entry in an embedding-models list. Port of `XAiModelEntry`.
struct XAiModelEntry: Codable, Sendable {
    let id: String?
    let name: String?
}

// MARK: - Image generation

/// Image generation request. Port of `XAiImageRequest`. `model` defaults to ``GrokModels/image``,
/// `n` to 1, `responseFormat` to `"url"`.
struct XAiImageRequest: Codable, Sendable {
    let model: String
    let prompt: String
    let n: Int
    let responseFormat: String       // "url" | "b64_json"
    let aspectRatio: String?         // e.g. "1:1", "16:9"
    let resolution: String?          // "1k" | "2k"

    init(
        model: String = GrokModels.image,
        prompt: String,
        n: Int = 1,
        responseFormat: String = "url",
        aspectRatio: String? = nil,
        resolution: String? = nil
    ) {
        self.model = model
        self.prompt = prompt
        self.n = n
        self.responseFormat = responseFormat
        self.aspectRatio = aspectRatio
        self.resolution = resolution
    }

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case n
        case responseFormat = "response_format"
        case aspectRatio = "aspect_ratio"
        case resolution
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(n, forKey: .n)
        try c.encode(responseFormat, forKey: .responseFormat)
        try c.encodeIfPresent(aspectRatio, forKey: .aspectRatio)
        try c.encodeIfPresent(resolution, forKey: .resolution)
    }
}

/// One generated image. Port of `XAiImageData`.
struct XAiImageData: Codable, Sendable {
    let url: String?
    let b64Json: String?
    let mimeType: String?
    let revisedPrompt: String?

    enum CodingKeys: String, CodingKey {
        case url
        case b64Json = "b64_json"
        case mimeType = "mime_type"
        case revisedPrompt = "revised_prompt"
    }
}

/// Image generation response. Port of `XAiImageResponse`.
struct XAiImageResponse: Codable, Sendable {
    let data: [XAiImageData]?
}
