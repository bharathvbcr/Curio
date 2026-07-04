import Foundation

/// X OAuth2 token + identity endpoints. Ports `interface XAuthApi` in
/// `data/remote/XAuthStructures.kt`.
///
/// `exchangeToken` / `refreshToken` POST `application/x-www-form-urlencoded` bodies to
/// `2/oauth2/token`; `getUserMe` GETs `2/users/me` with a per-call `Authorization` header. Base host
/// is `https://api.twitter.com/`. These are the ONE auth path that surfaces a typed failure
/// (CONVENTIONS §3 — `completeLogin` throws), so the client propagates ``APIError`` on non-2xx.
protocol XAuthApi: Sendable {
    func exchangeToken(
        grantType: String,
        clientId: String,
        redirectUri: String,
        code: String,
        codeVerifier: String
    ) async throws -> TokenResponse

    func refreshToken(
        grantType: String,
        clientId: String,
        refreshToken: String
    ) async throws -> TokenResponse

    func getUserMe(authorization: String) async throws -> UserResponse
}

/// Concrete `URLSession`-backed auth client. `actor` per CONVENTIONS §5.
actor XAuthApiClient: XAuthApi {

    /// Base host (exact — matches the Android Retrofit base `https://api.twitter.com/`).
    static let baseURL = URL(string: "https://api.twitter.com/")!

    private let http: HTTPClient
    private let baseURL: URL

    init(http: HTTPClient, baseURL: URL = XAuthApiClient.baseURL) {
        self.http = http
        self.baseURL = baseURL
    }

    func exchangeToken(
        grantType: String,
        clientId: String,
        redirectUri: String,
        code: String,
        codeVerifier: String
    ) async throws -> TokenResponse {
        let body = Self.formURLEncoded([
            ("grant_type", grantType),
            ("client_id", clientId),
            ("redirect_uri", redirectUri),
            ("code", code),
            ("code_verifier", codeVerifier)
        ])
        return try await postForm("2/oauth2/token", body: body)
    }

    func refreshToken(
        grantType: String,
        clientId: String,
        refreshToken: String
    ) async throws -> TokenResponse {
        let body = Self.formURLEncoded([
            ("grant_type", grantType),
            ("client_id", clientId),
            ("refresh_token", refreshToken)
        ])
        return try await postForm("2/oauth2/token", body: body)
    }

    func getUserMe(authorization: String) async throws -> UserResponse {
        let url = baseURL.appendingPathComponent("2/users/me")
        let request = HTTPClient.jsonRequest(url: url, method: "GET", authorization: authorization)
        return try await http.send(UserResponse.self, request: request, session: .primary)
    }

    // MARK: - Plumbing

    private func postForm(_ path: String, body: Data) async throws -> TokenResponse {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        return try await http.send(TokenResponse.self, request: request, session: .primary)
    }

    /// `application/x-www-form-urlencoded` body builder. Matches Retrofit `@Field` encoding:
    /// form-component percent-encoding (space → `%20`, not `+`; `&`/`=` escaped).
    static func formURLEncoded(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = pairs.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }
}
