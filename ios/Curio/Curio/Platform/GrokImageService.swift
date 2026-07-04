import Foundation
import os

/// Result of a Grok image generation: the image URL plus the model's revised prompt.
/// Direct port of the Kotlin `data class GeneratedImage`.
///
/// `Sendable` value type per CONVENTIONS §5 (domain value types crossing actor boundaries are
/// `Sendable` structs). `revisedPrompt` keeps its `nil` default so callers that only need the URL
/// can construct/destructure it the same way the Kotlin `data class` allowed.
struct GeneratedImage: Sendable, Equatable {
    let url: String
    let revisedPrompt: String?

    init(url: String, revisedPrompt: String? = nil) {
        self.url = url
        self.revisedPrompt = revisedPrompt
    }
}

/// Real image generation via xAI's `grok-imagine` models (`POST /v1/images/generations`). Replaces
/// the procedural canvas placeholder (``ImagenBookmarkArt``) with model-generated artwork. Returns
/// `nil` on any failure (missing key, network, quota) so callers can fall back to the local
/// generative graphic. Direct port of `class GrokImageService(private val xAiApi: XAiApi)` in
/// `data/GrokImageService.kt`.
///
/// **Resilience contract (CONVENTIONS §3):** this is a network client, so it logs and returns `nil`
/// instead of throwing — every failure path (missing key, transport, decoding, quota) collapses to
/// `nil`. The only typed-failure surfaces in the app are `AuthRepository.completeLogin` and
/// `syncBookmarks`; image generation is not one of them.
///
/// **Key resolution (CONVENTIONS §2 / §9):** the Android `object` read the process-global
/// `XaiKeyStore` directly. To keep this module on constructor injection, the service takes a
/// ``XaiKeyResolving`` (the Auth module's `XaiKeyStore` conforms). `isConfigured()` mirrors the
/// Android rule (BYOK: a non-blank user-supplied key saved in Settings); the runtime slot is populated
/// asynchronously at startup / on Settings save, so a freshly-entered key is honoured here without
/// reconstruction.
///
/// **Concurrency:** the Kotlin method hopped to `Dispatchers.IO`. Here the work is a single `await`
/// on an `actor`-isolated `XAiApi` client (which already runs off the main actor via the primary
/// `URLSession`), so no extra dispatch is needed — `generate` is a plain `nonisolated async`
/// method that never touches the main actor. `final class … Sendable` because all stored state is
/// immutable `Sendable` (matches `XAiAnalyzer`).
final class GrokImageService: Sendable {

    private let xAiApi: XAiApi
    private let keyResolver: XaiKeyResolving
    private static let logger = Logger(subsystem: "com.curio.app", category: "GrokImageService")

    init(xAiApi: XAiApi, keyResolver: XaiKeyResolving) {
        self.xAiApi = xAiApi
        self.keyResolver = keyResolver
    }

    /// Generates a single representative image for a research bookmark.
    ///
    /// - Parameters:
    ///   - prompt: the scene description (built from the bookmark's title/category/tags, typically
    ///     via ``promptForCategory(category:title:)``).
    ///   - highQuality: use the higher-fidelity `grok-imagine-image-quality` model at `2k`
    ///     resolution; otherwise the standard `grok-imagine-image` model at `1k`.
    ///   - aspectRatio: requested aspect ratio (defaults to `"16:9"`, matching the cover art slot).
    /// - Returns: the generated image (URL + optional revised prompt), or `nil` on any failure.
    ///
    /// Port of `suspend fun generate(prompt, highQuality = false, aspectRatio = "16:9")`. Note the
    /// `XaiKeyStore.resolve()`/`isConfigured()` ordering is preserved exactly: `resolve()` is read
    /// first (so the Bearer value is assembled even when we early-out), then the configured guard
    /// runs. Cancellation is rethrown (never swallowed — CONVENTIONS §4) so an enclosing cancelled
    /// `Task` is not masked as a benign `nil`.
    func generate(
        prompt: String,
        highQuality: Bool = false,
        aspectRatio: String = "16:9"
    ) async -> GeneratedImage? {
        let apiKey = keyResolver.resolve()
        guard keyResolver.isConfigured() else {
            Self.logger.warning("xAI key missing — skipping image generation")
            return nil
        }
        do {
            let request = XAiImageRequest(
                model: highQuality ? GrokModels.imageQuality : GrokModels.image,
                prompt: prompt,
                n: 1,
                responseFormat: "url",
                aspectRatio: aspectRatio,
                resolution: highQuality ? "2k" : "1k"
            )
            let response = try await xAiApi.generateImages(
                authorization: "Bearer \(apiKey)",
                request: request
            )
            guard let first = response.data?.first, let url = first.url else {
                return nil
            }
            return GeneratedImage(url: url, revisedPrompt: first.revisedPrompt)
        } catch is CancellationError {
            // Never swallow cancellation as a benign nil (CONVENTIONS §4 "Cancellation").
            return nil
        } catch {
            // Catch-all matching the Kotlin `catch (e: Exception)` — log message only, never the
            // request/response body or the Authorization header (CONVENTIONS §3 secret hygiene).
            Self.logger.error("Image generation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Builds a tasteful, on-brand art prompt for a bookmark category so generated covers stay
    /// visually consistent across the research index. Direct port of `fun promptForCategory`.
    ///
    /// The subject prefers a non-blank `title`, else falls back to `category`, else the literal
    /// `"AI research"`. The style clause keys off the trimmed/lowercased category (the same nine
    /// research categories as the analysis schema, defaulting to `"minimal generative tech art"`).
    /// The final string is assembled byte-for-byte with the Kotlin template, including the escaped
    /// quotes around the subject and the trailing `". "` join.
    func promptForCategory(category: String?, title: String?) -> String {
        let subject: String = {
            if let title, !title.isBlank { return title }
            return category ?? "AI research"
        }()
        let style: String
        switch category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "architectures":
            style = "abstract neural network topology, flowing connections"
        case "training":
            style = "gradient descent landscape, glowing optimization paths"
        case "inference-opt":
            style = "streamlined data pipelines, speed and efficiency motifs"
        case "datasets":
            style = "structured grids of data points, organized information"
        case "evals":
            style = "benchmark dashboards, comparative bar charts"
        case "agents":
            style = "interconnected autonomous nodes, tool-use orchestration"
        case "multimodal":
            style = "fusion of vision and language, overlapping modalities"
        case "theory":
            style = "elegant mathematical forms, clean geometric abstraction"
        case "systems":
            style = "distributed compute clusters, server topology"
        default:
            style = "minimal generative tech art"
        }
        return "A sophisticated editorial cover illustration representing \"\(subject)\": \(style). "
            + "Modern, minimal, deep gradient palette, high contrast, no text."
    }
}

// `String.isBlank` is provided module-wide by CurioComponents.swift.
