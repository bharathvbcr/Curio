package com.example.data

import android.util.Log
import com.example.data.remote.GrokModels
import com.example.data.remote.GrokReasoning
import com.example.data.remote.XAiApi
import com.example.data.remote.XAiContentPart
import com.example.data.remote.XAiMessage
import com.example.data.remote.XAiRequest
import com.example.data.remote.XAiResponseFormat
import com.example.data.remote.XAiSearchParameters
import com.example.data.remote.XAiVisionMessage
import com.example.data.remote.XAiVisionRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class AnalysisConfig(
    val forceLocal: Boolean = false
)

data class AnalysisResult(
    val summary: String,
    val tags: List<String>,
    val category: String,
    val entities: String?,       // JSON: {models:[], methods:[], datasets:[], metrics:[]}
    val usedLocalAnalysis: Boolean
)

/** A chat reply plus any source URLs xAI Live Search grounded it in. */
data class ChatResponse(
    val text: String,
    val citations: List<String> = emptyList()
)

data class DeepAnalysisResult(
    val contribution: String,
    val significance: String,
    val caveats: String
) {
    fun formatted(): String = buildString {
        if (contribution.isNotBlank()) appendLine("**Contribution:** $contribution")
        if (significance.isNotBlank()) appendLine("**Significance:** $significance")
        if (caveats.isNotBlank()) append("**Caveats:** $caveats")
    }.trim()
}

private val SYSTEM_INSTRUCTION = """
You are a specialized AI/ML research curator for Curio. Analyze the provided research content and
return ONLY a valid JSON object with exactly these fields:
- "summary": concise TL;DR one-liner (max 100 chars)
- "category": one value from ["architectures","training","inference-opt","datasets","evals","agents","multimodal","theory","systems","other"]
- "tags": array of 1-4 specific lowercase tags (e.g. "mamba", "state-space-model", "flash-attention-3")
- "entities": object with four arrays: "models" (model/arch names), "methods" (algorithmic methods), "datasets" (dataset/benchmark names), "metrics" (performance metrics)
Return only JSON. No markdown.
""".trimIndent()

private val CATEGORY_GUIDE = """
category guide:
- architectures: attention, SSMs/Mamba/S4/Hyena, linear attention, MoE, transformer variants
- training: pretraining, RLHF, DPO, PPO, SFT, distillation, quantization, LoRA, QLoRA, fine-tuning
- inference-opt: KV-cache, speculative decoding, FlashAttention, vLLM, PagedAttention, batching, kernels
- datasets: training corpora, benchmark datasets, evaluation suites
- evals: model evaluations, benchmarks, leaderboards, capability studies
- agents: agentic workflows, tool-use, function-calling, autonomous agents, RAG, orchestration
- multimodal: vision-language models, image/audio/video generation, VLMs, CLIP
- theory: mathematical analysis, convergence, generalization, optimization theory
- systems: distributed training, serving infrastructure, MLOps, hardware accelerators
""".trimIndent()

