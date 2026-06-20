package com.example.data

/**
 * Process-wide resolver for the xAI API key.
 *
 * Shipping a shared developer key inside the APK lets any installer extract it and run up the
 * developer's xAI bill. This holder prefers a key the user supplied at runtime (persisted
 * encrypted in [com.example.data.remote.TokenStore] and loaded into [runtimeKey] at startup /
 * when saved in Settings) and only falls back to the build-time [com.example.BuildConfig.XAI_API_KEY]
 * — which for a public release should be left as the `.env.example` placeholder so no real key
 * ever ships.
 *
 * A simple holder (rather than constructor injection through every AI service) keeps the change
 * surface to the read sites; the key is genuinely app-global.
 */
object XaiKeyStore {

    @Volatile
    private var runtimeKey: String? = null

    /** Sets (or clears, with null/blank) the user-supplied key. */
    fun setRuntimeKey(key: String?) {
        runtimeKey = key?.takeIf { it.isNotBlank() }
    }

    /** The user key if present, else the build-time fallback (which may be a placeholder). */
    fun resolve(): String = runtimeKey ?: com.example.BuildConfig.XAI_API_KEY

    /** True when a usable key is configured (set by the user or a real build-time key). */
    fun isConfigured(): Boolean = resolve().let { it.isNotEmpty() && it != PLACEHOLDER }

    const val PLACEHOLDER = "MY_XAI_API_KEY"
}
