package com.example.data.semantic

import android.content.Context

/**
 * User preference for the on-device semantic layer (response cache + RAG compression +
 * complexity routing). When enabled, chat consults the local cache before calling xAI, compresses
 * retrieved context, and routes reasoning effort by query complexity. Everything runs on-device;
 * disabling it makes chat call xAI directly with the full retrieved context.
 */
object SemanticPreference {

    private const val PREFS = "curio_embedding_prefs"
    private const val KEY_ENABLED = "semantic_layer_enabled"
    private const val KEY_THRESHOLD = "semantic_cache_threshold"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Default ON. Disable in Settings to skip the semantic layer entirely. */
    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    /**
     * Adaptive cosine threshold for a semantic cache hit. Nudged up on thumbs-down feedback so a
     * bad match isn't repeated; persisted so tuning survives restarts. Clamped to [MIN, MAX].
     */
    fun getCacheThreshold(context: Context): Float =
        prefs(context).getFloat(KEY_THRESHOLD, THRESHOLD_INITIAL).coerceIn(THRESHOLD_MIN, THRESHOLD_MAX)

    fun setCacheThreshold(context: Context, value: Float) {
        prefs(context).edit()
            .putFloat(KEY_THRESHOLD, value.coerceIn(THRESHOLD_MIN, THRESHOLD_MAX))
            .apply()
    }

    const val THRESHOLD_INITIAL = 0.90f
    const val THRESHOLD_MIN = 0.85f
    const val THRESHOLD_MAX = 0.97f
}