class XAiAnalyzer(
    private val xAiApi: XAiApi
) {
    suspend fun analyzeBookmark(
        text: String,
        ocrText: String?,
        config: AnalysisConfig,
        sourceAbstract: String? = null
    ): AnalysisResult = withContext(Dispatchers.Default) {
        if (config.forceLocal) {
            return@withContext localSimulate(text, ocrText)
        }

        Log.d("XAiAnalyzer", "Calling xAI API for analysis...")
        try {
            val apiKey = XaiKeyStore.resolve()
            if (!XaiKeyStore.isConfigured()) {
                throw Exception("xAI API key is missing. Add your key in Settings.")
            }

            val content = buildString {
                if (!sourceAbstract.isNullOrBlank()) append("Abstract: $sourceAbstract\n\n")
                append("Content: $text")
                if (!ocrText.isNullOrBlank()) append("\n\nOCR: $ocrText")
            }

            val prompt = "$CATEGORY_GUIDE\n\nAnalyze:\n$content"
            val request = XAiRequest(
                model = GrokModels.ANALYSIS,
                messages = listOf(
                    XAiMessage(role = "system", content = SYSTEM_INSTRUCTION),
                    XAiMessage(role = "user", content = prompt)
                ),
                temperature = 0.3f,
                // Cheap, fast structured extraction — no deep reasoning needed.
                reasoningEffort = GrokReasoning.LOW,
                responseFormat = XAiResponseFormat.JSON_OBJECT
            )

            val rawResponse = xAiApi.chatCompletions("Bearer $apiKey", request)
            val jsonText = rawResponse.choices?.firstOrNull()?.message?.content
                ?: throw Exception("Empty response from xAI")

            parseAnalysisResult(cleanJsonFence(jsonText))
        } catch (e: Exception) {
            Log.e("XAiAnalyzer", "xAI analysis error", e)
            throw e
        }
    }

    /**
     * Vision-grounded analysis: lets Grok actually SEE a bookmark's image (figure, chart,
     * screenshot) instead of relying only on OCR text, then returns the same structured
     * [AnalysisResult]. [imageUrl] may be a public URL or a data: URI. Falls back to the text-only
     * [analyzeBookmark] if the key is missing or the vision call fails, so callers never lose the
     * analysis entirely.
     */
    suspend fun analyzeImageBookmark(
        imageUrl: String,
        text: String,
        ocrText: String?,
        sourceAbstract: String? = null
    ): AnalysisResult = withContext(Dispatchers.Default) {
        val apiKey = XaiKeyStore.resolve()
        if (!XaiKeyStore.isConfigured()) {
            return@withContext analyzeBookmark(text, ocrText, AnalysisConfig(forceLocal = false), sourceAbstract)
        }
        try {
            val content = buildString {
                if (!sourceAbstract.isNullOrBlank()) append("Abstract: $sourceAbstract\n\n")
                append("Content: $text")
                if (!ocrText.isNullOrBlank()) append("\n\nOCR: $ocrText")
            }
            val prompt = "$CATEGORY_GUIDE\n\nRead the attached image and analyze together with:\n$content"
            val request = XAiVisionRequest(
                model = GrokModels.VISION,
                messages = listOf(
                    XAiVisionMessage(role = "system", content = listOf(XAiContentPart.text(SYSTEM_INSTRUCTION))),
                    XAiVisionMessage(
                        role = "user",
                        content = listOf(
                            XAiContentPart.image(imageUrl, detail = "high"),
                            XAiContentPart.text(prompt)
                        )
                    )
                ),
                temperature = 0.3f
            )
            val rawResponse = xAiApi.visionCompletions("Bearer $apiKey", request)
            val jsonText = rawResponse.choices?.firstOrNull()?.message?.content
                ?: throw Exception("Empty vision response from xAI")
            parseAnalysisResult(cleanJsonFence(jsonText))
        } catch (e: Exception) {
            Log.e("XAiAnalyzer", "xAI vision analysis failed; falling back to text", e)
            analyzeBookmark(text, ocrText, AnalysisConfig(forceLocal = false), sourceAbstract)
        }
    }

    suspend fun deepAnalyzeBookmark(
        text: String,
        ocrText: String?,
        sourceAbstract: String?
    ): DeepAnalysisResult = withContext(Dispatchers.Default) {
        val apiKey = XaiKeyStore.resolve()
        if (!XaiKeyStore.isConfigured()) {
            throw Exception("xAI API key required for deep analysis")
        }

        val content = buildString {
            if (!sourceAbstract.isNullOrBlank()) append("Abstract: $sourceAbstract\n\n")
            append("Tweet/Content: $text")
            if (!ocrText.isNullOrBlank()) append("\n\nOCR: $ocrText")
        }

        val prompt = """
            Analyze this AI/ML research item. Return JSON with exactly 3 fields:
            - "contribution": the specific technical contribution (1-2 sentences)
            - "significance": why this matters for the field (1-2 sentences)
            - "caveats": limitations or open questions (1 sentence)

            Content:
            $content
        """.trimIndent()

        val request = XAiRequest(
            model = GrokModels.DEEP_ANALYSIS,
            messages = listOf(
                XAiMessage(role = "system", content = "You are an AI/ML research analyst. Return only valid JSON."),
                XAiMessage(role = "user", content = prompt)
            ),
            temperature = 0.3f,
            // Deep synthesis benefits from full reasoning.
            reasoningEffort = GrokReasoning.HIGH,
            responseFormat = XAiResponseFormat.JSON_OBJECT
        )

        val rawResponse = xAiApi.chatCompletions("Bearer $apiKey", request)
        val jsonText = rawResponse.choices?.firstOrNull()?.message?.content
            ?: throw Exception("Empty response from xAI")

        val obj = org.json.JSONObject(cleanJsonFence(jsonText))
        DeepAnalysisResult(
            contribution = obj.optString("contribution", ""),
            significance = obj.optString("significance", ""),
            caveats = obj.optString("caveats", "")
        )
    }

    private fun parseAnalysisResult(json: String): AnalysisResult {
        val obj = org.json.JSONObject(json)

        val summary = obj.optString("summary", "No summary")

        val tags = when (val rawTags = obj.opt("tags")) {
            is org.json.JSONArray -> (0 until rawTags.length()).map { rawTags.optString(it).lowercase().trim() }.filter { it.isNotEmpty() }
            is String -> rawTags.split(",").map { it.lowercase().trim() }.filter { it.isNotEmpty() }
            else -> emptyList()
        }

        val category = obj.optString("category", "other").trim()

        val entitiesJson = try {
            val entitiesObj = obj.opt("entities")
            if (entitiesObj != null && entitiesObj != org.json.JSONObject.NULL) entitiesObj.toString() else null
        } catch (e: Exception) { null }

        return AnalysisResult(
            summary = summary,
            tags = tags,
            category = category,
            entities = entitiesJson,
            usedLocalAnalysis = false
        )
    }

    private fun localSimulate(text: String, ocrText: String?): AnalysisResult {
        Log.d("XAiAnalyzer", "Running local keyword simulation...")
        val combined = (text + " " + (ocrText ?: "")).lowercase()

        fun String.has(vararg terms: String) = terms.any { this.contains(it) }

        val category = when {
            combined.has("attention", "transformer", "mamba", "ssm", "state space", "moe",
                "mixture of experts", "linear attention", "hyena", "retention") -> "architectures"
            combined.has("rlhf", "dpo", "ppo", "sft", "lora", "qlora", "fine-tun",
                "pretraining", "distill", "quantiz", "instruction tun") -> "training"
            combined.has("kv cache", "kv-cache", "speculative", "flashattention",
                "flash attention", "vllm", "paged", "batching", "kernel") -> "inference-opt"
            combined.has("dataset", "corpus", "benchmark data", "training data") -> "datasets"
            combined.has("benchmark", "eval", "leaderboard", "mmlu", "humaneval", "hellaswag") -> "evals"
            combined.has("agent", "tool use", "function call", "autonomous", "rag", "retrieval-augmented") -> "agents"
            combined.has("multimodal", "vision", "image gen", "audio model", "video", "vlm", "clip", "diffusion") -> "multimodal"
            combined.has("theory", "convergence", "proof", "regret bound", "generalization bound") -> "theory"
            combined.has("distributed", "infrastructure", "serving", "mlops", "hardware", "gpu", "tpu") -> "systems"
            combined.has("android", "kotlin", "compose", "mobile", "app") -> "systems"
            else -> "other"
        }

        val words = combined.split(Regex("[^a-zA-Z0-9-]+"))
            .filter { it.length > 4 && it !in stopWords }
            .distinct()
            .take(3)
        val tags = if (words.isEmpty()) listOf("curated") else words

        return AnalysisResult(
            summary = "⚡ [Local] ${text.take(80).trim()}",
            tags = tags,
            category = category,
            entities = null,
            usedLocalAnalysis = true
        )
    }

    private fun cleanJsonFence(raw: String): String =
        raw.replace("```json", "").replace("```", "").trim()

    /**
     * Generates a chat reply. When [searchParameters] is non-null, xAI Live Search is
     * enabled so the model can ground its answer in real-time Web / X / News sources and
     * return citations. When null, the model answers purely from the supplied prompt
     * context (the user's saved research library).
     */
    suspend fun generateChatResponse(
        prompt: String,
        systemInstruction: String = "You are a helpful AI assistant.",
        searchParameters: XAiSearchParameters? = null
    ): ChatResponse = withContext(Dispatchers.Default) {
        val apiKey = XaiKeyStore.resolve()
        if (!XaiKeyStore.isConfigured()) {
            return@withContext ChatResponse("xAI API key is missing. Add your key in Settings.")
        }
        val request = XAiRequest(
            model = com.example.data.remote.GrokModels.CHAT,
            messages = listOf(
                XAiMessage(role = "system", content = systemInstruction),
                XAiMessage(role = "user", content = prompt)
            ),
            temperature = 0.7f,
            searchParameters = searchParameters
        )
        try {
            val rawResponse = xAiApi.chatCompletions("Bearer $apiKey", request)
            val text = rawResponse.choices?.firstOrNull()?.message?.content
                ?: "No response generated by xAI assistant."
            ChatResponse(text = text, citations = rawResponse.citations.orEmpty())
        } catch (e: Exception) {
            ChatResponse("Connection failed: ${e.localizedMessage ?: "Unknown networking error"}. Check XAI_API_KEY in Secrets panel.")
        }
    }

    /**
     * Generates a themed markdown digest of a set of recent saves. [itemsBlock] is a pre-formatted
     * one-line-per-item list (title / category / summary) and [itemCount] the number of items.
     * Returns markdown suitable for [com.example.ui.MarkdownText]. Throws when the API key is absent
     * so the caller can surface a clear "key required" state rather than a silent empty digest.
     */
    suspend fun generateWeeklyDigest(itemsBlock: String, itemCount: Int): String = withContext(Dispatchers.Default) {
        val apiKey = XaiKeyStore.resolve()
        if (!XaiKeyStore.isConfigured()) {
            throw Exception("xAI API key required for the weekly digest")
        }

        val prompt = """
            Below are $itemCount research items I saved this week. Write a concise weekly digest in markdown:
            - One **TL;DR** line capturing the week's themes.
            - 2–4 `## Theme` sections grouping related items, each a short paragraph on what's notable and how the items connect.
            - A final `## Worth a closer look` list of the 1–3 most significant items and why.
            Keep it tight and skimmable. Do not invent items beyond those listed.

            Items:
            $itemsBlock
        """.trimIndent()

        val request = XAiRequest(
            model = GrokModels.DEEP_ANALYSIS,
            messages = listOf(
                XAiMessage(role = "system", content = "You are a research librarian writing a weekly digest. Output only markdown."),
                XAiMessage(role = "user", content = prompt)
            ),
            temperature = 0.5f,
            reasoningEffort = GrokReasoning.MEDIUM
        )

        val rawResponse = xAiApi.chatCompletions("Bearer $apiKey", request)
        rawResponse.choices?.firstOrNull()?.message?.content?.trim()
            ?: throw Exception("Empty response from xAI")
    }

    private companion object {
        val stopWords = setOf("about", "their", "there", "would", "bookmark", "https", "tweet",
            "thread", "paper", "model", "models", "using", "neural", "learning", "which")
    }
}
