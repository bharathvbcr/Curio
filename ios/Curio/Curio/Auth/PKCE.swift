import Foundation
import CryptoKit

/// PKCE (RFC 7636) code-verifier / code-challenge generation. Ports the private
/// `generateCodeVerifier` / `generateCodeChallenge` helpers from `data/repo/AuthRepositoryImpl.kt`.
///
/// Byte-for-byte fidelity with the Android implementation is load-bearing — the verifier and
/// challenge must hash to the same value that X validated for the Android client, and the
/// base64url-no-pad encoding must match exactly:
///
/// - **verifier:** 32 cryptographically-secure random bytes → base64url, no padding, no line wraps
///   (`SecureRandom().nextBytes(ByteArray(32))` + `Base64.URL_SAFE or NO_PADDING or NO_WRAP`).
/// - **challenge:** `S256` = base64url-no-pad( SHA-256( ASCII bytes of verifier ) ). The Android
///   code hashes `verifier.toByteArray(Charsets.US_ASCII)` — the base64url verifier alphabet is pure
///   ASCII so UTF-8 and US-ASCII coincide here, but we encode to ASCII explicitly to preserve the
///   exact input bytes.
///
/// `SystemRandomNumberGenerator` / `SecRandomCopyBytes` provide the CSPRNG equivalent to Java's
/// `SecureRandom`; `CryptoKit.SHA256` replaces `MessageDigest.getInstance("SHA-256")`.
enum PKCE {

    /// Generates a fresh PKCE code verifier: 32 secure-random bytes, base64url-encoded with no
    /// padding (`=` stripped) and no line wrapping. Length is a fixed 43 characters (`ceil(32*4/3)`
    /// without padding), well within RFC 7636's 43–128 range.
    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // Defensive fallback to the system CSPRNG; in practice SecRandomCopyBytes does not fail.
            var generator = SystemRandomNumberGenerator()
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
            }
        }
        return base64URLNoPad(Data(bytes))
    }

    /// Computes the `S256` code challenge for `verifier`: base64url-no-pad of `SHA-256` over the
    /// verifier's ASCII bytes (matching `Charsets.US_ASCII` on Android).
    static func codeChallengeS256(for verifier: String) -> String {
        // The base64url alphabet is ASCII; encoding to ASCII reproduces the exact Android input
        // bytes. `data(using: .ascii)` cannot fail for an ASCII-only verifier, but fall back to
        // UTF-8 (identical for ASCII) if a caller ever passes non-ASCII.
        let asciiBytes = verifier.data(using: .ascii) ?? Data(verifier.utf8)
        let digest = SHA256.hash(data: asciiBytes)
        return base64URLNoPad(Data(digest))
    }

    /// Base64url (RFC 4648 §5) with padding removed — mirrors Android's
    /// `Base64.URL_SAFE or NO_PADDING or NO_WRAP`: standard base64 then `+`→`-`, `/`→`_`, drop `=`.
    /// `Data.base64EncodedString()` never inserts line breaks, matching `NO_WRAP`.
    private static func base64URLNoPad(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
