import Foundation

/// Build-time configuration and secret resolver — the iOS analogue of Android `com.example.BuildConfig`.
///
/// On Android these values are baked into `BuildConfig` by `build.gradle.kts` (`X_CLIENT_ID`,
/// `X_REDIRECT_URI`) and by the Secrets Gradle Plugin from `.env` / `.env.example`
/// (`CLIENT_ID`). On iOS the same role is played by build settings
/// (`.xcconfig`) surfaced into the app's `Info.plist`, read here at runtime (CONVENTIONS §9
/// "Config (`CurioConfig`) sources … from Info.plist/xcconfig (Android `BuildConfig` analogue)").
///
/// Resolution order for every key mirrors Android exactly: an Info.plist value (the
/// xcconfig-injected secret) wins, falling back to the same baked-in default the Gradle script
/// uses when no `local.properties` / `.env` value is present. This keeps a checkout-and-run build
/// behaving identically to the Android app without any local secret configuration.
///
/// Secrets policy (CONVENTIONS §3, §9): BYOK — the xAI API key and the Hugging Face token are NOT
/// baked into the build at all. Users supply them at runtime in Settings and they live in the
/// Keychain (`TokenStore`); see `XaiKeyStore` and `EmbeddingModelManager`. Only the OAuth client
/// id / redirect URI remain build-time configuration.
enum CurioConfig {

    // MARK: - Baked-in defaults (mirror `app/build.gradle.kts` + `.env.example`)

    /// Default X (Twitter) OAuth client id baked into `build.gradle.kts`
    /// (`xClientId … ?: "S2l6bVJubWFrTmh1emUxYW45dmM6MTpjaQ"`). Used when neither an
    /// Info.plist override nor a `CLIENT_ID` secret is provided.
    private static let defaultXClientID = "S2l6bVJubWFrTmh1emUxYW45dmM6MTpjaQ"

    /// Default OAuth redirect URI baked into `build.gradle.kts`
    /// (`xRedirectUri … ?: "curio-oauth://callback"`). Also registered as the
    /// ASWebAuthenticationSession callback scheme (`curio-oauth`).
    private static let defaultXRedirectURI = "curio-oauth://callback"

    // MARK: - Info.plist keys (xcconfig-injected secrets)

    private enum Key {
        /// Secrets-plugin `CLIENT_ID` (distinct from `X_CLIENT_ID`; empty by default on Android —
        /// `BuildConfig.CLIENT_ID.takeIf { it.isNotEmpty() } ?: BuildConfig.X_CLIENT_ID`).
        static let clientID = "CLIENT_ID"
        /// Gradle `X_CLIENT_ID` (the baked default applies when absent).
        static let xClientID = "X_CLIENT_ID"
        /// Gradle `X_REDIRECT_URI`.
        static let xRedirectURI = "X_REDIRECT_URI"
    }

    /// Reads a string from the main bundle's Info.plist, trimming nothing (values are used verbatim
    /// to preserve Android `BuildConfig` byte-for-byte semantics). Returns `nil` when the key is
    /// absent or not a string.
    private static func plist(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    // MARK: - Public configuration surface

    /// The X (Twitter) OAuth2 client id, resolved exactly as Android resolves it in
    /// `AuthRepositoryImpl`: a non-empty secrets-plugin `CLIENT_ID` wins, otherwise the
    /// Gradle `X_CLIENT_ID` (with its baked default). Every call site that does
    /// `BuildConfig.CLIENT_ID.takeIf { it.isNotEmpty() } ?: BuildConfig.X_CLIENT_ID`
    /// maps to this single resolved value.
    static var clientID: String {
        let secretClientID = plist(Key.clientID) ?? ""
        if !secretClientID.isEmpty { return secretClientID }
        return xClientID
    }

    /// The raw Gradle `X_CLIENT_ID` value (Info.plist override else baked default). Exposed for the
    /// one Repository call site (`BookmarkRepositoryImpl`) that reads `X_CLIENT_ID` first and only
    /// then falls back to `CLIENT_ID` — the inverse precedence of `clientID`.
    static var xClientID: String {
        let value = plist(Key.xClientID) ?? ""
        return value.isEmpty ? defaultXClientID : value
    }

    /// Repository-side client-id resolution mirroring `BookmarkRepositoryImpl`:
    /// `X_CLIENT_ID.ifBlank { CLIENT_ID }`. Note the precedence is the reverse of `clientID`
    /// (used by `AuthRepositoryImpl`); both are preserved verbatim.
    static var repositoryClientID: String {
        let primary = xClientID
        if !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return primary }
        let secret = plist(Key.clientID) ?? ""
        return secret
    }

    /// The OAuth2 redirect URI (`BuildConfig.X_REDIRECT_URI`); also the
    /// ASWebAuthenticationSession callback scheme host. Info.plist override else baked default.
    static var xRedirectURI: String {
        let value = plist(Key.xRedirectURI) ?? ""
        return value.isEmpty ? defaultXRedirectURI : value
    }

    /// The URL scheme component of `xRedirectURI` (e.g. `curio-oauth`), used as the
    /// `callbackURLScheme` for `ASWebAuthenticationSession`. Falls back to the default scheme if
    /// the configured URI has no scheme.
    static var callbackScheme: String {
        if let scheme = URLComponents(string: xRedirectURI)?.scheme, !scheme.isEmpty {
            return scheme
        }
        return URLComponents(string: defaultXRedirectURI)?.scheme ?? "curio-oauth"
    }

}
