package com.example.data.embedding

import android.content.Context

/**
 * Which backend computes embeddings. The user can override the automatic choice from Settings so a
 * "0 embedded" result is diagnosable: e.g. forcing [ON_DEVICE] makes it obvious the local model
 * isn't downloaded, and forcing [XAI] surfaces that xAI ships no public embeddings endpoint yet
 * (see [com.example.data.remote.GrokModels.EMBEDDING]).
 */
enum class EmbeddingBackend {
    /** On-device EmbeddingGemma when downloaded, else the xAI cloud fallback. Default. */
    AUTO,

    /** Force on-device EmbeddingGemma; never falls back to the cloud (fully private). */
    ON_DEVICE,

    /** Force the xAI cloud embedder; never runs on-device. */
    XAI
}

/**
 * Persists the chosen [EmbeddingBackend]. Shares the same prefs file as
 * [com.example.background.EmbeddingIndexScheduler] so all embedding settings live together.
 */
object EmbeddingPreference {

    private const val PREFS = "curio_embedding_prefs"
    private const val KEY_BACKEND = "embedding_backend"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun get(context: Context): EmbeddingBackend =
        prefs(context).getString(KEY_BACKEND, null)
            ?.let { name -> runCatching { EmbeddingBackend.valueOf(name) }.getOrNull() }
            ?: EmbeddingBackend.AUTO

    fun set(context: Context, backend: EmbeddingBackend) {
        prefs(context).edit().putString(KEY_BACKEND, backend.name).apply()
    }
}
