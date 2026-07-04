package com.example.data

/**
 * Process-wide holder for the user-supplied xAI API key (BYOK).
 *
 * No key ships inside the APK. Users paste their own key in Settings → xAI API Key;
 * it is encrypted via [com.example.data.remote.TokenStore] and loaded into [runtimeKey]
 * at app startup and whenever the user saves a new value.
 *
 * A simple singleton (rather than constructor injection through every AI service) keeps the
 * change surface to the read sites; the key is genuinely app-global.
 */
object XaiKeyStore {

    @Volatile
    private var runtimeKey: String? = null

    /**
     * Sets (or clears, with null/blank) the user-supplied key.
     *
     * Trims first: a key pasted into Settings or loaded from disk can carry a trailing newline or
     * spaces. Left intact, that whitespace makes OkHttp throw on the "Bearer …" header (an illegal
     * header value), breaking every xAI call. Trimming here — the single write choke point — sanitizes
     * every path (Settings save, startup load) so [resolve] always returns a clean key.
     */
    fun setRuntimeKey(key: String?) {
        runtimeKey = key?.trim()?.takeIf { it.isNotBlank() }
    }

    /** The user-supplied key, or empty string if none has been set. */
    fun resolve(): String = runtimeKey ?: ""

    /** True only when the user has saved a non-blank key. */
    fun isConfigured(): Boolean = !runtimeKey.isNullOrBlank()
}
