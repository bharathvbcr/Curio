import Foundation
import os

/// Hugging Face model metadata. Port of `data class HfModelResponse`. `tags` defaults to `[]`;
/// `downloads`/`likes` are nullable (HF omits them for gated/private models and on 404).
struct HfModelResponse: Codable, Sendable, Equatable {
    let modelId: String?
    let id: String?
    let author: String?
    let downloads: Int?
    let likes: Int?
    let lastModified: String?
    let pipelineTag: String?
    let tags: [String]
    let description: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.modelId = try c.decodeIfPresent(String.self, forKey: .modelId)
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
        self.author = try c.decodeIfPresent(String.self, forKey: .author)
        self.downloads = try c.decodeIfPresent(Int.self, forKey: .downloads)
        self.likes = try c.decodeIfPresent(Int.self, forKey: .likes)
        self.lastModified = try c.decodeIfPresent(String.self, forKey: .lastModified)
        self.pipelineTag = try c.decodeIfPresent(String.self, forKey: .pipelineTag)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
    }

    enum CodingKeys: String, CodingKey {
        case modelId
        case id
        case author
        case downloads
        case likes
        case lastModified
        case pipelineTag = "pipeline_tag"
        case tags
        case description
    }
}

/// Hugging Face dataset metadata. Port of `data class HfDatasetResponse`. `tags` defaults to `[]`.
struct HfDatasetResponse: Codable, Sendable, Equatable {
    let id: String?
    let author: String?
    let downloads: Int?
    let likes: Int?
    let lastModified: String?
    let tags: [String]
    let description: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
        self.author = try c.decodeIfPresent(String.self, forKey: .author)
        self.downloads = try c.decodeIfPresent(Int.self, forKey: .downloads)
        self.likes = try c.decodeIfPresent(Int.self, forKey: .likes)
        self.lastModified = try c.decodeIfPresent(String.self, forKey: .lastModified)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case author
        case downloads
        case likes
        case lastModified
        case tags
        case description
    }
}

/// Hugging Face model/dataset metadata client. Ports `interface HuggingFaceApi` in
/// `data/remote/HuggingFaceApi.kt`.
///
/// GET `https://huggingface.co/api/models|datasets/{id}`. The id slashes are NOT percent-encoded
/// (Retrofit `@Path(encoded = true)` — `org/model` stays `org/model`). HF returns 404 for
/// private/non-existent ids → the Retrofit nullable return is `nil`; we map any non-success / error
/// to `nil`. `actor` per CONVENTIONS §5. Rethrows `CancellationError`.
actor HuggingFaceApiClient {

    static let baseURL = URL(string: "https://huggingface.co/")!

    private let http: HTTPClient
    private let baseURL: URL
    private static let logger = Logger(subsystem: "com.curio.app", category: "HuggingFaceApi")

    init(http: HTTPClient, baseURL: URL = HuggingFaceApiClient.baseURL) {
        self.http = http
        self.baseURL = baseURL
    }

    /// Port of `getModel(id:)` — `@Path(encoded = true)` so slashes in `id` are preserved literally.
    func getModel(_ id: String) async -> HfModelResponse? {
        await get(path: "api/models/", id: id, as: HfModelResponse.self)
    }

    /// Port of `getDataset(id:)`.
    func getDataset(_ id: String) async -> HfDatasetResponse? {
        await get(path: "api/datasets/", id: id, as: HfDatasetResponse.self)
    }

    private func get<T: Decodable & Sendable>(path: String, id: String, as type: T.Type) async -> T? {
        // Build the URL WITHOUT percent-encoding the id's slashes (encoded = true). We append the
        // raw id to the absolute string and parse, so `org/model` traverses path segments verbatim.
        let urlString = baseURL.absoluteString + path + id
        guard let url = URL(string: urlString) else { return nil }
        let request = HTTPClient.jsonRequest(url: url, method: "GET")
        do {
            return try await http.send(T.self, request: request, session: .metadata)
        } catch is CancellationError {
            return nil
        } catch let apiError as APIError {
            // 404 (and any other non-success) → nil, mirroring the nullable Retrofit return.
            if apiError.statusCode != 404 {
                Self.logger.warning("HF lookup HTTP \(apiError.statusCode ?? -1) for \(id)")
            }
            return nil
        } catch {
            Self.logger.warning("HF lookup failed for \(id)")
            return nil
        }
    }
}
