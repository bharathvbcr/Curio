import Foundation

/// xAI Grok REST surface — chat, vision, embeddings, image generation. Ports `interface XAiApi`
/// in `data/remote/XAiApi.kt`.
///
/// The Retrofit `@Header("Authorization") authorization: String` becomes a per-call `authorization`
/// argument (the full `"Bearer <key>"` value the caller assembles — CONVENTIONS Networking
/// cross-cutting "per-call `Bearer` header (not interceptor)"). The base URL is `https://api.x.ai/`.
protocol XAiApi: Sendable {
    func chatCompletions(authorization: String, request: XAiRequest) async throws -> XAiResponse
    func visionCompletions(authorization: String, request: XAiVisionRequest) async throws -> XAiResponse
    func createEmbeddings(authorization: String, request: XAiEmbeddingRequest) async throws -> XAiEmbeddingResponse
    func listEmbeddingModels(authorization: String) async throws -> XAiEmbeddingModelsResponse
    func generateImages(authorization: String, request: XAiImageRequest) async throws -> XAiImageResponse
}

/// Concrete `URLSession`-backed xAI client. `actor` per CONVENTIONS §5 (each API client is an
/// actor). Long completions use the primary (120s) session; embeddings/images use it too because
/// generation can take seconds.
actor XAiApiClient: XAiApi {

    /// Base host for all xAI v1 endpoints.
    static let baseURL = URL(string: "https://api.x.ai/")!

    private let http: HTTPClient
    private let baseURL: URL

    init(http: HTTPClient, baseURL: URL = XAiApiClient.baseURL) {
        self.http = http
        self.baseURL = baseURL
    }

    // MARK: - Endpoints

    func chatCompletions(authorization: String, request: XAiRequest) async throws -> XAiResponse {
        try await post("v1/chat/completions", authorization: authorization, body: request)
    }

    func visionCompletions(authorization: String, request: XAiVisionRequest) async throws -> XAiResponse {
        // Same endpoint as chat — the body just carries multimodal content parts.
        try await post("v1/chat/completions", authorization: authorization, body: request)
    }

    func createEmbeddings(authorization: String, request: XAiEmbeddingRequest) async throws -> XAiEmbeddingResponse {
        try await post("v1/embeddings", authorization: authorization, body: request)
    }

    func listEmbeddingModels(authorization: String) async throws -> XAiEmbeddingModelsResponse {
        try await get("v1/embedding-models", authorization: authorization)
    }

    func generateImages(authorization: String, request: XAiImageRequest) async throws -> XAiImageResponse {
        try await post("v1/images/generations", authorization: authorization, body: request)
    }

    // MARK: - Plumbing

    private func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        authorization: String,
        body: Body
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent(path)
        let encoded = try await http.encode(body)
        let request = HTTPClient.jsonRequest(
            url: url,
            method: "POST",
            authorization: authorization,
            body: encoded
        )
        return try await http.send(Response.self, request: request, session: .primary)
    }

    private func get<Response: Decodable & Sendable>(
        _ path: String,
        authorization: String
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent(path)
        let request = HTTPClient.jsonRequest(
            url: url,
            method: "GET",
            authorization: authorization,
            body: nil
        )
        return try await http.send(Response.self, request: request, session: .primary)
    }
}
