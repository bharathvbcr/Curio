import Foundation
import os

/// GitHub repo owner. Port of `data class GithubOwner`.
struct GithubOwner: Codable, Sendable, Equatable {
    let login: String
}

/// GitHub repo metadata. Port of `data class GithubRepoResponse`. `stars` defaults to 0, `topics`
/// to `[]` (mirrors the Kotlin defaults so missing/null fields decode safely).
struct GithubRepoResponse: Codable, Sendable, Equatable {
    let fullName: String
    let description: String?
    let stars: Int
    let language: String?
    let topics: [String]
    let pushedAt: String?
    let owner: GithubOwner

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.fullName = try c.decode(String.self, forKey: .fullName)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.stars = try c.decodeIfPresent(Int.self, forKey: .stars) ?? 0
        self.language = try c.decodeIfPresent(String.self, forKey: .language)
        self.topics = try c.decodeIfPresent([String].self, forKey: .topics) ?? []
        self.pushedAt = try c.decodeIfPresent(String.self, forKey: .pushedAt)
        self.owner = try c.decode(GithubOwner.self, forKey: .owner)
    }

    init(
        fullName: String,
        description: String? = nil,
        stars: Int = 0,
        language: String? = nil,
        topics: [String] = [],
        pushedAt: String? = nil,
        owner: GithubOwner
    ) {
        self.fullName = fullName
        self.description = description
        self.stars = stars
        self.language = language
        self.topics = topics
        self.pushedAt = pushedAt
        self.owner = owner
    }

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case description
        case stars = "stargazers_count"
        case language
        case topics
        case pushedAt = "pushed_at"
        case owner
    }
}

/// GitHub repo metadata client. Ports `interface GithubApi` in `data/remote/GithubApi.kt`.
///
/// GET `https://api.github.com/repos/{owner}/{repo}` with the fixed `Accept` /
/// `X-GitHub-Api-Version` headers. `actor` per CONVENTIONS §5. Resilient: logs + returns `nil` on
/// any failure; rethrows `CancellationError`.
actor GithubApiClient {

    static let baseURL = URL(string: "https://api.github.com/")!

    private static let acceptHeader = "application/vnd.github+json"
    private static let apiVersion = "2022-11-28"

    private let http: HTTPClient
    private let baseURL: URL
    private static let logger = Logger(subsystem: "com.curio.app", category: "GithubApi")

    init(http: HTTPClient, baseURL: URL = GithubApiClient.baseURL) {
        self.http = http
        self.baseURL = baseURL
    }

    /// Port of `getRepo(owner:repo:)`. The Android Retrofit method is non-optional (`suspend fun …:
    /// GithubRepoResponse`); the resilient caller wraps it in `try/catch` → nil. We fold that into a
    /// nil-returning method so callers match the resolver's expectations.
    func getRepo(owner: String, repo: String) async -> GithubRepoResponse? {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)")
        let request = HTTPClient.jsonRequest(
            url: url,
            method: "GET",
            extraHeaders: [
                "Accept": Self.acceptHeader,
                "X-GitHub-Api-Version": Self.apiVersion
            ]
        )
        do {
            return try await http.send(GithubRepoResponse.self, request: request, session: .metadata)
        } catch is CancellationError {
            return nil
        } catch {
            Self.logger.warning("GitHub repo lookup failed for \(owner)/\(repo)")
            return nil
        }
    }
}
