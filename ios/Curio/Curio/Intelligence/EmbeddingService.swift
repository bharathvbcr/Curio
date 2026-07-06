import Foundation
import os

/// Cloud embedding backend (xAI). Used as the fallback when on-device EmbeddingGemma is absent.
/// Ports `class EmbeddingService` from `data/embedding/EmbeddingService.kt`.
///
/// Caveat (from the Android source): as of 2026-06 xAI does NOT expose a public `/v1/embeddings` REST
/// endpoint (embeddings live only behind the Collections feature), so this call is best-effort and
/// usually returns `nil`. `EmbeddingProviderSelector` handles that by preferring on-device
/// EmbeddingGemma and the recency fallback in the chat path, so RAG keeps working regardless
/// (CONVENTIONS Networking cross-cutting "embedding endpoint best-effort (nil-tolerant)").
///
/// Resilient: logs + returns `nil` on any error, never throws (CONVENTIONS §3). Reuses the shared
/// `EmbeddingText` assembly so the cloud path embeds the *same* text as the on-device path.
final class EmbeddingService: EmbeddingProvider {

    private let xAiApi: XAiApi
    private let keyStore: XaiKeyStore
    private static let logger = Logger(subsystem: "com.curio.app", category: "EmbeddingService")

    /// Human-readable reason the last embed attempt failed, for the UI to surface. Nil on success.
    /// `nonisolated(unsafe)` (as with `entityStripRegex` above): this cloud path is best-effort and
    /// mirrors the Kotlin plain-class field; not worth an actor hop for a usually-nil fallback.
    private(set) nonisolated(unsafe) var lastError: String?

    /// Cache the discovered model id for the process lifetime.
    private nonisolated(unsafe) var cachedModelId: String?

    init(xAiApi: XAiApi, keyStore: XaiKeyStore = XaiKeyStore()) {
        self.xAiApi = xAiApi
        self.keyStore = keyStore
    }

    func isOnDevice() -> Bool { false }

    /// Chunk + mean-pool so long documents retain body content (mirrors the on-device path).
    /// Port of `embedDocument(bookmark)`.
    func embedDocument(_ bookmark: Bookmark) async -> [Float]? {
        var vectors: [[Float]] = []
        for chunk in EmbeddingText.chunksForDocument(bookmark, chunkChars: EmbeddingText.cloudChunkChars) {
            if let v = await embed(chunk) { vectors.append(v) }
        }
        return EmbeddingText.meanPool(vectors)
    }

    func embedQuery(_ query: String) async -> [Float]? {
        await embed(query)
    }

    /// Single best-effort embedding call. Port of the private `suspend fun embed(text)`:
    /// resolves the key, gates on `isConfigured()`, POSTs `input.take(8000)`, returns the first
    /// vector. Any error → `nil` and sets `lastError`.
    private func embed(_ text: String) async -> [Float]? {
        do {
            let apiKey = keyStore.resolve()
            guard keyStore.isConfigured() else {
                lastError = "No xAI API key set (Settings → xAI API Key)."
                return nil
            }

            let request = XAiEmbeddingRequest(
                model: try await resolveModelId(apiKey: apiKey),
                input: String(text.prefix(8000))
            )
            let response = try await xAiApi.createEmbeddings(
                authorization: "Bearer \(apiKey)",
                request: request
            )
            let vector = response.data?.first?.embedding
            if vector == nil {
                lastError = "xAI returned no embedding — your account may not have an embedding model provisioned."
                Self.logger.warning("\(self.lastError!, privacy: .public)")
            } else {
                lastError = nil
            }
            return vector
        } catch is CancellationError {
            return nil
        } catch let error as APIError {
            if case let .http(status, _, body) = error {
                let bodyText = String(data: body, encoding: .utf8).map { String($0.prefix(300)) } ?? ""
                lastError = switch status {
                case 404: "xAI has no embeddings endpoint/model for this key (404). Use On-device embeddings."
                case 401, 403: "xAI rejected the key for embeddings (HTTP \(status))."
                default: "xAI embeddings failed: HTTP \(status) \(bodyText)"
                }
            } else {
                lastError = "xAI embeddings failed: \(error)"
            }
            Self.logger.error("\(self.lastError!, privacy: .public)")
            return nil
        } catch {
            lastError = "xAI embeddings failed: \(error.localizedDescription)"
            Self.logger.error("\(self.lastError!, privacy: .public)")
            return nil
        }
    }

    /// Cached → account-provisioned (discovered) → compile-time default.
    private func resolveModelId(apiKey: String) async throws -> String {
        if let cached = cachedModelId { return cached }
        let discovered: String?
        do {
            discovered = try await xAiApi.listEmbeddingModels(authorization: "Bearer \(apiKey)").firstModelId
        } catch {
            Self.logger.warning("embedding-models list failed: \(error.localizedDescription, privacy: .public)")
            discovered = nil
        }
        let id = discovered ?? GrokModels.embedding
        cachedModelId = id
        if discovered != nil {
            Self.logger.info("Using discovered xAI embedding model: \(id, privacy: .public)")
        }
        return id
    }
}
