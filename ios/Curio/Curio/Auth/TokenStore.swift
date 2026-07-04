import Foundation
import Combine
import Security
import os

/// Persists and retrieves OAuth credentials (and the HF / xAI secrets) in the iOS **Keychain**.
/// Ports `data/remote/TokenStore.kt`.
///
/// Android used AndroidKeyStore AES-GCM over a Preferences DataStore named `curio_tokens`. On iOS
/// the Keychain already provides hardware-backed, at-rest-encrypted secure storage, so we take
/// **Path A** (direct Keychain, CONVENTIONS §"AndroidKeyStore AES-GCM + DataStore" / §9) — each
/// secret is a `kSecClassGenericPassword` item with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (available after first unlock, never
/// migrated to a new device — mirroring the device-bound, non-exportable AndroidKeyStore key). The
/// per-item AES-GCM envelope the Android code hand-rolled is unnecessary and intentionally dropped:
/// the Keychain is the encryption boundary.
///
/// **Account-string fidelity (CONVENTIONS §"Persistence-key stability is sacred"):** the Keychain
/// `kSecAttrAccount` values are the *exact* DataStore preference keys from Android
/// (`access_token_surface`, `refresh_token_surface`, `user_id`, `user_username`, `user_name`,
/// `hf_token_surface`, `xai_key_surface`) so a migrated install (or a shared semantic contract)
/// reads/writes the same logical slots. Never rename these.
///
/// **Semantics preserved verbatim from Kotlin:**
/// - `hasTokens()` = access-token item present AND non-empty (`!isNullOrEmpty`).
/// - `saveTokens(refreshToken: nil)` writes an empty string for the refresh slot (Kotlin
///   `refreshToken?.let { encrypt(it) } ?: ""`), so a later `getRefreshToken()` returns `nil`
///   (empty → treated as absent, see `getRefreshToken`).
/// - `saveTokens(username: nil)` / `name: nil` **removes** that item (Kotlin `preferences.remove`).
/// - `saveXaiKey("")` / blank **deletes** the xAI item (Kotlin `if (key.isBlank()) remove`).
/// - `clear()` removes ONLY the X-session items (access/refresh/userId/username/name); the HF token
///   and xAI key intentionally survive (Kotlin `clear` leaves `KEY_HF_TOKEN` / `KEY_XAI_KEY`).
///
/// **Reactive identity (CONVENTIONS §11):** Android exposed `userIdFlow` / `usernameFlow` /
/// `nameFlow` as hot DataStore-backed `Flow<String?>`. Here three `CurrentValueSubject<String?,
/// Never>` carry the current value and re-emit on every `saveTokens` / `clear`, exposed as
/// `AnyPublisher`s. They are seeded from the Keychain at construction. The subjects are reference
/// types, created before isolation is established, and are `nonisolated` so `AuthRepositoryImpl`'s
/// boot restore and the auth controller can subscribe without hopping onto the actor.
///
/// `actor` per CONVENTIONS §5 (owns mutable secure-storage access; serializes reads/writes).
actor TokenStore {

    // MARK: - Account keys (mirror Android DataStore preference keys EXACTLY)

    private enum Account {
        static let accessToken = "access_token_surface"
        static let refreshToken = "refresh_token_surface"
        static let userId = "user_id"
        static let username = "user_username"
        static let name = "user_name"
        static let huggingFaceToken = "hf_token_surface"
        static let xaiKey = "xai_key_surface"
    }

    /// Keychain service namespace for all Curio secrets (groups the items; mirrors the
    /// `curio_tokens` DataStore name).
    private static let service = "com.curio.app.tokens"

    /// UserDefaults key for the agent-write permission (Android DataStore `allow_agent_writes`).
    /// A plain preference, not a secret — it lives in UserDefaults, not the Keychain.
    private static let allowAgentWritesKey = "allow_agent_writes"

    private static let logger = Logger(subsystem: "com.curio.app", category: "TokenStore")

    // MARK: - Reactive identity subjects (nonisolated, reference-typed, thread-safe)

    // `nonisolated(unsafe)`: Combine subjects are reference-typed and thread-safe for send/subscribe
    // but not formally `Sendable`; we vouch for the cross-isolation access.
    private nonisolated(unsafe) let userIdSubject: CurrentValueSubject<String?, Never>
    private nonisolated(unsafe) let usernameSubject: CurrentValueSubject<String?, Never>
    private nonisolated(unsafe) let nameSubject: CurrentValueSubject<String?, Never>
    private nonisolated(unsafe) let allowAgentWritesSubject: CurrentValueSubject<Bool, Never>

    /// Observable mapping of the current logged-in X userId (Android `userIdFlow`).
    nonisolated var userIdPublisher: AnyPublisher<String?, Never> {
        userIdSubject.eraseToAnyPublisher()
    }

    /// Observable X handle (without the leading `@`) of the current account (Android `usernameFlow`).
    nonisolated var usernamePublisher: AnyPublisher<String?, Never> {
        usernameSubject.eraseToAnyPublisher()
    }

    /// Observable X display name of the current account (Android `nameFlow`).
    nonisolated var namePublisher: AnyPublisher<String?, Never> {
        nameSubject.eraseToAnyPublisher()
    }

    /// Whether on-device AI agents / system assistants may invoke the *write* App Intents
    /// (add bookmark, add note, toggle favourite). Defaults to true; the user can revoke it in
    /// Settings. Read-only discovery/detail intents are unaffected. Android `allowAgentWritesFlow`.
    nonisolated var allowAgentWritesPublisher: AnyPublisher<Bool, Never> {
        allowAgentWritesSubject.eraseToAnyPublisher()
    }

    // MARK: - Init

    init() {
        // Seed the subjects from the Keychain so subscribers see the persisted identity immediately
        // (mirrors DataStore replaying the last value to a new collector). Reads here are static so
        // they do not touch actor-isolated state.
        userIdSubject = CurrentValueSubject(Self.readString(account: Account.userId))
        usernameSubject = CurrentValueSubject(Self.readString(account: Account.username))
        nameSubject = CurrentValueSubject(Self.readString(account: Account.name))
        allowAgentWritesSubject = CurrentValueSubject(Self.readAllowAgentWrites())
    }

    // MARK: - Session reads

    /// Returns the currently logged-in X userId, or `nil` if not signed in. Plain `suspend` →
    /// `async` (no throws), per CONVENTIONS §3.
    func getUserId() -> String? {
        Self.readString(account: Account.userId)
    }

    /// Checks whether cached credentials exist: the access-token item must be present AND non-empty
    /// (Kotlin `!prefs[KEY_ACCESS_TOKEN_SURFACE].isNullOrEmpty()`).
    func hasTokens() -> Bool {
        guard let token = Self.readString(account: Account.accessToken) else { return false }
        return !token.isEmpty
    }

    /// Resolves the plain-text access token, or `nil` if none was saved.
    func getAccessToken() -> String? {
        Self.readString(account: Account.accessToken)
    }

    /// Resolves the stored X handle (without the leading `@`), or `nil`. Mirrors reading the
    /// Android `usernameFlow`'s current value (used by the boot restore).
    func getUsername() -> String? {
        Self.readString(account: Account.username)
    }

    /// Resolves the stored X display name, or `nil`. Mirrors reading the Android `nameFlow`'s
    /// current value (used by the boot restore).
    func getName() -> String? {
        Self.readString(account: Account.name)
    }

    /// Resolves the plain-text refresh token, or `nil` if none was saved. The empty-string sentinel
    /// written for a missing refresh token (see `saveTokens`) is normalised back to `nil`.
    func getRefreshToken() -> String? {
        guard let token = Self.readString(account: Account.refreshToken), !token.isEmpty else {
            return nil
        }
        return token
    }

    // MARK: - Session writes

    /// Saves credentials. Mirrors the Kotlin write transaction exactly:
    /// - refresh token: persisted, or empty string when `nil`;
    /// - username / name: written when non-nil, otherwise the item is **removed**.
    func saveTokens(
        accessToken: String,
        refreshToken: String?,
        userId: String,
        username: String? = nil,
        name: String? = nil
    ) {
        Self.write(account: Account.accessToken, value: accessToken)
        Self.write(account: Account.refreshToken, value: refreshToken ?? "")
        Self.write(account: Account.userId, value: userId)

        if let username {
            Self.write(account: Account.username, value: username)
        } else {
            Self.delete(account: Account.username)
        }

        if let name {
            Self.write(account: Account.name, value: name)
        } else {
            Self.delete(account: Account.name)
        }

        // Re-emit identity (mirrors DataStore Flow re-emission on edit).
        userIdSubject.send(userId)
        usernameSubject.send(username)
        nameSubject.send(name)
    }

    // MARK: - Hugging Face token (survives clear())

    /// Resolves the Hugging Face token used to fetch gated model weights, or `nil`. Independent of
    /// the X session — intentionally **not** removed by `clear()`.
    func getHuggingFaceToken() -> String? {
        Self.readString(account: Account.huggingFaceToken)
    }

    /// Persists the Hugging Face token.
    func saveHuggingFaceToken(_ token: String) {
        Self.write(account: Account.huggingFaceToken, value: token)
    }

    // MARK: - xAI key (survives clear(); blank deletes)

    /// Resolves the user-supplied xAI API key, or `nil`. Independent of the X session — intentionally
    /// **not** removed by `clear()`.
    func getXaiKey() -> String? {
        Self.readString(account: Account.xaiKey)
    }

    /// Persists (or clears, with a blank value) the xAI API key. Mirrors Kotlin: a blank key
    /// **removes** the item rather than storing whitespace.
    func saveXaiKey(_ key: String) {
        if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Self.delete(account: Account.xaiKey)
        } else {
            Self.write(account: Account.xaiKey, value: key)
        }
    }

    // MARK: - Agent write permission (plain preference; survives clear())

    /// One-shot read of the agent-write permission, for the App Intent write gate
    /// (Android `isAgentWritesAllowed`). Defaults to true when never set.
    func isAgentWritesAllowed() -> Bool {
        Self.readAllowAgentWrites()
    }

    /// Persists the agent-write permission toggled from Settings (Android `setAgentWritesAllowed`).
    func setAgentWritesAllowed(_ allowed: Bool) {
        UserDefaults.standard.set(allowed, forKey: Self.allowAgentWritesKey)
        allowAgentWritesSubject.send(allowed)
    }

    /// Reads the persisted permission, defaulting to true when the key was never written
    /// (mirrors Android `preferences[KEY_ALLOW_AGENT_WRITES] ?: true`).
    private static func readAllowAgentWrites() -> Bool {
        UserDefaults.standard.object(forKey: allowAgentWritesKey) as? Bool ?? true
    }

    // MARK: - Session purge

    /// Purges the X-session items ONLY (access/refresh/userId/username/name). The HF token and xAI
    /// key intentionally survive (mirrors Kotlin `clear`, which leaves `KEY_HF_TOKEN` / `KEY_XAI_KEY`
    /// in place).
    func clear() {
        Self.delete(account: Account.accessToken)
        Self.delete(account: Account.refreshToken)
        Self.delete(account: Account.userId)
        Self.delete(account: Account.username)
        Self.delete(account: Account.name)

        userIdSubject.send(nil)
        usernameSubject.send(nil)
        nameSubject.send(nil)
    }

    // MARK: - Keychain primitives (static — used during init before isolation is established)

    /// Base query identifying a single generic-password item by service + account.
    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Reads a UTF-8 string for `account`, or `nil` if absent / unreadable. Resilient (logs +
    /// returns `nil`) — never throws, mirroring the Android decrypt `catch → null` contract
    /// (CONVENTIONS §3 "Resilience contract").
    private static func readString(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                logger.warning("Keychain read failed (status: \(status))")
            }
            return nil
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Upserts a UTF-8 string for `account`. Performs an update-then-add so the item is replaced
    /// in place (mirrors DataStore `edit { … = value }` overwrite semantics).
    private static func write(account: String, value: String) {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.warning("Keychain add failed (status: \(addStatus))")
            }
        } else {
            logger.warning("Keychain update failed (status: \(updateStatus))")
        }
    }

    /// Removes the item for `account` (idempotent — `errSecItemNotFound` is success).
    private static func delete(account: String) {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.warning("Keychain delete failed (status: \(status))")
        }
    }
}
