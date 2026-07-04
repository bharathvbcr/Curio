import Foundation
import os

/// Typed networking error surfaced by ``HTTPClient`` and the API clients built on top of it.
///
/// Mirrors the error model in CONVENTIONS §3. The Android stack used Retrofit/OkHttp exceptions
/// (`HttpException`, `IOException`) plus per-client `try/catch` that logged and returned
/// `null`/empty. On iOS the resilient clients still swallow these (log + `nil`/fallback); only the
/// auth `completeLogin` path and `syncBookmarks` propagate a typed failure.
///
/// SECURITY: `APIError` deliberately carries the response **headers** (needed for `429`
/// `x-rate-limit-reset` and arXiv `Retry-After`) and the raw body `Data`, but its `description`
/// **never** prints the `Authorization` header value or the request body (CONVENTIONS §3
/// "Never log secrets").
enum APIError: Error, Sendable {
    /// A non-2xx HTTP status. `headers` are lower-cased keys; `body` is the raw response payload.
    case http(status: Int, headers: [String: String], body: Data)
    /// A transport-level `URLError` (timeout, no connectivity, cancelled, …).
    case transport(URLError)
    /// A response decoding failure.
    case decoding(Error)

    /// The HTTP status code when this is an `.http` error, else `nil`.
    var statusCode: Int? {
        if case let .http(status, _, _) = self { return status }
        return nil
    }

    /// Response headers (lower-cased keys) when this is an `.http` error, else empty.
    var headers: [String: String] {
        if case let .http(_, headers, _) = self { return headers }
        return [:]
    }
}

extension APIError: CustomStringConvertible {
    /// Redacted description — never includes the `Authorization` header or any body bytes.
    var description: String {
        switch self {
        case let .http(status, _, _):
            return "APIError.http(status: \(status))"
        case let .transport(error):
            return "APIError.transport(\(error.code.rawValue))"
        case .decoding:
            return "APIError.decoding"
        }
    }
}

/// Shared, low-level HTTP layer used by every API client (xAI, X bookmarks/auth, arXiv, Crossref,
/// GitHub, Hugging Face).
///
/// Ports the OkHttp/Retrofit wiring from `di/AppContainer.kt`. There is no DI library; the two
/// `URLSession` configurations (primary 120s for xAI long calls, metadata 15s for scholarly
/// lookups — CONVENTIONS §2) are built once and reused. An `actor` so the lazily-built sessions and
/// shared coders are isolated.
///
/// The per-call `Authorization` header is passed by the caller (NOT an interceptor) so the secret
/// stays out of any shared state and is never logged (CONVENTIONS §3 / Networking cross-cutting:
/// "per-call `Bearer` header (not interceptor)").
actor HTTPClient {

    /// Long-call session: 120s request timeout, waits for connectivity. For xAI completions which
    /// can run for tens of seconds (reasoning + Live Search).
    let primarySession: URLSession

    /// Metadata session: 15s request timeout for the small scholarly lookups (arXiv / Crossref /
    /// GitHub / Hugging Face) where a fast failure is preferable to a long hang.
    let metadataSession: URLSession

    private static let logger = Logger(subsystem: "com.curio.app", category: "HTTPClient")

    /// Shared decoder/encoder. ISO-8601 dates; the xAI DTOs hand-roll their CodingKeys so no
    /// snake-case strategy is needed globally (CONVENTIONS §7 prefers explicit `CodingKeys`).
    /// Kept `private` so the non-`Sendable` coders never cross an actor isolation boundary — callers
    /// go through ``encode(_:)`` / ``send(_:request:session:)``.
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        let primaryConfig = URLSessionConfiguration.default
        primaryConfig.timeoutIntervalForRequest = 120
        primaryConfig.timeoutIntervalForResource = 300
        primaryConfig.waitsForConnectivity = true
        self.primarySession = URLSession(configuration: primaryConfig)

        let metadataConfig = URLSessionConfiguration.default
        metadataConfig.timeoutIntervalForRequest = 15
        metadataConfig.timeoutIntervalForResource = 30
        self.metadataSession = URLSession(configuration: metadataConfig)

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        self.decoder = decoder
        self.encoder = encoder
    }

    /// Allow construction from caller-supplied sessions (test injection / `MockURLProtocol`).
    init(primarySession: URLSession, metadataSession: URLSession) {
        self.primarySession = primarySession
        self.metadataSession = metadataSession
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Raw data

    /// Selects which configured session to use for a request.
    enum SessionKind: Sendable {
        case primary
        case metadata
    }

    private func session(for kind: SessionKind) -> URLSession {
        switch kind {
        case .primary: return primarySession
        case .metadata: return metadataSession
        }
    }

    /// Performs `request` and returns the raw body, throwing ``APIError`` for non-2xx status or a
    /// transport failure. The response status / headers are surfaced inside `.http` so callers can
    /// inspect `429` reset headers or arXiv `Retry-After`. Cancellation is rethrown.
    func data(for request: URLRequest, session kind: SessionKind = .primary) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session(for: kind).data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport(URLError(.badServerResponse))
            }
            if !(200..<300).contains(http.statusCode) {
                throw APIError.http(
                    status: http.statusCode,
                    headers: Self.lowercasedHeaders(http),
                    body: data
                )
            }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw APIError.transport(error)
        } catch is CancellationError {
            throw CancellationError()
        }
    }

    // MARK: - Decoded send

    /// Performs `request` and decodes the body as `T`, mirroring the Retrofit `suspend fun` contract
    /// (success → decoded value; non-2xx → throw). Decoding errors become `APIError.decoding`.
    func send<T: Decodable & Sendable>(
        _ type: T.Type = T.self,
        request: URLRequest,
        session kind: SessionKind = .primary
    ) async throws -> T {
        let (data, _) = try await data(for: request, session: kind)
        do {
            return try decoder.decode(T.self, from: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Encodes `value` to JSON using the shared encoder (kept actor-isolated so the non-`Sendable`
    /// `JSONEncoder` never crosses an isolation boundary).
    func encode<T: Encodable & Sendable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    // MARK: - Helpers

    /// Lower-cases header names so lookups (`x-rate-limit-reset`, `retry-after`) are case-stable.
    static func lowercasedHeaders(_ response: HTTPURLResponse) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                result[k.lowercased()] = v
            }
        }
        return result
    }

    /// Builds a `URLRequest` for `url` with a JSON `Accept` and the (optional) per-call
    /// `Authorization` header. The header value is NEVER logged.
    static func jsonRequest(
        url: URL,
        method: String,
        authorization: String? = nil,
        body: Data? = nil,
        extraHeaders: [String: String] = [:]
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        if let authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}
