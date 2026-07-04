import Foundation

/// Process-wide holder for the user-supplied xAI API key (BYOK). Ports `object XaiKeyStore` from
/// `data/XaiKeyStore.kt`.
///
/// No key ships inside the app bundle. Users paste their own key in Settings → xAI API Key;
/// it is stored in the Keychain via `TokenStore` (under `xai_key_surface`) and loaded into the
/// runtime slot at app startup and whenever the user saves a new value.
///
/// **Why a synchronous holder and not constructor injection / async TokenStore reads:** the read
/// sites (`GrokImageService`, `EmbeddingService`, `XAiAnalyzer`) call `resolve()` / `isConfigured()`
/// synchronously inside non-async code paths, exactly as the Android `object` did. `TokenStore` is
/// an `actor` (async), so it cannot be read synchronously here. We therefore mirror Android's
/// design 1:1: a `static` runtime slot is populated **asynchronously** at startup and whenever the
/// user saves a key (`CurioApp`/`BookmarkViewModel` call `setRuntimeKey(await tokenStore.getXaiKey())`),
/// and `resolve()` reads that cached value with no awaiting (BYOK — there is no build-time
/// fallback; an unset key resolves to `""`).
///
/// `DESIGN.md` types this as a `struct`; the mutable runtime state is a `static` slot (the key is
/// genuinely app-global — the same global-singleton justification as the Kotlin `object`). The slot
/// is guarded by a lock so it is `Sendable`-safe under Swift 6 strict concurrency.
struct XaiKeyStore: Sendable {

    // Runtime slot for the user-supplied key. `nil`/blank means "no key configured".
    // Guarded by `lock` so concurrent reads/writes are data-race-free (replaces Kotlin `@Volatile`).
    nonisolated(unsafe) private static var runtimeKey: String?
    private static let lock = NSLock()

    init() {}

    /// Sets (or clears, with `nil`/blank) the user-supplied key (Kotlin `setRuntimeKey`). Called
    /// after an async `TokenStore.getXaiKey()` read at startup and from Settings when the user saves.
    ///
    /// Trims first: a key pasted into Settings or loaded from disk can carry a trailing newline or
    /// spaces. Left intact, that whitespace makes URLSession reject the "Bearer …" header (an
    /// illegal header value), breaking every xAI call. Trimming here — the single write choke
    /// point — sanitizes every path (Settings save, startup load) so `resolve()` always returns a
    /// clean key.
    static func setRuntimeKey(_ key: String?) {
        let normalized = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        runtimeKey = (normalized?.isEmpty ?? true) ? nil : normalized
        lock.unlock()
    }

    /// The user-supplied key, or empty string if none has been set.
    /// Kotlin `resolve(): String = runtimeKey ?: ""`.
    func resolve() -> String {
        Self.lock.lock()
        let key = Self.runtimeKey
        Self.lock.unlock()
        return key ?? ""
    }

    /// True only when the user has saved a non-blank key (Kotlin `isConfigured()`).
    func isConfigured() -> Bool {
        !resolve().isEmpty
    }
}
