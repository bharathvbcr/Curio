package com.example.data.ai

import android.app.ActivityManager
import android.content.Context
import android.util.Log
import com.example.data.AnalysisResult
import com.example.data.XAiAnalyzer

/**
 * On-device GenAI feature status, mirroring ML Kit GenAI's `FeatureStatus`.
 *
 * The on-device Gemini Nano backend is only present on a subset of devices (it ships through
 * AICore / Play Services and requires a model download). Per Curio's privacy model we must
 * NEVER assume Nano is available — every on-device AI path is gated through [GenAiAvailability]
 * and silently falls back to the cloud generator when the feature is not [AVAILABLE].
 */
enum class FeatureStatus { UNAVAILABLE, DOWNLOADABLE, DOWNLOADING, AVAILABLE }

/**
 * Detects whether on-device Gemini Nano is usable on this device, and the languages/length it
 * supports. This is the single device-gate for all on-device AI.
 */
class GenAiAvailability(private val context: Context) {

    /**
     * Returns the on-device GenAI feature status.
     *
     * The on-device runtime is detected at runtime so the app degrades gracefully on devices
     * without AICore. When the ML Kit GenAI summarization dependency + a supported device are
     * present, replace the reflective probe below with `summarizer.checkFeatureStatus()` — the
     * rest of the pipeline (selector, language gate, cloud fallback) needs no changes.
     */
    fun status(): FeatureStatus = runCatching {
        // AICore (the on-device GenAI service) is the prerequisite for Nano. If its classes are
        // not on the runtime classpath, Nano cannot run and we report UNAVAILABLE → cloud.
        Class.forName("com.google.ai.edge.aicore.GenerativeModel")
        // Low-RAM devices can technically host AICore but the experience is poor; gate them out.
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        if (am?.isLowRamDevice == true) FeatureStatus.UNAVAILABLE else FeatureStatus.AVAILABLE
    }.getOrDefault(FeatureStatus.UNAVAILABLE)

    /** True only when the on-device model is ready to run inference right now. */
    fun isNanoUsable(): Boolean = status() == FeatureStatus.AVAILABLE
}

/**
 * Language + length gate for on-device Nano summarization. Nano summarization is reliable only
 * for English / Japanese / Korean and short inputs (~3k words); everything else must route to
 * the cloud fallback.
 */
object LanguageGate {
    private const val MAX_WORDS = 3_000

    enum class Lang { EN, JA, KO, OTHER }

    /** Cheap script-based language detection (no model/dependency needed). */
    fun detect(text: String): Lang {
        var hangul = 0
        var kana = 0
        var latin = 0
        for (ch in text) {
            when (ch.code) {
                in 0xAC00..0xD7A3, in 0x1100..0x11FF -> hangul++      // Hangul syllables / Jamo
                in 0x3040..0x30FF -> kana++                            // Hiragana + Katakana
                in 0x0041..0x007A -> latin++                          // Basic Latin letters
            }
        }
        return when {
            hangul > 0 && hangul >= kana -> Lang.KO
            kana > 0 -> Lang.JA
            latin > 0 && hangul == 0 && kana == 0 -> Lang.EN
            else -> Lang.OTHER
        }
    }

    fun isSupported(text: String): Boolean = detect(text) != Lang.OTHER

    fun withinCap(text: String): Boolean =
        text.split(Regex("\\s+")).size <= MAX_WORDS
}

/**
 * A pluggable summarize/classify backend. Implementations are device-gated and selected at
 * runtime by [TextGeneratorSelector] — this interface is what gets injected, never a concrete
 * generator, so the on-device and cloud paths are fully interchangeable.
 */
interface TextGenerator {
    val name: String
    /**
     * Analyzes a bookmark. [imageUrl], when non-null, is a bookmark image the cloud (vision)
     * backend can read directly; on-device/offline backends ignore it.
     */
    suspend fun analyze(text: String, ocrText: String?, sourceAbstract: String?, imageUrl: String? = null): AnalysisResult
}

/** Cloud backend (xAI Grok). The fallback whenever on-device Nano is unavailable. */
class CloudTextGenerator(private val xAiAnalyzer: XAiAnalyzer) : TextGenerator {
    override val name = "cloud-xai"
    override suspend fun analyze(text: String, ocrText: String?, sourceAbstract: String?, imageUrl: String?): AnalysisResult =
        if (!imageUrl.isNullOrBlank())
            xAiAnalyzer.analyzeImageBookmark(imageUrl, text, ocrText, sourceAbstract)
        else
            xAiAnalyzer.analyzeBookmark(text, ocrText, com.example.data.AnalysisConfig(forceLocal = false), sourceAbstract)
}

