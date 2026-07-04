import Foundation

/// X v2 bookmarks endpoint. Ports `interface XBookmarksApi` in `data/remote/XBookmarksApi.kt`.
///
/// Paginated GET to `https://api.twitter.com/2/users/{userId}/bookmarks` with the exact fixed query
/// expansions/fields the Retrofit `@Query` defaults carried. The `Authorization` header is passed
/// per-call (CONVENTIONS Networking cross-cutting). On non-2xx (e.g. 401 / 429) it throws
/// ``APIError`` so the repository can refresh tokens / read the rate-limit reset header.
protocol XBookmarksApi: Sendable {
    func getBookmarks(
        authHeader: String,
        userId: String,
        maxResults: Int,
        paginationToken: String?
    ) async throws -> BookmarksResponse
}

extension XBookmarksApi {
    /// Default-argument bridge mirroring the Kotlin `maxResults = 100`, `paginationToken = null`.
    func getBookmarks(authHeader: String, userId: String) async throws -> BookmarksResponse {
        try await getBookmarks(authHeader: authHeader, userId: userId, maxResults: 100, paginationToken: nil)
    }
}

/// Concrete `URLSession`-backed bookmarks client. `actor` per CONVENTIONS §5.
actor XBookmarksApiClient: XBookmarksApi {

    /// Base host (exact — CONVENTIONS Networking cross-cutting "authorize host `twitter.com` exact").
    static let baseURL = URL(string: "https://api.twitter.com/")!

    // Fixed v2 query parameters — byte-identical to the Retrofit `@Query` defaults.
    private static let tweetFields = "created_at,attachments,author_id,note_tweet,entities"
    private static let expansions = "attachments.media_keys,author_id"
    private static let mediaFields = "url,preview_image_url,type,alt_text"
    private static let userFields = "name,username"

    private let http: HTTPClient
    private let baseURL: URL

    init(http: HTTPClient, baseURL: URL = XBookmarksApiClient.baseURL) {
        self.http = http
        self.baseURL = baseURL
    }

    func getBookmarks(
        authHeader: String,
        userId: String,
        maxResults: Int = 100,
        paginationToken: String? = nil
    ) async throws -> BookmarksResponse {
        let base = baseURL.appendingPathComponent("2/users/\(userId)/bookmarks")
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "max_results", value: String(maxResults))
        ]
        if let token = paginationToken {
            items.append(URLQueryItem(name: "pagination_token", value: token))
        }
        items.append(contentsOf: [
            URLQueryItem(name: "tweet.fields", value: Self.tweetFields),
            URLQueryItem(name: "expansions", value: Self.expansions),
            URLQueryItem(name: "media.fields", value: Self.mediaFields),
            URLQueryItem(name: "user.fields", value: Self.userFields)
        ])
        components.queryItems = items

        let request = HTTPClient.jsonRequest(
            url: components.url!,
            method: "GET",
            authorization: authHeader
        )
        return try await http.send(BookmarksResponse.self, request: request, session: .primary)
    }
}
