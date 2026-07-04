import Foundation

// ---------------------------------------------------------------------------
// X OAuth2 token + identity DTOs — direct port of `data/remote/XAuthStructures.kt`.
// ---------------------------------------------------------------------------

/// OAuth2 token response. Port of `TokenResponse`. `refreshToken`/`expiresIn`/`scope` are optional
/// (some grants omit them); `accessToken` is required.
struct TokenResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}

/// `/2/users/me` envelope. Port of `UserResponse`.
struct UserResponse: Codable, Sendable {
    let data: UserData
}

/// The authenticated user's identity. Port of `UserData`. All three fields are required by the
/// Kotlin DTO (non-null) — keep them non-optional so a malformed payload fails decoding (the only
/// caller surfaces that as a login failure).
struct UserData: Codable, Sendable {
    let id: String
    let name: String
    let username: String
}
