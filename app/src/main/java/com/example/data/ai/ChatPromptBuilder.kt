package com.example.data.ai

import com.example.data.remote.GrokSearchMode
import com.example.data.remote.XAiSearchParameters
import com.example.data.remote.XAiSearchSource
import com.example.domain.model.Bookmark

/**
 * Assembles the Curio Research Assistant chat request (context prompt, system instruction and
 * xAI Live Search parameters) from retrieved library items and the user's selected live sources.
 *
 * Extracted out of BookmarkViewModel so the presentation layer no longer builds prompts or
 * constructs remote DTOs — the VM just supplies data and forwards the result to the analyzer.
 */
object ChatPromptBuilder {

    data class Parts(
        val contextPrompt: String,
        val systemInstruction: String,
        val searchParameters: XAiSearchParameters?
    )

    /**
     * @param liveSourceApiTypes xAI source ids the user enabled ("web" / "x" / "news"); the local
     *   library is handled via [useLibrary] and is never a live source.
     * @param liveLabels human labels of the live sources for the system instruction (e.g. "Web/News").
     */
    fun build(
        userQuery: String,
        contextItems: List<Bookmark>,
        useLibrary: Boolean,
        liveSourceApiTypes: List<String>,
        liveLabels: String
    ): Parts {
        val contextPrompt = buildString {
            if (contextItems.isNotEmpty()) {
                appendLine("Research library context (semantically retrieved):")
                contextItems.forEach { b ->
                    val sourceInfo = if (b.sourceType != null) "[${b.sourceType?.name}:${b.sourceId}] " else ""
                    appendLine("- ${sourceInfo}${b.sourceTitle ?: b.title ?: "Untitled"}")
                    if (!b.sourceAuthors.isNullOrBlank()) appendLine("  Authors: ${b.sourceAuthors}")
                    appendLine("  Category: ${b.category ?: "?"} | Tags: ${b.tags.take(4).joinToString(",")}")
                    if (!b.summary.isNullOrBlank()) appendLine("  Summary: ${b.summary}")
                    if (!b.deepSummary.isNullOrBlank()) appendLine("  Deep: ${b.deepSummary?.take(200)}")
                }
            } else if (useLibrary) {
                appendLine("Library is empty.")
            }
            appendLine("\nUser query: \"$userQuery\"")
        }

        val liveSources = liveSourceApiTypes.mapNotNull { apiType ->
            when (apiType) {
                "web" -> XAiSearchSource.web()
                "x" -> XAiSearchSource.x()
                "news" -> XAiSearchSource.news()
                else -> null
            }
        }
        val searchParameters = if (liveSources.isNotEmpty()) {
            XAiSearchParameters(
                mode = GrokSearchMode.ON,
                returnCitations = true,
                maxSearchResults = 12,
                sources = liveSources
            )
        } else null

        val systemInstruction = buildString {
            appendLine("You are Curio Research Assistant — a personal AI for an ML researcher's saved papers and repos.")
            if (useLibrary) appendLine("Prefer the retrieved library context. Cite paper titles and arXiv IDs when relevant.")
            if (searchParameters != null) appendLine("You also have live $liveLabels search — use it to ground claims and cite sources with markdown links.")
            appendLine("Use markdown (headings, bold, bullets, links). Keep answers concise and formatted for mobile screens.")
        }.trimIndent()

        return Parts(contextPrompt, systemInstruction, searchParameters)
    }
}