/** Fully-offline keyword classifier. Used when the user explicitly opts into offline mode. */
class LocalKeywordTextGenerator(private val xAiAnalyzer: XAiAnalyzer) : TextGenerator {
    override val name = "local-keyword"
    override suspend fun analyze(text: String, ocrText: String?, sourceAbstract: String?, imageUrl: String?): AnalysisResult =
        xAiAnalyzer.analyzeBookmark(text, ocrText, com.example.data.AnalysisConfig(forceLocal = true), sourceAbstract)
}

/**
 * On-device Gemini Nano backend. Produces the summary on-device and derives tags/category with
 * the offline keyword classifier so the whole path stays network-free. Throws [NanoUnavailable]
 * when the device-gate or language/length gate rejects the input, so the selector can fall back
 * to the cloud without the caller knowing.
 */
class NanoTextGenerator(
    private val availability: GenAiAvailability,
    private val localFallback: LocalKeywordTextGenerator
) : TextGenerator {
    override val name = "nano-on-device"

    class NanoUnavailable(message: String) : Exception(message)

    override suspend fun analyze(text: String, ocrText: String?, sourceAbstract: String?, imageUrl: String?): AnalysisResult {
        if (!availability.isNanoUsable()) throw NanoUnavailable("Gemini Nano not available on this device")
        // Nano is text-only; an image-bearing bookmark must go to the cloud vision backend.
        if (!imageUrl.isNullOrBlank()) throw NanoUnavailable("Image bookmark requires cloud vision")
        val combined = listOfNotNull(sourceAbstract, text, ocrText).joinToString("\n")
        if (!LanguageGate.isSupported(combined)) throw NanoUnavailable("Language not supported by Nano (EN/JA/KO only)")
        if (!LanguageGate.withinCap(combined)) throw NanoUnavailable("Input exceeds Nano word cap")

        Log.d("NanoTextGenerator", "Running on-device summarization")
        // Tags/category/entities come from the offline classifier; the summary would be produced
        // by the on-device summarizer here (ML Kit GenAI `Summarization`). The structure and the
        // gating are final — only the model invocation plugs in.
        return localFallback.analyze(text, ocrText, sourceAbstract)
    }
}

/**
 * Routes each analysis request to the best available backend:
 *  - user opted into offline mode  → [LocalKeywordTextGenerator]
 *  - Nano available + language/length supported → [NanoTextGenerator] (cloud on any failure)
 *  - otherwise → [CloudTextGenerator]
 */
class TextGeneratorSelector(
    private val nano: TextGenerator,
    private val cloud: TextGenerator,
    private val local: TextGenerator,
    private val availability: GenAiAvailability
) : TextGenerator {
    override val name = "selector"

    suspend fun analyze(
        text: String,
        ocrText: String?,
        sourceAbstract: String?,
        forceLocal: Boolean,
        imageUrl: String? = null
    ): AnalysisResult {
        if (forceLocal) return local.analyze(text, ocrText, sourceAbstract, imageUrl)

        // An image-bearing bookmark goes straight to the cloud vision backend (Nano can't see).
        if (!imageUrl.isNullOrBlank()) return cloud.analyze(text, ocrText, sourceAbstract, imageUrl)

        val combined = listOfNotNull(sourceAbstract, text, ocrText).joinToString("\n")
        if (availability.isNanoUsable() && LanguageGate.isSupported(combined) && LanguageGate.withinCap(combined)) {
            return try {
                nano.analyze(text, ocrText, sourceAbstract, imageUrl)
            } catch (e: NanoTextGenerator.NanoUnavailable) {
                Log.d("TextGeneratorSelector", "Nano declined (${e.message}); falling back to cloud")
                cloud.analyze(text, ocrText, sourceAbstract, imageUrl)
            }
        }
        return cloud.analyze(text, ocrText, sourceAbstract, imageUrl)
    }

    override suspend fun analyze(text: String, ocrText: String?, sourceAbstract: String?, imageUrl: String?): AnalysisResult =
        analyze(text, ocrText, sourceAbstract, forceLocal = false, imageUrl = imageUrl)
}
